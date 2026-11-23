import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class KeyboardFocusVisibility: ObservableObject {
    @Published private(set) var isVisible = false
    private var eventMonitor: Any?

    func startMonitoring() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return event
        }
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    func hide() {
        if isVisible { isVisible = false }
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .keyDown else {
            hide()
            return
        }
        guard !isVisible, let window = event.window ?? NSApp.keyWindow,
              event.modifierFlags.isDisjoint(with: [.command, .control, .option])
        else { return }

        switch Int(event.keyCode) {
        case kVK_Tab:
            isVisible = true
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            // Arrows move the caret while editing text.
            if !(window.firstResponder is NSTextView) {
                isVisible = true
            }
        default:
            break
        }
    }
}

struct KeyboardFocusEffect: ViewModifier {
    @ObservedObject var visibility: KeyboardFocusVisibility

    func body(content: Content) -> some View {
        content.focusEffectDisabled(!visibility.isVisible)
    }
}
