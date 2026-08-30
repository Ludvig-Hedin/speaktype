import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI

@main
struct speaktypeApp: App {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
    @AppStorage("hotkeyEnabled") private var hotkeyEnabled: Bool = true

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // License Manager
    @StateObject private var licenseManager = LicenseManager.shared

    // Trial Manager
    @StateObject private var trialManager = TrialManager.shared

    init() {
        // For UI testing: bypass onboarding automatically
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            hasCompletedOnboarding = true
        }
    }

    var body: some Scene {
        // Main Dashboard Window (Hidden by default, opened via Menu Bar or Dock)
        WindowGroup(id: "main-dashboard") {
            ThemeProvider {
                Group {
                    if hasCompletedOnboarding {
                        MainView()
                    } else {
                        OnboardingView()
                    }
                }
            }
            .environmentObject(licenseManager)
            .environmentObject(trialManager)
            .preferredColorScheme(appTheme.colorScheme)
            // Tint native controls (menu arrows, toggles, sliders, checkmarks) with our one
            // accent instead of the user's system accent — keeps the palette monochrome + blue.
            .tint(Color.accentBlue)
            // No keyboard focus rings anywhere — this is a pointer-first utility, and the
            // accent-colored ring on launch/tab reads as a glitch.
            .focusEffectDisabled()
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: ["main-dashboard", "open"])
        .commands {
            SidebarCommands()
        }

        // Menu Bar Extra (Always running listener)
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            ThemeProvider {
                MenuBarDashboardView(
                    openDashboard: openDashboard,
                    startRecording: startRecordingFromMenuBar,
                    quit: { NSApplication.shared.terminate(nil) }
                )
            }
            .preferredColorScheme(appTheme.colorScheme)
            .tint(Color.accentBlue)
            .focusEffectDisabled()
        } label: {
            // Icon changes when the hotkey is disabled so the user has a persistent visual cue
            Label(
                "SpeakType",
                systemImage: hotkeyEnabled ? "waveform" : "waveform.badge.minus"
            )
            .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Actions

    private func openDashboard() {
        // Ensure a Dock presence + focus so the window opens in front, even when the app
        // is running as a background agent (Dock icon hidden).
        appDelegate.presentDashboardForeground()
        if let url = URL(string: "speaktype://open") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startRecordingFromMenuBar() {
        appDelegate.startRecordingFromMenuBar()
    }
}
