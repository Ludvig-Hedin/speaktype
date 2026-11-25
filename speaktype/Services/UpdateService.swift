import AppKit
import Combine
import Foundation

/// Service to check for app updates and manage update preferences
class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var availableUpdate: AppVersion?
    @Published var isCheckingForUpdates = false
    @Published var lastCheckDate: Date?
    @Published var manualCheckMessage: String?

    // Install progress state
    @Published var isInstalling = false
    @Published var installProgress: Double = 0  // 0.0 – 1.0
    @Published var installPhase: String = ""
    @Published var installStatus: String = ""  // human-readable status
    @Published var installError: String?

    // Publisher to request UI display (e.g. show update window)
    let showUpdateWindowPublisher = PassthroughSubject<AppVersion, Never>()

    // User Defaults keys
    private let lastCheckDateKey = "lastUpdateCheckDate"
    private let skippedVersionKey = "skippedVersion"
    private let autoUpdateKey = "autoUpdate"
    private var manualCheckRequested = false
    private let lastReminderDateKey = "lastUpdateReminderDate"

    private init() {
        loadLastCheckDate()
    }

    // MARK: - Update Checking

    /// Check for updates from server
    func checkForUpdates(silent: Bool = false) async {
        if !silent {
            manualCheckMessage = nil
            manualCheckRequested = true
        }
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        defer {
            isCheckingForUpdates = false
            manualCheckRequested = false
        }

        do {
            var request = URLRequest(url: UpdateConfiguration.latestReleaseAPIURL)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("SpeakType/\(AppVersion.currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard release.assets.contains(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
                throw URLError(.fileDoesNotExist)
            }
            let releaseVersion = AppVersion(from: release)
            let currentVersion = AppVersion.currentVersion

            await MainActor.run {
                let manual = self.manualCheckRequested
                if AppVersion.isNewerVersion(releaseVersion.version, than: currentVersion) {
                    let skipped = self.isVersionSkipped(releaseVersion.version)
                    if manual || !skipped {
                        self.availableUpdate = releaseVersion
                        // Silent checks only raise the window on the reminder schedule so
                        // users aren’t nagged on every launch; manual “Check for Updates” always prompts.
                        if !manual {
                            if self.shouldShowReminder() {
                                self.showUpdateWindowPublisher.send(releaseVersion)
                            }
                        } else {
                            self.showUpdateWindowPublisher.send(releaseVersion)
                        }
                    } else {
                        self.availableUpdate = nil
                    }
                } else {
                    self.availableUpdate = nil
                    if manual { self.manualCheckMessage = "Taly is up to date." }
                }
                self.lastCheckDate = Date()
                self.saveLastCheckDate()
            }
        } catch {
            print("Failed to check for updates: \(error)")
            if manualCheckRequested { manualCheckMessage = "Could not check for updates. Try again in a moment." }
        }
    }

    /// Check if enough time has passed since last check (24 hours)
    func shouldCheckForUpdates() -> Bool {
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) / 3600 >= 24
    }

    /// Check if we should show the reminder (every 24 hours)
    func shouldShowReminder() -> Bool {
        guard availableUpdate != nil else { return false }
        let lastReminder = UserDefaults.standard.object(forKey: lastReminderDateKey) as? Date
        guard let lastReminder else { return true }
        return Date().timeIntervalSince(lastReminder) / 3600 >= 24
    }

    // MARK: - Version Management

    func skipVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: skippedVersionKey)
        availableUpdate = nil
    }

    private func isVersionSkipped(_ version: String) -> Bool {
        UserDefaults.standard.string(forKey: skippedVersionKey) == version
    }

    func markReminderShown() {
        UserDefaults.standard.set(Date(), forKey: lastReminderDateKey)
    }

    func clearSkippedVersion() {
        UserDefaults.standard.removeObject(forKey: skippedVersionKey)
    }

    // MARK: - Persistence

    private func saveLastCheckDate() {
        if let date = lastCheckDate {
            UserDefaults.standard.set(date, forKey: lastCheckDateKey)
        }
    }

    private func loadLastCheckDate() {
        lastCheckDate = UserDefaults.standard.object(forKey: lastCheckDateKey) as? Date
    }

    // MARK: - Auto Update

    var isAutoUpdateEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoUpdateKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoUpdateKey) }
    }

    // MARK: - Update Installation

    /// Download the DMG, mount it, copy the .app over the running installation, and relaunch.
    func installUpdate(url downloadURLString: String) {
        guard let downloadURL = URL(string: downloadURLString) else {
            setError("Invalid download URL.")
            return
        }

        // If the URL isn't a direct asset (falls back to HTML page), open browser instead.
        guard downloadURL.pathExtension == "dmg" else {
            NSWorkspace.shared.open(downloadURL)
            return
        }

        Task {
            await MainActor.run {
                self.isInstalling = true
                self.installProgress = 0
                self.installPhase = "Downloading"
                self.installStatus = "Preparing download…"
                self.installError = nil
            }

            do {
                // 1. Download DMG with progress
                let dmgURL = try await downloadWithProgress(from: downloadURL)

                // 2. Verify the DMG before mounting it
                await MainActor.run {
                    self.installPhase = "Verifying"
                    self.installStatus = "Checking downloaded update…"
                    self.setInstallProgress(0.84)
                }
                try await Task.detached(priority: .userInitiated) {
                    try Self.verifyDMG(at: dmgURL)
                }.value

                // 3. Mount the DMG
                await MainActor.run {
                    self.installPhase = "Mounting"
                    self.installStatus = "Opening downloaded update…"
                    self.setInstallProgress(0.9)
                }
                let mountPoint = try await Task.detached(priority: .userInitiated) {
                    try Self.mountDMG(at: dmgURL)
                }.value

                // 4. Find the .app inside the mounted volume
                await MainActor.run {
                    self.installPhase = "Installing"
                    self.installStatus = "Copying new app into place…"
                    self.setInstallProgress(0.95)
                }

                // 5. Find + replace the running app, then detach — all blocking work off the
                // main actor (this type is implicitly @MainActor) so the UI stays responsive.
                let installedApp = try await Task.detached(priority: .userInitiated) {
                    let appInDMG = try Self.findApp(in: mountPoint)
                    let installed = try Self.replaceCurrentApp(with: appInDMG)
                    Self.detachDMG(mountPoint: mountPoint)
                    return installed
                }.value

                // 7. Relaunch
                await MainActor.run {
                    self.installPhase = "Relaunching"
                    self.installStatus = "Finishing update…"
                    self.setInstallProgress(1)
                }
                relaunch(at: installedApp.path)

            } catch {
                await MainActor.run {
                    self.isInstalling = false
                    self.installError = error.localizedDescription
                    self.installPhase = ""
                    self.installStatus = ""
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func downloadWithProgress(from url: URL) async throws -> URL {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        let total = response.expectedContentLength  // may be -1 if unknown
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakType-update-\(UUID().uuidString).dmg")

        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(1024 * 64)
        let startedAt = Date()

        for try await byte in asyncBytes {
            buffer.append(byte)
            received += 1

            // Flush every 64 KB so the UI moves more smoothly.
            if buffer.count >= 1024 * 64 {
                handle.write(buffer)
                buffer.removeAll(keepingCapacity: true)

                if total > 0 {
                    let progress = Double(received) / Double(total)
                    let safeElapsed = max(Date().timeIntervalSince(startedAt), 0.1)
                    let bytesPerSecond = Double(received) / safeElapsed
                    await MainActor.run {
                        self.installPhase = "Downloading"
                        self.setInstallProgress(progress * 0.8)  // download = 0-80%
                        self.installStatus =
                            "\(Self.byteString(received)) of \(Self.byteString(total)) • \(Self.byteString(Int64(bytesPerSecond)))/s • \(Int(progress * 100))%"
                    }
                }
            }
        }

        // Flush remaining bytes
        if !buffer.isEmpty { handle.write(buffer) }

        await MainActor.run {
            self.installPhase = "Verifying"
            self.setInstallProgress(0.82)
            self.installStatus = "Download complete. Preparing update…"
        }

        return dest
    }

    nonisolated private static func verifyDMG(at dmgURL: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["verify", dmgURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            throw UpdateError.verificationFailed
        }
    }

    nonisolated private static func mountDMG(at dmgURL: URL) throws -> URL {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["attach", dmgURL.path, "-nobrowse", "-readonly", "-plist"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            throw UpdateError.mountFailed
        }

        let plistData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
            let dict = plist as? [String: Any],
            let entities = dict["system-entities"] as? [[String: Any]],
            let mountEntry = entities.first(where: { $0["mount-point"] != nil }),
            let mountPath = mountEntry["mount-point"] as? String
        else {
            throw UpdateError.mountFailed
        }

        return URL(fileURLWithPath: mountPath)
    }

    nonisolated private static func findApp(in mountPoint: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: nil
        )
        guard let appURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.appNotFoundInDMG
        }
        guard Bundle(url: appURL)?.bundleIdentifier == "com.ludvighedin.speaktype" else {
            throw UpdateError.invalidAppSignature
        }

        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", appURL.path]
        verify.standardOutput = FileHandle.nullDevice
        verify.standardError = FileHandle.nullDevice
        try verify.run()
        verify.waitUntilExit()
        guard verify.terminationStatus == 0 else { throw UpdateError.invalidAppSignature }

        let details = Process()
        details.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        details.arguments = ["-dv", "--verbose=4", appURL.path]
        let detailsPipe = Pipe()
        details.standardOutput = FileHandle.nullDevice
        details.standardError = detailsPipe
        try details.run()
        details.waitUntilExit()
        let signingText = String(
            data: detailsPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard details.terminationStatus == 0,
              signingText.contains("TeamIdentifier=XDBG7P4V96") else {
            throw UpdateError.invalidAppSignature
        }
        return appURL
    }

    /// File name the app should have in Applications. Older installs are called SpeakType.app.
    nonisolated static let appFileName = "Taly.app"

    /// Hidden staging folders an install leaves next to the app if it is interrupted.
    nonisolated static let stagingPrefixes = [".Taly-update-", ".SpeakType-update-"]

    /// Installs `sourceApp` over the app at `destURL` and returns where the app ends up.
    /// The new Contents folder is swapped in with one atomic rename, so the bundle folder stays
    /// the same item on disk and Dock or Finder links to it keep working, even after the rename
    /// to Taly.app. If that swap is not possible (e.g. another user owns the app folder), it
    /// falls back to replacing the whole bundle, as older versions did.
    nonisolated static func installUpdate(
        from sourceApp: URL,
        over destURL: URL,
        fileManager fm: FileManager = .default
    ) throws -> URL {
        let folder = destURL.deletingLastPathComponent()
        removeStagingLeftovers(in: folder, fileManager: fm)
        let staging = folder.appendingPathComponent(".Taly-update-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: sourceApp, to: staging)

        let contents = destURL.appendingPathComponent("Contents")
        let newContents = staging.appendingPathComponent("Contents")
        // After the swap the old contents sit in the staging folder, which `defer` removes.
        if renamex_np(newContents.path, contents.path, UInt32(RENAME_SWAP)) == 0 {
            // The bundle folder keeps its old flags; drop quarantine like a fresh copy would.
            removexattr(destURL.path, "com.apple.quarantine", 0)
        } else {
            _ = try fm.replaceItemAt(
                destURL,
                withItemAt: staging,
                backupItemName: ".Taly-update-backup.app"
            )
        }
        return renamedToCurrentName(destURL, fileManager: fm)
    }

    /// Removes staging folders left by an install that was interrupted (crash, power loss).
    nonisolated static func removeStagingLeftovers(
        in folder: URL,
        fileManager fm: FileManager = .default
    ) {
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where stagingPrefixes.contains(where: name.hasPrefix) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Gives an app in an Applications folder the current file name, so Finder and the Dock
    /// show "Taly". Leaves it as is anywhere else, or if that name is already taken.
    nonisolated static func renamedToCurrentName(
        _ appURL: URL,
        fileManager fm: FileManager = .default
    ) -> URL {
        let folder = appURL.deletingLastPathComponent()
        let target = folder.appendingPathComponent(appFileName)
        guard folder.lastPathComponent == "Applications",
              appURL.lastPathComponent.caseInsensitiveCompare(appFileName) != .orderedSame,
              !fm.fileExists(atPath: target.path)
        else { return appURL }
        do {
            try fm.moveItem(at: appURL, to: target)
            return target
        } catch {
            return appURL
        }
    }

    nonisolated private static func replaceCurrentApp(with sourceApp: URL) throws -> URL {
        try installUpdate(from: sourceApp, over: URL(fileURLWithPath: Bundle.main.bundlePath))
    }

    nonisolated private static func detachDMG(mountPoint: URL) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["detach", mountPoint.path, "-force"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    private func relaunch(at bundlePath: String) {
        // Use a shell to wait for the current process to exit, then reopen the app
        let pid = ProcessInfo.processInfo.processIdentifier

        // The path is passed as an argument ($1), never pasted into the script text.
        let script = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            open "$1"
            """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", script, "sh", bundlePath]
        try? proc.run()

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private func setError(_ message: String) {
        DispatchQueue.main.async {
            self.installError = message
            self.isInstalling = false
            self.installPhase = ""
            self.installStatus = ""
        }
    }

    @MainActor
    private func setInstallProgress(_ target: Double) {
        let clamped = min(max(target, installProgress), 1)
        installProgress = installProgress + (clamped - installProgress) * 0.45
        if clamped - installProgress < 0.01 {
            installProgress = clamped
        }
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case mountFailed
    case appNotFoundInDMG
    case copyFailed(String)
    case verificationFailed
    case invalidAppSignature

    var errorDescription: String? {
        switch self {
        case .mountFailed: return "Failed to mount the update disk image."
        case .appNotFoundInDMG: return "Could not find the app inside the downloaded update."
        case .copyFailed(let msg): return "Failed to install: \(msg)"
        case .verificationFailed: return "The downloaded update failed verification."
        case .invalidAppSignature: return "The update is not a valid Taly app."
        }
    }
}
