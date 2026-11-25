import Cocoa
import SwiftUI

class MiniRecorderWindowController: NSObject {
    private let keyboardFocusVisibility: KeyboardFocusVisibility
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    /// Frontmost app at the latest start request. Promoted to `lastActiveApp` only when the
    /// recorder accepts the start, so a rejected press (e.g. while transcribing) can't change
    /// where the current transcript gets pasted.
    private var startCandidateApp: NSRunningApplication?
    private var lastActiveApp: NSRunningApplication?
    private(set) var capturesEscape = false
    private var pasteTask: Task<Void, Never>?
    private var pendingPasteTarget: NSRunningApplication?

    static let accessibilityPasteMessage =
        "Copied. Press ⌘V to paste. Turn on Accessibility for auto-paste."

    init(keyboardFocusVisibility: KeyboardFocusVisibility) {
        self.keyboardFocusVisibility = keyboardFocusVisibility
    }

    // Start recording - show panel and begin recording
    func startRecording() {
        // Remember the app the user was in; it becomes the paste target if the start is accepted.
        startCandidateApp = NSWorkspace.shared.frontmostApplication

        showPanel()

        // Trigger instant recording
        NotificationCenter.default.post(name: .recordingStartRequested, object: nil)
    }

    #if DEBUG
    /// Debug builds launched with `--recorder-demo` play every pill state (no mic, no paste).
    func runVisualDemo() {
        showPanel()
        NotificationCenter.default.addObserver(
            forName: .recorderDemoShowPanel, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showPanel() }
        }
        // Give the freshly created SwiftUI view a moment to subscribe.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .recorderDemoRequested, object: nil)
        }
    }
    #endif

    private func showPanel() {
        if panel == nil {
            setupPanel()
        }

        guard let panel = panel else { return }

        if !panel.isVisible {
            print("Showing Mini Recorder Panel")

            // Force layout to ensure frame is correct
            panel.layoutIfNeeded()

            // Bottom center of the screen the user is on, just above the Dock.
            let canvas = MiniRecorderView.canvasSize
            if let screen = NSScreen.main {
                let visibleFrame = screen.visibleFrame
                let x = visibleFrame.midX - (canvas.width / 2)
                let y = visibleFrame.minY + 24
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                panel.center()
            }

            // Show without activating, with a short fade so it doesn't pop.
            hideGeneration += 1
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            // Re-shown while fading out: cancel the pending hide and fade back in from where
            // the fade-out is, so a running animation can't end at 0.
            hideGeneration += 1
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                panel.animator().alphaValue = 1
            }
        }
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
                self?.hidePanel()
            },
            onCancelPaste: { [weak self] in self?.pasteTask?.cancel() },
            onEscapeCaptureChanged: { [weak self] capture in self?.capturesEscape = capture },
            onStartAccepted: { [weak self] in
                guard let self else { return }
                self.pasteTask?.cancel()
                self.pendingPasteTarget = nil
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
            rootView: AnyView(
                recorderView
                    .background(Color.clear)
                    .modifier(KeyboardFocusEffect(visibility: keyboardFocusVisibility))
            )
        )

        let canvas = MiniRecorderView.canvasSize
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: canvas.width, height: canvas.height),
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
        p.isMovableByWindowBackground = false
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

    /// Bumped on every show; a fade-out only hides the panel if nothing re-showed it.
    private var hideGeneration = 0

    private func hidePanel() {
        guard let panel, panel.isVisible else { return }
        hideGeneration += 1
        let generation = hideGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.hideGeneration == generation else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    private func handleCommit(text: String) {
        let pasteTarget = pendingPasteTarget ?? lastActiveApp
        pendingPasteTarget = nil
        pasteTask?.cancel()
        pasteTask = Task { @MainActor in
            let result = await ClipboardService.shared.pasteText(
                text,
                into: pasteTarget,
                // The pill stays up to show the checkmark. It is a non-activating panel, but
                // make sure it can't hold key focus while ⌘V is sent to the target app.
                beforePaste: { [weak self] in self?.panel?.resignKey() },
                afterPaste: {
                    NotificationCenter.default.post(name: .recordingPasteSucceeded, object: nil)
                }
            )

            if result == .copiedOnly && !Task.isCancelled {
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
            "Taly needs Accessibility permission to automatically paste transcriptions into the active app.\n\nYour transcription has been copied to the clipboard.\n\nTo enable auto-paste, grant permission in:\nSystem Settings → Privacy & Security → Accessibility"
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
