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
    private struct Span {
        let local: Int64
        let count: Int64
        let start: Int64
        let end: Int64
    }

    /// Map successive source-frame positions onto their common host clock. Old recordings
    /// have only an offset. An interruption creates a gap instead of stretching speech.
    private final class Source {
        let url: URL
        private var reader: AVAudioFile?
        private var readBuffer: AVAudioPCMBuffer?
        let spans: [Span]
        var cursor = 0

        init(url: URL) throws {
            self.url = url
            let file = try AVAudioFile(forReading: url)
            let base = url.deletingPathExtension()
            let offset = try JSONDecoder().decode(Int64.self, from: Data(contentsOf: base.appendingPathExtension("offset")))
            var local: Int64 = 0
            var host = offset
            var result = [Span]()
            var ratio = 1.0
            let anchors = (try? String(contentsOf: base.appendingPathExtension("anchors"), encoding: .utf8)) ?? ""
            for line in anchors.split(separator: "\n") {
                let fields = line.split(separator: " ")
                guard fields.count == 2, let next = Int64(fields[0]), let time = Int64(fields[1]),
                      next > local, next <= file.length, time > host else { continue }
                let count = next - local
                let measured = Double(time - host) / Double(count)
                let continuous = (0.95...1.05).contains(measured)
                if continuous { ratio = measured }
                let end = continuous ? time : min(time, host + count)
                result.append(Span(local: local, count: continuous ? count : end - host, start: host, end: end))
                local = next
                host = time
            }
            let remaining = file.length - local
            if remaining > 0 {
                result.append(Span(local: local, count: remaining, start: host,
                                   end: host + max(1, Int64((Double(remaining) * ratio).rounded()))))
            }
            spans = result
        }

        func add(to samples: UnsafeMutablePointer<Float>, at position: Int64, count: Int64) throws {
            while cursor < spans.count {
                let span = spans[cursor]
                let start = max(position, span.start)
                let end = min(position + count, span.end)
                if end > start {
                    if reader == nil {
                        reader = try AVAudioFile(forReading: url)
                        readBuffer = AVAudioPCMBuffer(pcmFormat: reader!.processingFormat, frameCapacity: 8192)
                    }
                    guard let file = reader, let buffer = readBuffer else { throw MeetingAudioError(message: "Cannot read meeting track.") }
                    let step = Double(span.count) / Double(span.end - span.start)
                    let first = Double(start - span.start) * step
                    let base = Int64(first)
                    let last = Int64(Double(end - 1 - span.start) * step)
                    let frames = min(span.count - base, last - base + 2)
                    guard frames > 0, frames <= buffer.frameCapacity else { throw MeetingAudioError(message: "Invalid track timing.") }
                    if file.framePosition != span.local + base { file.framePosition = span.local + base }
                    try file.read(into: buffer, frameCount: UInt32(frames))
                    guard buffer.frameLength == UInt32(frames) else { throw MeetingAudioError(message: "Incomplete meeting track.") }
                    let input = buffer.floatChannelData![0]
                    let target = samples.advanced(by: Int(start - position))
                    for i in 0..<Int(end - start) {
                        if step == 1 { target[i] += input[i]; continue }
                        let index = first - Double(base) + Double(i) * step
                        let j = min(Int(index), Int(frames) - 1)
                        let next = min(j + 1, Int(frames) - 1)
                        target[i] += input[j] + Float(index - Double(j)) * (input[next] - input[j])
                    }
                }
                if span.end > position + count { break }
                cursor += 1
            }
            if cursor == spans.count { reader = nil; readBuffer = nil }
        }
    }

    static func mix(at url: URL) throws -> TimeInterval {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter {
            $0.lastPathComponent.range(of: #"^(mic|system)(-[0-9]+)?\.caf$"#, options: .regularExpression) != nil
        }
        if files.isEmpty, fm.fileExists(atPath: url.path) {
            return Double(try AVAudioFile(forReading: url).length) / rate
        }
        let sources = try files.map(Source.init)
        guard let length = sources.compactMap({ $0.spans.last?.end }).max(), length > 0 else {
            throw MeetingAudioError(message: "No meeting audio was captured.")
        }
        let temporary = folder.appendingPathComponent("mix-\(UUID()).wav")
        defer { try? fm.removeItem(at: temporary) }
        try writeMix(sources, length: length, url: temporary)
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: url)
        }
        return Double(length) / rate
    }

    private static func writeMix(_ sources: [Source], length: Int64, url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true)!
        let output = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 4096)!
        let samples = buffer.floatChannelData![0]
        let pieces = sources.filter { !$0.spans.isEmpty }.sorted { $0.spans[0].start < $1.spans[0].start }
        var nextPiece = 0
        var active = [Source]()
        var position: Int64 = 0
        while position < length {
            let count = min(4096, length - position)
            buffer.frameLength = UInt32(count)
            samples.update(repeating: 0, count: Int(count))
            while nextPiece < pieces.count, pieces[nextPiece].spans[0].start < position + count {
                active.append(pieces[nextPiece])
                nextPiece += 1
            }
            for source in active { try source.add(to: samples, at: position, count: count) }
            active.removeAll { $0.cursor == $0.spans.count }
            // Preserve ordinary speech gain and smoothly limit simultaneous loud voices.
            for i in 0..<Int(count) where abs(samples[i]) > 0.75 {
                let amplitude = abs(samples[i]) - 0.75
                samples[i] = (samples[i] < 0 ? -1 : 1) * (0.75 + 0.25 * amplitude / (0.25 + amplitude))
            }
            try output.write(from: buffer)
            position += count
        }
    }

    static func segmentEnd(_ input: AVAudioFile, start: Int64) throws -> Int64 {
        let limit = min(input.length, start + segmentFrames)
        guard limit < input.length else { return limit }
        let search = Int(rate * 20)
        let window = Int(rate * 0.3)
        input.framePosition = limit - Int64(search)
        let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: UInt32(search))!
        try input.read(into: buffer)
        guard buffer.frameLength == search else { throw MeetingAudioError(message: "Incomplete meeting audio.") }
        let samples = buffer.floatChannelData![0]
        var energy = 0.0
        var best = Double.infinity
        var cut = limit
        for i in 0..<search {
            energy += Double(samples[i]) * Double(samples[i])
            if i >= window { energy -= Double(samples[i-window]) * Double(samples[i-window]) }
            if i >= window - 1, energy <= best {
                best = energy
                cut = limit - Int64(search - i + window / 2 - 1)
            }
        }
        return cut
    }

    /// Encode one range at a time, keeping both the working set and upload size bounded.
    static func segment(from url: URL, startingAt start: Int64, to destination: URL) throws -> (end: Int64, last: Bool) {
        let input = try AVAudioFile(forReading: url)
        let end = try segmentEnd(input, start: start)
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
