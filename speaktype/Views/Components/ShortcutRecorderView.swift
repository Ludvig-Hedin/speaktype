import AppKit
import SwiftUI

// MARK: - UserDefaults keys for custom shortcut

enum CustomShortcutStorage {
    static let keyCodeKey = "customShortcutKeyCode"
    static let modifiersKey = "customShortcutModifiers"
    static let notSet = -1

    static var keyCode: Int {
        get {
            guard let val = UserDefaults.standard.object(forKey: keyCodeKey) as? Int else { return notSet }
            return val
        }
        set { UserDefaults.standard.set(newValue, forKey: keyCodeKey) }
    }

    static var modifiers: Int {
        get { UserDefaults.standard.integer(forKey: modifiersKey) }
        set { UserDefaults.standard.set(newValue, forKey: modifiersKey) }
    }

    static var isSet: Bool { keyCode != notSet }

    /// The only modifier flags considered part of a custom shortcut. Incidental bits
    /// (Caps Lock, Fn, numeric pad, Help) are deliberately excluded so a combo recorded
    /// with — say — Caps Lock off still matches when Caps Lock is later toggled on.
    /// Record-time (ShortcutRecorderView) and match-time (AppDelegate) MUST use this same
    /// mask, or the stored and live modifier sets can silently diverge and the combo dies.
    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    static var displayString: String {
        guard isSet else { return "" }
        return formatShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    static func formatShortcut(keyCode: Int, modifiers: Int) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(virtualKeyName(UInt16(keyCode)))
        return parts.joined()
    }

    static func virtualKeyName(_ code: UInt16) -> String {
        switch Int(code) {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "Esc"
        case 122: return "F1";  case 120: return "F2";  case 99:  return "F3"
        case 118: return "F4";  case 96:  return "F5";  case 97:  return "F6"
        case 98:  return "F7";  case 100: return "F8";  case 101: return "F9"
        case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
        case 105: return "F13"; case 107: return "F14"; case 113: return "F15"
        case 106: return "F16"; case 64:  return "F17"; case 79:  return "F18"
        case 80:  return "F19"
        case 0:  return "A"; case 11: return "B"; case 8:  return "C"
        case 2:  return "D"; case 14: return "E"; case 3:  return "F"
        case 5:  return "G"; case 4:  return "H"; case 34: return "I"
        case 38: return "J"; case 40: return "K"; case 37: return "L"
        case 46: return "M"; case 45: return "N"; case 31: return "O"
        case 35: return "P"; case 12: return "Q"; case 15: return "R"
        case 1:  return "S"; case 17: return "T"; case 32: return "U"
        case 9:  return "V"; case 13: return "W"; case 7:  return "X"
        case 16: return "Y"; case 6:  return "Z"
        case 29: return "0"; case 18: return "1"; case 19: return "2"
        case 20: return "3"; case 21: return "4"; case 23: return "5"
        case 22: return "6"; case 26: return "7"; case 28: return "8"
        case 25: return "9"
        case 27: return "-"; case 24: return "="; case 33: return "["
        case 30: return "]"; case 41: return ";"; case 39: return "'"
        case 43: return ","; case 47: return "."; case 44: return "/"
        case 42: return "\\"
        default: return "Key\(code)"
        }
    }
}

// MARK: - SwiftUI wrapper

/// A badge-style control the user clicks to record a keyboard shortcut.
/// Reads/writes directly to CustomShortcutStorage (UserDefaults).
struct ShortcutRecorderView: NSViewRepresentable {
    /// Called when the recorded shortcut changes so callers can react
    var onChange: (() -> Void)?

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        // Re-sync display whenever SwiftUI re-renders (e.g. after external change)
        if !nsView.isRecording {
            nsView.refreshDisplay()
        }
    }
}

// MARK: - NSView implementation

final class ShortcutRecorderNSView: NSView {
    var onChange: (() -> Void)?
    private(set) var isRecording = false

    /// Local key-event monitor, active only while recording.
    private var eventMonitor: Any?

    private let badge = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "✕", target: nil, action: nil)

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    // MARK: Setup

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8

        // Badge label
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        badge.alignment = .center
        badge.isEditable = false
        badge.isSelectable = false
        badge.drawsBackground = false
        badge.isBordered = false
        addSubview(badge)

        // Clear button (×)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 10)
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        clearButton.isHidden = true
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 4),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)

        refreshDisplay()
    }

    // MARK: Display

    func refreshDisplay() {
        if isRecording {
            badge.stringValue = "Type shortcut…"
            badge.textColor = .controlAccentColor
            clearButton.isHidden = true
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 1.5
        } else if CustomShortcutStorage.isSet {
            badge.stringValue = CustomShortcutStorage.displayString
            badge.textColor = .labelColor
            clearButton.isHidden = false
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.15).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
        } else {
            badge.stringValue = "Click to record"
            badge.textColor = .secondaryLabelColor
            clearButton.isHidden = true
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
            layer?.borderWidth = 1
        }
    }

    // MARK: Actions

    @objc private func handleClick() {
        if isRecording {
            stopRecording(save: false)
        } else {
            startRecording()
        }
    }

    @objc private func clearShortcut() {
        CustomShortcutStorage.keyCode = CustomShortcutStorage.notSet
        CustomShortcutStorage.modifiers = 0
        refreshDisplay()
        onChange?()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        window?.makeFirstResponder(self)

        // Capture via a local event monitor rather than relying on first-responder routing,
        // which is unreliable for a raw NSView hosted inside SwiftUI. The monitor swallows
        // the keystroke (returns nil) so it isn't also delivered elsewhere while recording.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            return self.handleRecordingKeyDown(event) ? nil : event
        }

        refreshDisplay()
    }

    private func stopRecording(save: Bool) {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        refreshDisplay()
    }

    // MARK: Key capture

    override var acceptsFirstResponder: Bool { true }

    /// Handles a key event while recording. Returns `true` if the event was consumed
    /// (recorded a shortcut, cleared it, cancelled, or is being ignored mid-capture).
    @discardableResult
    private func handleRecordingKeyDown(_ event: NSEvent) -> Bool {
        // Escape → cancel
        if event.keyCode == 53 {
            stopRecording(save: false)
            return true
        }

        // Delete with no modifiers → clear stored shortcut
        if event.keyCode == 51,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            clearShortcut()
            stopRecording(save: false)
            return true
        }

        // Disallow modifier-only keys as the "key" (those are offered via HotkeyOption).
        // Swallow but keep recording so the user can complete the combo.
        let modifierOnlyCodes: [UInt16] = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierOnlyCodes.contains(event.keyCode) { return true }

        let maskedModifiers = event.modifierFlags.intersection(CustomShortcutStorage.relevantModifiers)
        let isFKey = Self.functionKeyCodes.contains(event.keyCode)

        // Require at least one modifier unless it's an F-key. A bare key would hijack that
        // key system-wide, so we swallow it and keep waiting for a valid combo.
        guard !maskedModifiers.isEmpty || isFKey else { return true }

        CustomShortcutStorage.keyCode = Int(event.keyCode)
        CustomShortcutStorage.modifiers = Int(maskedModifiers.rawValue)
        onChange?()
        stopRecording(save: true)
        return true
    }

    override func keyDown(with event: NSEvent) {
        // Fallback path if the event reaches the responder chain directly.
        if isRecording, handleRecordingKeyDown(event) { return }
        super.keyDown(with: event)
    }

    // MARK: Helpers

    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1–F12
        105, 107, 113, 106, 64, 79, 80                           // F13–F19
    ]
}
