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
    
    private init() {
        loadStats()
        loadHistory()
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

    /// Re-run transcription (and optional polish) for a failed item and update it in place.
    func retryTranscription(id: UUID) async {
        guard !retryingItemIDs.contains(id),
            let item = items.first(where: { $0.id == id }), item.isFailed,
            let audioURL = item.audioFileURL
        else { return }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            markFailed(id: id, reason: "Audio file missing")
            return
        }

        retryingItemIDs.insert(id)
        defer { retryingItemIDs.remove(id) }

        let language = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
        do {
            let outcome = try await TranscriptionCoordinator.transcribe(
                audioFile: audioURL, language: language)
            let raw = Self.cleanedTranscript(outcome.text)
            guard !raw.isEmpty else {
                markFailed(id: id, reason: "No speech detected")
                return
            }
            let finalText = Self.cleanedTranscript(
                await TranscriptionFinalizer.finalizeTranscript(rawTranscript: raw))
            completeFailedItem(
                id: id,
                transcript: finalText.isEmpty ? raw : finalText,
                rawTranscript: raw,
                outcome: outcome
            )
        } catch is CancellationError {
            return
        } catch {
            markFailed(id: id, reason: error.localizedDescription)
        }
    }

    private func completeFailedItem(id: UUID, transcript: String, rawTranscript: String, outcome: TranscriptionOutcome) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].transcript = transcript
        items[index].rawTranscript = rawTranscript
        items[index].polishedTranscript = transcript == rawTranscript ? nil : transcript
        items[index].modelUsed = outcome.modelLabel
        items[index].transcriptionTime = outcome.transcriptionTime
        items[index].provider = outcome.provider.rawValue
        items[index].estimatedCostUSD = outcome.estimatedCostUSD
        items[index].failureReason = nil

        let item = items[index]
        statsEntries.removeAll { $0.id == id }
        statsEntries.append(
            HistoryStatsEntry(
                id: id,
                date: item.date,
                wordCount: Self.wordCount(of: transcript),
                duration: item.duration,
                provider: item.provider,
                estimatedCostUSD: item.estimatedCostUSD
            )
        )
        statsEntries.sort { $0.date > $1.date }
        saveHistory()
        saveStats()
    }

    private func markFailed(id: UUID, reason: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].failureReason = reason
        saveHistory()
    }

    /// Most recent successful transcript, for "Paste last transcript".
    var lastTranscriptText: String? {
        items.first(where: { !$0.isFailed && !$0.transcript.isEmpty })?.transcript
    }

    func setPolishedTranscript(_ text: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].polishedTranscript = text
        items[index].transcript = text
        saveHistory()
    }

    func setSummary(_ text: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].summary = text
        saveHistory()
    }
    
    func deleteItem(at offsets: IndexSet, deleteAudioFile: Bool = true) {
        let itemsToDelete = offsets.compactMap { items.indices.contains($0) ? items[$0] : nil }
        let deletedIds = Set(itemsToDelete.map(\.id))
        items.remove(atOffsets: offsets)
        // Statistics read from `statsEntries`, not `items`; without this mirror-delete a removed
        // transcript keeps inflating word/duration totals forever (the orphaned entry is also
        // re-persisted across launches). Keep the two stores in lockstep.
        statsEntries.removeAll { deletedIds.contains($0.id) }
        if deleteAudioFile {
            itemsToDelete.forEach(removeAudioFileIfNeeded(for:))
        }
        saveHistory()
        saveStats()
    }

    func deleteItem(id: UUID, deleteAudioFile: Bool = true) {
        let itemToDelete = items.first { $0.id == id }
        items.removeAll { $0.id == id }
        statsEntries.removeAll { $0.id == id }
        if deleteAudioFile, let itemToDelete {
            removeAudioFileIfNeeded(for: itemToDelete)
        }
        saveHistory()
        saveStats()
    }

    func clearAll() {
        items.forEach(removeAudioFileIfNeeded(for:))
        items.removeAll()
        saveHistory()
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
        let snapshot = items
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
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
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
        if let data = UserDefaults.standard.data(forKey: statsSaveKey),
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
        Self.persistenceQueue.sync {}
        items = []
        retryingItemIDs = []
        statsEntries = []
        UserDefaults.standard.removeObject(forKey: saveKey)
        UserDefaults.standard.removeObject(forKey: statsSaveKey)
    }
#endif
}
