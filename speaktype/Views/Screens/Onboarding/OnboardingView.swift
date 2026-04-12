import AppKit
import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @State private var currentPage = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - Match main app exactly
                Color.bgApp.ignoresSafeArea()

                // Content ZStack
                ZStack {
                    if currentPage == 0 {
                        WelcomePage(action: {
                            withAnimation(.easeInOut(duration: 0.5)) { currentPage = 1 }
                        })
                        .transition(.opacity)
                    } else if currentPage == 1 {
                        GlobeKeyOptimizationPage(action: {
                            withAnimation(.easeInOut(duration: 0.5)) { currentPage = 2 }
                        })
                        .transition(.opacity)
                    } else if currentPage == 2 {
                        PermissionsPage(onContinue: {
                            withAnimation(.easeInOut(duration: 0.5)) { currentPage = 3 }
                        })
                        .transition(.opacity)
                    } else {
                        OnboardingModelDownloadPage(finishAction: {
                            completeOnboarding()
                        })
                        .transition(.opacity)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 500)  // Lower minimum size
        .frame(minWidth: 600, minHeight: 500)  // Lower minimum size
    }

    func completeOnboarding() {
        withAnimation {
            hasCompletedOnboarding = true
        }
        Task(priority: .userInitiated) {
            await ModelDownloadService.shared.refreshDownloadedModels()
            await SelectedModelPreference.preloadSelectedModelIfDownloaded()
        }
    }
}

struct WelcomePage: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon / Hero with refined shadow
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 8)

            VStack(spacing: 14) {
                Text("Welcome to")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)
                    .tracking(2.5)

                Text("SpeakType")
                    .font(.system(size: 48, weight: .regular, design: .serif))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.5)

                HStack(spacing: 0) {
                    Text("Voice to text, powered by AI.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.textSecondary)

                    Text(" Private. Fast. Offline.")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 32)

            HStack(spacing: 20) {
                FeatureCard(
                    icon: "lock.shield.fill", title: "Private",
                    description: "Your audio never leaves your device")
                FeatureCard(
                    icon: "bolt.fill", title: "Fast", description: "Optimized for Apple Silicon")
                FeatureCard(
                    icon: "keyboard.fill", title: "Universal", description: "Works in any app")
            }
            .padding(.top, 48)

            Spacer()

            GetStartedButton(action: action)
                .padding(.bottom, 48)
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 40)
    }
}

struct GetStartedButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("Get Started")
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .offset(x: isHovered ? 3 : 0)
            }
            .foregroundStyle(Color.bgApp)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.textPrimary)
            )
            .shadow(
                color: Color.black.opacity(isHovered ? 0.18 : 0.08), radius: isHovered ? 14 : 8, x: 0,
                y: isHovered ? 6 : 3
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct PermissionsPage: View {
    var onContinue: () -> Void
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var accessibilityStatus: Bool = false
    @State private var documentsAccessGranted: Bool = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Text("QUICK SETUP")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)
                    .tracking(2)

                Text("Permissions")
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundStyle(Color.textPrimary)

                Text("Grant these permissions to unlock the full experience.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            VStack(spacing: 12) {
                // Microphone
                OnboardingPermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "To hear and transcribe your voice",
                    isGranted: micStatus == .authorized,
                    action: requestMicPermission
                )

                // Documents Folder
                OnboardingPermissionRow(
                    icon: "folder.fill",
                    title: "Documents Folder",
                    description: "To store AI models locally on your Mac",
                    isGranted: documentsAccessGranted,
                    action: requestDocumentsAccess
                )

                // Accessibility
                OnboardingPermissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "To type transcribed text into any app",
                    isGranted: accessibilityStatus,
                    action: requestAccessibilityPermission
                )
            }
            .frame(maxWidth: 520)
            .padding(.top, 48)

            Spacer()

            ContinueButton(
                isEnabled: micStatus == .authorized && accessibilityStatus
                    && documentsAccessGranted,
                action: onContinue
            )
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 40)
        .onAppear {
            checkPermissions()
            startPolling()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            print("App became active, checking permissions...")
            checkPermissions()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    // ... Copy-paste existing helpers (checkPermissions, request, polling) ...
    // Note: Re-implementing them inline for the tool call

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                self.checkPermissions()
            }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func checkPermissions() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let newAccessStatus = AXIsProcessTrusted()
        if newAccessStatus != accessibilityStatus {
            print("🔐 Accessibility status changed: \(accessibilityStatus) → \(newAccessStatus)")
        }
        accessibilityStatus = newAccessStatus

        // Check documents access by verifying the huggingface folder exists or can be created
        checkDocumentsAccess()
    }

    func checkDocumentsAccess() {
        guard
            let documentsDir = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            documentsAccessGranted = false
            return
        }

        let huggingfacePath = documentsDir.appendingPathComponent("huggingface")
        // If the folder exists or we can access it, permission was granted
        documentsAccessGranted =
            FileManager.default.fileExists(atPath: huggingfacePath.path)
            || FileManager.default.isReadableFile(atPath: documentsDir.path)
    }

    func requestDocumentsAccess() {
        guard
            let documentsDir = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return
        }

        let huggingfacePath = documentsDir.appendingPathComponent("huggingface")

        // Creating a directory in Documents triggers the permission prompt
        do {
            try FileManager.default.createDirectory(
                at: huggingfacePath, withIntermediateDirectories: true)
            print("✅ Documents folder access granted - created huggingface directory")
            documentsAccessGranted = true
        } catch {
            print("⚠️ Documents folder access error: \(error)")
            // Permission may have been denied, or there was another error
            documentsAccessGranted = false
        }
    }

    func requestMicPermission() {
        // Check current status
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch currentStatus {
        case .authorized:
            // Already granted
            micStatus = .authorized
            return

        case .notDetermined:
            // Show native permission prompt
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.checkPermissions()
                }
            }

        case .denied, .restricted:
            // User previously denied - open System Settings
            openSettings(for: "Privacy_Microphone")

        @unknown default:
            break
        }
    }

    func requestAccessibilityPermission() {
        print("DEBUG: Requesting Accessibility Permission")

        // First check current status
        let currentStatus = AXIsProcessTrusted()

        if currentStatus {
            // Already granted
            accessibilityStatus = true
            return
        }

        // Show the native macOS prompt (will appear automatically)
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        accessibilityStatus = accessEnabled

        // Note: We don't manually open System Settings here because
        // the native prompt will show. Only open manually if user
        // needs to re-enable after denying (handled by polling)
    }

    func openSettings(for pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with subtle background
            ZStack {
                Circle()
                    .fill(Color.textPrimary.opacity(0.05))
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()
                .frame(height: 20)

            // Title in serif
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(Color.textPrimary)

            Spacer()
                .frame(height: 6)

            // Description
            Text(description)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(width: 160, height: 165)
        .padding(.horizontal, 16)
        .background(
            ZStack {
                // Base fill - always light for "floating card" effect
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.bgCard)

                // Subtle inner border for depth
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.bgCard.opacity(0.8),
                                Color.textSecondary.opacity(0.03),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
        .shadow(
            color: Color.black.opacity(isHovered ? 0.12 : 0.06), radius: isHovered ? 20 : 12, x: 0,
            y: isHovered ? 10 : 6
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct OnboardingPermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Clean icon
            Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(isGranted ? Color.green : Color.textPrimary.opacity(0.7))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)

                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.green)
            } else {
                Button(action: action) {
                    Text("Allow")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.bgApp)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.textPrimary)
                        )
                }
                .buttonStyle(.stPlain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgCard)
                .shadow(
                    color: Color.black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 8 : 4,
                    x: 0, y: 2)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ContinueButton: View {
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false
    /// Tracks whether this control called `NSCursor.pointingHand.push()` so we can balance on disappear or when disabled mid-hover.
    @State private var handCursorPushed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("Continue")
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: isEnabled ? "arrow.right" : "lock.fill")
                    .font(.system(size: isEnabled ? 12 : 10, weight: .medium))
                    .offset(x: (isHovered && isEnabled) ? 3 : 0)
            }
            .foregroundStyle(Color.bgApp)
            .frame(width: 160, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? Color.textPrimary : Color.textSecondary.opacity(0.3))
            )
            .shadow(
                color: isEnabled ? Color.black.opacity(isHovered ? 0.2 : 0.1) : Color.clear,
                radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 6 : 3
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onHover { hovering in
            if isEnabled { isHovered = hovering }
            if isEnabled {
                if hovering {
                    NSCursor.pointingHand.push()
                    handCursorPushed = true
                } else {
                    NSCursor.pop()
                    handCursorPushed = false
                }
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled && handCursorPushed {
                NSCursor.pop()
                handCursorPushed = false
            }
        }
        .onDisappear {
            if handCursorPushed {
                NSCursor.pop()
                handCursorPushed = false
            }
            isHovered = false
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if isEnabled { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct GlobeKeyOptimizationPage: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Text("OPTIMIZE WORKFLOW")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)
                    .tracking(2)

                Text("The Globe Key")
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundStyle(Color.textPrimary)

                Text(
                    "By default, macOS uses the \u{1F310} key to show the Emoji Picker, which interrupts SpeakType.\n\nPlease open Keyboard Settings and change **\"Press \u{1F310} key to\"** to **\"Do Nothing\"**."
                )
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .lineSpacing(4)
            }

            VStack(spacing: 12) {
                Button(action: openKeyboardSettings) {
                    HStack {
                        Image(systemName: "switch.2")
                        Text("Open Keyboard Settings")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.bgApp)
                    .frame(width: 260, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.textPrimary)
                    )
                }
                .buttonStyle(.stPlain)
            }
            .padding(.top, 40)

            Spacer()

            ContinueButton(
                isEnabled: true,
                action: action
            )
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 40)
    }

    private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Model download (onboarding)

/// Lets new users pull the recommended Core ML model before the first hotkey, so transcription works immediately after setup.
struct OnboardingModelDownloadPage: View {
    let finishAction: () -> Void
    @ObservedObject private var downloadService = ModelDownloadService.shared
    @State private var showOtherModels = false

    private var recommended: AIModel {
        AIModel.recommendedModel(forDeviceRAMGB: WhisperService.deviceRAMGB)
    }

    private var otherModels: [AIModel] {
        AIModel.availableModels.filter { $0.variant != recommended.variant }
    }

    private var hasAnyModelDownloaded: Bool {
        downloadService.downloadProgress.values.contains { $0 >= 1.0 }
    }

    private func progress(for variant: String) -> Double {
        downloadService.downloadProgress[variant] ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Text("VOICE MODEL")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)
                    .tracking(2)

                Text("Download transcription model")
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(
                    "SpeakType runs entirely on your Mac. Grab the recommended model for \(WhisperService.deviceRAMGB) GB RAM — you can start dictating as soon as the download finishes."
                )
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            }

            VStack(alignment: .leading, spacing: 14) {
                recommendedCard

                DisclosureGroup(isExpanded: $showOtherModels) {
                    VStack(spacing: 10) {
                        ForEach(otherModels) { model in
                            otherModelRow(model)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Other models")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                }
                .tint(Color.textPrimary)
            }
            .frame(maxWidth: 520)
            .padding(.top, 36)

            Spacer()

            ContinueButton(isEnabled: hasAnyModelDownloaded, action: finishAction)
                .padding(.bottom, 48)
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 40)
        .onAppear {
            Task {
                await downloadService.refreshDownloadedModels()
            }
        }
    }

    private var recommendedCard: some View {
        let variant = recommended.variant
        let p = progress(for: variant)
        let loading = downloadService.isDownloading[variant] == true

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommended.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(recommended.size) · \(recommended.details)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                    Text("Best match for your Mac (\(WhisperService.deviceRAMGB) GB RAM)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
                statusTrailing(variant: variant, progress: p, isDownloading: loading)
            }

            if p > 0 && p < 1 {
                ProgressView(value: p)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgCard)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.textPrimary.opacity(0.08), lineWidth: 1)
        )
    }

    private func otherModelRow(_ model: AIModel) -> some View {
        let p = progress(for: model.variant)
        let loading = downloadService.isDownloading[model.variant] == true

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                    Text(model.size)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                statusTrailing(variant: model.variant, progress: p, isDownloading: loading)
            }
            if p > 0 && p < 1 {
                ProgressView(value: p)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.textPrimary.opacity(0.04))
        )
    }

    @ViewBuilder
    private func statusTrailing(variant: String, progress: Double, isDownloading: Bool) -> some View {
        if progress >= 1.0 {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.green)
        } else if isDownloading {
            ProgressView()
                .controlSize(.regular)
        } else {
            Button {
                downloadService.downloadModel(variant: variant)
            } label: {
                Text("Download")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.bgApp)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.textPrimary)
                    )
            }
            .buttonStyle(.stPlain)
        }
    }
}

#Preview {
    OnboardingView()
}
