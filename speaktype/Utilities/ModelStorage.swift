import Foundation
import os

/// Canonical on-disk location for downloaded Core ML / WhisperKit models.
///
/// Historically models lived in `~/Documents/huggingface`, which is a TCC-protected
/// location: every launch that created or enumerated that directory triggered the
/// "SpeakType would like to access files in your Documents folder" prompt. Application
/// Support is app-managed storage and is not TCC-protected, so nothing prompts.
nonisolated enum ModelStorage {
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

    private static var legacyDocumentsBase: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface")
    }

    static func modelDirectory(for variant: String) -> URL {
        whisperKitModelsDirectory.appendingPathComponent(variant)
    }

    /// Create the model directory and kick off the one-time migration. Safe to call
    /// repeatedly. The directory creation itself never touches Documents.
    static func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: whisperKitModelsDirectory, withIntermediateDirectories: true)
        startMigrationIfNeeded()
    }

    private static let migrationStarted = OSAllocatedUnfairLock(initialState: false)

    private static func startMigrationIfNeeded() {
        let alreadyStarted = migrationStarted.withLock { started -> Bool in
            defer { started = true }
            return started
        }
        guard !alreadyStarted else { return }

        // Detached and low priority: reading Documents can block on a pending TCC prompt
        // for as long as the user takes to answer, and nothing may wait on that.
        Task.detached(priority: .utility) {
            guard let legacy = legacyDocumentsBase, migrateLegacyCache(from: legacy, to: downloadBase) else { return }
            await ModelDownloadService.shared.refreshDownloadedModels()
        }
    }

    /// Move old model weights and copy cached tokenizers so local dictation can load
    /// both from Application Support. Existing destinations and unrelated files are kept.
    static func migrateLegacyCache(from legacy: URL, to current: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacy.path) else { return false }

        var migrated = false
        for (path, prefix, copy) in [
            ("models/openai", "whisper-", true),
            ("models/argmaxinc/whisperkit-coreml", "openai_whisper-", false),
        ] {
            let sourceDirectory = legacy.appendingPathComponent(path)
            let destinationDirectory = current.appendingPathComponent(path)
            guard let entries = try? fileManager.contentsOfDirectory(atPath: sourceDirectory.path),
                entries.contains(where: { $0.hasPrefix(prefix) })
            else { continue }

            do {
                try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            } catch {
                print("Could not create local Whisper cache: \(error)")
                continue
            }

            for entry in entries where entry.hasPrefix(prefix) {
                let source = sourceDirectory.appendingPathComponent(entry)
                let destination = destinationDirectory.appendingPathComponent(entry)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                do {
                    if copy {
                        try fileManager.copyItem(at: source, to: destination)
                    } else {
                        try fileManager.moveItem(at: source, to: destination)
                    }
                    migrated = true
                } catch {
                    print("Could not migrate \(entry): \(error)")
                }
            }
        }
        return migrated
    }
}
