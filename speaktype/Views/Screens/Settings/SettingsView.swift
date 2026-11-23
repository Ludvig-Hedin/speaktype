import AppKit
import AVFoundation
import KeyboardShortcuts
import SwiftUI

// MARK: - Settings (one centered column, grouped like System Settings / Linear)

struct SettingsView: View {
    var body: some View {
        PageScaffold(title: "Settings", spacing: 16) {
            ShortcutsSection()
            GeneralBehaviorSection()
            SpokenLanguageSection()
            InputDeviceSection()
            AppearanceSection()
            UpdatesSection()
            PermissionsSection()

            // Advanced / optional configuration, at the bottom.
            RemoteTranscriptionSettingsSection()
            WritingPolishSettingsSection()
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
            SettingsSectionHeader(title: "Shortcuts")

            VStack(spacing: 0) {
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
                    .appMenuStyle()
                    .fixedSize()
                    .clickActionPointerCursor()
                }
                .settingsRowPadding()

                if selectedHotkey == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom shortcut")
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(Color.textPrimary)
                                Text("Click the badge to record")
                                    .font(Typography.caption)
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer()
                            ShortcutRecorderView(onChange: {
                                customShortcutDisplay = CustomShortcutStorage.displayString
                            })
                            .frame(width: 160, height: 32)
                        }

                        Text("Needs at least one modifier (⌃ ⌥ ⇧ ⌘) unless using F13–F19.")
                            .font(Typography.caption)
                            .foregroundStyle(Color.textMuted)
                    }
                    .padding(.bottom, 11)
                    .onAppear { customShortcutDisplay = CustomShortcutStorage.displayString }
                }

                RowDivider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Recording mode")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        RecordingModePicker(recordingMode: $recordingMode)
                            .frame(width: 160)
                    }
                    Text(recordingMode == 0
                        ? "Hold the hotkey to record; release when done."
                        : "Press once to start, again to stop.")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textMuted)
                }
                .settingsRowPadding()
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
            SettingsSectionHeader(title: "General")

            VStack(spacing: 0) {
                settingToggle(
                    "Launch at login",
                    help: "Start in the background at login so the hotkey is always ready.",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLoginService.setEnabled(newValue)
                }

                RowDivider()

                settingToggle(
                    "Run in background",
                    help: "Hide the Dock icon and run menu-bar-only. Reopen from the menu bar icon.",
                    isOn: Binding(get: { !showDockIcon }, set: { showDockIcon = !$0 })
                )
                .onChange(of: showDockIcon) { _, newValue in
                    if !newValue { showMenuBarIcon = true }
                    (NSApp.delegate as? AppDelegate)?.applyActivationPolicy()
                }

                RowDivider()

                settingToggle(
                    "Show menu bar icon",
                    help: showDockIcon
                        ? nil : "Required while the Dock icon is hidden — the only way back in.",
                    isOn: $showMenuBarIcon
                )
                .disabled(!showDockIcon)
            }
        }
    }

    private func settingToggle(_ title: String, help: String?, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                if let help {
                    Text(help)
                        .font(Typography.caption)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn).labelsHidden()
        }
        .settingsRowPadding()
        .clickActionPointerCursor()
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
            SettingsSectionHeader(title: "Spoken language")

            VStack(alignment: .leading, spacing: 4) {
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
                    .appMenuStyle()
                    .fixedSize()
                    .clickActionPointerCursor()
                }

                Text("Auto-detect is safest. Only set a language if you always dictate in it — a mismatch can garble the result. Use a multilingual model for non-English.")
                    .font(Typography.caption)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsRowPadding()
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
            SettingsSectionHeader(title: "Appearance")

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
            .padding(.vertical, 5)
        }
    }
}

// MARK: - Updates

private struct UpdatesSection: View {
    @AppStorage("autoUpdate") private var autoUpdate = true
    @StateObject private var updateService = UpdateService.shared

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(title: "Updates")

            VStack(spacing: 0) {
                HStack {
                    Text("Check automatically")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Toggle("", isOn: $autoUpdate).labelsHidden()
                }
                .settingsRowPadding()
                .clickActionPointerCursor()

                RowDivider()

                HStack(spacing: 12) {
                    Text("SpeakType \(AppVersion.currentVersion)")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button(action: { NSWorkspace.shared.open(UpdateConfiguration.releasesPageURL) }) {
                        Text("Browse all releases…")
                            .font(Typography.labelMedium)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.stPlain)
                    .clickActionPointerCursor()

                    Button(action: { Task { await updateService.checkForUpdates() } }) {
                        HStack(spacing: 6) {
                            if updateService.isCheckingForUpdates {
                                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                            }
                            Text(updateService.isCheckingForUpdates ? "Checking…" : "Check for updates")
                        }
                    }
                    .buttonStyle(.stSecondary)
                    .disabled(updateService.isCheckingForUpdates)
                }
                .settingsRowPadding()
            }
        }
    }
}

// MARK: - Input device

private struct InputDeviceSection: View {
    @StateObject private var audioRecorder = AudioRecordingService.shared

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(title: "Microphone")

            VStack(spacing: 0) {
                if audioRecorder.availableDevices.isEmpty {
                    Text("No input devices found")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsRowPadding()
                } else {
                    ForEach(audioRecorder.availableDevices, id: \.uniqueID) { device in
                        DeviceListRow(
                            name: device.localizedName,
                            isActive: audioRecorder.isRecording
                                && audioRecorder.selectedDeviceId == device.uniqueID,
                            isSelected: audioRecorder.selectedDeviceId == device.uniqueID,
                            action: { audioRecorder.selectedDeviceId = device.uniqueID }
                        )
                        RowDivider()
                    }
                }

                HStack {
                    Button(action: { audioRecorder.fetchAvailableDevices() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11))
                            Text("Refresh")
                        }
                        .font(Typography.labelMedium)
                        .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.stPlain)
                    .clickActionPointerCursor()
                    Spacer()
                }
                .padding(.vertical, 11)
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
            SettingsSectionHeader(title: "Permissions")

            VStack(spacing: 0) {
                SettingsPermissionItem(
                    icon: "mic.fill", color: Color.textSecondary,
                    title: "Microphone", desc: "Record your voice",
                    isGranted: permissions.isMicGranted,
                    action: { permissions.requestMicPermission() }
                )
                RowDivider()
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
    let title: String
    var subtitle: String? = nil

    /// `icon` is accepted for older call sites but no longer drawn: section titles stay text-only.
    init(icon: String? = nil, title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Typography.headlineSmall)
                .foregroundStyle(Color.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Constants.UI.space2)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.UI.cardPadding)
        .padding(.top, 18)
        .padding(.bottom, 9)
        .themedCard(padding: 0)
        // Settings rows are switches, like System Settings — not checkboxes.
        .toggleStyle(.switch)
    }
}

extension View {
    /// Vertical rhythm for one row inside a grouped settings list.
    func settingsRowPadding() -> some View {
        padding(.vertical, 11)
    }

    /// Menus in settings: render our label as-is (no flattened icon, no second chevron).
    func appMenuStyle() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
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
                            Color.textMuted.opacity(0.55),
                            lineWidth: isSelected ? 1.5 : 1.25
                        )
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle().fill(Color.accentBlue).frame(width: 8, height: 8)
                    }
                }

                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 8)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(desc)
                    .font(Typography.caption)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentSuccess)
                    .font(.system(size: 16))
            } else {
                Button("Enable") { action() }
                    .buttonStyle(.stAction)
            }
        }
        .settingsRowPadding()
    }
}

/// One microphone in the Microphone list: plain row, radio on the left, no card.
private struct DeviceListRow: View {
    let name: String
    let isActive: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.textMuted.opacity(0.55), lineWidth: isSelected ? 1.5 : 1.25)
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle().fill(Color.accentBlue).frame(width: 8, height: 8)
                    }
                }
                Text(name)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(isSelected || isHovered ? Color.textPrimary : Color.textSecondary)
                Spacer()
                if isActive {
                    Text("Active")
                        .font(Typography.labelSmall)
                        .foregroundStyle(Color.accentSuccess)
                }
            }
            .settingsRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.stPlain)
        .clickActionPointerCursor()
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recording mode (compact two-segment control)

private struct RecordingModePicker: View {
    @Binding var recordingMode: Int

    var body: some View {
        HStack(spacing: 2) {
            modeSegment(tag: 0, title: "Hold")
            modeSegment(tag: 1, title: "Toggle")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Constants.UI.radiusSmall, style: .continuous)
                .fill(Color.bgHover)
        )
    }

    private func modeSegment(tag: Int, title: String) -> some View {
        let selected = recordingMode == tag
        return Button {
            recordingMode = tag
        } label: {
            Text(title)
                .font(Typography.labelMedium)
                .foregroundStyle(selected ? Color.textPrimary : Color.textMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: Constants.UI.radiusSmall - 2, style: .continuous)
                            .fill(Color.segmentSelected)
                            .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                    }
                }
                .contentShape(Rectangle())
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
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .controlChrome()
    }
}

extension View {
    /// Menu-label chrome matching `.stSecondary`. Shared across settings sections.
    func menuCapsule() -> some View { modifier(MenuCapsule()) }
}
