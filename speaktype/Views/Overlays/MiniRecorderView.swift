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
    @State private var releasedAt: ContinuousClock.Instant?
    /// Pill is showing a transient message (error, "No speech detected", paste hint).
    @State private var isShowingMessage = false
    @State private var awaitingPasteResult = false
    @State private var recoveryText: String?
    @State private var dismissTask: Task<Void, Never>?
    /// Route decided once at record start (see `startRecording`).
    @State private var usesLocalRoute = true
    @State private var routeIsRemote = false
    @State private var routeProviderLabel: String?
    @State private var capturedLanguage = "auto"
    @State private var retryRoute: DictationRetryRoute?
    var onCancelPaste: (() -> Void)?
    var onEscapeCaptureChanged: ((Bool) -> Void)?
    var onCommit: ((String, UUID, ContinuousClock.Instant) -> Void)?
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
    @State private var savedTranscript: String?
    @State private var globalEscapeMonitor: Any?
    @State private var localEscapeMonitor: Any?

    // Default Init for Preview
    init(
        onCommit: ((String, UUID, ContinuousClock.Instant) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onCancelPaste: (() -> Void)? = nil,
        onEscapeCaptureChanged: ((Bool) -> Void)? = nil,
        onStartAccepted: (() -> Void)? = nil,
        onStopAccepted: (() -> Void)? = nil
    ) {
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onCancelPaste = onCancelPaste
        self.onEscapeCaptureChanged = onEscapeCaptureChanged
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
        case message(String, isError: Bool, copyText: String?)
    }

    private var pillState: PillState {
        if let frozenState { return frozenState }
        if isShowingMessage {
            if showsPasted { return .done }
            if awaitingPasteResult { return .working }
            return .message(statusMessage, isError: Self.isErrorMessage(statusMessage), copyText: recoveryText)
        }
        // Dots only while text is actually being produced. Every other moment the pill is on
        // screen (mic starting, first frame before the start request lands) shows the
        // waveform, so a start never flashes the "working" look.
        if isProcessing && !isListening && recordingStartTask == nil { return .working }
        return .listening
    }

    /// Neutral notes ("No speech detected", the ⌘V hint) vs. real failures.
    private static func isErrorMessage(_ text: String) -> Bool {
        let neutral = ["No speech detected", "Copied.", "Dictation stopped", "Transcript saved"]
        return !neutral.contains(where: { text.hasPrefix($0) })
    }

    @State private var isHovering = false
    /// The paste was confirmed; the checkmark is showing.
    @State private var showsPasted = false
    /// Set for a state change that happens while the panel is hidden, so the pill appears
    /// already in its new shape instead of morphing during the fade-in.
    @State private var skipNextAnimation = false
    /// Bumped by anything that puts new content in the pill; a pending fade-out reset only
    /// applies if nothing newer was shown meanwhile.
    @State private var contentGeneration = 0
    /// What the pill showed when a fade-out began. Held until the panel is gone (or newer
    /// content arrives) so resetting the recorder's state never changes the fading pill.
    @State private var frozenState: PillState?

    /// The panel is a fixed transparent canvas; the pill sits at its bottom center and
    /// animates its own size, so the window never jumps.
    /// Tall enough for a tooltip above the pill; the empty area is transparent to clicks.
    static let canvasSize = CGSize(width: 420, height: 124)
    private static let pillHeight: CGFloat = 34

    private var showsControls: Bool { pillState == .listening && isHovering }
    /// Id of the pill element whose tooltip is showing, drawn above the pill.
    @State private var tooltipID: String?

    private var capturesEscape: Bool {
        isListening || (isProcessing && (!isShowingMessage || (awaitingPasteResult && !showsPasted)))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            pill
                .pillTooltipFrame()
                .padding(.bottom, 6)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height, alignment: .bottom)
        .overlayPreferenceValue(PillTooltipAnchors.self) { anchors in
            tooltipLayer(anchors)
        }
        .contextMenu {
            modelSelectionMenu
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingStartRequested)) { _ in
            startRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingStopRequested)) { _ in
            stopAndTranscribe()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingEscapeRequested)) { _ in
            handleEscape()
        }
        .onChange(of: capturesEscape) { _, capture in
            onEscapeCaptureChanged?(capture)
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
                if event.keyCode == 53, !event.isARepeat {
                    Task { @MainActor in self.handleEscape() }
                }
            }
            localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, !event.isARepeat else { return event }
                // Local monitors run on the main thread. Only take Escape while the recorder is
                // actually recording or transcribing, so other SpeakType windows (sheets,
                // menus, fields) keep their normal Escape behavior.
                let shouldSwallow = MainActor.assumeIsolated {
                    self.capturesEscape
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
                    cancelButton
                        .transition(Self.contentTransition)
                }
                LiveWaveform(level: audioRecorder.audioLevel, isLive: isListening)
                    .transition(Self.contentTransition)
                if showsControls {
                    finishButton
                        .transition(Self.contentTransition)
                }
            case .working:
                WorkingDots()
                    .pillTooltip(statusMessage, id: "status", shown: $tooltipID)
                    .transition(Self.contentTransition)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .message(let text, let isError, let copyText):
                HStack(spacing: 7) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isError ? Color(red: 1.0, green: 0.62, blue: 0.32) : .white.opacity(0.7))
                    Text(text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let copyText {
                        Button("Copy") {
                            ClipboardService.shared.copy(text: copyText)
                            showMessage("Copied. Press ⌘V to paste.", seconds: 3)
                        }
                        .buttonStyle(.stPlain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.16), in: Capsule())
                    }
                }
                // Short notes hug their text on one line; long ones wrap to two lines at a
                // readable width instead of stretching the pill across the screen.
                .frame(width: text.count > 44 ? 300 : nil)
                .fixedSize(horizontal: text.count <= 44, vertical: true)
                .padding(.vertical, 7)
                .pillTooltip(text, id: "message", shown: $tooltipID)
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
            ? "Release the hotkey to insert text. Esc stops and saves."
            : "Press the hotkey again to insert text. Esc stops and saves."
    }

    /// Same as Esc: stops without inserting; the audio stays in History.
    private var cancelButton: some View {
        Button {
            handleEscape()
        } label: {
            PillCircleIcon(kind: .cancel)
        }
        .buttonStyle(.stPlain)
        .clickActionPointerCursor()
        .pillTooltip("Cancel", id: "cancel", shown: $tooltipID)
        .accessibilityLabel("Cancel")
    }

    private var finishButton: some View {
        Button {
            handleRecordingControlTap()
        } label: {
            PillCircleIcon(kind: .finish)
        }
        .buttonStyle(.stPlain)
        .clickActionPointerCursor()
        .pillTooltip("Finish and paste", id: "finish", shown: $tooltipID)
        .accessibilityLabel("Finish and paste")
    }

    /// The hovered element's tooltip, centered over it and floating just above the pill.
    private func tooltipLayer(_ anchors: [String: PillTooltipEntry]) -> some View {
        GeometryReader { proxy in
            if let id = tooltipID, let target = anchors[id],
               let pill = anchors[PillTooltipAnchors.pillKey] {
                let targetRect = proxy[target.anchor]
                let pillRect = proxy[pill.anchor]
                PillTooltipBubble(text: target.text)
                    .padding(.bottom, proxy.size.height - pillRect.minY + 6)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                    .offset(x: targetRect.midX - proxy.size.width / 2)
                    .transition(.opacity)
                    .id(id)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: tooltipID)
    }

    private var isErrorState: Bool {
        if case .message(_, let isError, _) = pillState { return isError }
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
        case .message(let message, _, _): text = message
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
        let generation = contentGeneration
        if frozenState == nil { frozenState = pillState }
        onCancel?()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            // Something new was shown during the fade (a recording, a message): leave it alone.
            guard generation == contentGeneration else { return }
            skipNextAnimation = true
            if !isListening && recordingStartTask == nil { clearMessage() }
            showsPasted = false
            isHovering = false
            frozenState = nil
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
        guard !cancelCommit, !isStoppingRecording else { return }
        cancelCommit = true
        recordingStartTask?.cancel()
        recordingStartTask = nil
        pendingStopAfterStart = false
        transcriptionTask?.cancel()
        transcriptionTask = nil
        // Freeze the current look and fade out before any state below changes it.
        dismissTask?.cancel()
        dismissAfterFade()
        clearMessage()

        let shouldStopRecording = isListening || audioRecorder.isRecording
        isListening = false
        isProcessing = false
        statusMessage = "Transcribing..."

        guard shouldStopRecording else { return }
        guard !isStoppingRecording else { return }
        isStoppingRecording = true
        Task {
            _ = await audioRecorder.stopRecording(discardOutput: true)
            isStoppingRecording = false
        }
    }

    private func startRecording() {
        guard !isStoppingRecording else {
            debugLog("Audio recorder is still stopping, ignoring start request")
            return
        }

        // A new press pre-empts a message state (error, "No speech detected", paste hint).
        if isShowingMessage { clearMessage() }

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
        let mode = TranscriptionModeUserDefaults.mode
        retryRoute = DictationRetryRoute.current
        capturedLanguage = transcriptionLanguage
        let localModelReady = (ModelDownloadService.shared.downloadProgress[selectedModel] ?? 0) >= 1
        usesLocalRoute = mode != .remoteOnly && !route.isRemote && (retryRoute == nil || localModelReady)

        if mode == .remoteOnly && retryRoute == nil {
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
        contentGeneration += 1
        frozenState = nil
        isHovering = false
        cancelCommit = false
        savedTranscript = nil
        pendingStopAfterStart = false
        releasedAt = nil
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
    private func showMessage(_ message: String, seconds: Double, copyText: String? = nil) {
        debugLog(message)
        dismissTask?.cancel()
        contentGeneration += 1
        frozenState = nil
        // Coming from a hidden pill (e.g. a start error): appear already as the message.
        let fromHidden = !isListening && !isProcessing && !isShowingMessage
        if fromHidden { skipNextAnimation = true }
        awaitingPasteResult = false
        showsPasted = false
        isListening = false
        isProcessing = true
        isShowingMessage = true
        recoveryText = copyText
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
        recoveryText = nil
        guard isShowingMessage else { return }
        isShowingMessage = false
        isProcessing = false
        statusMessage = "Transcribing..."
    }

    /// After handing text to the paste flow, wait briefly for its result (the paste flow closes
    /// the panel, or asks for the "press ⌘V" hint) without blocking a new recording.
    private func awaitPasteResult() {
        dismissTask?.cancel()
        contentGeneration += 1
        frozenState = nil
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
        showMessage(message, seconds: 8, copyText: savedTranscript)
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
            if releasedAt == nil { releasedAt = .now }
            onStopAccepted?()
            return
        }

        guard isListening || audioRecorder.isRecording else {
            debugLog("Not listening, ignoring duplicate stop request")
            return
        }

        if !cancelCommit { onStopAccepted?() }
        let release = releasedAt ?? .now
        isStoppingRecording = true
        isListening = false
        isProcessing = true
        statusMessage = "Transcribing..."
        let language = capturedLanguage
        let route = retryRoute
        transcriptionTask = Task {
            let url = await audioRecorder.stopRecording()
            let stoppedAt = ContinuousClock.now
            guard let url else {
                isStoppingRecording = false
                showMessage("No audio was recorded", seconds: 4)
                return
            }

            async let audioDuration = getAudioDuration(url: url)
            async let peakLevel = audioRecorder.lastRecordingPeakLevel()
            let (duration, peak) = await (audioDuration, peakLevel)
            let shouldProcess = !cancelCommit
            let history = HistoryService.shared
            let id: UUID
            do {
                id = try await history.beginDictation(
                    audioURL: url, duration: duration, language: language, processing: shouldProcess)
            } catch {
                isStoppingRecording = false
                showMessage("Could not save to History. Audio kept on this Mac.", seconds: 7)
                return
            }
            Self.logStage("stop_audio", id: id, startedAt: release, endedAt: stoppedAt)
            Self.logStage("prepare_audio_and_save", id: id, startedAt: stoppedAt)
            isStoppingRecording = false
            defer { history.finishDictation(id: id) }
            guard shouldProcess, !cancelCommit else {
                await history.failDictation(id: id, reason: "Dictation stopped")
                showMessage("Dictation stopped. Audio saved in History.", seconds: 6)
                return
            }
            if let peak, peak < AudioRecordingService.speechPeakThreshold {
                await history.failDictation(id: id, reason: "No speech detected")
                showMessage("No speech detected", seconds: 1.5)
                return
            }
            await processRecording(url: url, id: id, language: language, retryRoute: route, releasedAt: release)
        }
    }

    private func handleEscape() {
        guard isListening || isProcessing else { return }

        if isShowingMessage {
            if awaitingPasteResult && !showsPasted {
                onCancelPaste?()
                showMessage("Transcript saved in History", seconds: 8, copyText: savedTranscript)
            } else {
                dismissAfterFade()
            }
            return
        }

        if cancelCommit { return }
        cancelCommit = true
        if recordingStartTask != nil {
            // Finish opening the writer, then save whatever the microphone captured.
            pendingStopAfterStart = true
        } else if isListening {
            stopAndTranscribe()
        } else if !isStoppingRecording {
            transcriptionTask?.cancel()
            if let savedTranscript {
                showMessage("Transcript saved in History", seconds: 8, copyText: savedTranscript)
            } else {
                showMessage("Dictation stopped. Audio saved in History.", seconds: 6)
            }
        }
    }

    /// Diagnostics go to the unified log (Console.app), not a world-readable file. Messages here
    /// carry no transcript text; transcript snippets are logged separately as `.private`.
    private func debugLog(_ message: String) {
        AppLogger.transcription.debug("\(message, privacy: .public)")
    }

    private func processRecording(
        url: URL, id: UUID, language: String, retryRoute: DictationRetryRoute?,
        releasedAt: ContinuousClock.Instant
    ) async {
        let history = HistoryService.shared
        do {
            statusMessage = routeIsRemote ? "Transcribing via \(routeProviderLabel ?? "cloud")…" : "Transcribing..."
            let transcriptionStarted = ContinuousClock.now
            let outcome = try await TranscriptionCoordinator.transcribe(
                audioFile: url, language: language,
                allowRemote: retryRoute != nil && retryRoute == DictationRetryRoute.current)
            Self.logStage("transcription_\(outcome.provider.rawValue)", id: id, startedAt: transcriptionStarted)
            try Task.checkCancellation()
            guard history.containsDictation(id: id) else {
                dismissAfterFade()
                isProcessing = false
                return
            }
            let raw = HistoryService.cleanedTranscript(outcome.text)
            guard !raw.isEmpty else {
                await history.failDictation(id: id, reason: "No speech detected")
                showMessage("No speech detected", seconds: 1.5)
                return
            }

            savedTranscript = raw
            let rawSaveStarted = ContinuousClock.now
            var textSaved = await history.saveDictationText(id: id, transcript: raw, raw: raw, outcome: outcome)
            Self.logStage("save_raw", id: id, startedAt: rawSaveStarted)
            try Task.checkCancellation()
            let polishStarted = ContinuousClock.now
            let finalized = await TranscriptionFinalizer.finalizeDictation(rawTranscript: raw) {
                statusMessage = "Polishing..."
            }
            let polished = finalized == raw ? raw : HistoryService.cleanedTranscript(finalized)
            Self.logStage("cleanup", id: id, startedAt: polishStarted)
            try Task.checkCancellation()
            guard history.containsDictation(id: id) else {
                dismissAfterFade()
                isProcessing = false
                return
            }

            if !polished.isEmpty, polished != raw {
                savedTranscript = polished
                let saveStarted = ContinuousClock.now
                textSaved = await history.saveDictationText(id: id, transcript: polished, raw: raw, outcome: outcome)
                Self.logStage("save_polished", id: id, startedAt: saveStarted)
                try Task.checkCancellation()
                guard history.containsDictation(id: id) else {
                    dismissAfterFade()
                    return
                }
            }
            let finalText = savedTranscript ?? raw
            guard textSaved else {
                showMessage("Could not save the transcript", seconds: 10, copyText: finalText)
                return
            }

            awaitPasteResult()
            onCommit?(finalText, id, releasedAt)
        } catch is CancellationError {
            await history.failDictation(id: id, reason: "Dictation stopped")
        } catch {
            guard !Task.isCancelled else { return }
            let message = await history.recordDictationError(error, id: id, retryRoute: retryRoute)
            guard !Task.isCancelled else { return }
            showMessage(message, seconds: 6)
        }
    }

    static func logStage(
        _ stage: String, id: UUID, startedAt: ContinuousClock.Instant,
        endedAt: ContinuousClock.Instant = .now
    ) {
        let elapsed = (endedAt - startedAt).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        AppLogger.transcription.notice(
            "dictation=\(id.uuidString, privacy: .public) stage=\(stage, privacy: .public) seconds=\(seconds, format: .fixed(precision: 3))")
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
            if event.keyCode == 53, !event.isARepeat {  // Escape key
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
