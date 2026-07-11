import Foundation
import os
import WhisperKit

@Observable
class WhisperService {
    // Shared singleton instance - use this everywhere
    static let shared = WhisperService()
    private static let placeholderPatterns = [
        #"\[(?:BLANK_AUDIO|SILENCE)\]"#,
        #"<\|nospeech\|>"#,
        #"\[\s*S\s*\]"#,
    ]
    private static let noiseLabelTerms = [
        "applause",
        "background noise",
        "blank audio",
        "breathing",
        "cough",
        "coughing",
        "exhale",
        "heartbeat",
        "indistinct",
        "inaudible",
        "inhale",
        "laughing",
        "laughter",
        "loud noise",
        "muffled speech",
        "music",
        "noise",
        "silence",
        "sigh",
        "sighs",
        "sniffing",
        "static",
        "unclear speech",
        "unintelligible",
        "wind",
        "wind blowing",
        "wind noise",
    ]
    private static let bracketedNoisePattern: String = {
        let escaped = noiseLabelTerms.map(NSRegularExpression.escapedPattern(for:)).joined(
            separator: "|")
        return #"[\[\(]\s*(?:"# + escaped + #")\s*[\]\)]"#
    }()

    var pipe: WhisperKit?
    var isInitialized = false
    var isTranscribing = false
    var isLoading = false
    var loadingStage: String = ""  // Descriptive stage for UI

    var currentModelVariant: String = ""  // No default - must be explicitly set

    /// When `true` the loaded model is kept in RAM permanently (ample-memory machines).
    /// When `false` it is released after an idle period to free memory (low-memory machines).
    /// Set automatically by `ModelMemoryPolicy` each time a model loads.
    var keepResident = false

    /// Lock-protected coalescing/idle state. This class is a non-isolated `@Observable` whose async
    /// methods run off the caller's actor (plus a `Task.detached` warm-load at record-start), so
    /// these fields are read-modify-written from multiple threads. Guarding them prevents a double
    /// model load (2× RAM spike on the low-RAM Macs this targets) and a missed idle-unload cancel.
    private struct LoadState {
        /// The single in-flight load, so concurrent callers coalesce onto one `performLoad`.
        var loadingTask: Task<Void, Error>?
        /// Identity of `loadingTask` (Task is a value type, so identity needs an explicit id).
        var loadingTaskID: Int = 0
        var nextLoadID: Int = 0
        /// Monotonic token that invalidates a scheduled idle-unload when new activity happens.
        var idleUnloadGeneration: Int = 0
    }

    /// `OSAllocatedUnfairLock` (not `NSLock`) because it is safe to use from async contexts and
    /// gives the cross-thread happens-before needed for the generation token to be reliable.
    private let lockedState = OSAllocatedUnfairLock(initialState: LoadState())

    /// Device RAM in GB (cached on init)
    static let deviceRAMGB: Int = {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }()

    enum TranscriptionError: Error, LocalizedError {
        case notInitialized
        case fileNotFound
        case alreadyLoading
        case loadingTimeout

        var errorDescription: String? {
            switch self {
            case .notInitialized: return "Model is not initialized"
            case .fileNotFound: return "Audio file not found"
            case .alreadyLoading: return "Model loading already in progress"
            case .loadingTimeout:
                return "Model loading timed out — your Mac may not have enough RAM for this model"
            }
        }
    }

    // Init is internal to allow testing, but prefer using .shared in production
    init() {}

    // Default initialization (loads default or saved model).
    // Falls back to the persisted selected variant when nothing is loaded yet — `currentModelVariant`
    // is cleared to "" by idle-unload(), so relying on it alone would try to load an empty variant.
    func initialize() async throws {
        try await loadModel(variant: resolvedVariant())
    }

    /// The variant to (re)load: the one already loaded, else the user's persisted selection.
    private func resolvedVariant() -> String {
        if !currentModelVariant.isEmpty { return currentModelVariant }
        return UserDefaults.standard.string(forKey: SelectedModelPreference.storageKey) ?? ""
    }

    // Dynamic model loading with optimized WhisperKitConfig.
    // Coalesces concurrent calls so parallel callers (e.g. record-start warm-up + the
    // safety load before transcribe) share a single load instead of colliding.
    func loadModel(variant: String) async throws {
        // Any load request signals imminent use — cancel a pending idle-unload up front, even on
        // the early-return paths below, so a caller that re-requests the resident model still
        // defers the release. (Must run before the early returns, not only on the new-load path.)
        cancelIdleUnload()

        while true {
            // Fast path: this exact model is already loaded.
            if isInitialized && variant == currentModelVariant && pipe != nil {
                return
            }

            // Atomically become the one that starts the load, or bail if another caller already
            // has one in flight — so two concurrent callers never both run performLoad (which
            // would double the RAM spike). The Task is created inside the lock only on the winning
            // path, so a loser never spawns a redundant load.
            let created: (task: Task<Void, Error>, id: Int)? = lockedState.withLock { state in
                if state.loadingTask != nil { return nil }
                state.nextLoadID += 1
                let id = state.nextLoadID
                let task = Task { try await self.performLoad(variant: variant) }
                state.loadingTask = task
                state.loadingTaskID = id
                return (task, id)
            }

            if let created {
                // Clear the slot only if it's still OUR task — a later concurrent call for a
                // different variant may have already replaced it, and we must not wipe that out.
                defer {
                    lockedState.withLock { state in
                        if state.loadingTaskID == created.id { state.loadingTask = nil }
                    }
                }
                try await created.task.value
                return
            }

            // A load is already in flight — await it, then re-check whether it satisfied us.
            if let existing = lockedState.withLock({ $0.loadingTask }) {
                try? await existing.value
            }
        }
    }

    private func performLoad(variant: String) async throws {
        let ramGB = Self.deviceRAMGB
        print("🔄 Initializing WhisperKit with model: \(variant)...")
        print("💻 Device RAM: \(ramGB) GB")

        if let model = AIModel.availableModels.first(where: { $0.variant == variant }),
            ramGB < model.minimumRAMGB
        {
            print(
                "⚠️ WARNING: Model \(variant) recommends \(model.minimumRAMGB)GB+ RAM, device has \(ramGB)GB. Loading may fail or be very slow."
            )
        }

        isLoading = true
        isInitialized = false
        loadingStage = "Preparing model..."

        // Release existing model to free memory
        if pipe != nil {
            print("🗑️ Releasing previous model from memory...")
            pipe = nil
        }

        do {
            let documentDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!
            let modelFolderPath = documentDirectory.appendingPathComponent(
                "huggingface/models/argmaxinc/whisperkit-coreml/\(variant)"
            ).path

            // Use WhisperKitConfig with optimized settings
            let config = WhisperKitConfig(
                model: variant,
                modelFolder: modelFolderPath,
                computeOptions: ModelComputeOptions(),  // Uses GPU + Neural Engine
                verbose: false,
                logLevel: .error,
                prewarm: true,  // Built-in model specialization (replaces manual warmup)
                load: true,
                download: false  // Already downloaded via ModelDownloadService
            )

            loadingStage = "Loading AI model..."

            // Start a watchdog timer that will flag a timeout
            let loadStart = Date()

            pipe = try await WhisperKit(config)

            let loadDuration = Date().timeIntervalSince(loadStart)
            print("⏱️ Model loaded in \(String(format: "%.1f", loadDuration))s")

            currentModelVariant = variant
            isInitialized = true
            isLoading = false
            loadingStage = ""

            // Decide whether to keep this model resident permanently or release it when
            // idle, based on how much RAM is free right now.
            keepResident = ModelMemoryPolicy.shouldKeepResident(variant: variant)
            print("✅ WhisperKit initialized with \(variant) — keepResident=\(keepResident)")
        } catch {
            isLoading = false
            loadingStage = ""
            print(
                "❌ Failed to initialize WhisperKit with \(variant): \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Idle memory management

    /// Release the loaded model and free its memory. Safe to call when nothing is loaded.
    /// Self-guards against releasing while a load or transcription is in progress, so it
    /// stays safe regardless of caller. (Even if it did race, `transcribe()` captures a
    /// strong local reference to the pipe, so an in-flight transcription is never broken.)
    func unload() {
        guard pipe != nil, !isTranscribing, !isLoading else { return }
        print("🌙 Releasing Whisper model to free memory (idle)")
        pipe = nil
        isInitialized = false
        currentModelVariant = ""
    }

    /// Cancel a pending idle-unload (e.g. a new recording just started).
    func cancelIdleUnload() {
        lockedState.withLock { $0.idleUnloadGeneration += 1 }
    }

    /// After a transcription, if the policy says we should not keep the model resident,
    /// release it once it has been idle for `ModelMemoryPolicy.idleUnloadDelay`.
    /// A newer load/record/transcribe bumps the generation token and cancels this.
    func scheduleIdleUnloadIfNeeded() {
        guard !keepResident else { return }
        let generation: Int = lockedState.withLock { state in
            state.idleUnloadGeneration += 1
            return state.idleUnloadGeneration
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ModelMemoryPolicy.idleUnloadDelay) {
            [weak self] in
            guard let self else { return }
            // Superseded by newer activity (the lock gives the cross-thread happens-before so a
            // cancel from a background-thread load is reliably seen here), or busy → keep model.
            let current = self.lockedState.withLock { $0.idleUnloadGeneration }
            guard current == generation else { return }
            guard !self.keepResident, !self.isTranscribing, !self.isLoading else { return }
            guard !AudioRecordingService.shared.isRecording else { return }
            self.unload()
        }
    }

    func transcribe(audioFile: URL, language: String = "auto") async throws -> String {
        // Self-heal: idle-unload() may have released the model. Reload the selected variant on
        // demand so every caller (mini recorder, dashboard, file transcribe) works after an idle
        // period instead of throwing .notInitialized. loadModel() coalesces with any warm-load
        // already started at record-time.
        if pipe == nil || !isInitialized {
            let variant = resolvedVariant()
            guard !variant.isEmpty else { throw TranscriptionError.notInitialized }
            try await loadModel(variant: variant)
        }

        guard let pipe = pipe, isInitialized else {
            throw TranscriptionError.notInitialized
        }

        guard FileManager.default.fileExists(atPath: audioFile.path) else {
            throw TranscriptionError.fileNotFound
        }

        isTranscribing = true
        defer {
            isTranscribing = false
            // Start the idle countdown after each transcription (no-op when keepResident).
            scheduleIdleUnloadIfNeeded()
        }

        print("Starting transcription for: \(audioFile.lastPathComponent)")

        do {
            let options = decodingOptions(for: language)
            let results = try await pipe.transcribe(audioPath: audioFile.path, decodeOptions: options)
            let text = Self.normalizedTranscription(
                from: results.map { $0.text }.joined(separator: " "))

            print("Transcription complete: \(text.prefix(50))...")
            return text
        } catch {
            print("Transcription failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Transcribe a background audio chunk without affecting the global `isTranscribing` flag.
    /// Chunk files are automatically deleted after transcription.
    func transcribeChunk(audioFile: URL, language: String = "auto") async throws -> String {
        guard let pipe = pipe, isInitialized else {
            throw TranscriptionError.notInitialized
        }

        guard FileManager.default.fileExists(atPath: audioFile.path) else {
            // Chunk file may have been cleaned up already - return empty gracefully
            return ""
        }

        print("🔪 Chunk transcription started: \(audioFile.lastPathComponent)")

        let results = try await pipe.transcribe(
            audioPath: audioFile.path,
            decodeOptions: decodingOptions(for: language)
        )
        let text = Self.normalizedTranscription(from: results.map { $0.text }.joined(separator: " "))

        print("🔪 Chunk done: \(text.prefix(40))...")
        // Clean up temp chunk file after transcription
        try? FileManager.default.removeItem(at: audioFile)
        return text
    }

    private func decodingOptions(for language: String) -> DecodingOptions {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = (language == "auto") ? nil : language
        return options
    }

    static func normalizedTranscription(from rawText: String) -> String {
        var normalized = rawText

        for pattern in placeholderPatterns {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        normalized = normalized.replacingOccurrences(
            of: bracketedNoisePattern,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        normalized = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
