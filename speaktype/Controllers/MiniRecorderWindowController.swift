import Cocoa
import SwiftUI

class MiniRecorderWindowController: NSObject {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    /// Frontmost app at the latest start request. Promoted to `lastActiveApp` only when the
    /// recorder accepts the start, so a rejected press (e.g. while transcribing) can't change
    /// where the current transcript gets pasted.
    private var startCandidateApp: NSRunningApplication?
    private var lastActiveApp: NSRunningApplication?
    private var pendingPasteTarget: NSRunningApplication?

    static let accessibilityPasteMessage =
        "Copied. Press ⌘V to paste. Turn on Accessibility for auto-paste."

    // Start recording - show panel and begin recording
    func startRecording() {
        // Remember the app the user was in; it becomes the paste target if the start is accepted.
        startCandidateApp = NSWorkspace.shared.frontmostApplication

        if panel == nil {
            setupPanel()
        }

        guard let panel = panel else { return }

        if !panel.isVisible {
            print("Showing Mini Recorder Panel")

            // Force layout to ensure frame is correct
            panel.layoutIfNeeded()

            // Position above dock with fixed width (panel width 300, matches NSPanel & MiniRecorderView)
            if let screen = NSScreen.main {
                let visibleFrame = screen.visibleFrame
                let windowWidth: CGFloat = 300  // Match MiniRecorderView frame width
                let x = visibleFrame.midX - (windowWidth / 2)
                let y = visibleFrame.minY + 50  // 50px padding above dock
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                panel.center()
            }

            // Show without activating to avoid pulling main app focus unnecessarily
            panel.orderFrontRegardless()
        }

        // Trigger instant recording
        NotificationCenter.default.post(name: .recordingStartRequested, object: nil)
    }

    // Stop recording - trigger transcription and paste
    func stopRecording() {
        // 1. Hide recorder immediately - REMOVED so it shows "Transcribing..."
        // panel?.orderOut(nil)

        // Keep focus unchanged while the hotkey is still being released.
        // Re-activation happens later during commit, right before auto-paste. The paste target
        // is captured in `onStopAccepted`, only when the recorder actually takes this stop.
        NotificationCenter.default.post(name: .recordingStopRequested, object: nil)
    }

    func cancelRecording() {
        NotificationCenter.default.post(name: .recordingCancelRequested, object: nil)
    }

    private func setupPanel() {
        // Initialize View with callbacks
        let recorderView = MiniRecorderView(
            onCommit: { [weak self] text in
                self?.handleCommit(text: text)
            },
            onCancel: { [weak self] in
                self?.panel?.orderOut(nil)
            },
            onStartAccepted: { [weak self] in
                guard let self else { return }
                self.lastActiveApp = self.startCandidateApp
            },
            onStopAccepted: { [weak self] in
                guard let self else { return }
                self.pendingPasteTarget = self.lastActiveApp
            }
        )

        // Initialize hosting controller with transparent background view
        // Wrap in AnyView because .background() changes the type from MiniRecorderView to some View
        hostingController = NSHostingController(
            rootView: AnyView(recorderView.background(Color.clear)))

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 50),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear

        p.contentViewController = hostingController

        // Ensure hosting view has transparent background to prevent visual artifacts
        if let hostView = hostingController?.view {
            hostView.wantsLayer = true
            hostView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.hasShadow = false  // Disable system shadow to avoid transparency artifacts (View has its own shadow)

        // Window Behavior
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false  // Keep floating even if focus lost
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true

        self.panel = p
    }

    private func handleCommit(text: String) {
        let pasteTarget = pendingPasteTarget ?? lastActiveApp
        pendingPasteTarget = nil
        Task { @MainActor in
            let result = await ClipboardService.shared.pasteText(
                text,
                into: pasteTarget,
                beforePaste: { [weak self] in self?.panel?.orderOut(nil) }
            )

            if result == .copiedOnly {
                // No Accessibility: say so in the panel instead of failing silently. The text
                // stays on the clipboard for a manual ⌘V.
                NotificationCenter.default.post(
                    name: .recordingShowMessageRequested,
                    object: nil,
                    userInfo: ["message": Self.accessibilityPasteMessage]
                )
            }
        }
    }

    /// Paste text that is not from a fresh recording (e.g. "Paste last transcript" in the menu
    /// bar) into `target`, or whatever app is frontmost.
    func pasteExistingText(_ text: String, into target: NSRunningApplication?) {
        let target = target ?? NSWorkspace.shared.frontmostApplication
        Task { @MainActor in
            _ = await ClipboardService.shared.pasteText(text, into: target)
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText =
            "SpeakType needs Accessibility permission to automatically paste transcriptions into the active app.\n\nYour transcription has been copied to the clipboard.\n\nTo enable auto-paste, grant permission in:\nSystem Settings → Privacy & Security → Accessibility"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
