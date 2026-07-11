import Foundation
import ServiceManagement

/// Registers SpeakType as a macOS login item so it auto-starts as a background agent.
///
/// Uses `SMAppService.mainApp` (macOS 13+), which registers the main app bundle itself —
/// no separate helper target required. The user controls it via the "Launch at login"
/// toggle in Settings; the registration also appears in System Settings → General → Login Items.
enum LaunchAtLoginService {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the login item. Idempotent and failure-tolerant:
    /// registration can legitimately fail for unsigned dev builds run from DerivedData,
    /// so errors are logged rather than surfaced — they resolve in a real installed build.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            AppLogger.error("LaunchAtLogin update failed", error: error)
        }
    }

    /// Reconcile the system login-item state with the stored user preference.
    /// Called on launch so the OS state always matches what the user expects.
    static func syncWithPreference() {
        setEnabled(UserDefaults.standard.bool(forKey: "launchAtLogin"))
    }
}
