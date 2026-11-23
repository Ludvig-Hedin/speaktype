import AVFoundation
import Foundation

/// Shrinks a recording before it is uploaded to a cloud transcription model.
///
/// The recorder writes 16 kHz 16-bit WAV (~32 KB per second). Re-encoding it as 32 kbps AAC
/// makes the upload ~8× smaller. Benchmark 2026-11-23 (9 real dictations, GPT Transcribe via
/// OpenRouter): median response 2.5 s → 0.9 s with identical text. The WAV on disk is kept
/// as-is for History and retries.
/// `nonisolated`: the project defaults to MainActor, and encoding must stay off the main thread.
nonisolated enum AudioUploadEncoder {
    /// Returns a temporary `.m4a` next to nothing the user sees, or `nil` to fall back to WAV.
    /// The caller deletes the file when done.
    static func compressedCopy(of wav: URL) async -> URL? {
        await Task.detached(priority: .userInitiated) { encode(wav) }.value
    }

    private static func encode(_ wav: URL) -> URL? {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaktype-upload-\(UUID().uuidString).m4a")
        let asset = AVURLAsset(url: wav)
        guard let track = asset.tracks(withMediaType: .audio).first,
            let reader = try? AVAssetReader(asset: asset),
            let writer = try? AVAssetWriter(outputURL: out, fileType: .m4a)
        else { return nil }

        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        guard reader.canAdd(readerOutput), writer.canAdd(writerInput) else { return nil }
        reader.add(readerOutput)
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            try? FileManager.default.removeItem(at: out)
            return nil
        }
        writer.startSession(atSourceTime: .zero)

        while let buffer = readerOutput.copyNextSampleBuffer() {
            while !writerInput.isReadyForMoreMediaData {
                if writer.status != .writing { break }
                usleep(1_000)
            }
            guard writer.status == .writing, writerInput.append(buffer) else { break }
        }
        writerInput.markAsFinished()

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()

        guard reader.status == .completed, writer.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            return nil
        }
        return out
    }
}
