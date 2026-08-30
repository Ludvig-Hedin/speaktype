import ApplicationServices
import AVFoundation
import Combine
import Foundation
import AppKit

/// Single source of truth for microphone + accessibility permission state.
///
/// Both `AXIsProcessTrusted()` and `AXIsProcessTrustedWithOptions()` are synchronous IPC
/// round-trips to `tccd`. While the system permission dialog is on screen `tccd` is busy,
/// so those calls can block for seconds. Calling them on the main thread — which every
/// call site used to do, several of them on a repeating 0.5s/1.0s `Timer` — is what froze
/// the app when the accessibility prompt appeared. Everything here hops off the main
/// thread and publishes results back.
@MainActor
final class PermissionService: ObservableObject {
    static let shared = PermissionService()

    @Published private(set) var isMicGranted: Bool = false
    @Published private(set) var isAccessibilityGranted: Bool = false

    /// True while a system permission dialog we triggered is expected to be on screen.
    /// Polling pauses during this window so we never pile up blocking `tccd` calls.
    @Published private(set) var isRequestingAccessibility: Bool = false

    private var pollTask: Task<Void, Never>?
    private var observerCount = 0

    private init() {
        isMicGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        // Deliberately not calling AXIsProcessTrusted() here — `shared` is often first
        // touched during launch on the main thread, and a cold tccd round-trip stalls it.
        Task { await refresh() }
    }

    var arePermissionsGranted: Bool { isMicGranted && isAccessibilityGranted }

    // MARK: - Polling

    /// Start observing permission changes. Balanced by `stopObserving()`.
    /// Multiple views can observe concurrently; only one poll loop ever runs.
    func startObserving() {
        observerCount += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopObserving() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    /// Read both permission states off the main thread and publish the result.
    func refresh() async {
        // Don't hit tccd while its own dialog is up — that is the blocking window.
        guard !isRequestingAccessibility else { return }

        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let accessibility = await Task.detached(priority: .utility) {
            AXIsProcessTrusted()
        }.value

        if isMicGranted != mic { isMicGranted = mic }
        if isAccessibilityGranted != accessibility {
            print("🔐 Accessibility status changed: \(isAccessibilityGranted) → \(accessibility)")
            isAccessibilityGranted = accessibility
        }
    }

    // MARK: - Requests

    /// Show the system accessibility prompt.
    ///
    /// Two things are required to avoid a hang:
    /// 1. The blocking `AXIsProcessTrustedWithOptions` call runs off the main thread.
    /// 2. The app is brought forward first. SpeakType normally runs as an `.accessory`
    ///    background agent, and the TCC dialog then opens *behind* the frontmost app —
    ///    the user sees a stuck, unresponsive UI with no visible dialog.
    func requestAccessibilityPermission() {
        guard !isRequestingAccessibility else { return }

        if isAccessibilityGranted {
            return
        }

        // Ensure the prompt is visible even when running as a background agent.
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        isRequestingAccessibility = true

        Task {
            let granted = await Task.detached(priority: .userInitiated) { () -> Bool in
                let options =
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    as CFDictionary
                return AXIsProcessTrustedWithOptions(options)
            }.value

            isRequestingAccessibility = false
            isAccessibilityGranted = granted

            if previousPolicy != .regular && NSApp.activationPolicy() != previousPolicy {
                NSApp.setActivationPolicy(previousPolicy)
            }

            // The user usually grants it in System Settings after the dialog, so keep
            // checking for a short while even if the immediate answer was "no".
            if !granted { await pollForAccessibilityGrant() }
        }
    }

    /// After the prompt is dismissed the user typically flips the toggle in System
    /// Settings. Poll (off-main) for up to 2 minutes so the UI updates without a restart.
    private func pollForAccessibilityGrant() async {
        for _ in 0..<120 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            let granted = await Task.detached(priority: .utility) { AXIsProcessTrusted() }.value
            if granted {
                isAccessibilityGranted = true
                return
            }
        }
    }

    /// Show the system microphone prompt, or route to System Settings if already denied.
    func requestMicPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isMicGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in self.isMicGranted = granted }
            }
        case .denied, .restricted:
            openSystemSettings(pane: "Privacy_Microphone")
        @unknown default:
            break
        }
    }

    func openSystemSettings(pane: String) {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
