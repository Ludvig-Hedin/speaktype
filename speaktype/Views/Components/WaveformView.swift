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
        .onAppear {
            generateSamples()
        }
        .onChange(of: audioURL) {
            generateSamples()
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

    private func generateSamples() {
        guard let audioURL else {
            samples = []
            return
        }
        // Read + downsample the real recording off the main thread (a long dictation can be a few
        // MB), then publish on the main actor. Previously this drew RANDOM samples, so the waveform
        // had no relation to the audio and changed every time the same item was opened.
        Task.detached(priority: .utility) {
            let extracted = Self.extractSamples(from: audioURL, bucketCount: 100)
            await MainActor.run {
                self.samples = extracted
            }
        }
    }

    /// Peak-amplitude downsample of the first audio channel into `bucketCount` normalized (0...1)
    /// bars. Returns `[]` on any failure (missing/unreadable file) so the view simply draws nothing.
    private static func extractSamples(from url: URL, bucketCount: Int) -> [Float] {
        guard bucketCount > 0,
              let file = try? AVAudioFile(forReading: url) else { return [] }

        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channelData = buffer.floatChannelData else { return [] }

        let channel = channelData[0]
        let total = Int(buffer.frameLength)
        guard total > 0 else { return [] }

        let bucketSize = max(1, total / bucketCount)
        var result: [Float] = []
        result.reserveCapacity(bucketCount)
        var peak: Float = 0

        var bucket = 0
        while bucket < bucketCount {
            let start = bucket * bucketSize
            if start >= total { break }
            let end = min(start + bucketSize, total)

            var maxAmp: Float = 0
            var i = start
            while i < end {
                maxAmp = max(maxAmp, abs(channel[i]))
                i += 1
            }
            result.append(maxAmp)
            peak = max(peak, maxAmp)
            bucket += 1
        }

        // Normalize to 0...1 so quiet recordings still fill the view.
        if peak > 0 {
            result = result.map { $0 / peak }
        }
        return result
    }
}
