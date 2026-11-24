import XCTest
import Observation
@testable import speaktype

final class HistoryServiceTests: XCTestCase {
    
    var service: HistoryService!
    
    override func setUp() async throws {
        try await super.setUp()
        let history = await HistoryService.shared
        await history.waitForStartup()
        await MainActor.run {
            service = history
            history.resetAllDataForTesting()
        }
    }
    
    override func tearDown() {
        service.resetAllDataForTesting()
        super.tearDown()
    }
    
    func testAddItem() {
        XCTAssertTrue(service.items.isEmpty)
        
        let transcript = "Test Transcript"
        let duration: TimeInterval = 10.0
        
        service.addItem(transcript: transcript, duration: duration)
        
        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.transcript, transcript)
        XCTAssertEqual(service.items.first?.duration, duration)
    }
    
    func testHistoryWordCountTracksTranscriptEditsWithoutChangingJSON() throws {
        var item = HistoryItem(id: UUID(), date: .now, transcript: "first\nsecond",
                               duration: 2, audioFileURL: nil)
        item.prepareForDisplay()
        XCTAssertEqual(item.wordCount, 2)

        item.transcript = "Edited\ttext here"
        XCTAssertEqual(item.wordCount, 3)

        let data = try JSONEncoder().encode(item)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["wordCount"])
        var restored = try JSONDecoder().decode(HistoryItem.self, from: data)
        restored.prepareForDisplay()
        XCTAssertEqual(restored.wordCount, 3)
    }

    @MainActor
    func testPlaybackProgressDoesNotInvalidatePlaybackButtons() {
        let player = AudioPlayerService.shared
        let previousTime = player.currentTime
        defer { player.currentTime = previousTime }

        withObservationTracking {
            _ = player.isPlaying
            _ = player.currentAudioURL
        } onChange: {
            XCTFail("Playback controls should not observe progress ticks")
        }
        player.currentTime += 0.1
    }

    func testHistoryMetricsKeepTheRollingPeriodAndCalendarDayCounts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12)))
        let entries = [
            HistoryStatsEntry(id: UUID(), date: now, wordCount: 12, duration: 5, estimatedCostUSD: 0.01),
            HistoryStatsEntry(id: UUID(), date: now.addingTimeInterval(-86_400), wordCount: 8, duration: 4),
            HistoryStatsEntry(id: UUID(), date: now.addingTimeInterval(-6 * 86_400 - 1), wordCount: 4, duration: 2),
        ]

        let dashboard = DashboardHistoryMetrics(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(dashboard.wordCount, 24)
        XCTAssertEqual(dashboard.todayCount, 1)
        XCTAssertEqual(dashboard.weeklyData.map(\.count), [1, 0, 0, 0, 0, 1, 1])

        let week = HistoryPeriodMetrics(entries: entries, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(week.buckets.map(\.wordCount), [0, 0, 0, 0, 0, 8, 12])
        XCTAssertEqual(week.transcriptionCount, 2)
        XCTAssertEqual(week.totalDuration, 9)
        XCTAssertEqual(week.totalCost, 0.01)
        XCTAssertEqual(week.averageWordsPerTranscription, 10)

        let year = HistoryPeriodMetrics(entries: entries, period: .year, now: now, calendar: calendar)
        XCTAssertEqual(year.buckets.last?.wordCount, 24)
        XCTAssertEqual(year.totalDuration, 11)
    }

    func testPersistence() {
        let transcript = "Persistent Item"
        service.addItem(transcript: transcript, duration: 5.0)
        service.flushPendingSavesForTesting()
        
        // Simulate app restart by re-initializing (or checking UserDefaults directly)
        // Since 'init' loads from UserDefaults, creating a new instance isn't easy with singleton,
        // but we can check if UserDefaults has the data.
        
        guard let data = AppStorageIsolation.historyDefaults.data(forKey: "history_items"),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            XCTFail("Failed to load from UserDefaults")
            return
        }
        
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.transcript, transcript)
    }
    
    @MainActor
    func testDeleteItem() async {
        service.addItem(transcript: "Item 1", duration: 1.0)
        service.addItem(transcript: "Item 2", duration: 2.0)
        
        XCTAssertEqual(service.items.count, 2)
        
        let itemToDelete = service.items.last! // "Item 1" (since newest is first)
        await service.deleteItem(id: itemToDelete.id)
        
        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.transcript, "Item 2")
    }

    @MainActor
    func testDeleteItemRemovesAudioFileWhenPresent() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try Data("audio".utf8).write(to: audioURL)

        service.addItem(
            transcript: "Item with audio",
            duration: 1.0,
            audioFileURL: audioURL
        )

        let itemID = try XCTUnwrap(service.items.first?.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))

        await service.deleteItem(id: itemID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertTrue(service.items.isEmpty)
    }

    @MainActor
    func testClearAllPreservesStatsHistory() async {
        service.addItem(transcript: "One short note", duration: 10.0)
        service.addItem(transcript: "Another slightly longer note", duration: 20.0)

        let countBeforeClear = service.transcriptionCount()
        let wordsBeforeClear = service.totalWordCount()
        let durationBeforeClear = service.totalDuration()

        await service.clearAll()

        XCTAssertTrue(service.items.isEmpty)
        XCTAssertEqual(service.transcriptionCount(), countBeforeClear)
        XCTAssertEqual(service.totalWordCount(), wordsBeforeClear)
        XCTAssertEqual(service.totalDuration(), durationBeforeClear)
    }

    func testStatsPersistenceUsesSeparateStore() {
        service.addItem(transcript: "Persistent stats entry", duration: 5.0)
        service.flushPendingSavesForTesting()

        guard let data = AppStorageIsolation.historyDefaults.data(forKey: "history_stats_entries"),
              let decoded = try? JSONDecoder().decode([HistoryStatsEntry].self, from: data) else {
            XCTFail("Failed to load stats from UserDefaults")
            return
        }

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.wordCount, 3)
        XCTAssertEqual(decoded.first?.duration, 5.0)
    }

    func testFailedItemKeepsAudioAndSkipsStats() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        service.addFailedItem(audioFileURL: audioURL, duration: 3.0, errorMessage: "Network error")

        let item = try XCTUnwrap(service.items.first)
        XCTAssertTrue(item.isFailed)
        XCTAssertEqual(item.failureReason, "Network error")
        XCTAssertEqual(item.audioFileURL, audioURL)
        XCTAssertEqual(service.transcriptionCount(), 0)
        XCTAssertNil(service.lastTranscriptText)
    }

    func testLegacyItemWithoutFailureFieldDecodes() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","date":0,"transcript":"Hi","duration":1}]"#
        let decoded = try JSONDecoder().decode([HistoryItem].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertFalse(decoded[0].isFailed)
    }

    func testAddItemPreservesLineBreaks() {
        service.addItem(transcript: "First point.\n\n- one\n- two  [BLANK_AUDIO]", duration: 2.0)
        XCTAssertEqual(service.items.first?.transcript, "First point.\n\n- one\n- two")
    }
}

final class DictationRecoveryTests: XCTestCase {
    func testInterruptedDictationCanBeRecoveredOnRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationRecoveryStore(directory: directory)
        let item = HistoryItem(
            id: UUID(), date: Date(), transcript: "", duration: 3,
            audioFileURL: directory.appendingPathComponent("recording.wav"),
            failureReason: "Recording saved", recordingLanguage: "sv")
        try store.write(item)
        let restored = try XCTUnwrap(store.load().first)
        XCTAssertEqual(restored.id, item.id)
        XCTAssertEqual(restored.audioFileURL, item.audioFileURL)
        XCTAssertEqual(restored.recordingLanguage, "sv")
        XCTAssertTrue(restored.isFailed)

        var completed = item
        completed.transcript = "Sparad text"
        completed.failureReason = nil
        try store.write(completed)
        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(store.load().first?.transcript, "Sparad text")

        try store.remove(id: item.id)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testOnlyTransientCloudErrorsAreQueued() {
        typealias Failure = RemoteTranscriptionClient.ClientError
        XCTAssertTrue(Failure.network("Connection lost", transient: true).allowsBackgroundRetry)
        XCTAssertTrue(Failure.httpStatus(503).allowsBackgroundRetry)
        XCTAssertFalse(Failure.network("Bad certificate", transient: false).allowsBackgroundRetry)
        XCTAssertFalse(Failure.rateLimited.allowsBackgroundRetry)
        XCTAssertFalse(Failure.unauthorized.allowsBackgroundRetry)
    }

    /// Guards the fix for tests wiping the user's real history: a test run must never use
    /// the app's real preferences domain or Application Support folder.
    func testTestsUseIsolatedHistoryStorage() {
        XCTAssertTrue(AppStorageIsolation.isRunningTests)
        XCTAssertFalse(AppStorageIsolation.historyDefaults === UserDefaults.standard)
        XCTAssertTrue(DictationRecoveryStore.live.directory.path.contains("/SpeakType-Tests/"))
    }
}
