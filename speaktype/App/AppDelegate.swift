import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var miniRecorderController: MiniRecorderWindowController?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var hotkeyEventTap: CFMachPort?
    private var hotkeyEventTapSource: CFRunLoopSource?
    var isHotkeyPressed = false
    private var cancellables = Set<AnyCancellable>()
    private var lastHandledHotkeyTimestamp: TimeInterval = 0
    private var lastHandledHotkeyPressedState = false
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyUpMonitor: Any?
    private weak var updateWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register background-mode defaults before any UI is built so the activation policy
        // (Dock icon vs. background agent) is correct on the very first frame — no Dock flash.
        UserDefaults.standard.register(defaults: [
            "showDockIcon": false,
            "launchAtLogin": true,
        ])

        // Reachability invariant: never leave the app with no Dock icon AND no menu bar icon,
        // or it becomes impossible to reopen. Covers existing users who had disabled the menu
        // bar icon before background mode existed.
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        let showMenuBar = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        if !showDock && !showMenuBar {
            UserDefaults.standard.set(true, forKey: "showMenuBarIcon")
        }

        applyActivationPolicy()

        // Revert to a background agent when the user closes the dashboard window.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        miniRecorderController = MiniRecorderWindowController()

        WritingPolishUserDefaults.registerDefaults(in: .standard)
        // Transcription defaults to on-device only (privacy-safe) until the user opts into cloud.
        TranscriptionModeUserDefaults.registerDefaults()
        // Start network monitoring early so `auto` mode can pre-decide before the first dictation.
        _ = NetworkReachability.shared

        // Register defaults so hotkeyEnabled is true when first launched
        UserDefaults.standard.register(defaults: ["hotkeyEnabled": true])

        // Keep the macOS login-item registration in sync with the user's preference.
        LaunchAtLoginService.syncWithPreference()

        // Setup dynamic hotkey monitoring based on user selection
        setupHotkeyMonitoring()

        checkForUpdatesOnLaunch()

        UpdateService.shared.showUpdateWindowPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showUpdateWindow()
            }
            .store(in: &cancellables)

        // Scan disk for Core ML models, sync `selectedModelVariant`, then warm WhisperKit so the first hotkey is responsive.
        Task(priority: .userInitiated) {
            await ModelDownloadService.shared.refreshDownloadedModels()
            await SelectedModelPreference.preloadSelectedModelIfDownloaded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Background agent / Dock icon

    /// Apply the Dock-icon policy: run as a background agent (`.accessory`, no Dock icon,
    /// no ⌘-Tab entry) unless the user opted to show the Dock icon — or onboarding hasn't
    /// been completed yet, in which case a normal focusable window is required.
    func applyActivationPolicy() {
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        let onboardingDone = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let policy: NSApplication.ActivationPolicy =
            (showDock || !onboardingDone) ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    /// Bring the app forward with a Dock presence so an opened window is focusable.
    /// Called right before the dashboard window is opened from the menu bar.
    func presentDashboardForeground() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        // Only relevant when running as a background agent.
        guard !UserDefaults.standard.bool(forKey: "showDockIcon") else { return }

        // After the window finishes closing, drop back to a background agent if no
        // standard app window remains visible.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.hasVisibleStandardWindow() else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// A "standard" window is any visible titled window (dashboard, onboarding, or the update
    /// sheet) — but not the borderless mini-recorder panel or the menu-bar popover. The update
    /// window is intentionally counted so the Dock icon stays present while it is on screen.
    private func hasVisibleStandardWindow() -> Bool {
        for window in NSApp.windows {
            guard window.isVisible else { continue }
            if window is NSPanel { continue }
            if window.styleMask.contains(.titled) {
                return true
            }
        }
        return false
    }

    // MARK: - Public API (called from MenuBarDashboardView)

    func startRecordingFromMenuBar() {
        miniRecorderController?.startRecording()
    }

    // MARK: - Emoji Picker Suppression

    private func suppressEmojiPicker() {
        let dummyKeyCode: CGKeyCode = 0x50  // F19 (80)
        let eventSource = CGEventSource(stateID: .hidSystemState)

        if let keyDown = CGEvent(
            keyboardEventSource: eventSource, virtualKey: dummyKeyCode, keyDown: true)
        {
            keyDown.post(tap: .cghidEventTap)
        }

        if let keyUp = CGEvent(
            keyboardEventSource: eventSource, virtualKey: dummyKeyCode, keyDown: false)
        {
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Hotkey Monitoring

    private func setupHotkeyMonitoring() {
        setupSuppressingHotkeyEventTap()

        // flagsChanged: handles modifier-only keys (Fn/Globe, ⌘, ⌃, ⌥, ⇧, Caps Lock)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            self?.handleFlagsChangedEvent(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            self?.handleFlagsChangedEvent(event)
            return event
        }

        // keyDown: F-keys, custom combos, and recording cancellation
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handleKeyDownEvent(event)
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handleKeyDownEvent(event)
            return event
        }

        // keyUp: stop recording in hold-mode for F-keys and custom combos
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) {
            [weak self] event in
            self?.handleKeyUpEvent(event)
        }
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) {
            [weak self] event in
            self?.handleKeyUpEvent(event)
            return event
        }
    }

    private func setupSuppressingHotkeyEventTap() {
        guard hotkeyEventTap == nil else { return }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            return appDelegate.handleHotkeyEventTap(type: type, event: event)
        }

        guard
            let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            print("Failed to create suppressing hotkey event tap")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        hotkeyEventTap = eventTap
        hotkeyEventTapSource = runLoopSource
    }

    // MARK: - Event Tap (CGEvent level — only for Fn/Globe suppression)

    private func handleHotkeyEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let hotkeyEventTap {
                CGEvent.tapEnable(tap: hotkeyEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let currentHotkey = getSelectedHotkey()
        guard currentHotkey == .fn else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == currentHotkey.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        let isPressed = event.flags.contains(.maskSecondaryFn)
        DispatchQueue.main.async { [weak self] in
            self?.handleHotkeyStateChange(isPressed: isPressed)
        }

        // Suppress the Fn flagsChanged event so terminal apps do not receive raw CSI sequences.
        return nil
    }

    // MARK: - flagsChanged handler (modifier-only keys)

    private func handleFlagsChangedEvent(_ event: NSEvent) {
        let currentHotkey = getSelectedHotkey()
        guard !currentHotkey.usesKeyDownEvents else { return }
        guard event.keyCode == currentHotkey.keyCode else { return }

        // Caps Lock reports the LOCK toggle state, not a physical press/release: each tap
        // flips the LED and only one flagsChanged arrives per tap (there is no separate
        // "key up"). Drive recording as a pure toggle — start when idle, stop when recording —
        // so it behaves sanely in either recording mode and never strands a session the way a
        // press/release state machine would (the release event simply never comes).
        if currentHotkey == .capsLock {
            handleCapsLockToggle()
            return
        }

        let isPressed: Bool
        switch currentHotkey {
        case .leftShift, .rightShift:
            isPressed = event.modifierFlags.contains(.shift)
        default:
            isPressed = event.modifierFlags.contains(currentHotkey.modifierFlag)
        }

        handleHotkeyStateChange(isPressed: isPressed)
    }

    /// Toggle recording for the Caps Lock hotkey. See `handleFlagsChangedEvent` for why Caps
    /// Lock cannot use the normal press/release path.
    private func handleCapsLockToggle() {
        guard UserDefaults.standard.bool(forKey: "hotkeyEnabled") else { return }
        // Both the global and local flags monitors fire for a single physical tap; the 50ms
        // dedup window collapses them into one toggle.
        guard !isDuplicateHotkeyEvent(isPressed: true) else { return }

        if AudioRecordingService.shared.isRecording {
            miniRecorderController?.stopRecording()
        } else {
            miniRecorderController?.startRecording()
        }
    }

    // MARK: - keyDown handler (F-keys, custom combos, cancellation)

    private func handleKeyDownEvent(_ event: NSEvent) {
        let currentHotkey = getSelectedHotkey()

        // For F-keys / custom combos: first keyDown (not repeat) triggers recording
        if currentHotkey.usesKeyDownEvents && !event.isARepeat {
            if isKeyDownMatchingHotkey(event: event, hotkey: currentHotkey) {
                handleHotkeyStateChange(isPressed: true)
                return
            }
        }

        // Cancel hold-mode recording if another key is pressed
        // (only for modifier-only hotkeys, since keyDown IS the trigger for the others)
        guard isHotkeyPressed else { return }
        guard UserDefaults.standard.integer(forKey: "recordingMode") == 0 else { return }
        guard !event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return }
        guard !currentHotkey.usesKeyDownEvents else { return }
        guard event.keyCode != currentHotkey.keyCode else { return }

        isHotkeyPressed = false
        miniRecorderController?.cancelRecording()
    }

    // MARK: - keyUp handler (hold-mode stop for F-keys / custom combos)

    private func handleKeyUpEvent(_ event: NSEvent) {
        let currentHotkey = getSelectedHotkey()
        guard currentHotkey.usesKeyDownEvents else { return }
        guard isKeyUpMatchingHotkey(event: event, hotkey: currentHotkey) else { return }
        handleHotkeyStateChange(isPressed: false)
    }

    // MARK: - Hotkey matching helpers

    private func isKeyDownMatchingHotkey(event: NSEvent, hotkey: HotkeyOption) -> Bool {
        switch hotkey {
        case .f13, .f14, .f15, .f16, .f17, .f18, .f19:
            return event.keyCode == hotkey.keyCode

        case .custom:
            guard CustomShortcutStorage.isSet else { return false }
            let storedKeyCode = CustomShortcutStorage.keyCode
            let storedModifiers = CustomShortcutStorage.modifiers
            // Mask to the same canonical modifier set used when the shortcut was recorded
            // (excludes Caps Lock / Fn / numeric-pad / Help), so an incidental bit doesn't
            // make a valid combo silently fail to match.
            let eventModifiers = Int(
                event.modifierFlags.intersection(CustomShortcutStorage.relevantModifiers).rawValue
            )
            return Int(event.keyCode) == storedKeyCode && eventModifiers == storedModifiers

        default:
            return false
        }
    }

    /// keyUp matching deliberately ignores modifier state. When the user releases a custom
    /// combo, the modifier keys often lift a few milliseconds before the main key, so by the
    /// time the main key's keyUp arrives `modifierFlags` no longer matches what was stored.
    /// The keyCode alone uniquely identifies the hotkey being released, which is all the
    /// hold-mode stop path needs.
    private func isKeyUpMatchingHotkey(event: NSEvent, hotkey: HotkeyOption) -> Bool {
        switch hotkey {
        case .f13, .f14, .f15, .f16, .f17, .f18, .f19:
            return event.keyCode == hotkey.keyCode

        case .custom:
            guard CustomShortcutStorage.isSet else { return false }
            return Int(event.keyCode) == CustomShortcutStorage.keyCode

        default:
            return false
        }
    }

    // MARK: - Recording state machine

    private func handleHotkeyStateChange(isPressed: Bool) {
        // Respect the enabled/disabled toggle
        guard UserDefaults.standard.bool(forKey: "hotkeyEnabled") else { return }
        guard !isDuplicateHotkeyEvent(isPressed: isPressed) else { return }

        let currentHotkey = getSelectedHotkey()
        if isPressed && !isHotkeyPressed {
            isHotkeyPressed = true

            if currentHotkey == .fn {
                suppressEmojiPicker()
            }

            let recordingMode = UserDefaults.standard.integer(forKey: "recordingMode")
            if recordingMode == 1 {
                if AudioRecordingService.shared.isRecording {
                    miniRecorderController?.stopRecording()
                } else {
                    miniRecorderController?.startRecording()
                }
            } else {
                miniRecorderController?.startRecording()
            }
        } else if !isPressed && isHotkeyPressed {
            isHotkeyPressed = false

            let recordingMode = UserDefaults.standard.integer(forKey: "recordingMode")
            if recordingMode == 0 {
                miniRecorderController?.stopRecording()
            }
        }
    }

    private func isDuplicateHotkeyEvent(isPressed: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let isDuplicate =
            abs(now - lastHandledHotkeyTimestamp) < 0.05
            && lastHandledHotkeyPressedState == isPressed

        lastHandledHotkeyTimestamp = now
        lastHandledHotkeyPressedState = isPressed
        return isDuplicate
    }

    // MARK: - Hotkey selection

    private func getSelectedHotkey() -> HotkeyOption {
        // Migration: honour legacy useFnKey setting
        if UserDefaults.standard.object(forKey: "useFnKey") != nil {
            let useFnKey = UserDefaults.standard.bool(forKey: "useFnKey")
            if useFnKey {
                UserDefaults.standard.set(HotkeyOption.fn.rawValue, forKey: "selectedHotkey")
                UserDefaults.standard.removeObject(forKey: "useFnKey")
                return .fn
            }
        }

        if let rawValue = UserDefaults.standard.string(forKey: "selectedHotkey"),
           let option = HotkeyOption(rawValue: rawValue)
        {
            return option
        }

        return .fn
    }

    // MARK: - Update Checking

    private func checkForUpdatesOnLaunch() {
        let updateService = UpdateService.shared
        let autoUpdate = UserDefaults.standard.bool(forKey: "autoUpdate")
        guard autoUpdate && updateService.shouldCheckForUpdates() else { return }

        Task {
            await updateService.checkForUpdates(silent: true)
        }
    }

    private func showUpdateWindow() {
        guard let update = UpdateService.shared.availableUpdate else { return }

        if let existing = updateWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let updateSheetView = UpdateSheet(update: update)
        let hostingController = NSHostingController(rootView: updateSheetView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Software Update"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.isMovableByWindowBackground = true
        updateWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
