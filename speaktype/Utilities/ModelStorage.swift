import Foundation
import os

/// Canonical on-disk location for downloaded Core ML / WhisperKit models.
///
/// Historically models lived in `~/Documents/huggingface`, which is a TCC-protected
/// location: every launch that created or enumerated that directory triggered the
/// "SpeakType would like to access files in your Documents folder" prompt. Application
/// Support is app-managed storage and is not TCC-protected, so nothing prompts.
enum ModelStorage {
    /// `~/Library/Application Support/SpeakType/huggingface`
    ///
    /// Passed to WhisperKit as `downloadBase`; it appends `models/<repo>/<variant>`,
    /// so the layout below this directory matches the old Documents layout exactly.
    static var downloadBase: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return
            appSupport
            .appendingPathComponent("SpeakType")
            .appendingPathComponent("huggingface")
    }

    /// Directory holding the WhisperKit Core ML variants.
    static var whisperKitModelsDirectory: URL {
        downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    }

    /// The pre-1.0.30 location. Only referenced for migration and as a read fallback.
    static var legacyDocumentsBase: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface")
    }

    static var legacyWhisperKitModelsDirectory: URL? {
        legacyDocumentsBase?.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    }

    /// Directories to search for an already-downloaded model, best first.
    ///
    /// The legacy Documents directory is included only while it still exists, so a fresh
    /// install never touches Documents and never triggers its TCC prompt. Once
    /// `migrateFromDocumentsIfNeeded()` succeeds the legacy entry disappears for good.
    static func modelSearchDirectories() -> [URL] {
        var directories = [whisperKitModelsDirectory]
        if let legacy = legacyWhisperKitModelsDirectory,
            FileManager.default.fileExists(atPath: legacy.path)
        {
            directories.append(legacy)
        }
        return directories
    }

    /// Resolve where a given variant actually lives on disk, preferring the new location.
    /// Falls back to the new location when the model isn't downloaded yet.
    static func modelDirectory(for variant: String) -> URL {
        for base in modelSearchDirectories() {
            let candidate = base.appendingPathComponent(variant)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return whisperKitModelsDirectory.appendingPathComponent(variant)
    }

    /// Create the model directory and kick off the one-time migration. Safe to call
    /// repeatedly. The directory creation itself never touches Documents.
    static func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: whisperKitModelsDirectory, withIntermediateDirectories: true)
        startMigrationIfNeeded()
    }

    private static let migrationStarted = OSAllocatedUnfairLock(initialState: false)

    /// Run `migrateFromDocumentsIfNeeded()` once per process, off the main thread.
    ///
    /// Anchored here rather than in `AppDelegate` because this runs whenever
    /// `ModelDownloadService` is first touched, which is guaranteed; the launch-time tasks
    /// in `applicationDidFinishLaunching` are not reliably scheduled.
    static func startMigrationIfNeeded() {
        let alreadyStarted = migrationStarted.withLock { started -> Bool in
            defer { started = true }
            return started
        }
        guard !alreadyStarted else { return }

        // Detached and low priority: reading Documents can block on a pending TCC prompt
        // for as long as the user takes to answer, and nothing may wait on that.
        Task.detached(priority: .utility) {
            migrateFromDocumentsIfNeeded()
        }
    }

    /// Move models downloaded by an older build out of `~/Documents/huggingface`.
    ///
    /// Runs off the main actor (blocking file I/O). Reading Documents may still raise one
    /// final TCC prompt on the first launch after upgrading — after that the folder is gone
    /// and nothing under Documents is ever touched again. Only migrates when the legacy
    /// directory already exists, so a fresh install never touches Documents at all.
    static func migrateFromDocumentsIfNeeded() {
        let fileManager = FileManager.default
        guard let legacyBase = legacyDocumentsBase,
            fileManager.fileExists(atPath: legacyBase.path)
        else { return }

        let legacyModels = legacyBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        guard let variants = try? fileManager.contentsOfDirectory(atPath: legacyModels.path) else {
            // A read failure does not prove the legacy cache is empty. Keep it and retry later.
            return
        }

        ensureDirectoryExists()
        let destinationRoot = whisperKitModelsDirectory

        var allMoved = true
        for variant in variants where !variant.hasPrefix(".") {
            let source = legacyModels.appendingPathComponent(variant)
            let destination = destinationRoot.appendingPathComponent(variant)
            if fileManager.fileExists(atPath: destination.path) {
                // A destination may be a partial download. Preserve both copies on collision.
                allMoved = false
                continue
            }
            do {
                try fileManager.moveItem(at: source, to: destination)
                print("📦 Migrated model \(variant) out of ~/Documents")
            } catch {
                print("⚠️ Could not migrate model \(variant): \(error)")
                allMoved = false
            }
        }

        // Only delete the legacy tree once everything is safely relocated — otherwise leave
        // it in place and retry next launch rather than destroying an unmigrated model.
        _ = allMoved
    }
}
