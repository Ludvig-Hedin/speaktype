import AVFoundation
import AppKit
import Combine

@MainActor
final class MeetingRecorder: ObservableObject {
    static let shared = MeetingRecorder()
    @Published private(set) var active = false
    @Published private(set) var started: Date?
    @Published private(set) var notice: String?
    private var capture: MeetingCapture?
    private var id: UUID?
    private var pendingStop: Bool?
    private var stopping = false
    private var wakeObserver: NSObjectProtocol?
    private var dictationNoticeUntil = Date.distantPast
    private var monitor: Task<Void, Never>?
    var level: Float {
        #if DEBUG
        if let demoLevel { return demoLevel }
        #endif
        return capture?.liveLevel ?? 0
    }

    #if DEBUG
    private var demoLevel: Float?
    /// Debug-only: shows the meeting pill with a fake level and clock. Records nothing,
    /// writes nothing. Launch a Debug build with `--meeting-demo`.
    func runDemo() {
        guard !active else { return }
        active = true
        notice = nil
        started = Date().addingTimeInterval(-12)
        Task { @MainActor in
            let begin = Date()
            while Date().timeIntervalSince(begin) < 9 {
                let t = Date().timeIntervalSince(begin)
                demoLevel = Float(0.25 + 0.6 * abs(sin(t * 8)) * (0.5 + 0.5 * abs(sin(t * 1.3))))
                if t > 4.5, (started ?? .now) > Date().addingTimeInterval(-3600) {
                    started = Date().addingTimeInterval(-3845)  // shows the hour format
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
            demoLevel = nil
            active = false
            started = nil
        }
    }
    #endif

    func start() {
        guard !active, !AudioRecordingService.shared.isRecordingOrStarting else { return }
        active = true
        notice = "Starting meeting…"
        let device = AudioRecordingService.shared.preferredDeviceID
        let language = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"
        Task {
            do {
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    throw MeetingAudioError(message: "Allow microphone access in Settings to record a meeting.")
                }
                let meetingID = UUID()
                let url = MeetingFiles.mixURL(id: meetingID)
                let folder = url.deletingLastPathComponent()
                try await Task.detached {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                }.value
                _ = try await HistoryService.shared.beginDictation(audioURL: url, duration: 0, language: language,
                                                                  meetingID: meetingID)
                id = meetingID
                let begin = Date.now
                let session = try await Task.detached {
                    let capture = MeetingCapture()
                    do { try capture.start(folder: folder, deviceUID: device) }
                    catch { capture.stop(); throw error }
                    return capture
                }.value
                capture = session
                wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                    object: nil, queue: nil) { [weak session] _ in session?.didWake() }
                started = begin
                notice = session.health.notice
                monitor = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled, let self, let capture = self.capture else { return }
                        let health = await Task.detached { capture.poll() }.value
                        guard !Task.isCancelled, self.capture === capture else { return }
                        if health.failed {
                            self.stop(transcribe: false)
                            return
                        }
                        if Date.now >= self.dictationNoticeUntil { self.notice = health.notice }
                    }
                }
                if let pendingStop { stop(transcribe: pendingStop) }
            } catch {
                if let id {
                    HistoryService.shared.revealStoppedMeeting(id: id)
                    await HistoryService.shared.failDictation(id: id, reason: error.localizedDescription)
                    HistoryService.shared.finishDictation(id: id)
                }
                finish(message: error.localizedDescription)
            }
        }
    }

    func dictationRequested() {
        guard !stopping else { return }
        dictationNoticeUntil = Date.now.addingTimeInterval(2)
        notice = "Stop the meeting to dictate."
    }

    func stop(transcribe: Bool) {
        guard active, !stopping else { return }
        guard let session = capture, let id else { pendingStop = transcribe; return }
        HistoryService.shared.revealStoppedMeeting(id: id)
        stopping = true
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver = nil }
        monitor?.cancel()
        monitor = nil
        capture = nil
        notice = "Saving meeting…"
        Task {
            let writeFailed = await Task.detached { session.stop() }.value
            let history = HistoryService.shared
            do {
                try await history.prepareMeeting(id: id)
                history.finishDictation(id: id)
                finish(message: writeFailed ? "Recording interrupted. Available audio saved in History." : nil)
                if transcribe { await history.retryTranscription(id: id) }
            } catch {
                if error is CancellationError || !history.containsDictation(id: id) {
                    history.finishDictation(id: id)
                    finish(message: nil)
                    return
                }
                await history.failDictation(id: id, reason: error.localizedDescription)
                history.finishDictation(id: id)
                finish(message: error.localizedDescription)
            }
        }
    }

    private func finish(message: String?) {
        started = nil
        notice = nil
        id = nil
        pendingStop = nil
        stopping = false
        active = false
        NotificationCenter.default.post(name: .meetingFinished, object: message)
    }
}
