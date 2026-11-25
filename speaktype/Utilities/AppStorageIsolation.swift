import Foundation

/// Unit tests run inside the real app (same bundle id), so without this they read and wipe the
/// user's actual history and dictation checkpoints. Under XCTest, history lives in its own
/// preferences suite and its own Application Support folder instead.
nonisolated enum AppStorageIsolation {
    static let isRunningTests: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.arguments.contains("--uitesting")

    /// Preferences store for history + stats. A named suite can't fail for a non-bundle name.
    static let historyDefaults: UserDefaults =
        isRunningTests ? UserDefaults(suiteName: "com.ludvighedin.speaktype.tests")! : .standard

    /// Application Support subfolder for dictation checkpoints.
    static let supportFolderName = isRunningTests ? "SpeakType-Tests" : "SpeakType"
}
