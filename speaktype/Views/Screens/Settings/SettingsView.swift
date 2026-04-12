import AppKit
import AVFoundation
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(Typography.displayLarge)
                    .foregroundStyle(Color.textPrimary)
                    .stCompactUI()

                GeneralSettingsTab()
                AudioSettingsTab()
                PermissionsSettingsTab()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.clear)
    }
}

// MARK: - General settings

struct GeneralSettingsTab: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("autoUpdate") private var autoUpdate = true
    @AppStorage("selectedHotkey") private var selectedHotkey: HotkeyOption = .fn
    @AppStorage("recordingMode") private var recordingMode: Int = 0  // 0: Hold to record, 1: Toggle
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage: String = "auto"
    @AppStorage("recentTranscriptionLanguages") private var recentLanguagesString: String = ""

    private var recentLanguageCodes: [String] {
        recentLanguagesString.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    private func updateRecentLanguages(code: String) {
        guard code != "auto" else { return }
        var recents = recentLanguageCodes.filter { $0 != code }
        recents.insert(code, at: 0)
        recentLanguagesString = recents.prefix(5).joined(separator: ",")
    }

    @StateObject private var updateService = UpdateService.shared
    @EnvironmentObject var licenseManager: LicenseManager

    @State private var showLicenseSheet = false
    @State private var showDeactivateAlert = false

    var body: some View {
        VStack(spacing: 16) {
                // Appearance
                SettingsSection {
                    SettingsSectionHeader(
                        icon: "paintpalette", title: "Appearance",
                        subtitle: "Choose your preferred theme")

                    HStack(spacing: 20) {
                        ForEach(AppTheme.allCases) { theme in
                            RadioButton(
                                title: theme.rawValue,
                                isSelected: appTheme == theme,
                                action: { appTheme = theme }
                            )
                        }
                    }
                }

                // Shortcuts
                SettingsSection {
                    SettingsSectionHeader(
                        icon: "command", title: "Shortcuts", subtitle: "Configure recording hotkeys"
                    )

                    VStack(spacing: 16) {
                        HStack {
                            Text("Primary Hotkey")
                                .font(Typography.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Menu {
                                ForEach(HotkeyOption.allCases) { option in
                                    Button(option.displayName) {
                                        selectedHotkey = option
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedHotkey.displayName)
                                        .font(Typography.bodySmall)
                                        .foregroundStyle(Color.textPrimary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.textMuted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.thinMaterial, in: Capsule(style: .continuous))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.border.opacity(0.45), lineWidth: 0.5)
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .clickActionPointerCursor()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Recording Mode")
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                RecordingModePicker(recordingMode: $recordingMode)
                                    .frame(maxWidth: 280)
                            }

                            Text(
                                recordingMode == 0
                                    ? "Hold the hotkey down to record, release when done."
                                    : "Press the hotkey to start recording, press again to stop."
                            )
                            .font(Typography.captionSmall)
                            .foregroundStyle(Color.textMuted)
                            .stCompactUI()
                            .padding(.top, 2)
                        }

                    }
                }

                // General Behavior
                SettingsSection {
                    SettingsSectionHeader(
                        icon: "macwindow", title: "General", subtitle: "App behavior settings"
                    )

                    VStack(spacing: 16) {
                        HStack {
                            Text("Show menu bar icon")
                                .font(Typography.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Toggle("", isOn: $showMenuBarIcon)
                                .labelsHidden()
                        }
                        .clickActionPointerCursor()
                    }
                }

                // Spoken Language
                SettingsSection {
                    SettingsSectionHeader(
                        icon: "globe", title: "Spoken Language",
                        subtitle: "Hint for the language you are speaking")

                    HStack {
                        Text("Speech language")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Menu {
                            Button("Auto-detect spoken language") { transcriptionLanguage = "auto" }
                            if !recentLanguageCodes.isEmpty {
                                Divider()
                                ForEach(recentLanguageCodes, id: \.self) { code in
                                    if let lang = Self.whisperLanguages.first(where: { $0.code == code }) {
                                        Button(lang.name) {
                                            transcriptionLanguage = code
                                            updateRecentLanguages(code: code)
                                        }
                                    }
                                }
                            }
                            Divider()
                            ForEach(Self.whisperLanguages, id: \.code) { lang in
                                Button(lang.name) {
                                    transcriptionLanguage = lang.code
                                    updateRecentLanguages(code: lang.code)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(displayName(for: transcriptionLanguage))
                                    .font(Typography.bodySmall)
                                    .foregroundStyle(Color.textPrimary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.border.opacity(0.45), lineWidth: 0.5)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .clickActionPointerCursor()
                    }

                    Text("This is a hint for transcription. It does not choose an output language and it does not translate the result.")
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 4)

                    Text("If this does not match the language you actually speak, the result can be inaccurate or even come back in the wrong language. Auto-detect is the safest default.")
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 4)

                    Text("Use a multilingual model for non-English dictation. Accuracy for languages like Hindi depends heavily on the model you selected.")
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 4)

                    Text("English-only models (.en) can only output English.")
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 4)
                }

                // Updates
                SettingsSection {
                    SettingsSectionHeader(
                        icon: "arrow.down.circle", title: "Updates",
                        subtitle: "SpeakType \(AppVersion.currentVersion)")

                    VStack(spacing: 16) {
                        HStack {
                            Text("Automatically check for updates")
                                .font(Typography.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Toggle("", isOn: $autoUpdate)
                                .labelsHidden()
                        }
                        .clickActionPointerCursor()

                        Button(action: {
                            Task {
                                await updateService.checkForUpdates()
                            }
                        }) {
                            HStack(spacing: 6) {
                                if updateService.isCheckingForUpdates {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12))
                                }
                                Text(
                                    updateService.isCheckingForUpdates
                                        ? "Checking..." : "Check for Updates"
                                )
                                .font(Typography.labelMedium)
                            }
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.thinMaterial, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.border.opacity(0.45), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.stPlain)
                        .disabled(updateService.isCheckingForUpdates)

                        Button(action: {
                            NSWorkspace.shared.open(UpdateConfiguration.releasesPageURL)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 12))
                                Text("Browse all releases…")
                                    .font(Typography.labelMedium)
                            }
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.stPlain)
                        .clickActionPointerCursor()

                        Text(
                            "Install the latest from “Check for Updates”, or download any published build (DMG) from GitHub."
                        )
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // License - Hidden (logic kept for future use)
                // SettingsSection {
                //     SettingsSectionHeader(
                //         icon: "key",
                //         title: "License",
                //         subtitle: licenseManager.isPro ? "Pro Active" : "Free Plan"
                //     )
                //
                //     if licenseManager.isPro {
                //         Button(action: { showDeactivateAlert = true }) {
                //             Text("Deactivate License")
                //                 .font(Typography.labelMedium)
                //                 .frame(maxWidth: .infinity)
                //         }
                //         .buttonStyle(.stSecondary)
                //     } else {
                //         Button(action: { showLicenseSheet = true }) {
                //             Text("Activate License")
                //                 .font(Typography.labelMedium)
                //                 .frame(maxWidth: .infinity)
                //         }
                //         .buttonStyle(.stPrimary)
                //     }
                // }
        }

        .sheet(isPresented: $showLicenseSheet) {
            LicenseView()
                .environmentObject(licenseManager)
        }
        .alert("Deactivate License", isPresented: $showDeactivateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Deactivate", role: .destructive) {
                Task { try? await licenseManager.deactivateLicense() }
            }
        } message: {
            Text("Are you sure you want to deactivate your Pro license?")
        }
    }

    private func displayName(for code: String) -> String {
        if code == "auto" { return "Auto-detect" }
        return Self.whisperLanguages.first(where: { $0.code == code })?.name ?? code
    }

    // All languages supported by Whisper, sorted alphabetically
    static let whisperLanguages: [(code: String, name: String)] = [
        ("af", "Afrikaans"), ("sq", "Albanian"), ("am", "Amharic"), ("ar", "Arabic"),
        ("hy", "Armenian"), ("as", "Assamese"), ("az", "Azerbaijani"), ("ba", "Bashkir"),
        ("eu", "Basque"), ("be", "Belarusian"), ("bn", "Bengali"), ("bs", "Bosnian"),
        ("br", "Breton"), ("bg", "Bulgarian"), ("yue", "Cantonese"), ("ca", "Catalan"),
        ("zh", "Chinese"), ("hr", "Croatian"), ("cs", "Czech"), ("da", "Danish"),
        ("nl", "Dutch"), ("en", "English"), ("et", "Estonian"), ("fo", "Faroese"),
        ("fi", "Finnish"), ("fr", "French"), ("gl", "Galician"), ("ka", "Georgian"),
        ("de", "German"), ("el", "Greek"), ("gu", "Gujarati"), ("ht", "Haitian Creole"),
        ("ha", "Hausa"), ("haw", "Hawaiian"), ("he", "Hebrew"), ("hi", "Hindi"),
        ("hu", "Hungarian"), ("is", "Icelandic"), ("id", "Indonesian"), ("it", "Italian"),
        ("ja", "Japanese"), ("jw", "Javanese"), ("kn", "Kannada"), ("kk", "Kazakh"),
        ("km", "Khmer"), ("ko", "Korean"), ("lo", "Lao"), ("la", "Latin"),
        ("lv", "Latvian"), ("ln", "Lingala"), ("lt", "Lithuanian"), ("lb", "Luxembourgish"),
        ("mk", "Macedonian"), ("mg", "Malagasy"), ("ms", "Malay"), ("ml", "Malayalam"),
        ("mt", "Maltese"), ("mi", "Maori"), ("mr", "Marathi"), ("mn", "Mongolian"),
        ("my", "Myanmar"), ("ne", "Nepali"), ("no", "Norwegian"), ("nn", "Nynorsk"),
        ("oc", "Occitan"), ("ps", "Pashto"), ("fa", "Persian"), ("pl", "Polish"),
        ("pt", "Portuguese"), ("pa", "Punjabi"), ("ro", "Romanian"), ("ru", "Russian"),
        ("sa", "Sanskrit"), ("sr", "Serbian"), ("sn", "Shona"), ("sd", "Sindhi"),
        ("si", "Sinhala"), ("sk", "Slovak"), ("sl", "Slovenian"), ("so", "Somali"),
        ("es", "Spanish"), ("su", "Sundanese"), ("sw", "Swahili"), ("sv", "Swedish"),
        ("tl", "Tagalog"), ("tg", "Tajik"), ("ta", "Tamil"), ("tt", "Tatar"),
        ("te", "Telugu"), ("th", "Thai"), ("bo", "Tibetan"), ("tr", "Turkish"),
        ("tk", "Turkmen"), ("uk", "Ukrainian"), ("ur", "Urdu"), ("uz", "Uzbek"),
        ("vi", "Vietnamese"), ("cy", "Welsh"), ("yi", "Yiddish"), ("yo", "Yoruba"),
    ]
}

// MARK: - Audio

struct AudioSettingsTab: View {
    @StateObject private var audioRecorder = AudioRecordingService.shared

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection {
                SettingsSectionHeader(
                    icon: "mic", title: "Input Device", subtitle: "Select your microphone")

                VStack(spacing: 12) {
                    if audioRecorder.availableDevices.isEmpty {
                        Text("No input devices found")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Color.textMuted)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(audioRecorder.availableDevices, id: \.uniqueID) { device in
                            DeviceRow(
                                name: device.localizedName,
                                isActive: audioRecorder.isRecording
                                    && audioRecorder.selectedDeviceId == device.uniqueID,
                                isSelected: audioRecorder.selectedDeviceId == device.uniqueID
                            )
                            .onTapGesture {
                                audioRecorder.selectedDeviceId = device.uniqueID
                            }
                        }
                    }
                }

                Button(action: { audioRecorder.fetchAvailableDevices() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Refresh Devices")
                            .font(Typography.labelMedium)
                    }
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.border.opacity(0.45), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.stPlain)
                .padding(.top, 8)
            }
        }
        .onAppear {
            audioRecorder.fetchAvailableDevices()
        }
    }
}

// MARK: - Permissions

struct PermissionsSettingsTab: View {
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var accessibilityStatus: Bool = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection {
                SettingsSectionHeader(
                    icon: "shield", title: "App Permissions",
                    subtitle: "Required for full functionality")

                VStack(spacing: 10) {
                    SettingsPermissionItem(
                        icon: "mic.fill",
                        color: Color.textSecondary,
                        title: "Microphone Access",
                        desc: "Record your voice for transcription",
                        isGranted: micStatus == .authorized,
                        action: { openSettings(for: "Privacy_Microphone") }
                    )

                    SettingsPermissionItem(
                        icon: "hand.raised.fill",
                        color: Color.textSecondary,
                        title: "Accessibility Access",
                        desc: "Paste transcribed text directly",
                        isGranted: accessibilityStatus,
                        action: {
                            ClipboardService.shared.requestAccessibilityPermission()
                            // System dialog handles opening Settings when user clicks "Open System Settings"
                        }
                    )
                }
            }
        }
        .onAppear {
            checkPermissions()
            startPolling()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkPermissions()
        }
    }

    private func checkPermissions() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityStatus = AXIsProcessTrusted()
    }

    private func openSettings(for pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Supporting Components

struct SettingsSectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.labelLarge)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
                    .stCompactUI()
            }

            Spacer()
        }
        .padding(.bottom, 16)
    }
}

struct SettingsSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .themedCard(padding: 24)
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct RadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.textPrimary : Color.textMuted.opacity(0.55),
                            lineWidth: isSelected ? 2 : 1.25
                        )
                        .frame(width: 20, height: 20)

                    if isSelected {
                        Circle()
                            .fill(Color.textPrimary)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(title)
                    .font(Typography.bodyMedium)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.bgSelected.opacity(0.85) : Color.clear)
            }
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.border.opacity(isSelected ? 0.4 : 0), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.stPlain)
    }
}

struct SettingsPermissionItem: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(Color.textMuted)
                .font(.system(size: 16))
                .frame(width: 32, height: 32)
                .background(Color.bgHover)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(desc)
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.textSecondary)
                    .font(.system(size: 20))
            } else {
                Button("Enable") {
                    action()
                }
                .font(Typography.labelSmall)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.border.opacity(0.45), lineWidth: 0.5)
                )
                .buttonStyle(.stPlain)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.border.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - Recording mode (custom pills — clearer active segment than system segmented control)

private struct RecordingModePicker: View {
    @Binding var recordingMode: Int

    var body: some View {
        HStack(spacing: 4) {
            modeSegment(tag: 0, title: "Hold to record")
            modeSegment(tag: 1, title: "Toggle")
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.bgHover.opacity(0.55))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.border.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func modeSegment(tag: Int, title: String) -> some View {
        let selected = recordingMode == tag
        return Button {
            recordingMode = tag
        } label: {
            Text(title)
                .font(Typography.labelMedium)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.textPrimary : Color.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.textPrimary.opacity(selected ? 0.12 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.stPlain)
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    var id: String { rawValue }
}
