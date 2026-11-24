import Foundation
import Combine
import WhisperKit

class ModelDownloadService: ObservableObject {
    static let shared = ModelDownloadService()
    
    @Published var downloadProgress: [String: Double] = [:] // Map Model Variant (String) to progress
    @Published var downloadError: [String: String] = [:] // Debugging: track errors
    @Published var isDownloading: [String: Bool] = [:]
    
    private var activeTasks: [String: Task<Void, Never>] = [:] // Track running download tasks
    private var modelScanGeneration = 0
    
    private init() {
        // Directory creation only — no Documents access, so nothing triggers a TCC prompt.
        // Launch-time `refreshDownloadedModels()` runs from AppDelegate to avoid racing duplicate Tasks.
        ModelStorage.ensureDirectoryExists()
    }
    
    // Check which models are already downloaded and update progress dictionary
    func refreshDownloadedModels() async {
        print("🔍 Checking for already-downloaded models...")
        modelScanGeneration += 1
        let generation = modelScanGeneration
        ModelStorage.startMigrationIfNeeded(for: TranscriptionModeUserDefaults.mode)
        let preserveSavedSelection = !ModelStorage.legacyMigrationFinished

        // Capture the expected-size table on the main actor (it's derived from @MainActor
        // `AIModel` state), then hand it to the off-main scan as a plain Sendable value.
        let expectedSizes = AIModel.availableModels.reduce(into: [String: Int64]()) {
            $0[$1.variant] = $1.expectedSizeBytes
        }

        // The disk scan does a recursive `getattrlistbulk` walk over the (multi-GB) model
        // cache. This type is implicitly @MainActor (SWIFT_DEFAULT_ACTOR_ISOLATION), so it
        // MUST run in a detached task or it blocks the main thread and beachballs the app on
        // launch. `Task.detached` is the only reliable off-main hop under approachable
        // concurrency (a plain `nonisolated` helper still runs on the calling actor).
        let foundModels = await Task.detached(priority: .userInitiated) {
            ModelDownloadService.scanDownloadedModels(expectedSizes: expectedSizes)
        }.value

        // Back on the main actor: publish results.
        guard generation == modelScanGeneration else { return }
        self.downloadProgress = self.downloadProgress.filter { self.isDownloading[$0.key] == true }

        for variant in foundModels where self.isDownloading[variant] != true {
            self.downloadProgress[variant] = 1.0
            print("✅ Marked as downloaded: \(variant)")
        }

        if foundModels.isEmpty {
            print("❌ No models found - all will show as 'Download' buttons")
        } else {
            print("✅ Found \(foundModels.count) usable model(s)")
        }

        SelectedModelPreference.ensureValidSelection(
            downloadService: self, preserveSavedSelection: preserveSavedSelection
        )
    }

    /// Enumerate the WhisperKit cache on disk and return the set of complete model variants.
    /// `nonisolated` + only Sendable inputs so it is safe to run off the main actor via
    /// `Task.detached` — all the blocking FileManager work stays off the main thread.
    nonisolated static func scanDownloadedModels(
        expectedSizes: [String: Int64],
        in directory: URL = ModelStorage.whisperKitModelsDirectory
    ) -> Set<String> {
        var foundModels = Set<String>()

        // Only scan application storage. The legacy migration may be waiting for macOS permission.
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return foundModels
        }

        for item in contents {
            let modelName = item.lastPathComponent

            // Skip non-model directories
            if modelName == "config.json" || modelName == ".DS_Store" {
                continue
            }

            // Verify this directory has actual model files (not just empty directory)
            guard let subContents = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: [.fileSizeKey]),
                  !subContents.isEmpty else {
                continue
            }

            // Check if it has the essential files for a model (must have config.json)
            let hasConfigJson = subContents.contains(where: { $0.lastPathComponent == "config.json" })
            let hasModelFiles = subContents.contains(where: { $0.lastPathComponent.hasSuffix(".mlmodelc") })

            guard hasConfigJson && hasModelFiles else {
                print("⚠️ Model \(modelName) is incomplete (missing config.json or .mlmodelc files)")
                continue
            }

            // Calculate total directory size
            let directorySize = calculateDirectorySize(at: item)
            let expectedSize = expectedSizes[modelName] ?? 50_000_000

            // Model is complete if it's at least 80% of expected size
            let minAcceptableSize = Int64(Double(expectedSize) * 0.8)

            if directorySize >= minAcceptableSize {
                print("✅ Model \(modelName) verified: \(formatBytes(directorySize)) (expected ~\(formatBytes(expectedSize)))")
                foundModels.insert(modelName)
            } else {
                print("⚠️ Model \(modelName) is INCOMPLETE: \(formatBytes(directorySize)) < \(formatBytes(minAcceptableSize)) minimum")
            }
        }

        return foundModels
    }

    private func downloadModelFiles(variant: String) async throws {
        // WhisperKit downloads model weights and tokenizer files separately.
        if let tokenizerVariant = ModelVariant.allCases.first(where: {
            variant == "openai_whisper-\($0)" || variant.hasPrefix("openai_whisper-\($0)_")
        }) {
            _ = try await loadTokenizer(for: tokenizerVariant, tokenizerFolder: ModelStorage.downloadBase)
        }
        try Task.checkCancellation()
        _ = try await WhisperKit.download(variant: variant, downloadBase: ModelStorage.downloadBase) { progress in
            DispatchQueue.main.async {
                self.downloadProgress[variant] = progress.fractionCompleted
            }
        }
    }
    
    // Asynchronous download using WhisperKit
    func downloadModel(variant: String) {
        guard isDownloading[variant] != true else { return }
        
        isDownloading[variant] = true
        downloadProgress[variant] = 0.0
        downloadError[variant] = nil
        print("Starting WhisperKit download for: \(variant)")
        
        let task = Task {
            do {
                try await downloadModelFiles(variant: variant)

                // Check if task was cancelled before declaring success
                if Task.isCancelled { return }
                
                print("Model downloaded successfully")
                
                DispatchQueue.main.async {
                    self.isDownloading[variant] = false
                    self.downloadProgress[variant] = 1.0
                    self.activeTasks[variant] = nil // Cleanup task
                    SelectedModelPreference.ensureValidSelection(downloadService: self)
                }
            } catch {
                if Task.isCancelled {
                   print("Download cancelled for \(variant)")
                   return
                }
                
                print("WhisperKit download error: \(error)")
                
                // Auto-Repair: If duplicate models found, delete and retry ONCE
                if error.localizedDescription.contains("Multiple models found") {
                     print("⚠️ Multiple models detected. Cleaning cache and retrying...")
                     
                     await MainActor.run {
                         self.downloadError[variant] = "Cleaning duplicates..."
                     }
                     
                     let log = await self.deleteModel(variant: variant)
                     print("🧹 Cleanup result: \(log)")
                     
                     // Give filesystem time to settle
                     try? await Task.sleep(nanoseconds: 2_000_000_000)
                     if Task.isCancelled { return }
                     
                     await MainActor.run {
                         self.downloadError[variant] = "Retrying download..."
                     }
                     
                     // Retry download once
                     do {
                         try await downloadModelFiles(variant: variant)

                         if Task.isCancelled { return }
                         
                         print("✅ Model downloaded successfully after cleanup")
                         
                         DispatchQueue.main.async {
                             self.isDownloading[variant] = false
                             self.downloadProgress[variant] = 1.0
                             self.downloadError[variant] = nil
                             self.activeTasks[variant] = nil
                             SelectedModelPreference.ensureValidSelection(downloadService: self)
                         }
                     } catch {
                         if Task.isCancelled { return }
                         print("❌ Retry failed: \(error)")
                         DispatchQueue.main.async {
                             self.isDownloading[variant] = false
                             self.downloadProgress[variant] = 0.0
                             self.downloadError[variant] = "Error: \(error.localizedDescription)\n\nTry clicking the trash icon to manually clean cache."
                             self.activeTasks[variant] = nil
                         }
                     }
                     return
                }

                DispatchQueue.main.async {
                    self.isDownloading[variant] = false
                    self.downloadProgress[variant] = 0.0
                    self.downloadError[variant] = error.localizedDescription + "\n\n(Try Trash icon to clean cache)"
                    self.activeTasks[variant] = nil
                }
            }
        }
        
        activeTasks[variant] = task
    }
    
    // Aggressively deletes any potential cache for this variant
    func deleteModel(variant: String) async -> String {
        // The file search + deletion is blocking FileManager work; run it off the main actor
        // (this type is implicitly @MainActor) so the UI never hitches while a large model
        // directory is being removed.
        let result = await Task.detached(priority: .userInitiated) {
            ModelDownloadService.purgeModelCaches(variant: variant)
        }.value

        self.downloadProgress[variant] = 0.0
        self.isDownloading[variant] = false
        return result
    }

    /// Search every known cache location and delete anything matching this variant.
    /// `nonisolated` so the blocking FileManager traversal runs off the main actor.
    nonisolated static func purgeModelCaches(variant: String) -> String {
        let fileManager = FileManager.default
        // Documents is intentionally excluded: models no longer live there, and enumerating
        // it would raise a TCC prompt. Only the one-time migration reads that location.
        let searchDirs: [FileManager.SearchPathDirectory] = [.applicationSupportDirectory, .cachesDirectory]

        let homeDir = fileManager.homeDirectoryForCurrentUser
        let tempDir = fileManager.temporaryDirectory
        let standardDirectories = searchDirs.flatMap { directory -> [URL] in
            guard let base = fileManager.urls(for: directory, in: .userDomainMask).first else { return [] }
            return [base.appendingPathComponent("huggingface/models"),
                    base.appendingPathComponent("huggingface/hub"), base]
        }
        let directories = standardDirectories + [
            homeDir.appendingPathComponent(".cache/huggingface/models"),
            homeDir.appendingPathComponent(".cache/huggingface/hub"),
            tempDir.appendingPathComponent("huggingface"),
            tempDir,
            ModelStorage.whisperKitModelsDirectory,
        ]
        let deletedCount = purgeModelCaches(variant: variant, in: directories)
        if deletedCount > 0 { return "Deleted \(deletedCount) items" }
        return "No cached files found for '\(variant)'"
    }

    nonisolated static func purgeModelCaches(variant: String, in directories: [URL]) -> Int {
        let modelName = variant.split(separator: "/").last.map(String.init) ?? variant
        let underscoreVariant = variant.replacingOccurrences(of: "/", with: "_")
        return directories.reduce(0) {
            $0 + cleanupDirectory($1, matchAny: [modelName, underscoreVariant])
        }
    }

    nonisolated private static func cleanupDirectory(_ dir: URL, matchAny patterns: [String]) -> Int {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return 0 }
        
        var count = 0
        for url in contents {
            let fileName = url.lastPathComponent
            // Check if any pattern matches
            if matchesCacheName(fileName, patterns: patterns) {
                do {
                    try fileManager.removeItem(at: url)
                    print("✅ Deleted cache: \(url.lastPathComponent)")
                    count += 1
                } catch {
                    print("❌ Failed to delete \(url.lastPathComponent): \(error)")
                }
            }
        }
        return count
    }

    nonisolated private static func matchesCacheName(_ fileName: String, patterns: [String]) -> Bool {
        if patterns.contains("openai_whisper-large-v3") || patterns.contains("whisper-large-v3") {
            // The full model's short ID is a prefix of the Turbo and quantized variants.
            return ["whisper-large-v3", "openai_whisper-large-v3", "models--openai--whisper-large-v3"].contains(fileName)
        }
        return patterns.contains { pattern in
            fileName.contains(pattern) || fileName.contains(pattern.replacingOccurrences(of: "/", with: "--"))
        }
    }

    func cancelDownload(for variant: String) {
        if let task = activeTasks[variant] {
            task.cancel()
            activeTasks[variant] = nil
            print("Cancelled download task for \(variant)")
        }

        downloadError[variant] = nil
        // Keep `isDownloading` TRUE while we delete the partial files. `downloadModel()` guards on
        // `isDownloading[variant] != true`, so this blocks a rapid re-tap of Download until cleanup
        // finishes — otherwise the new download races this delete and the cleanup can wipe the
        // freshly-downloading files, leaving an incomplete model. `deleteModel` flips
        // `isDownloading`/`downloadProgress` back to false/0 on the main actor when it completes.
        isDownloading[variant] = true

        Task {
            let result = await deleteModel(variant: variant)
            print("🗑️ Cleaned up partial download: \(result)")
        }
    }
    
    // MARK: - Helper Functions
    
    /// Calculate total size of a directory recursively.
    /// `nonisolated` so it can run off the main actor during the launch-time cache scan.
    nonisolated static func calculateDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    /// Format bytes into human-readable string
    nonisolated static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
