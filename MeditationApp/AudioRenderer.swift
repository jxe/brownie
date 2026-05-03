import AVFoundation

// MARK: - Bell Registry

struct BellDef {
    let id: String
    let filename: String          // bundle resource name, no extension
    let occupiedDuration: TimeInterval
}

enum BellRegistry {
    static let defaultID = "bell"

    static let bells: [String: BellDef] = [
        "bell":  BellDef(id: "bell",  filename: "brownie-bell",  occupiedDuration:  7.0),
        "chime": BellDef(id: "chime", filename: "brownie-chime", occupiedDuration:  3.0),
        "gong":  BellDef(id: "gong",  filename: "brownie-gong",  occupiedDuration: 10.0),
    ]

    // Both variation-selector and bare emoji map to the same id.
    static let emojiToID: [Character: String] = [
        "\u{1F514}":          "bell",   // 🔔
        "\u{1F6CE}\u{FE0F}":  "chime",  // 🛎️
        "\u{1F6CE}":          "chime",  // 🛎
        "\u{1F6E2}\u{FE0F}":  "gong",   // 🛢️
        "\u{1F6E2}":          "gong",   // 🛢
    ]

    static func id(for ch: Character) -> String? { emojiToID[ch] }
    static func def(for id: String) -> BellDef   { bells[id] ?? bells[defaultID]! }
}

/// Renders meditation steps into AVAudioPCMBuffers for streaming playback.
class AudioRenderer {
    /// Standard output format: 16kHz mono float32
    let format: AVAudioFormat

    private let synthesizer = AVSpeechSynthesizer()
    private var cachedBells: [String: AVAudioPCMBuffer] = [:]

    init() {
        self.format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    }

    // MARK: - Speech Rendering

    /// Renders spoken text to an audio buffer using AVSpeechSynthesizer.write.
    func renderSpeech(text: String, voice: AVSpeechSynthesisVoice?, rate: Float) async throws -> AVAudioPCMBuffer {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = voice
        utterance.pitchMultiplier = 1.0

        let buffers: [AVAudioPCMBuffer] = try await withCheckedThrowingContinuation { continuation in
            var collected: [AVAudioPCMBuffer] = []
            var finished = false

            // AVSpeechSynthesizer.write must be called on the main thread
            DispatchQueue.main.async {
                self.synthesizer.write(utterance) { buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                        if !finished {
                            finished = true
                            continuation.resume(returning: collected)
                        }
                        return
                    }
                    collected.append(pcm)
                }
            }
        }

        guard !buffers.isEmpty else {
            // Return a tiny silent buffer if synthesis produced nothing
            return renderSilence(duration: 0.01)
        }

        return try concatenateAndConvert(buffers: buffers)
    }

    // MARK: - Bell

    /// Loads a named bell recording from the app bundle, converts it to the
    /// renderer's standard format (16 kHz mono float32), and caches it by id.
    /// Returns a silent buffer (matching the bell's occupied duration) if the
    /// audio file is missing or fails to load.
    func renderBell(id: String) -> AVAudioPCMBuffer {
        let def = BellRegistry.def(for: id)
        if let cached = cachedBells[def.id] {
            return cached
        }
        let fallback: () -> AVAudioPCMBuffer = { [format] in
            let frames = AVAudioFrameCount(def.occupiedDuration * format.sampleRate)
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frames, 1))!
            buf.frameLength = max(frames, 1)
            return buf
        }
        guard let url = Bundle.main.url(forResource: def.filename, withExtension: "mp3"),
              let file = try? AVAudioFile(forReading: url) else {
            return fallback()
        }

        let sourceFormat = file.processingFormat
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)) else {
            return fallback()
        }
        do {
            try file.read(into: sourceBuffer)
        } catch {
            return fallback()
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: format) else {
            return fallback()
        }
        let ratio = format.sampleRate / sourceFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 100
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCapacity) else {
            return fallback()
        }

        var error: NSError?
        var consumed = false
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return sourceBuffer
        }
        if error != nil {
            return fallback()
        }

        cachedBells[def.id] = output
        return output
    }

    // MARK: - Mixing

    /// Adds `count` float32 samples from `source` (starting at `srcStart`) into
    /// `destination` (starting at `dstStart`). Only valid within existing
    /// `frameLength` on both buffers. Destination must not be a cached bell.
    func mixIn(destination: AVAudioPCMBuffer,
               source: AVAudioPCMBuffer,
               srcStart: Int,
               dstStart: Int,
               count: Int) {
        guard count > 0,
              let dst = destination.floatChannelData,
              let src = source.floatChannelData else { return }
        assert(srcStart + count <= Int(source.frameLength), "source read out of bounds")
        assert(dstStart + count <= Int(destination.frameLength), "destination write out of bounds")
        let dstPtr = dst[0].advanced(by: dstStart)
        let srcPtr = src[0].advanced(by: srcStart)
        for i in 0..<count {
            dstPtr[i] += srcPtr[i]
        }
    }

    // MARK: - Silence

    /// Creates a silent buffer of exact duration in the standard format.
    func renderSilence(duration: TimeInterval) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameCount, 1))!
        buffer.frameLength = max(frameCount, 1)
        // Buffer is zero-filled by default
        return buffer
    }

    // MARK: - Countdown Expansion

    /// Expands a countdown duration into a flat array of speak/pause steps.
    func expandCountdown(_ seconds: TimeInterval) -> [MeditationStep] {
        var steps: [MeditationStep] = []

        if seconds >= 120 {
            var t = seconds
            while t > 60 {
                steps.append(.speak(formatCountdownNumber(t)))
                steps.append(.pause(30))
                t -= 30
            }
            steps.append(.speak("60"))
            steps.append(.pause(20))
            steps.append(.speak("40"))
            steps.append(.pause(20))
        } else if seconds >= 60 {
            steps.append(.speak("60"))
            steps.append(.pause(20))
            steps.append(.speak("40"))
            steps.append(.pause(20))
        } else if seconds >= 30 {
            steps.append(.speak(formatCountdownNumber(seconds)))
            steps.append(.pause(seconds - 20))
        }

        if seconds >= 20 {
            steps.append(.speak("20"))
            steps.append(.pause(10))
        }

        steps.append(.speak("10"))
        steps.append(.pause(5))
        steps.append(.speak("5"))
        steps.append(.pause(5))
        steps.append(.bell("chime"))

        return steps
    }

    // MARK: - Private

    private func formatCountdownNumber(_ seconds: TimeInterval) -> String {
        if seconds >= 60 {
            let mins = seconds / 60
            if mins == Double(Int(mins)) {
                return "\(Int(mins))"
            }
            return String(format: "%.1f", mins)
        }
        return "\(Int(seconds))"
    }

    /// Concatenates multiple buffers and converts to the standard format.
    private func concatenateAndConvert(buffers: [AVAudioPCMBuffer]) throws -> AVAudioPCMBuffer {
        let sourceFormat = buffers[0].format

        // Calculate total frames in source
        let totalSourceFrames = buffers.reduce(0) { $0 + AVAudioFrameCount($1.frameLength) }

        if sourceFormat == format {
            // No conversion needed, just concatenate
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalSourceFrames)!
            for buf in buffers {
                let dst = output.floatChannelData![0].advanced(by: Int(output.frameLength))
                let src = buf.floatChannelData![0]
                dst.update(from: src, count: Int(buf.frameLength))
                output.frameLength += buf.frameLength
            }
            return output
        }

        // Need format conversion — concatenate source first
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: totalSourceFrames)!
        for buf in buffers {
            if sourceFormat.commonFormat == .pcmFormatFloat32, let srcData = buf.floatChannelData, let dstData = sourceBuffer.floatChannelData {
                let dst = dstData[0].advanced(by: Int(sourceBuffer.frameLength))
                dst.update(from: srcData[0], count: Int(buf.frameLength))
            } else if sourceFormat.commonFormat == .pcmFormatInt16, let srcData = buf.int16ChannelData, let dstData = sourceBuffer.int16ChannelData {
                let dst = dstData[0].advanced(by: Int(sourceBuffer.frameLength))
                dst.update(from: srcData[0], count: Int(buf.frameLength))
            }
            sourceBuffer.frameLength += buf.frameLength
        }

        // Convert to target format
        guard let converter = AVAudioConverter(from: sourceFormat, to: format) else {
            throw AudioRendererError.conversionFailed
        }

        let ratio = format.sampleRate / sourceFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(totalSourceFrames) * ratio) + 100
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: estimatedFrames)!

        var error: NSError?
        var consumed = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let error = error {
            throw error
        }

        return output
    }
}

enum AudioRendererError: Error {
    case conversionFailed
}
