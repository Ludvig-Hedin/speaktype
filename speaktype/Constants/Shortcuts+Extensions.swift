import Foundation
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleMeeting = Self("toggleMeeting", default: .init(.m, modifiers: [.control, .option]))
    static let toggleRecord = Self("toggleRecord", default: .init(.space, modifiers: [.control, .option]))
}

extension Notification.Name {
    static let meetingToggleRequested = Self("meetingToggleRequested")
    static let meetingReplaceMessage = Self("meetingReplaceMessage")
    static let meetingFinished = Self("meetingFinished")
    static let hotkeyTriggered = Notification.Name("hotkeyTriggered") // Legacy, can be removed
    static let recordingStartRequested = Notification.Name("recordingStartRequested")
    static let recordingStopRequested = Notification.Name("recordingStopRequested")
    static let recordingEscapeRequested = Notification.Name("recordingEscapeRequested")
    static let recordingCancelRequested = Notification.Name("recordingCancelRequested")
    /// Show a short message in the recorder panel. userInfo["message"]: String.
    static let recordingShowMessageRequested = Notification.Name("recordingShowMessageRequested")
    /// The text really landed in the target app (drives the recorder's checkmark).
    static let recordingPasteSucceeded = Notification.Name("recordingPasteSucceeded")
    #if DEBUG
    static let recorderDemoRequested = Notification.Name("recorderDemoRequested")
    static let recorderDemoShowPanel = Notification.Name("recorderDemoShowPanel")
    #endif
}

extension HotkeyOption {
    func conflicts(with shortcut: KeyboardShortcuts.Shortcut?) -> Bool {
        guard let shortcut, usesKeyDownEvents else { return false }
        if self == .custom {
            return shortcut.carbonKeyCode == CustomShortcutStorage.keyCode
                && Int(shortcut.modifiers.intersection(CustomShortcutStorage.relevantModifiers).rawValue) == CustomShortcutStorage.modifiers
        }
        return shortcut.carbonKeyCode == Int(keyCode)
    }

    var conflictsWithMeeting: Bool { conflicts(with: KeyboardShortcuts.getShortcut(for: .toggleMeeting)) }
}
