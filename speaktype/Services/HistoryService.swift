import Foundation
import Combine
import SwiftUI // For IndexSet operations if needed, though Foundation usually covers it, but error says missing import.

nonisolated struct HistoryStatsEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let wordCount: Int
    let duration: TimeInterval
    // Optional so existing persisted JSON (which lacks these keys) decodes unchanged.
    var provider: String? = nil
    var estimatedCostUSD: Double? = nil
}

nonisolated struct HistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    var transcript: String
    let duration: TimeInterval
    let audioFileURL: URL?
    var modelUsed: String?
    var transcriptionTime: TimeInterval?
    // Optional so existing persisted JSON decodes unchanged; carry provenance + cost for stats.
    var provider: String? = nil
    var estimatedCostUSD: Double? = nil
    var rawTranscript: String? = nil
    var polishedTranscript: String? = nil
    var summary: String? = nil
    /// Set when transcription failed. The audio is kept so the user can retry from History.
    /// Optional so older persisted JSON decodes unchanged (nil = a normal, successful item).
    var failureReason: String? = nil

    var recordingLanguage: String? = nil
    var queuedRetry: DictationRetry? = nil

    var isFailed: Bool { failureReason != nil }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
        lhs.id == rhs.id
    }
}

class HistoryService: ObservableObject {
    static let shared = HistoryService()
    
    @Published var items: [HistoryItem] = []
    @Published private(set) var statsEntries: [HistoryStatsEntry] = []
    /// Failed items currently being re-transcribed.
    @Published private(set) var retryingItemIDs: Set<UUID> = []
    
    private let saveKey = "history_items"
    private let statsSaveKey = "history_stats_entries"
    
    private let recoveryStore = DictationRecoveryStore.live
    private var durableIDs: Set<UUID> = []
    private var retryWorker: Task<Void, Never>?

    private init() {
        loadStats()
        loadHistory()
        let restored = recoveryStore.load()
        durableIDs = Set(restored.map(\.id))
        items.removeAll { durableIDs.contains($0.id) }
        items = (items + restored).sorted { $0.date > $1.date }
        for item in restored where !item.isFailed && !statsEntries.contains(where: { $0.id == item.id }) {
            recordStats(for: item)
        }
    }

    /// Create a recoverable entry before transcription begins. While processing, the
    /// same entry is reserved so History cannot start a duplicate transcription.
    func beginDictation(audioURL: URL, duration: TimeInterval, language: String, processing: Bool = true) throws -> UUID {
        var item = HistoryItem(
            id: UUID(), date: .now, transcript: "", duration: duration, audioFileURL: audioURL,
            failureReason: processing ? "Recording saved — retry to transcribe" : "Dictation stopped",
            recordingLanguage: language)
        do {
            try recoveryStore.write(item)
            durableIDs.insert(item.id)
        } catch {
            item.failureReason = "Could not save recovery information"
            items.insert(item, at: 0)
            saveHistory()
            throw error
        }
        if processing { retryingItemIDs.insert(item.id) }
        items.insert(item, at: 0)
        return item.id
    }

    func finishDictation(id: UUID) {
        retryingItemIDs.remove(id)
    }

    func containsDictation(id: UUID) -> Bool {
        items.contains { $0.id == id }
    }

    /// Checkpoint raw text before polish, then replace it in place if polish succeeds.
    @discardableResult
    func saveDictationText(id: UUID, transcript: String, raw: String, outcome: TranscriptionOutcome) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var item = items[index]
        item.transcript = transcript
        item.rawTranscript = raw
        item.polishedTranscript = transcript == raw ? nil : transcript
        item.modelUsed = outcome.modelLabel
        item.transcriptionTime = outcome.transcriptionTime
        item.provider = outcome.provider.rawValue
        item.estimatedCostUSD = outcome.estimatedCostUSD
        item.failureReason = nil
        item.queuedRetry = nil
        let saved = persist(item, at: index)
        recordStats(for: item)
        return saved
    }

    func failDictation(id: UUID, reason: String, retry: DictationRetry? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isFailed else { return }
        var item = items[index]
        item.failureReason = reason
        item.queuedRetry = retry
        _ = persist(item, at: index)
        if retry != nil { resumeQueuedDictations() }
    }

    func recordDictationError(_ error: Error, id: UUID, retryRoute: DictationRetryRoute?) -> String {
        let transient = (error as? RemoteTranscriptionClient.ClientError)?.allowsBackgroundRetry == true
        let offlineWithoutEngine = !NetworkReachability.shared.isOnline
            && error is TranscriptionCoordinator.CoordinatorError
        if let retryRoute, retryRoute == DictationRetryRoute.current, transient || offlineWithoutEngine {
            let retry = DictationRetry(route: retryRoute, nextAttempt: .now.addingTimeInterval(5))
            failDictation(id: id, reason: "Waiting to retry transcription", retry: retry)
            return "Audio saved. SpeakType will retry."
        }
        failDictation(id: id, reason: error.localizedDescription)
        return "Audio saved. Retry in History."
    }

    func resumeQueuedDictations() {
        guard retryWorker == nil, items.contains(where: { $0.queuedRetry != nil }) else { return }
        retryWorker = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.retryWorker = nil }
            while !Task.isCancelled {
                let queued = self.items.filter { $0.queuedRetry != nil }
                guard !queued.isEmpty else { return }
                if NetworkReachability.shared.isOnline,
                   !AudioRecordingService.shared.isRecordingOrStarting,
                   self.retryingItemIDs.isEmpty,
                   let item = queued.last(where: { ($0.queuedRetry?.nextAttempt ?? .distantFuture) <= .now }) {
                    await self.retryTranscription(id: item.id, automatically: true)
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @discardableResult
    private func persist(_ item: HistoryItem, at index: Int) -> Bool {
        if durableIDs.contains(item.id) {
            do {
                try recoveryStore.write(item)
            } catch {
                AppLogger.warning("Could not update saved dictation", category: AppLogger.transcription)
                items[index] = item
                return false
            }
        }
        items[index] = item
        if !durableIDs.contains(item.id) { saveHistory() }
        return true
    }
    
    /// Serial background queue for JSON encoding + UserDefaults writes, so saving a long
    /// history never blocks the main thread right after a dictation lands.
    private static let persistenceQueue = DispatchQueue(
        label: "com.speaktype.historyPersistence", qos: .utility)

    /// Strips noise tags and trims, but keeps line breaks from polished output.
    static func cleanedTranscript(_ text: String) -> String {
        WhisperService.normalizedPreservingLineBreaks(from: text)
    }

    private static func wordCount(of text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    func addItem(transcript: String, duration: TimeInterval, audioFileURL: URL? = nil, modelUsed: String? = nil, transcriptionTime: TimeInterval? = nil, provider: String? = nil, estimatedCostUSD: Double? = nil, rawTranscript: String? = nil, polishedTranscript: String? = nil) {
        let normalizedTranscript = Self.cleanedTranscript(transcript)
        guard !normalizedTranscript.isEmpty else { return }

        let timestamp = Date()
        let wordCount = Self.wordCount(of: normalizedTranscript)

        let newItem = HistoryItem(
            id: UUID(),
            date: timestamp,
            transcript: normalizedTranscript,
            duration: duration,
            audioFileURL: audioFileURL,
            modelUsed: modelUsed,
            transcriptionTime: transcriptionTime,
            provider: provider,
            estimatedCostUSD: estimatedCostUSD,
            rawTranscript: rawTranscript,
            polishedTranscript: polishedTranscript
        )
        let statsEntry = HistoryStatsEntry(
            id: newItem.id,
            date: timestamp,
            wordCount: wordCount,
            duration: duration,
            provider: provider,
            estimatedCostUSD: estimatedCostUSD
        )
        items.insert(newItem, at: 0) // Newest first
        statsEntries.insert(statsEntry, at: 0)
        saveHistory()
        saveStats()
    }

    /// Save a recording whose transcription failed, keeping its audio for a later retry.
    /// Failed items do not count toward statistics until a retry succeeds.
    @discardableResult
    func addFailedItem(audioFileURL: URL, duration: TimeInterval, errorMessage: String, modelUsed: String? = nil) -> UUID {
        let newItem = HistoryItem(
            id: UUID(),
            date: Date(),
            transcript: "",
            duration: duration,
            audioFileURL: audioFileURL,
            modelUsed: modelUsed,
            transcriptionTime: nil,
            failureReason: errorMessage
        )
        items.insert(newItem, at: 0)
        saveHistory()
        return newItem.id
    }

    /// Background retries only use the same cloud configuration. A manual retry is
    /// explicit and can use the current settings, e.g. after fixing a missing key.
    func retryTranscription(id: UUID, automatically: Bool = false) async {
        guard !retryingItemIDs.contains(id),
              let item = items.first(where: { $0.id == id }), item.isFailed,
              let audioURL = item.audioFileURL else { return }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            failDictation(id: id, reason: "Audio file missing")
            return
        }

        if automatically {
            guard let queued = item.queuedRetry, queued.route == DictationRetryRoute.current else {
                failDictation(id: id, reason: "Transcription settings changed — retry from History")
                return
            }
        }

        retryingItemIDs.insert(id)
        defer { retryingItemIDs.remove(id) }
        let language = item.recordingLanguage
            ?? UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
        do {
            let outcome: TranscriptionOutcome
            if automatically, let provider = TranscriptionModeUserDefaults.selectedRemoteProvider,
               let model = TranscriptionModeUserDefaults.selectedRemoteModel {
                outcome = try await RemoteTranscriptionClient(
                    provider: provider, model: model, requiredRetryRoute: item.queuedRetry?.route)
                    .transcribeDetailed(audioFile: audioURL, language: language)
            } else {
                outcome = try await TranscriptionCoordinator.transcribe(audioFile: audioURL, language: language)
            }
            try Task.checkCancellation()
            let raw = Self.cleanedTranscript(outcome.text)
            guard !raw.isEmpty else {
                failDictation(id: id, reason: "No speech detected")
                return
            }
            _ = saveDictationText(id: id, transcript: raw, raw: raw, outcome: outcome)
            // A delayed result can arrive after the user changed writing-polish preferences.
            // Only a user-initiated retry runs the current polish configuration.
            guard !automatically else { return }
            let finalText = Self.cleanedTranscript(
                await TranscriptionFinalizer.finalizeTranscript(rawTranscript: raw))
            if !Task.isCancelled, !finalText.isEmpty, finalText != raw {
                saveDictationText(id: id, transcript: finalText, raw: raw, outcome: outcome)
            }
        } catch is CancellationError {
            return
        } catch {
            if automatically, var retry = item.queuedRetry,
               (error as? RemoteTranscriptionClient.ClientError)?.allowsBackgroundRetry == true {
                retry.backOff()
                failDictation(id: id, reason: "Waiting to retry transcription", retry: retry)
            } else {
                failDictation(id: id, reason: error.localizedDescription)
            }
        }
    }

    private func recordStats(for item: HistoryItem) {
        statsEntries.removeAll { $0.id == item.id }
        statsEntries.append(
            HistoryStatsEntry(
                id: item.id, date: item.date, wordCount: Self.wordCount(of: item.transcript),
                duration: item.duration, provider: item.provider, estimatedCostUSD: item.estimatedCostUSD)
        )
        statsEntries.sort { $0.date > $1.date }
        saveStats()
    }

    /// Most recent successful transcript, for "Paste last transcript".
    var lastTranscriptText: String? {
        items.first(where: { !$0.isFailed && !$0.transcript.isEmpty })?.transcript
    }

    func setPolishedTranscript(_ text: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        item.polishedTranscript = text
        item.transcript = text
        persist(item, at: index)
    }

    func setSummary(_ text: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        item.summary = text
        persist(item, at: index)
    }
    
    func deleteItem(at offsets: IndexSet, deleteAudioFile: Bool = true) {
        let ids = offsets.compactMap { items.indices.contains($0) ? items[$0].id : nil }
        for id in ids { deleteItem(id: id, deleteAudioFile: deleteAudioFile) }
    }

    func deleteItem(id: UUID, deleteAudioFile: Bool = true) {
        guard let item = items.first(where: { $0.id == id }), removeCheckpoint(for: id) else { return }
        items.removeAll { $0.id == id }
        statsEntries.removeAll { $0.id == id }
        if deleteAudioFile { removeAudioFileIfNeeded(for: item) }
        saveHistory()
        saveStats()
    }

    func clearAll() {
        let removed = items.filter { removeCheckpoint(for: $0.id) }
        let ids = Set(removed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        removed.forEach(removeAudioFileIfNeeded(for:))
        saveHistory()
    }

    private func removeCheckpoint(for id: UUID) -> Bool {
        guard durableIDs.contains(id) else { return true }
        do {
            try recoveryStore.remove(id: id)
            durableIDs.remove(id)
            return true
        } catch {
            AppLogger.warning("Could not remove saved dictation", category: AppLogger.transcription)
            return false
        }
    }

    func totalWordCount() -> Int {
        statsEntries.reduce(0) { $0 + $1.wordCount }
    }
    
    func transcriptionCount(since startDate: Date? = nil) -> Int {
        filteredStatsEntries(since: startDate).count
    }
    
    func totalDuration(since startDate: Date? = nil) -> TimeInterval {
        filteredStatsEntries(since: startDate).reduce(0) { $0 + $1.duration }
    }
    
    func wordCount(on day: Date, calendar: Calendar = .current) -> Int {
        let startOfDay = calendar.startOfDay(for: day)
        return statsEntries
            .filter { calendar.isDate($0.date, inSameDayAs: startOfDay) }
            .reduce(0) { $0 + $1.wordCount }
    }
    
    func statsEntries(since startDate: Date) -> [HistoryStatsEntry] {
        filteredStatsEntries(since: startDate)
    }
    
    private func saveHistory() {
        let snapshot = items.filter { !durableIDs.contains($0.id) }
        let key = saveKey
        Self.persistenceQueue.async {
            Self.encodeAndStore(snapshot, forKey: key)
        }
    }

    private func saveStats() {
        let snapshot = statsEntries
        let key = statsSaveKey
        Self.persistenceQueue.async {
            Self.encodeAndStore(snapshot, forKey: key)
        }
    }

    nonisolated private static func encodeAndStore<T: Encodable>(_ value: T, forKey key: String) {
        if let encoded = try? JSONEncoder().encode(value) {
            AppStorageIsolation.historyDefaults.set(encoded, forKey: key)
        }
    }
    
    private func loadHistory() {
        if let data = AppStorageIsolation.historyDefaults.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            let normalizedItems = decoded.compactMap { item -> HistoryItem? in
                // Failed items have no transcript yet; keep them so they can be retried.
                if item.isFailed { return item }
                let normalizedTranscript = Self.cleanedTranscript(item.transcript)
                guard !normalizedTranscript.isEmpty else { return nil }

                guard normalizedTranscript != item.transcript else { return item }

                return HistoryItem(
                    id: item.id,
                    date: item.date,
                    transcript: normalizedTranscript,
                    duration: item.duration,
                    audioFileURL: item.audioFileURL,
                    modelUsed: item.modelUsed,
                    transcriptionTime: item.transcriptionTime,
                    provider: item.provider,
                    estimatedCostUSD: item.estimatedCostUSD,
                    rawTranscript: item.rawTranscript,
                    polishedTranscript: item.polishedTranscript,
                    summary: item.summary,
                    failureReason: item.failureReason
                )
            }

            items = normalizedItems

            if normalizedItems.count != decoded.count
                || zip(decoded, normalizedItems).contains(where: { $0.transcript != $1.transcript })
            {
                saveHistory()
            }

            migrateStatsIfNeeded(from: normalizedItems)
        }
    }

    private func loadStats() {
        if let data = AppStorageIsolation.historyDefaults.data(forKey: statsSaveKey),
           let decoded = try? JSONDecoder().decode([HistoryStatsEntry].self, from: data) {
            statsEntries = decoded.sorted { $0.date > $1.date }
        }
    }
    
    private func migrateStatsIfNeeded(from historyItems: [HistoryItem]) {
        let historyItems = historyItems.filter { !$0.isFailed }
        guard statsEntries.isEmpty, !historyItems.isEmpty else { return }

        statsEntries = historyItems.map { item in
            HistoryStatsEntry(
                id: item.id,
                date: item.date,
                wordCount: item.transcript
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .count,
                duration: item.duration,
                provider: item.provider,
                estimatedCostUSD: item.estimatedCostUSD
            )
        }
        saveStats()
    }
    
    private func filteredStatsEntries(since startDate: Date?) -> [HistoryStatsEntry] {
        guard let startDate else { return statsEntries }
        return statsEntries.filter { $0.date >= startDate }
    }

    /// Total estimated USD spent on cloud transcription in the period (0 when all on-device).
    func totalEstimatedCostUSD(since startDate: Date?) -> Double {
        filteredStatsEntries(since: startDate).compactMap { $0.estimatedCostUSD }.reduce(0, +)
    }

    private func removeAudioFileIfNeeded(for item: HistoryItem) {
        guard let audioFileURL = item.audioFileURL else { return }
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else { return }
        try? FileManager.default.removeItem(at: audioFileURL)
    }

#if DEBUG
    /// Block until queued background saves have been written (tests read UserDefaults directly).
    func flushPendingSavesForTesting() {
        Self.persistenceQueue.sync {}
    }

    func resetAllDataForTesting() {
        // Never touch real history outside a test run.
        guard AppStorageIsolation.isRunningTests else { return }
        Self.persistenceQueue.sync {}
        items = []
        retryingItemIDs = []
        statsEntries = []
        AppStorageIsolation.historyDefaults.removeObject(forKey: saveKey)
        AppStorageIsolation.historyDefaults.removeObject(forKey: statsSaveKey)
    }
#endif
}
