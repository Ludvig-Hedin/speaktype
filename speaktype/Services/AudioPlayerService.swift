import Foundation
import AVFoundation
import Observation

/// Service for playing back audio recordings
@Observable
class AudioPlayerService: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayerService()
    
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentAudioURL: URL?
    
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    
    @ObservationIgnored private var loadGeneration = 0

    private override init() {
        super.init()
    }
    
    /// A newly created player is handed to the main actor once, before playback or
    /// delegate registration. The background task never touches it after the handoff.
    private nonisolated struct PreparedPlayer: @unchecked Sendable {
        let player: AVAudioPlayer
    }

    @discardableResult
    func loadAudio(from url: URL) async -> Bool {
        reset()
        let generation = loadGeneration
        let prepared = await Task.detached(priority: .userInitiated) {
            Self.prepareAudio(from: url)
        }.value
        guard !Task.isCancelled, generation == loadGeneration, let prepared else { return false }
        let player = prepared.player
        player.delegate = self
        audioPlayer = player
        currentAudioURL = url
        duration = player.duration
        return true
    }

    nonisolated private static func prepareAudio(from url: URL) -> PreparedPlayer? {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        return PreparedPlayer(player: player)
    }

    /// Start or resume playback
    func play() {
        guard let player = audioPlayer else { return }
        guard player.play() else { return }
        isPlaying = true
        startTimer()
    }
    
    /// Pause playback
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    /// Stop playback and reset to beginning
    func stop() {
        loadGeneration += 1
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
    }
    
    /// Seek to specific time in the audio
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = min(max(0, time), duration)
        currentTime = player.currentTime
    }
    
    /// Reset player completely
    func reset() {
        stop()
        audioPlayer = nil
        currentAudioURL = nil
        duration = 0
        currentTime = 0
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedPlayer = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let audioPlayer, ObjectIdentifier(audioPlayer) == finishedPlayer else { return }
            isPlaying = false
            stopTimer()
            currentTime = 0
            audioPlayer.currentTime = 0
        }
    }
}
