import Foundation
import Combine
import SwiftUI // For IndexSet operations if needed, though Foundation usually covers it, but error says missing import.

struct HistoryStatsEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let wordCount: Int
    let duration: TimeInterval
    // Optional so existing persisted JSON (which lacks these keys) decodes unchanged.
    var provider: String? = nil
    var estimatedCostUSD: Double? = nil
}

struct HistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let transcript: String
    let duration: TimeInterval
    let audioFileURL: URL?
    let modelUsed: String?
    let transcriptionTime: TimeInterval?
    // Optional so existing persisted JSON decodes unchanged; carry provenance + cost for stats.
    var provider: String? = nil
    var estimatedCostUSD: Double? = nil

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
    
    private let saveKey = "history_items"
    private let statsSaveKey = "history_stats_entries"
    
    private init() {
        loadStats()
        loadHistory()
    }
    
    func addItem(transcript: String, duration: TimeInterval, audioFileURL: URL? = nil, modelUsed: String? = nil, transcriptionTime: TimeInterval? = nil, provider: String? = nil, estimatedCostUSD: Double? = nil) {
        let normalizedTranscript = WhisperService.normalizedTranscription(from: transcript)
        guard !normalizedTranscript.isEmpty else { return }

        let timestamp = Date()
        let wordCount = normalizedTranscript.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        let newItem = HistoryItem(
            id: UUID(),
            date: timestamp,
            transcript: normalizedTranscript,
            duration: duration,
            audioFileURL: audioFileURL,
            modelUsed: modelUsed,
            transcriptionTime: transcriptionTime,
            provider: provider,
            estimatedCostUSD: estimatedCostUSD
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
        items.removeAll()
        statsEntries.removeAll()
        saveHistory()
        saveStats()
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
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func saveStats() {
        if let encoded = try? JSONEncoder().encode(statsEntries) {
            UserDefaults.standard.set(encoded, forKey: statsSaveKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            let normalizedItems = decoded.compactMap { item -> HistoryItem? in
                let normalizedTranscript = WhisperService.normalizedTranscription(
                    from: item.transcript)
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
                    estimatedCostUSD: item.estimatedCostUSD
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
    func resetAllDataForTesting() {
        items = []
        statsEntries = []
        UserDefaults.standard.removeObject(forKey: saveKey)
        UserDefaults.standard.removeObject(forKey: statsSaveKey)
    }
#endif
}
