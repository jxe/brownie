import AVFoundation

/// Tracks a step's position within the rendered audio stream.
struct StepMarker {
    let sampleOffset: AVAudioFramePosition
    let stepIndex: Int
    let displayText: String
}

/// AVAudioEngine-based player that streams pre-rendered buffers.
class StreamingPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    let format: AVAudioFormat

    /// Cumulative frames scheduled so far.
    private(set) var scheduledFrames: AVAudioFramePosition = 0

    /// Step markers for mapping playback position to UI state.
    private(set) var stepMarkers: [StepMarker] = []

    /// Total duration in seconds (updated as buffers are scheduled).
    var totalDuration: TimeInterval {
        Double(scheduledFrames) / format.sampleRate
    }

    /// Called when the last buffer finishes playing.
    var onPlaybackFinished: (() -> Void)?

    /// Called on the main queue ~10x/sec while playing with the current step marker and elapsed seconds.
    var onPositionUpdate: ((_ stepIndex: Int, _ displayText: String, _ elapsedSeconds: Int) -> Void)?

    private var positionTimer: Timer?

    init(format: AVAudioFormat) {
        self.format = format
    }

    // MARK: - Setup

    func setup() throws {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try engine.start()
    }

    // MARK: - Buffer Scheduling

    /// Schedule a buffer for sequential playback and record its step marker.
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer, marker: StepMarker) {
        stepMarkers.append(marker)
        scheduledFrames += AVAudioFramePosition(buffer.frameLength)
        playerNode.scheduleBuffer(buffer)
    }

    /// Schedule the final buffer with a completion handler to detect end of playback.
    func scheduleFinalBuffer(_ buffer: AVAudioPCMBuffer, marker: StepMarker) {
        stepMarkers.append(marker)
        scheduledFrames += AVAudioFramePosition(buffer.frameLength)
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onPlaybackFinished?()
            }
        }
    }

    // MARK: - Playback Controls

    func play() {
        playerNode.play()
        startPositionTracking()
    }

    func pause() {
        playerNode.pause()
        engine.pause()
        stopPositionTracking()
    }

    func resume() throws {
        try ensureRunning()
        playerNode.play()
        startPositionTracking()
    }

    /// Restart the audio engine if iOS stopped it (e.g. after interruption or long background pause).
    func ensureRunning() throws {
        if !engine.attachedNodes.contains(playerNode) {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        }
        if !engine.isRunning {
            try engine.start()
        }
    }

    func stop() {
        stopPositionTracking()
        playerNode.stop()
        engine.stop()
        engine.reset()
        // Re-attach for potential reuse
        if !engine.attachedNodes.contains(playerNode) {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        }
        scheduledFrames = 0
        stepMarkers = []
        onPlaybackFinished = nil
        onPositionUpdate = nil
    }

    // MARK: - Position Tracking Timer

    private func startPositionTracking() {
        guard positionTimer == nil else { return }
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickPosition()
        }
    }

    private func stopPositionTracking() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func tickPosition() {
        guard let position = currentPlaybackPosition() else { return }
        let elapsedSecs = Int(Double(position) / format.sampleRate)
        guard let marker = stepMarker(at: position) else { return }
        onPositionUpdate?(marker.stepIndex, marker.displayText, elapsedSecs)
    }

    // MARK: - Position Tracking

    /// Returns the current playback position in frames, or nil if not playing.
    func currentPlaybackPosition() -> AVAudioFramePosition? {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        return playerTime.sampleTime
    }

    /// Returns current playback time in seconds.
    func currentTime() -> TimeInterval? {
        guard let frames = currentPlaybackPosition() else { return nil }
        return Double(frames) / format.sampleRate
    }

    /// Finds the step marker for a given frame position via binary search.
    func stepMarker(at position: AVAudioFramePosition) -> StepMarker? {
        guard !stepMarkers.isEmpty else { return nil }

        // Binary search for the last marker whose sampleOffset <= position
        var low = 0
        var high = stepMarkers.count - 1
        var result = 0

        while low <= high {
            let mid = (low + high) / 2
            if stepMarkers[mid].sampleOffset <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return stepMarkers[result]
    }
}
