import AVFoundation
import Combine
import CoreMedia
import OSLog
import SwiftUI

struct MiniRecorderView: View {
    @ObservedObject private var audioRecorder = AudioRecordingService.shared
    private var whisperService: WhisperService { WhisperService.shared }
    @State private var isListening = false

    @State private var isProcessing = false
    @State private var isStoppingRecording = false
    @State private var statusMessage = "Transcribing..."
    @State private var isWarmingUp = false
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var recordingStartTask: Task<Void, Never>?
    /// A stop that arrived while the mic was still starting; applied once capture is live.
    @State private var pendingStopAfterStart = false
    /// Pill is showing a transient message (error, "No speech detected", paste hint).
    @State private var isShowingMessage = false
    @State private var awaitingPasteResult = false
    @State private var dismissTask: Task<Void, Never>?
    /// Route decided once at record start (see `startRecording`).
    @State private var usesLocalRoute = true
    @State private var routeIsRemote = false
    @State private var routeProviderLabel: String?
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    /// The recorder accepted a start request (used to pick the paste target).
    var onStartAccepted: (() -> Void)?
    /// The recorder accepted a stop request; the transcript will be committed.
    var onStopAccepted: (() -> Void)?

    @AppStorage(wrappedValue: SelectedModelPreference.recommendedVariant(), SelectedModelPreference.storageKey) private var selectedModel: String
    @AppStorage("recordingMode") private var recordingMode: Int = 0
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage: String = "auto"
    @AppStorage("recentTranscriptionLanguages") private var recentLanguagesString: String = ""
    private let quickLanguageDefaults = ["en", "es", "fr", "de", "hi", "pt", "ja", "zh"]

    private var recentLanguageCodes: [String] {
        recentLanguagesString.split(separator: ",").map(String.init).filter { $0 != DictationHints.swedishEnglish }
    }

    private var quickLanguageCodes: [String] {
        var orderedCodes: [String] = []
        let candidateCodes = [transcriptionLanguage] + recentLanguageCodes + quickLanguageDefaults

        for code in candidateCodes where code != "auto" {
            guard !orderedCodes.contains(code) else { continue }
            guard SpokenLanguageSection.languageOptions.contains(where: { $0.code == code }) else {
                continue
            }
            orderedCodes.append(code)
        }

        return Array(orderedCodes.prefix(6))
    }

    private func updateRecentLanguages(code: String) {
        guard code != "auto", code != DictationHints.swedishEnglish else { return }
        var recents = recentLanguageCodes.filter { $0 != code }
        recents.insert(code, at: 0)
        recentLanguagesString = recents.prefix(5).joined(separator: ",")
    }

    private func setLanguage(_ code: String) {
        transcriptionLanguage = code
        updateRecentLanguages(code: code)
    }

    private var currentLanguageLabel: String {
        if transcriptionLanguage == "auto" { return "Auto" }
        if transcriptionLanguage == DictationHints.swedishEnglish { return "SV + EN" }
        return spokenLanguageDisplayName(for: transcriptionLanguage)
    }

    private var spokenLanguageHelpText: String {
        if transcriptionLanguage == "auto" {
            return "Spoken language hint: Auto-detect. SpeakType will try to detect the language you are speaking."
        }
        if transcriptionLanguage == DictationHints.swedishEnglish {
            return "GPT Transcribe gets both Swedish and English as hints. Other models detect the language automatically."
        }

        return
            "Spoken language hint: \(spokenLanguageDisplayName(for: transcriptionLanguage)). If this does not match the language you actually speak, the result may be inaccurate or come back in the wrong language."
    }

    // MARK: - State for Escape key cancellation
    @State private var cancelCommit = false
    @State private var globalEscapeMonitor: Any?
    @State private var localEscapeMonitor: Any?

    // Default Init for Preview
    init(
        onCommit: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onStartAccepted: (() -> Void)? = nil,
        onStopAccepted: (() -> Void)? = nil
    ) {
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onStartAccepted = onStartAccepted
        self.onStopAccepted = onStopAccepted
    }

    // MARK: - Pill states

    /// What the pill shows. Derived from the recorder's existing state so the recording,
    /// transcription and paste logic below is unchanged.
    private enum PillState: Equatable {
        case listening
        case working
        case done
        case message(String, isError: Bool)
    }

    private var pillState: PillState {
        if isShowingMessage {
            if showsPasted { return .done }
            if awaitingPasteResult { return .working }
            return .message(statusMessage, isError: Self.isErrorMessage(statusMessage))
        }
        // Dots only while text is actually being produced. Every other moment the pill is on
        // screen (mic starting, first frame before the start request lands) shows the
        // waveform, so a start never flashes the "working" look.
        if isProcessing && !isListening && recordingStartTask == nil { return .working }
        return .listening
    }

    /// Neutral notes ("No speech detected", the ⌘V hint) vs. real failures.
    private static func isErrorMessage(_ text: String) -> Bool {
        let neutral = ["No speech detected", "Copied."]
        return !neutral.contains(where: { text.hasPrefix($0) })
    }

    @State private var isHovering = false
    /// The paste was confirmed; the checkmark is showing.
    @State private var showsPasted = false
    /// Set for a state change that happens while the panel is hidden, so the pill appears
    /// already in its new shape instead of morphing during the fade-in.
    @State private var skipNextAnimation = false

    /// The panel is a fixed transparent canvas; the pill sits at its bottom center and
    /// animates its own size, so the window never jumps.
    static let canvasSize = CGSize(width: 420, height: 64)
    private static let pillHeight: CGFloat = 34

    private var showsControls: Bool { pillState == .listening && isHovering }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            pill
                .padding(.bottom, 6)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height, alignment: .bottom)
        .contextMenu {
            modelSelectionMenu
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingStartRequested)) { _ in
            startRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingStopRequested)) { _ in
            stopAndTranscribe()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingCancelRequested)) { _ in
            cancelRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingShowMessageRequested)) {
            handlePanelMessage($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingPasteSucceeded)) { _ in
            handlePasteSucceeded()
        }
        .onChange(of: pillState) { _, state in
            announce(state)
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .recorderDemoRequested)) { _ in
            runVisualDemo()
        }
        #endif
        .onAppear {
            initializedService()

            // Set up Escape key monitors
            globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    Task { @MainActor in self.handleEscape() }
                }
            }
            localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                // Local monitors run on the main thread. Only take Escape while the recorder is
                // actually recording or transcribing, so other SpeakType windows (sheets,
                // menus, fields) keep their normal Escape behavior.
                let shouldSwallow = MainActor.assumeIsolated {
                    self.isListening || (self.isProcessing && !self.isShowingMessage)
                }
                Task { @MainActor in self.handleEscape() }
                return shouldSwallow ? nil : event
            }
        }
        .onDisappear {
            if let globalEscapeMonitor = globalEscapeMonitor {
                NSEvent.removeMonitor(globalEscapeMonitor)
            }
            if let localEscapeMonitor = localEscapeMonitor {
                NSEvent.removeMonitor(localEscapeMonitor)
            }
        }
        .background(
            KeyEventHandlerView(onEscape: {
                handleEscape()
            })
        )
    }

    #if DEBUG
    /// Debug-only walkthrough of every pill state with fake mic levels. No microphone, no
    /// transcription, no paste. Launch a Debug build with `--recorder-demo`.
    private func runVisualDemo() {
        Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            func speak(_ seconds: Double) async {
                let start = Date()
                while Date().timeIntervalSince(start) < seconds {
                    let t = Date().timeIntervalSince(start)
                    let syllable = abs(sin(t * 9)) * (0.55 + 0.45 * abs(sin(t * 1.7)))
                    audioRecorder.audioLevel = Float(0.25 + 0.65 * syllable)
                    await wait(1.0 / 30.0)
                }
                audioRecorder.audioLevel = 0
            }
            // Hover is not simulated here: the test moves the real mouse over the pill.
            isListening = true
            await speak(5.0)
            isListening = false
            isProcessing = true
            await wait(1.4)
            awaitPasteResult()
            await wait(0.3)
            handlePasteSucceeded()
            await wait(2.0)
            NotificationCenter.default.post(name: .recorderDemoShowPanel, object: nil)
            showMessage("No speech detected", seconds: 1.6)
            await wait(2.4)
            NotificationCenter.default.post(name: .recorderDemoShowPanel, object: nil)
            showMessage("Could not start the microphone", seconds: 1.8)
            await wait(2.6)
            NotificationCenter.default.post(name: .recorderDemoShowPanel, object: nil)
            showMessage(MiniRecorderWindowController.accessibilityPasteMessage, seconds: 2.4)
        }
    }
    #endif

    // MARK: - Subviews

    private var pill: some View {
        HStack(spacing: 10) {
            switch pillState {
            case .listening:
                if showsControls {
                    stopButton
                        .transition(Self.contentTransition)
                }
                LiveWaveform(level: audioRecorder.audioLevel, isLive: isListening)
                    .transition(Self.contentTransition)
                if showsControls {
                    languageMenu
                        .transition(Self.contentTransition)
                }
            case .working:
                WorkingDots()
                    .help(statusMessage)
                    .transition(Self.contentTransition)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .message(let text, let isError):
                HStack(spacing: 7) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isError ? Color(red: 1.0, green: 0.62, blue: 0.32) : .white.opacity(0.7))
                    Text(text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                // Short notes hug their text on one line; long ones wrap to two lines at a
                // readable width instead of stretching the pill across the screen.
                .frame(width: text.count > 44 ? 300 : nil)
                .fixedSize(horizontal: text.count <= 44, vertical: true)
                .padding(.vertical, 7)
                .help(text)
                .transition(Self.contentTransition)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(minWidth: Self.pillHeight, minHeight: Self.pillHeight)
        .background(pillBackground)
        .clipShape(RoundedRectangle(cornerRadius: Self.pillHeight / 2, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: Self.pillHeight / 2, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(skipNextAnimation ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: pillState)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: showsControls)
        .help(pillState == .listening && !showsControls ? listeningHelp : "")
    }

    private var horizontalPadding: CGFloat {
        switch pillState {
        case .listening: return showsControls ? 6 : 14  // controls are 22 pt, edges match
        case .working, .done: return 12
        case .message: return 14
        }
    }

    private var listeningHelp: String {
        recordingMode == 0
            ? "Release the hotkey to insert text. Esc cancels."
            : "Press the hotkey again to insert text. Esc cancels."
    }

    private var stopButton: some View {
        Button {
            handleRecordingControlTap()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.27, blue: 0.27))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.white)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.stPlain)
        .clickActionPointerCursor()
        .help("Stop and insert text")
        .accessibilityLabel("Stop and insert text")
    }

    private var languageMenu: some View {
        Menu {
            Button("Auto-detect") { setLanguage("auto") }

            if !quickLanguageCodes.isEmpty {
                Divider()
                ForEach(quickLanguageCodes, id: \.self) { code in
                    if let lang = SpokenLanguageSection.languageOptions.first(where: {
                        $0.code == code
                    }) {
                        Button(lang.name) { setLanguage(code) }
                    }
                }
            }

            Divider()
            Menu("More languages") {
                ForEach(SpokenLanguageSection.languageOptions, id: \.code) { lang in
                    Button(lang.name) { setLanguage(lang.code) }
                }
            }

            if !recentLanguageCodes.isEmpty {
                Divider()
                Button("Clear recents") { recentLanguagesString = "" }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentLanguageLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                DoubleChevronIcon(color: .white.opacity(0.7))
            }
            .frame(maxWidth: 80, alignment: .leading)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.16)))
        .contentShape(Capsule(style: .continuous))
        .clickActionPointerCursor()
        .help(spokenLanguageHelpText)
        .accessibilityLabel("Language: \(currentLanguageLabel)")
    }

    private var isErrorState: Bool {
        if case .message(_, let isError) = pillState { return isError }
        return false
    }

    private static let errorTint = Color(red: 1.0, green: 0.55, blue: 0.25)

    private var pillBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Self.pillHeight / 2, style: .continuous)
        return ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: Self.pillHeight / 2)
                .clipShape(shape)
            shape.fill(Color.black.opacity(0.78))
            if isErrorState {
                shape.fill(Self.errorTint.opacity(0.16))
            }
            shape.strokeBorder(
                isErrorState ? Self.errorTint.opacity(0.7) : Color.white.opacity(0.14),
                lineWidth: isErrorState ? 1 : 0.5)
        }
    }

    /// Quick crossfade between the pill's contents: the old content leaves fast, the new one
    /// arrives a beat later, so two states never sit on top of each other.
    private static let contentTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.06)),
        removal: .opacity.animation(.easeIn(duration: 0.06)))

    /// VoiceOver hears what the pill shows.
    private func announce(_ state: PillState) {
        let text: String
        switch state {
        case .listening: text = isListening ? "Listening" : ""
        case .working: text = "Writing"
        case .done: text = "Inserted"
        case .message(let message, _): text = message
        }
        guard !text.isEmpty else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Hide with the fade first, then reset the content, so the pill never morphs back to
    /// the waveform while it is fading out.
    private func dismissAfterFade() {
        onCancel?()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            // A new recording started during the fade: leave its state alone.
            guard !isListening, recordingStartTask == nil, !isStoppingRecording else { return }
            skipNextAnimation = true
            clearMessage()
            showsPasted = false
            isHovering = false
            try? await Task.sleep(for: .milliseconds(30))
            skipNextAnimation = false
        }
    }

    @ViewBuilder
    private var modelSelectionMenu: some View {
        ForEach(AIModel.availableModels) { model in
            Button {
                let previousModel = selectedModel
                selectedModel = model.variant

                // Pre-load the new model immediately so the first transcription isn't slow
                if model.variant != previousModel {
                    Task {
                        await MainActor.run { isWarmingUp = true }
                        do {
                            try await whisperService.loadModel(variant: model.variant)
                            debugLog("Model pre-loaded after switch: \(model.variant)")
                        } catch {
                            debugLog("Model pre-load failed: \(error.localizedDescription)")
                        }
                        await MainActor.run { isWarmingUp = false }
                    }
                }
            } label: {
                if selectedModel == model.variant {
                    Label(model.name, systemImage: "checkmark")
                } else {
                    Text(model.name)
                }
            }
        }
    }

    // MARK: - Logic

    private func initializedService() {
        // No microphone pre-warm here: it left the mic running (orange indicator) whenever the
        // first start failed. The session starts per recording and stops when it ends.
        usesLocalRoute = TranscriptionModeUserDefaults.mode != .remoteOnly
            && !TranscriptionCoordinator.willUseRemoteNextTranscript().isRemote

        guard TranscriptionModeUserDefaults.mode != .remoteOnly else {
            debugLog("Remote transcription selected - skipping local model initialization")
            return
        }

        // No preload here: the model loads when recording starts (while the user speaks) and is
        // released when idle, so it never sits in memory between dictations.
    }

    /// Recording control in the floating bar must follow `AudioRecordingService.isRecording`, not only
    /// local `@State`, so Stop still works if `isListening` drifts out of sync (e.g. toggle mode + hotkey flow).
    private func handleRecordingControlTap() {
        if isListening || audioRecorder.isRecording || recordingStartTask != nil {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func cancelRecording() {
        cancelCommit = true
        recordingStartTask?.cancel()
        recordingStartTask = nil
        pendingStopAfterStart = false
        transcriptionTask?.cancel()
        transcriptionTask = nil
        clearMessage()

        let shouldStopRecording = isListening || audioRecorder.isRecording
        isListening = false
        isProcessing = false
        statusMessage = "Transcribing..."
        onCancel?()

        guard shouldStopRecording else { return }
        guard !isStoppingRecording else { return }
        isStoppingRecording = true
        Task {
            _ = await audioRecorder.stopRecording(discardOutput: true)
            isStoppingRecording = false
        }
    }

    private func startRecording() {
        // A new press pre-empts a message state (error, "No speech detected", paste hint).
        if isShowingMessage {
            clearMessage()
        }

        guard !isStoppingRecording else {
            debugLog("Audio recorder is still stopping, ignoring start request")
            onCancel?()
            return
        }

        guard !isProcessing else {
            debugLog("Already processing, ignoring start request")
            return
        }

        guard !isListening else {
            debugLog("Already listening, ignoring duplicate start request")
            return
        }

        guard !audioRecorder.isRecording else {
            debugLog("Audio recorder is already active, ignoring start request")
            onCancel?()
            return
        }

        // Decide the route once per recording. It reads the Keychain and system load, so it
        // must not be recomputed in `body` on every audio-level update.
        let route = TranscriptionCoordinator.willUseRemoteNextTranscript()
        routeIsRemote = route.isRemote
        routeProviderLabel = route.providerLabel
        usesLocalRoute = TranscriptionModeUserDefaults.mode != .remoteOnly && !route.isRemote

        if TranscriptionModeUserDefaults.mode == .remoteOnly && !route.isRemote {
            showStartError("Enable audio upload in Settings to use cloud transcription")
            return
        }

        if usesLocalRoute {
            guard !selectedModel.isEmpty else {
                showStartError("No local model selected")
                return
            }

            let progress = ModelDownloadService.shared.downloadProgress[selectedModel] ?? 0
            guard progress >= 1.0 else {
                showStartError("Local model not downloaded")
                return
            }
        }

        onStartAccepted?()
        isHovering = false
        cancelCommit = false
        pendingStopAfterStart = false
        isProcessing = true
        statusMessage = "Starting microphone…"
        debugLog("Starting recording...")
        recordingStartTask?.cancel()
        recordingStartTask = Task {
            guard await audioRecorder.startRecording() else {
                guard !Task.isCancelled else { return }
                recordingStartTask = nil
                pendingStopAfterStart = false
                showStartError("Could not start the microphone")
                return
            }
            guard !Task.isCancelled else {
                _ = await audioRecorder.stopRecording(discardOutput: true)
                return
            }
            recordingStartTask = nil
            isProcessing = false
            isListening = true

            if usesLocalRoute {
                whisperService.cancelIdleUnload()
                if !whisperService.isInitialized || whisperService.currentModelVariant != selectedModel {
                    let variant = selectedModel
                    Task.detached(priority: .userInitiated) {
                        try? await WhisperService.shared.loadModel(variant: variant)
                    }
                }
            }

            // The user let go (or pressed again in toggle mode) while the mic was warming up.
            // Apply that stop now that capture is live, instead of dropping it.
            if pendingStopAfterStart {
                pendingStopAfterStart = false
                stopAndTranscribe()
            }
        }
    }

    private var shouldShowLocalWarmup: Bool {
        usesLocalRoute && (isWarmingUp || whisperService.isLoading)
    }

    private func showStartError(_ message: String) {
        showMessage(message, seconds: 2)
    }

    /// Show a status message in the pill, then close the panel. One cancellable timer: a new
    /// start or Escape cancels it, and a newer message replaces it.
    private func showMessage(_ message: String, seconds: Double) {
        debugLog(message)
        dismissTask?.cancel()
        // Coming from a hidden pill (e.g. a start error): appear already as the message.
        let fromHidden = !isListening && !isProcessing && !isShowingMessage
        if fromHidden { skipNextAnimation = true }
        awaitingPasteResult = false
        showsPasted = false
        isListening = false
        isProcessing = true
        isShowingMessage = true
        statusMessage = message
        if fromHidden {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                skipNextAnimation = false
            }
        }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            dismissAfterFade()
        }
    }

    private func clearMessage() {
        dismissTask?.cancel()
        dismissTask = nil
        awaitingPasteResult = false
        showsPasted = false
        guard isShowingMessage else { return }
        isShowingMessage = false
        isProcessing = false
        statusMessage = "Transcribing..."
    }

    /// After handing text to the paste flow, wait briefly for its result (the paste flow closes
    /// the panel, or asks for the "press ⌘V" hint) without blocking a new recording.
    private func awaitPasteResult() {
        dismissTask?.cancel()
        isShowingMessage = true
        awaitingPasteResult = true
        showsPasted = false
        // Fallback if no paste result ever arrives: close quietly.
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            dismissAfterFade()
        }
    }

    /// The text landed: show the checkmark for a moment, then fade out.
    private func handlePasteSucceeded() {
        guard awaitingPasteResult else { return }
        dismissTask?.cancel()
        showsPasted = true
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            dismissAfterFade()
        }
    }

    private func handlePanelMessage(_ notification: Notification) {
        guard awaitingPasteResult,
            let message = notification.userInfo?["message"] as? String
        else { return }
        showMessage(message, seconds: 3)
    }

    private func stopAndTranscribe() {
        debugLog("stopAndTranscribe called")

        guard !isStoppingRecording else {
            debugLog("Already stopping, ignoring duplicate stop request")
            return
        }

        // Stop arrived while the mic is still starting: remember it and apply it once live.
        if recordingStartTask != nil && !isListening {
            debugLog("Stop requested during mic warm-up, deferring until capture is live")
            pendingStopAfterStart = true
            onStopAccepted?()
            return
        }

        guard isListening || audioRecorder.isRecording else {
            debugLog("Not listening, ignoring duplicate stop request")
            return
        }

        // A local route needs a local model. Cloud-only does not.
        guard TranscriptionModeUserDefaults.mode == .remoteOnly || !selectedModel.isEmpty else {
            debugLog("No model selected - cannot transcribe")
            isStoppingRecording = true
            Task {
                _ = await audioRecorder.stopRecording(discardOutput: true)
                isStoppingRecording = false
            }
            showMessage("No AI model selected. Go to Settings → AI Models to download one.", seconds: 3)
            return
        }

        onStopAccepted?()
        transcriptionTask?.cancel()
        isStoppingRecording = true
        isListening = false
        isProcessing = true
        statusMessage = "Transcribing..."
        transcriptionTask = Task {
            let url = await audioRecorder.stopRecording()
            isStoppingRecording = false
            debugLog("stopRecording returned: \(url?.lastPathComponent ?? "nil")")

            guard let url = url else {
                debugLog("No recording URL, cancelling")
                isListening = false
                isProcessing = false
                onCancel?()
                return
            }

            // Escape during the stop: discard without transcribing.
            guard !Task.isCancelled, !cancelCommit else {
                try? FileManager.default.removeItem(at: url)
                return
            }

            // Always use the final full-recording transcription for committed output.
            // Chunk stitching caused repeated phrases at boundaries across languages.
            await processRecording(url: url)
        }
    }

    private func handleEscape() {
        guard isListening || isProcessing || isWarmingUp || whisperService.isLoading else { return }

        debugLog("Escape pressed - cancelling immediate commit")

        if isShowingMessage {
            clearMessage()
            onCancel?()
            return
        }

        cancelCommit = true
        recordingStartTask?.cancel()
        recordingStartTask = nil
        pendingStopAfterStart = false

        if isListening || audioRecorder.isRecording {
            cancelRecording()
        } else {
            transcriptionTask?.cancel()
            transcriptionTask = nil
            isProcessing = false
            onCancel?()
        }
    }

    /// Diagnostics go to the unified log (Console.app), not a world-readable file. Messages here
    /// carry no transcript text; transcript snippets are logged separately as `.private`.
    private func debugLog(_ message: String) {
        AppLogger.transcription.debug("\(message, privacy: .public)")
    }

    /// Keep the audio and record the failure in History so the user can retry later.
    private func saveFailedRecording(url: URL, reason: String) async {
        let duration = await getAudioDuration(url: url)
        HistoryService.shared.addFailedItem(
            audioFileURL: url, duration: duration, errorMessage: reason)
    }

    /// Recordings shorter than this with no detected speech are treated as accidental taps and
    /// discarded instead of filling History with failed items.
    private static let minimumRetainedSilentRecording: TimeInterval = 1.0

    private func processRecording(url: URL) async {
        debugLog("processRecording started with url: \(url.lastPathComponent)")

        // No voice in the take: don't spend a model call (or invent "Thank you."). Only when
        // the level was actually measured, and the audio always stays in History for Retry.
        if let peak = await audioRecorder.lastRecordingPeakLevel(),
            peak < AudioRecordingService.speechPeakThreshold
        {
            debugLog("Silent take (peak \(peak)) - skipping transcription")
            let duration = await getAudioDuration(url: url)
            HistoryService.shared.addFailedItem(
                audioFileURL: url, duration: duration, errorMessage: "No speech detected")
            showMessage("No speech detected", seconds: 1.5)
            return
        }

        do {
            // Only warm up the on-device model when the next transcription will run locally.
            if usesLocalRoute,
                !whisperService.isInitialized || whisperService.currentModelVariant != selectedModel
            {
                debugLog("Loading model: \(selectedModel)")
                statusMessage = "Warming up model. First use is slower..."
                do {
                    try await whisperService.loadModel(variant: selectedModel)
                    debugLog("Model loaded successfully")
                } catch {
                    debugLog("Model load failed: \(error.localizedDescription)")
                    guard !cancelCommit else {
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    await saveFailedRecording(
                        url: url, reason: "Model load failed: \(error.localizedDescription)")
                    showMessage("Model load failed", seconds: 2)
                    return
                }
            }

            debugLog("Starting transcription...")
            // Do not update visible status after the user cancels.
            if !cancelCommit {
                statusMessage = routeIsRemote ? "Transcribing via \(routeProviderLabel ?? "cloud")…" : "Transcribing..."
            }
            let outcome = try await TranscriptionCoordinator.transcribe(audioFile: url, language: transcriptionLanguage)
            try Task.checkCancellation()
            guard !cancelCommit else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            let text = outcome.text
            AppLogger.transcription.debug("Transcription result: \(String(text.prefix(50)), privacy: .private)")

            guard !text.isEmpty else {
                debugLog("Empty text")
                let duration = await getAudioDuration(url: url)
                if duration >= Self.minimumRetainedSilentRecording {
                    HistoryService.shared.addFailedItem(
                        audioFileURL: url, duration: duration, errorMessage: "No speech detected")
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
                showMessage("No speech detected", seconds: 1.5)
                return
            }

            let shouldPolish = TranscriptionFinalizer.willPolishNextTranscript()
            if shouldPolish, !cancelCommit {
                statusMessage = "Polishing..."
            }
            let finalText = await TranscriptionFinalizer.finalizeTranscript(rawTranscript: text)
            try Task.checkCancellation()
            guard !cancelCommit else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            AppLogger.transcription.debug("Final text: \(String(finalText.prefix(50)), privacy: .private)")

            // Paste first so the text lands without waiting on disk work, then save. The paste
            // flow is asynchronous, so the history entry exists before any keystroke is sent.
            onCommit?(finalText)
            awaitPasteResult()

            let duration = await getAudioDuration(url: url)
            HistoryService.shared.addItem(
                transcript: finalText,
                duration: duration,
                audioFileURL: url,
                modelUsed: outcome.modelLabel,
                transcriptionTime: outcome.transcriptionTime,
                provider: outcome.provider.rawValue,
                estimatedCostUSD: outcome.estimatedCostUSD,
                rawTranscript: text,
                polishedTranscript: finalText == text ? nil : finalText
            )
            debugLog("Committed and saved to history")
        } catch is CancellationError {
            debugLog("Transcription cancelled")
            try? FileManager.default.removeItem(at: url)
            isProcessing = false
        } catch {
            debugLog("Error: \(error.localizedDescription)")
            guard !cancelCommit else {
                try? FileManager.default.removeItem(at: url)
                isProcessing = false
                return
            }
            // Never throw away what the user said: keep the audio as a failed History item.
            await saveFailedRecording(url: url, reason: error.localizedDescription)
            showMessage(error.localizedDescription, seconds: 2)
        }
    }

    private func getAudioDuration(url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : 0
        } catch {
            return 0
        }
    }

    private func spokenLanguageDisplayName(for code: String) -> String {
        if code == "auto" { return "Auto-detect" }
        return SpokenLanguageSection.languageOptions.first(where: { $0.code == code })?.name ?? code
    }
}

// MARK: - Helper Shapes & Views

struct HorizontalWave: Shape {
    var phase: CGFloat
    var amplitude: CGFloat
    var frequency: CGFloat

    // Allow animation of phase, amplitude, AND frequency
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(phase, AnimatablePair(amplitude, frequency)) }
        set {
            phase = newValue.first
            amplitude = newValue.second.first
            frequency = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midHeight = height / 2

        // Start at left middle
        path.move(to: CGPoint(x: 0, y: midHeight))

        for x in stride(from: 0, through: width, by: 1) {
            let relativeX = x / width

            // Sine wave formula: y = A * sin(kx - wt)
            // k = 2pi * frequency (cycles across width)
            // wt = phase
            let sine = sin((relativeX * .pi * 2 * frequency) - phase)

            let y = midHeight + sine * amplitude

            path.addLine(to: CGPoint(x: x, y: y))
        }

        return path
    }
}

struct ChevronShape: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if pointsUp {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        return path
    }
}

struct DoubleChevronIcon: View {
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            ChevronShape(pointsUp: true)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 7, height: 4)

            ChevronShape(pointsUp: false)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 7, height: 4)
        }
        .frame(width: 8, height: 10)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active

        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.masksToBounds = true

        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.layer?.cornerRadius = cornerRadius
    }
}

// MARK: - Key Event Handler

struct KeyEventHandlerView: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyCaptureView {
            view.onEscape = onEscape
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
    }

    class KeyCaptureView: NSView {
        var onEscape: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {  // Escape key
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
