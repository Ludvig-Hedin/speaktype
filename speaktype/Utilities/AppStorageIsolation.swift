import Foundation

/// Test hosts and development builds keep their preferences, credentials, models and audio
/// separate from the installed release. Debug uses its own bundle identifier.
nonisolated enum AppStorageIsolation {
    static let isRunningTests: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.arguments.contains("--uitesting")

    static var isUnitTestHost: Bool { isRunningTests && !ProcessInfo.processInfo.arguments.contains("--uitesting") }

    static var keychainSuffix: String { supportFolderName == "SpeakType" ? "" : "." + supportFolderName }

    /// Preferences store for history + stats. A named suite can't fail for a non-bundle name.
    static let historyDefaults: UserDefaults =
        isRunningTests ? UserDefaults(suiteName: "com.ludvighedin.speaktype.tests")! : .standard

    /// Application Support subfolder for dictation checkpoints.
    static var supportFolderName: String {
        if isRunningTests { return "SpeakType-Tests" }
        #if DEBUG
        return "SpeakType-Development"
        #else
        return "SpeakType"
        #endif
    }
}
