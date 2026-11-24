import AVFoundation
import SwiftUI

/// Simple waveform visualization for audio playback
struct WaveformView: View {
    let audioURL: URL?
    @Binding var currentTime: TimeInterval
    @Binding var duration: TimeInterval

    @State private var samples: [Float] = []

    private var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(currentTime / duration)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background waveform (light blue)
                waveformPath(in: geometry.size, samples: samples)
                    .stroke(Color.accentBlue.opacity(0.3), lineWidth: 1.5)

                // Progress waveform (solid blue)
                waveformPath(in: geometry.size, samples: samples)
                    .stroke(Color.accentBlue, lineWidth: 1.5)
                    .frame(width: geometry.size.width * progress)
                    .clipped()
            }
        }
        .frame(height: 60)
        .task(id: audioURL) {
            samples = []
            guard let audioURL else { return }
            let worker = Task.detached(priority: .utility) {
                Self.extractSamples(from: audioURL, bucketCount: 100)
            }
            let extracted = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            samples = extracted
        }
    }

    private func waveformPath(in size: CGSize, samples: [Float]) -> Path {
        guard !samples.isEmpty else { return Path() }

        var path = Path()
        let midY = size.height / 2
        let barWidth = size.width / CGFloat(samples.count)

        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * barWidth
            let barHeight = CGFloat(sample) * midY

            // Draw vertical line from center
            path.move(to: CGPoint(x: x, y: midY - barHeight))
            path.addLine(to: CGPoint(x: x, y: midY + barHeight))
        }

        return path
    }

    /// Peak-amplitude downsample of the first audio channel into `bucketCount` normalized (0...1)
    /// bars. Returns `[]` on any failure (missing/unreadable file) so the view simply draws nothing.
    /// `nonisolated` so it genuinely runs off the main actor inside `Task.detached` — otherwise
    /// (this type is implicitly @MainActor) the decode hops back to main and hitches the UI.
    nonisolated private static func extractSamples(from url: URL, bucketCount: Int) -> [Float] {
        guard bucketCount > 0,
              let file = try? AVAudioFile(forReading: url) else { return [] }

        let total = file.length
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384)
        else { return [] }

        // Read in chunks so opening a long recording never allocates its entire decoded audio.
        let bucketSize = max(1, total / Int64(bucketCount))
        var result = [Float](repeating: 0, count: min(bucketCount, Int(total)))
        var position: Int64 = 0
        var peak: Float = 0
        while position < total, !Task.isCancelled {
            let count = AVAudioFrameCount(min(Int64(buffer.frameCapacity), total - position))
            guard (try? file.read(into: buffer, frameCount: count)) != nil,
                  buffer.frameLength > 0, let channel = buffer.floatChannelData?[0]
            else { return [] }
            for index in 0..<Int(buffer.frameLength) {
                let bucket = min(Int((position + Int64(index)) / bucketSize), result.count - 1)
                let amplitude = abs(channel[index])
                result[bucket] = max(result[bucket], amplitude)
                peak = max(peak, amplitude)
            }
            position += Int64(buffer.frameLength)
        }
        guard !Task.isCancelled else { return [] }
        if peak > 0 {
            result = result.map { $0 / peak }
        }
        return result
    }
}
