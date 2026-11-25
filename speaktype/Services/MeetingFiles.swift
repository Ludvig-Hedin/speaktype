import AVFoundation

nonisolated enum MeetingFiles {
    static let rate = 16_000.0
    static let segmentFrames = Int64(rate) * 600
    static var recordings: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppStorageIsolation.supportFolderName)
            .appendingPathComponent("Recordings")
    }
    static func mixURL(id: UUID) -> URL {
        recordings.appendingPathComponent("Meeting-\(id.uuidString)").appendingPathComponent("meeting.wav")
    }
    private struct Source {
        let file: AVAudioFile
        let offset: Int64
        let buffer: AVAudioPCMBuffer
    }
    /// Publish only a closed, complete mix. Interrupted attempts leave the inputs intact.
    static func mix(at url: URL) throws -> TimeInterval {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return Double(try AVAudioFile(forReading: url).length) / rate }
        let folder = url.deletingLastPathComponent()
        let sources = try ["mic", "system"].compactMap { name -> Source? in
            let sourceURL = folder.appendingPathComponent(name + ".caf")
            guard fm.fileExists(atPath: sourceURL.path) else { return nil }
            let file = try AVAudioFile(forReading: sourceURL)
            guard file.length > 0 else { return nil }
            let offset = try JSONDecoder().decode(Int64.self, from: Data(contentsOf: folder.appendingPathComponent(name + ".offset")))
            return Source(file: file, offset: offset, buffer: AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192)!)
        }
        guard let length = sources.map({ $0.offset + $0.file.length }).max(), length > 0 else {
            throw MeetingAudioError(message: "No meeting audio was captured.")
        }
        let temporary = folder.appendingPathComponent("mix-\(UUID()).wav")
        defer { try? fm.removeItem(at: temporary) }
        try writeMix(sources, length: length, url: temporary)
        try fm.moveItem(at: temporary, to: url)
        return Double(length) / rate
    }

    private static func writeMix(_ sources: [Source], length: Int64, url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true)!
        let output = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 8192)!
        let samples = buffer.floatChannelData![0]
        var position: Int64 = 0
        while position < length {
            let count = min(8192, length - position)
            buffer.frameLength = UInt32(count)
            samples.update(repeating: 0, count: Int(count))
            for source in sources {
                let start = max(position, source.offset)
                let end = min(position + count, source.offset + source.file.length)
                guard start < end else { continue }
                try source.file.read(into: source.buffer, frameCount: UInt32(end - start))
                let input = source.buffer.floatChannelData![0]
                for i in 0..<Int(source.buffer.frameLength) {
                    let j = Int(start - position) + i
                    samples[j] = max(-1, min(1, samples[j] + input[i]))
                }
            }
            try output.write(from: buffer)
            position += count
        }
    }

    /// Encode one range at a time, keeping both the working set and upload size bounded.
    static func segment(from url: URL, startingAt start: Int64, to destination: URL) throws -> (end: Int64, last: Bool) {
        let input = try AVAudioFile(forReading: url)
        let end = min(start + segmentFrames, input.length)
        guard start >= 0, start < end else { throw MeetingAudioError(message: "Invalid meeting segment.") }
        input.framePosition = start
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000]
        let output = try AVAudioFile(forWriting: destination, settings: settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192)!
        while input.framePosition < end {
            try input.read(into: buffer, frameCount: UInt32(min(8192, end - input.framePosition)))
            guard buffer.frameLength > 0 else { throw MeetingAudioError(message: "Incomplete meeting audio.") }
            try output.write(from: buffer)
        }
        return (end, end == input.length)
    }
}
