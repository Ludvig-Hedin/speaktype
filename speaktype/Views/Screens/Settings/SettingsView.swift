import AppKit
import AVFoundation
import KeyboardShortcuts
import SwiftUI

// MARK: - Settings (responsive 2-column)

struct SettingsView: View {
    var body: some View {
        GeometryReader { geo in
            // Two columns once the content pane is wide enough; single column when narrow.
            let twoColumn = geo.size.width > 880

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings")
                        .font(Typography.displayLarge)
                        .appleTitleTracking()
                        .foregroundStyle(Color.textPrimary)

                    if twoColumn {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                ShortcutsSection()
                                SpokenLanguageSection()
                                InputDeviceSection()
                            }
                            .frame(maxWidth: .infinity, alignment: .top)

                            VStack(spacing: 16) {
                                GeneralBehaviorSection()
                                AppearanceSection()
                                UpdatesSection()
                                PermissionsSection()
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        VStack(spacing: 16) {
                            ShortcutsSection()
                            GeneralBehaviorSection()
                            SpokenLanguageSection()
                            InputDeviceSection()
                            AppearanceSection()
                            UpdatesSection()
                            PermissionsSection()
                        }
                    }

                    // Advanced / optional configuration — full width, at the bottom.
                    RemoteTranscriptionSettingsSection()
                    WritingPolishSettingsSection()
                }
                // Cap the reading width so sections never stretch too wide, and center it.
                .frame(maxWidth: 1040, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsSection: View {
    @AppStorage("selectedHotkey") private var selectedHotkey: HotkeyOption = .fn
    @AppStorage("recordingMode") private var recordingMode: Int = 0
    @State private var customShortcutDisplay = CustomShortcutStorage.displayString

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(
                icon: "command", title: "Shortcuts", subtitle: "Recording hotkey")

            VStack(spacing: 14) {
                HStack {
                    Text("Primary hotkey")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Menu {
                        Group {
                            Button(HotkeyOption.fn.displayName) { selectedHotkey = .fn }
                            Button(HotkeyOption.capsLock.displayName) { selectedHotkey = .capsLock }
                            Divider()
                            Button(HotkeyOption.leftCommand.displayName) { selectedHotkey = .leftCommand }
                            Button(HotkeyOption.rightCommand.displayName) { selectedHotkey = .rightCommand }
                            Divider()
                            Button(HotkeyOption.leftControl.displayName) { selectedHotkey = .leftControl }
                            Button(HotkeyOption.rightControl.displayName) { selectedHotkey = .rightControl }
                            Divider()
                            Button(HotkeyOption.leftOption.displayName) { selectedHotkey = .leftOption }
                            Button(HotkeyOption.rightOption.displayName) { selectedHotkey = .rightOption }
                            Divider()
                            Button(HotkeyOption.leftShift.displayName) { selectedHotkey = .leftShift }
                            Button(HotkeyOption.rightShift.displayName) { selectedHotkey = .rightShift }
                        }
                        Divider()
                        Group {
                            Button(HotkeyOption.f13.displayName) { selectedHotkey = .f13 }
                            Button(HotkeyOption.f14.displayName) { selectedHotkey = .f14 }
                            Button(HotkeyOption.f15.displayName) { selectedHotkey = .f15 }
                            Button(HotkeyOption.f16.displayName) { selectedHotkey = .f16 }
                            Button(HotkeyOption.f17.displayName) { selectedHotkey = .f17 }
                            Button(HotkeyOption.f18.displayName) { selectedHotkey = .f18 }
                            Button(HotkeyOption.f19.displayName) { selectedHotkey = .f19 }
                        }
                        Divider()
                        Button(HotkeyOption.custom.displayName) { selectedHotkey = .custom }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedHotkey == .custom && !customShortcutDisplay.isEmpty
                                ? customShortcutDisplay
                                : selectedHotkey.displayName)
                                .font(Typography.bodySmall)
                                .foregroundStyle(Color.textPrimary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textMuted)
                        }
                        .menuCapsule()
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .clickActionPointerCursor()
                }

                if selectedHotkey == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom shortcut")
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(Color.textPrimary)
                                Text("Click the badge to record")
                                    .font(Typography.captionSmall)
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer()
                            ShortcutRecorderView(onChange: {
                                customShortcutDisplay = CustomShortcutStorage.displayString
                            })
                            .frame(width: 160, height: 32)
                        }

                        Text("Needs at least one modifier (⌃ ⌥ ⇧ ⌘) unless using F13–F19.")
                            .font(Typography.captionSmall)
                            .foregroundStyle(Color.textMuted)
                    }
                    .padding(14)
                    .background(Color.bgHover.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Constants.UI.radiusSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.UI.radiusSmall, style: .continuous)
                            .strokeBorder(Color.border.opacity(0.5), lineWidth: 0.5)
                    )
                    .onAppear { customShortcutDisplay = CustomShortcutStorage.displayString }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recording mode")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        RecordingModePicker(recordingMode: $recordingMode)
                            .frame(maxWidth: 240)
                    }
                    Text(recordingMode == 0
                        ? "Hold the hotkey to record; release when done."
                        : "Press once to start, again to stop.")
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                        .stCompactUI()
                }
            }
        }
    }
}

// MARK: - General behavior

private struct GeneralBehaviorSection: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
    @AppStorage("showDockIcon") private var showDockIcon: Bool = false
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = true

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(icon: "macwindow", title: "General", subtitle: "App behavior")

            VStack(spacing: 14) {
                settingToggle(
                    "Launch at login",
                    help: "Start in the background at login so the hotkey is always ready.",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLoginService.setEnabled(newValue)
                }

                settingToggle(
                    "Run in background",
                    help: "Hide the Dock icon and run menu-bar-only. Reopen from the menu bar icon.",
                    isOn: Binding(get: { !showDockIcon }, set: { showDockIcon = !$0 })
                )
                .onChange(of: showDockIcon) { _, newValue in
                    if !newValue { showMenuBarIcon = true }
                    (NSApp.delegate as? AppDelegate)?.applyActivationPolicy()
                }

                VStack(spacing: 6) {
                    HStack {
                        Text("Show menu bar icon")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Toggle("", isOn: $showMenuBarIcon)
                            .labelsHidden()
                            .disabled(!showDockIcon)
                    }
                    .clickActionPointerCursor()

                    if !showDockIcon {
                        Text("Required while the Dock icon is hidden — the only way back in.")
                            .font(Typography.captionSmall)
                            .foregroundStyle(Color.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func settingToggle(_ title: String, help: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Toggle("", isOn: isOn).labelsHidden()
            }
            .clickActionPointerCursor()
            Text(help)
                .font(Typography.captionSmall)
                .foregroundStyle(Color.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Spoken language

struct SpokenLanguageSection: View {
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

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(icon: "globe", title: "Spoken language", subtitle: "Dictation hint")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Language")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Menu {
                        Button("Auto-detect") { transcriptionLanguage = "auto" }
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
                        .menuCapsule()
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .clickActionPointerCursor()
                }

                Text("Auto-detect is safest. Only set a language if you always dictate in it — a mismatch can garble the result. Use a multilingual model for non-English.")
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func displayName(for code: String) -> String {
        if code == "auto" { return "Auto-detect" }
        return Self.whisperLanguages.first(where: { $0.code == code })?.name ?? code
    }

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

// MARK: - Appearance

private struct AppearanceSection: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(icon: "paintpalette", title: "Appearance", subtitle: "Theme")

            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    RadioButton(
                        title: theme.rawValue,
                        isSelected: appTheme == theme,
                        action: { appTheme = theme }
                    )
                }
                Spacer()
            }
        }
    }
}

// MARK: - Updates

private struct UpdatesSection: View {
    @AppStorage("autoUpdate") private var autoUpdate = true
    @StateObject private var updateService = UpdateService.shared

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(
                icon: "arrow.down.circle", title: "Updates",
                subtitle: "SpeakType \(AppVersion.currentVersion)")

            VStack(spacing: 14) {
                HStack {
                    Text("Check automatically")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Toggle("", isOn: $autoUpdate).labelsHidden()
                }
                .clickActionPointerCursor()

                Button(action: { Task { await updateService.checkForUpdates() } }) {
                    HStack(spacing: 6) {
                        if updateService.isCheckingForUpdates {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 12))
                        }
                        Text(updateService.isCheckingForUpdates ? "Checking…" : "Check for updates")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.stSecondary)
                .disabled(updateService.isCheckingForUpdates)

                Button(action: { NSWorkspace.shared.open(UpdateConfiguration.releasesPageURL) }) {
                    Text("Browse all releases…")
                        .font(Typography.labelMedium)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.stPlain)
                .clickActionPointerCursor()
            }
        }
    }
}

// MARK: - Input device

private struct InputDeviceSection: View {
    @StateObject private var audioRecorder = AudioRecordingService.shared

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(icon: "mic", title: "Microphone", subtitle: "Input device")

            VStack(spacing: 10) {
                if audioRecorder.availableDevices.isEmpty {
                    Text("No input devices found")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ForEach(audioRecorder.availableDevices, id: \.uniqueID) { device in
                        DeviceRow(
                            name: device.localizedName,
                            isActive: audioRecorder.isRecording
                                && audioRecorder.selectedDeviceId == device.uniqueID,
                            isSelected: audioRecorder.selectedDeviceId == device.uniqueID
                        )
                        .onTapGesture { audioRecorder.selectedDeviceId = device.uniqueID }
                    }
                }

                Button(action: { audioRecorder.fetchAvailableDevices() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12))
                        Text("Refresh")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.stSecondary)
                .padding(.top, 4)
            }
        }
        .onAppear { audioRecorder.fetchAvailableDevices() }
    }
}

// MARK: - Permissions

private struct PermissionsSection: View {
    @ObservedObject private var permissions = PermissionService.shared

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(icon: "shield", title: "Permissions", subtitle: "Required access")

            VStack(spacing: 10) {
                SettingsPermissionItem(
                    icon: "mic.fill", color: Color.textSecondary,
                    title: "Microphone", desc: "Record your voice",
                    isGranted: permissions.isMicGranted,
                    action: { permissions.requestMicPermission() }
                )
                SettingsPermissionItem(
                    icon: "hand.raised.fill", color: Color.textSecondary,
                    title: "Accessibility", desc: "Paste text into any app",
                    isGranted: permissions.isAccessibilityGranted,
                    action: { permissions.requestAccessibilityPermission() }
                )
            }
        }
        .onAppear { permissions.startObserving() }
        .onDisappear { permissions.stopObserving() }
    }
}

// MARK: - Supporting Components

struct SettingsSectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
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
        .padding(.bottom, Constants.UI.rowGap)
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
        .themedCard(padding: Constants.UI.cardPadding)
    }
}

struct RadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentBlue : Color.textMuted.opacity(0.55),
                            lineWidth: isSelected ? 1.5 : 1.25
                        )
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle().fill(Color.accentBlue).frame(width: 9, height: 9)
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.textSecondary)
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
                .background(Color.bgSelected.opacity(0.7))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
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
                    .foregroundStyle(Color.accentSuccess)
                    .font(.system(size: 18))
            } else {
                Button("Enable") { action() }
                    .buttonStyle(.stAction)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: Constants.UI.radiusControl, style: .continuous)
                .fill(Color.bgHover.opacity(0.5))
        }
        .clipShape(RoundedRectangle(cornerRadius: Constants.UI.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Constants.UI.radiusControl, style: .continuous)
                .strokeBorder(Color.border.opacity(0.45), lineWidth: 0.5)
        )
    }
}

// MARK: - Recording mode (custom pills — clearer active segment than system segmented control)

private struct RecordingModePicker: View {
    @Binding var recordingMode: Int

    var body: some View {
        HStack(spacing: 4) {
            modeSegment(tag: 0, title: "Hold")
            modeSegment(tag: 1, title: "Toggle")
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(Color.bgHover.opacity(0.55)))
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
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background {
                    if selected {
                        Capsule(style: .continuous).fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.textPrimary.opacity(selected ? 0.1 : 0), lineWidth: 0.5)
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

// MARK: - Shared control chrome

/// Capsule chrome for `Menu` labels — matches the `.stSecondary` button so pickers and
/// buttons share one vocabulary. (Menu labels can't take a ButtonStyle, hence the modifier.)
struct MenuCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.border.opacity(0.5), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Menu-label chrome matching `.stSecondary`. Shared across settings sections.
    func menuCapsule() -> some View { modifier(MenuCapsule()) }
}
