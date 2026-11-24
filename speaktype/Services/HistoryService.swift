import Foundation
import Combine

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
    var transcript: String {
        didSet {
            if transcript != oldValue { wordCount = Self.countWords(in: transcript) }
        }
    }
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

    private(set) var wordCount = 0
    private(set) var hasAudio = false

    private enum CodingKeys: String, CodingKey {
        case id, date, transcript, duration, audioFileURL, modelUsed, transcriptionTime
        case provider, estimatedCostUSD, rawTranscript, polishedTranscript, summary
        case failureReason, recordingLanguage, queuedRetry
    }

    mutating func prepareForDisplay(audioExists: Bool? = nil) {
        wordCount = Self.countWords(in: transcript)
        hasAudio = audioExists ?? audioFileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private static func countWords(in text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).count(where: { !$0.isEmpty })
    }

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
    
    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var statsEntries: [HistoryStatsEntry] = [] {
        didSet { statsRevision += 1 }
    }
    private(set) var statsRevision = 0
    /// Failed items currently being re-transcribed.
    @Published private(set) var retryingItemIDs: Set<UUID> = []
    
    nonisolated private static let saveKey = "history_items"
    nonisolated private static let statsSaveKey = "history_stats_entries"
    private let recoveryStore: DictationRecoveryStore
    private var durableIDs: Set<UUID> = []
    private var deletingIDs: Set<UUID> = []
    private var retryWorker: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?

    private init() {
        let store = DictationRecoveryStore.live
        recoveryStore = store
        startupTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                Self.loadSnapshot(from: store)
            }.value
            guard let self else { return }
            let addedItems = items
            let addedStats = statsEntries
            durableIDs = snapshot.durableIDs
            items = addedItems.isEmpty ? snapshot.items : (addedItems + snapshot.items).sorted { $0.date > $1.date }
            statsEntries = addedStats.isEmpty ? snapshot.stats : (addedStats + snapshot.stats).sorted { $0.date > $1.date }
            startupTask = nil
            if snapshot.historyChanged || !addedItems.isEmpty { saveHistory() }
            if snapshot.statsChanged || !addedStats.isEmpty { saveStats() }
            resumeQueuedDictations()
        }
    }

    func waitForStartup() async {
        await startupTask?.value
    }

    /// Create a recoverable entry before transcription begins. While processing, the
    /// same entry is reserved so History cannot start a duplicate transcription.
    func beginDictation(audioURL: URL, duration: TimeInterval, language: String, processing: Bool = true) async throws -> UUID {
        await waitForStartup()
        var item = HistoryItem(
            id: UUID(), date: .now, transcript: "", duration: duration, audioFileURL: audioURL,
            failureReason: processing ? "Recording saved — retry to transcribe" : "Dictation stopped",
            recordingLanguage: language)
        item.prepareForDisplay(audioExists: true)
        let checkpoint = item
        let store = recoveryStore
        do {
            try await Self.performRecoveryIO { try store.write(checkpoint) }
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
        !deletingIDs.contains(id) && items.contains { $0.id == id }
    }

    /// Checkpoint raw text before polish, then replace it in place if polish succeeds.
    @discardableResult
    func saveDictationText(id: UUID, transcript: String, raw: String, outcome: TranscriptionOutcome) async -> Bool {
        guard !deletingIDs.contains(id),
              let index = items.firstIndex(where: { $0.id == id }) else { return false }
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
        recordStats(for: item)
        return await persist(item, at: index)
    }

    func failDictation(id: UUID, reason: String, retry: DictationRetry? = nil) async {
        guard !deletingIDs.contains(id),
              let index = items.firstIndex(where: { $0.id == id }), items[index].isFailed else { return }
        var item = items[index]
        item.failureReason = reason
        item.queuedRetry = retry
        _ = await persist(item, at: index)
        if retry != nil { resumeQueuedDictations() }
    }

    func recordDictationError(_ error: Error, id: UUID, retryRoute: DictationRetryRoute?) async -> String {
        let transient = (error as? RemoteTranscriptionClient.ClientError)?.allowsBackgroundRetry == true
        let offlineWithoutEngine = !NetworkReachability.shared.isOnline
            && error is TranscriptionCoordinator.CoordinatorError
        if let retryRoute, retryRoute == DictationRetryRoute.current, transient || offlineWithoutEngine {
            let retry = DictationRetry(route: retryRoute, nextAttempt: .now.addingTimeInterval(5))
            await failDictation(id: id, reason: "Waiting to retry transcription", retry: retry)
            return "Audio saved. SpeakType will retry."
        }
        await failDictation(id: id, reason: error.localizedDescription)
        return "Audio saved. Retry in History."
    }

    func resumeQueuedDictations() {
        guard retryWorker == nil, items.contains(where: { $0.queuedRetry != nil }) else { return }
        retryWorker = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.retryWorker = nil }
            while !Task.isCancelled {
                guard self.items.contains(where: { $0.queuedRetry != nil }) else { return }
                if NetworkReachability.shared.isOnline,
                   !AudioRecordingService.shared.isRecordingOrStarting,
                   self.retryingItemIDs.isEmpty,
                   let item = self.items.last(where: {
                       !self.deletingIDs.contains($0.id)
                           && ($0.queuedRetry?.nextAttempt ?? .distantFuture) <= .now
                   }) {
                    await self.retryTranscription(id: item.id, automatically: true)
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @discardableResult
    private func persist(_ item: HistoryItem, at index: Int) async -> Bool {
        items[index] = item
        guard durableIDs.contains(item.id) else {
            saveHistory()
            return true
        }
        let store = recoveryStore
        do {
            try await Self.performRecoveryIO { try store.write(item) }
            return containsDictation(id: item.id)
        } catch {
            AppLogger.warning("Could not update saved dictation", category: AppLogger.transcription)
            return false
        }
    }

    private static let persistenceQueue = DispatchQueue(
        label: "com.speaktype.historyPersistence", qos: .utility)

    /// Submit writes and deletes in the order they were requested on the main actor.
    /// A delete queued after a checkpoint always wins, even if a model is still running.
    private static let recoveryQueue = DispatchQueue(
        label: "com.speaktype.dictationRecovery", qos: .userInitiated)

    private static func performRecoveryIO<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            recoveryQueue.async {
                continuation.resume(with: Result { try operation() })
            }
        }
    }

    /// Strips noise tags and trims, but keeps line breaks from polished output.
    nonisolated static func cleanedTranscript(_ text: String) -> String {
        WhisperService.normalizedPreservingLineBreaks(from: text)
    }

    func addItem(transcript: String, duration: TimeInterval, audioFileURL: URL? = nil, modelUsed: String? = nil, transcriptionTime: TimeInterval? = nil, provider: String? = nil, estimatedCostUSD: Double? = nil, rawTranscript: String? = nil, polishedTranscript: String? = nil) {
        let normalizedTranscript = Self.cleanedTranscript(transcript)
        guard !normalizedTranscript.isEmpty else { return }

        let timestamp = Date()
        var newItem = HistoryItem(
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
        newItem.prepareForDisplay(audioExists: audioFileURL != nil)
        let statsEntry = HistoryStatsEntry(
            id: newItem.id,
            date: timestamp,
            wordCount: newItem.wordCount,
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
        var newItem = HistoryItem(
            id: UUID(),
            date: Date(),
            transcript: "",
            duration: duration,
            audioFileURL: audioFileURL,
            modelUsed: modelUsed,
            transcriptionTime: nil,
            failureReason: errorMessage
        )
        newItem.prepareForDisplay(audioExists: true)
        items.insert(newItem, at: 0)
        saveHistory()
        return newItem.id
    }

    /// Background retries only use the same cloud configuration. A manual retry is
    /// explicit and can use the current settings, e.g. after fixing a missing key.
    func retryTranscription(id: UUID, automatically: Bool = false) async {
        guard !retryingItemIDs.contains(id), !deletingIDs.contains(id),
              let item = items.first(where: { $0.id == id }), item.isFailed,
              let audioURL = item.audioFileURL else { return }

        retryingItemIDs.insert(id)
        defer { retryingItemIDs.remove(id) }
        let exists = await Task.detached(priority: .utility) {
            FileManager.default.fileExists(atPath: audioURL.path)
        }.value
        guard containsDictation(id: id), !Task.isCancelled else { return }
        guard exists else {
            await failDictation(id: id, reason: "Audio file missing")
            return
        }

        if automatically {
            guard let queued = item.queuedRetry, queued.route == DictationRetryRoute.current else {
                await failDictation(id: id, reason: "Transcription settings changed — retry from History")
                return
            }
        }

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
                await failDictation(id: id, reason: "No speech detected")
                return
            }
            _ = await saveDictationText(id: id, transcript: raw, raw: raw, outcome: outcome)
            // A delayed result can arrive after the user changed writing-polish preferences.
            // Only a user-initiated retry runs the current polish configuration.
            guard !automatically, !Task.isCancelled, containsDictation(id: id) else { return }
            let finalText = Self.cleanedTranscript(
                await TranscriptionFinalizer.finalizeTranscript(rawTranscript: raw))
            if !Task.isCancelled, !finalText.isEmpty, finalText != raw {
                await saveDictationText(id: id, transcript: finalText, raw: raw, outcome: outcome)
            }
        } catch is CancellationError {
            return
        } catch {
            if automatically, var retry = item.queuedRetry,
               (error as? RemoteTranscriptionClient.ClientError)?.allowsBackgroundRetry == true {
                retry.backOff()
                await failDictation(id: id, reason: "Waiting to retry transcription", retry: retry)
            } else {
                await failDictation(id: id, reason: error.localizedDescription)
            }
        }
    }

    private func recordStats(for item: HistoryItem) {
        statsEntries.removeAll { $0.id == item.id }
        statsEntries.append(
            HistoryStatsEntry(
                id: item.id, date: item.date, wordCount: item.wordCount,
                duration: item.duration, provider: item.provider, estimatedCostUSD: item.estimatedCostUSD)
        )
        statsEntries.sort { $0.date > $1.date }
        saveStats()
    }

    /// Most recent successful transcript, for "Paste last transcript".
    var lastTranscriptText: String? {
        items.first(where: { !$0.isFailed && !$0.transcript.isEmpty })?.transcript
    }

    func setPolishedTranscript(_ text: String, for id: UUID) async {
        guard !deletingIDs.contains(id),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        item.polishedTranscript = text
        item.transcript = text
        await persist(item, at: index)
    }

    func setSummary(_ text: String, for id: UUID) async {
        guard !deletingIDs.contains(id),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        item.summary = text
        await persist(item, at: index)
    }
    
    func deleteItem(id: UUID, deleteAudioFile: Bool = true) async {
        await waitForStartup()
        guard let item = items.first(where: { $0.id == id }) else { return }
        await delete([item], deleteAudioFile: deleteAudioFile, preserveStats: false)
    }

    func clearAll() async {
        await waitForStartup()
        await delete(items, deleteAudioFile: true, preserveStats: true)
    }

    private func delete(_ candidates: [HistoryItem], deleteAudioFile: Bool, preserveStats: Bool) async {
        let candidates = candidates.filter { deletingIDs.insert($0.id).inserted }
        guard !candidates.isEmpty else { return }
        let store = recoveryStore
        let checkpoints = durableIDs
        let removed: Set<UUID>
        do {
            removed = try await Self.performRecoveryIO {
                Self.removeFiles(for: candidates, checkpoints: checkpoints,
                                 store: store, deleteAudioFile: deleteAudioFile)
            }
        } catch {
            removed = []
        }
        deletingIDs.subtract(candidates.map(\.id))
        if removed.count != candidates.count {
            AppLogger.warning("Could not remove saved dictation", category: AppLogger.transcription)
        }
        items.removeAll { removed.contains($0.id) }
        durableIDs.subtract(removed)
        if !preserveStats { statsEntries.removeAll { removed.contains($0.id) } }
        saveHistory()
        if !preserveStats { saveStats() }
    }

    nonisolated private static func removeFiles(
        for candidates: [HistoryItem], checkpoints: Set<UUID>,
        store: DictationRecoveryStore, deleteAudioFile: Bool
    ) -> Set<UUID> {
        Set(candidates.compactMap { item in
            if checkpoints.contains(item.id) {
                do { try store.remove(id: item.id) } catch { return nil }
            }
            if deleteAudioFile, let url = item.audioFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            return item.id
        })
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
        guard startupTask == nil else { return }
        let snapshot = items.filter { !durableIDs.contains($0.id) }
        let key = Self.saveKey
        Self.persistenceQueue.async {
            Self.encodeAndStore(snapshot, forKey: key)
        }
    }

    private func saveStats() {
        guard startupTask == nil else { return }
        let snapshot = statsEntries
        let key = Self.statsSaveKey
        Self.persistenceQueue.async {
            Self.encodeAndStore(snapshot, forKey: key)
        }
    }

    nonisolated private static func encodeAndStore<T: Encodable>(_ value: T, forKey key: String) {
        if let encoded = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private nonisolated struct Snapshot {
        let items: [HistoryItem]
        let stats: [HistoryStatsEntry]
        let durableIDs: Set<UUID>
        let historyChanged: Bool
        let statsChanged: Bool
    }

    nonisolated private static func loadSnapshot(from store: DictationRecoveryStore) -> Snapshot {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        let decoded = defaults.data(forKey: saveKey)
            .flatMap { try? decoder.decode([HistoryItem].self, from: $0) } ?? []
        var historyChanged = false
        let legacy = decoded.compactMap { entry -> HistoryItem? in
            var item = entry
            if !item.isFailed {
                let normalized = cleanedTranscript(item.transcript)
                if normalized != item.transcript { historyChanged = true }
                guard !normalized.isEmpty else {
                    historyChanged = true
                    return nil
                }
                if normalized != item.transcript { item.transcript = normalized }
            }
            item.prepareForDisplay()
            return item
        }

        let restored = store.load().map { entry in
            var item = entry
            item.prepareForDisplay()
            return item
        }
        let ids = Set(restored.map(\.id))
        let items = (legacy.filter { !ids.contains($0.id) } + restored).sorted { $0.date > $1.date }

        let savedStats = defaults.data(forKey: statsSaveKey)
            .flatMap { try? decoder.decode([HistoryStatsEntry].self, from: $0) } ?? []
        let statsIDs = Set(savedStats.map(\.id))
        let missingStats = (savedStats.isEmpty ? items : restored)
            .filter { !$0.isFailed && !statsIDs.contains($0.id) }
            .map {
                HistoryStatsEntry(id: $0.id, date: $0.date, wordCount: $0.wordCount,
                                  duration: $0.duration, provider: $0.provider,
                                  estimatedCostUSD: $0.estimatedCostUSD)
            }
        return Snapshot(items: items, stats: (savedStats + missingStats).sorted { $0.date > $1.date },
                        durableIDs: ids, historyChanged: historyChanged, statsChanged: !missingStats.isEmpty)
    }

    private func filteredStatsEntries(since startDate: Date?) -> [HistoryStatsEntry] {
        guard let startDate else { return statsEntries }
        return statsEntries.filter { $0.date >= startDate }
    }

    /// Total estimated USD spent on cloud transcription in the period (0 when all on-device).
    func totalEstimatedCostUSD(since startDate: Date?) -> Double {
        filteredStatsEntries(since: startDate).compactMap { $0.estimatedCostUSD }.reduce(0, +)
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
        UserDefaults.standard.removeObject(forKey: Self.saveKey)
        UserDefaults.standard.removeObject(forKey: Self.statsSaveKey)
    }
#endif
}


nonisolated struct DashboardHistoryMetrics {
    let wordCount: Int
    let todayCount: Int
    let allTimeCount: Int
    let weeklyData: [(day: String, count: Int)]

    init(entries: [HistoryStatsEntry], now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var words = 0
        var todayCount = 0
        var dayCounts: [Date: Int] = [:]
        for entry in entries {
            words += entry.wordCount
            if entry.date >= today { todayCount += 1 }
            if entry.date >= weekStart {
                dayCounts[calendar.startOfDay(for: entry.date), default: 0] += 1
            }
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE"
        self.wordCount = words
        self.todayCount = todayCount
        self.allTimeCount = entries.count
        self.weeklyData = (-6...0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return (String(formatter.string(from: date).prefix(3)), dayCounts[date, default: 0])
        }
    }
}


nonisolated enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        }
    }
}

nonisolated struct DailyWordCount: Identifiable {
    var id: Date { date }
    let date: Date
    let wordCount: Int
    let dateString: String
}

nonisolated struct HistoryPeriodMetrics {
    let buckets: [DailyWordCount]
    let transcriptionCount: Int
    let totalDuration: TimeInterval
    let totalCost: Double
    let totalWords: Int
    let bestDay: Int

    static let empty = Self(entries: [], period: .week, now: .now)

    var dailyAverage: Int { buckets.isEmpty ? 0 : totalWords / buckets.count }
    var averageWordsPerTranscription: Int {
        transcriptionCount == 0 ? 0 : totalWords / transcriptionCount
    }

    init(entries: [HistoryStatsEntry], period: StatisticsPeriod, now: Date, calendar: Calendar = .current) {
        let start = calendar.date(byAdding: .day, value: 1 - period.days, to: now) ?? now
        let unit: Calendar.Component = period == .year ? .month : .day
        func bucket(for date: Date) -> Date {
            calendar.dateInterval(of: unit, for: date)?.start ?? calendar.startOfDay(for: date)
        }
        let lastBucket = bucket(for: now)
        var counts: [Date: Int] = [:]
        var notes = 0
        var duration: TimeInterval = 0
        var cost = 0.0
        for entry in entries where entry.date >= start {
            notes += 1
            duration += entry.duration
            cost += entry.estimatedCostUSD ?? 0
            counts[bucket(for: entry.date), default: 0] += entry.wordCount
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = unit == .month ? "MMM" : "MMM d"
        var date = bucket(for: start)
        var buckets: [DailyWordCount] = []
        while date <= lastBucket {
            buckets.append(DailyWordCount(date: date, wordCount: counts[date, default: 0],
                                          dateString: formatter.string(from: date)))
            guard let next = calendar.date(byAdding: unit, value: 1, to: date), next > date else { break }
            date = bucket(for: next)
        }
        self.buckets = buckets
        self.transcriptionCount = notes
        self.totalDuration = duration
        self.totalCost = cost
        self.totalWords = buckets.reduce(0) { $0 + $1.wordCount }
        self.bestDay = buckets.map(\.wordCount).max() ?? 0
    }
}
