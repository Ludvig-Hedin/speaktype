import Foundation

/// Each new dictation is checkpointed on disk before any model call. A small atomic write
/// updates just that entry, so relaunch never depends on a background preferences write.
nonisolated struct DictationRecoveryStore {
    let directory: URL

    static var live: Self {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(directory: support.appendingPathComponent("\(AppStorageIsolation.supportFolderName)/DictationHistory", isDirectory: true))
    }

    func load() -> [HistoryItem] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in
            guard url.pathExtension == "json",
                let data = try? Data(contentsOf: url),
                let item = try? JSONDecoder().decode(HistoryItem.self, from: data),
                url.lastPathComponent == file(for: item.id).lastPathComponent
            else { return nil }
            return item
        }
    }

    func write(_ item: HistoryItem) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(item).write(to: file(for: item.id), options: .atomic)
    }

    func remove(id: UUID) throws {
        do {
            try FileManager.default.removeItem(at: file(for: id))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already removed.
        }
    }

    private func file(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}

/// A queued upload stays with the destination and mode the user selected for that dictation.
nonisolated struct DictationRetryRoute: Codable, Equatable {
    let mode: String
    let provider: String
    let model: String

    @MainActor static var current: Self? {
        let settings = TranscriptionModeUserDefaults.self
        guard settings.mode.canUseRemote, settings.isRemoteConfigured,
              let provider = settings.selectedRemoteProvider,
              let model = settings.selectedRemoteModel else { return nil }
        return Self(mode: settings.mode.rawValue, provider: provider.rawValue, model: model.id)
    }
}

nonisolated struct DictationRetry: Codable, Equatable {
    let route: DictationRetryRoute
    var nextAttempt: Date
    var delay: TimeInterval = 5

    mutating func backOff(now: Date = .now) {
        delay = min(delay * 2, 300)
        nextAttempt = now.addingTimeInterval(delay)
    }
}
