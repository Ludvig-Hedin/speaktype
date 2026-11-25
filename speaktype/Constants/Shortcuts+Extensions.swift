import Foundation
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleMeeting = Self("toggleMeeting", default: .init(.m, modifiers: [.control, .option]))
    static let toggleRecord = Self("toggleRecord", default: .init(.space, modifiers: [.control, .option]))
}

extension Notification.Name {
    static let meetingToggleRequested = Self("meetingToggleRequested")
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
