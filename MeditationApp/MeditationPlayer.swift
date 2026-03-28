import AVFoundation
import Combine
import MediaPlayer

class MeditationPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentText = ""
    @Published var stepIndex = 0
    @Published var totalSteps = 0
    @Published var currentSourceURL: URL?
    @Published var elapsedSeconds: Int = 0

    @Published var selectedVoiceID: String {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: "selectedVoiceID") }
    }

    @Published var speakingRate: Float {
        didSet { UserDefaults.standard.set(speakingRate, forKey: "speakingRate") }
    }

    var voice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: selectedVoiceID)
    }

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    private let renderer = AudioRenderer()
    private var streamingPlayer: StreamingPlayer?
    private var renderTask: Task<Void, Never>?
    private var positionTimer: Timer?
    private var isPaused = false
    private var userPaused = false
    private var currentTitle = ""
    private var playbackStarted = false

    override init() {
        if let saved = UserDefaults.standard.string(forKey: "selectedVoiceID"),
           AVSpeechSynthesisVoice(identifier: saved) != nil {
            self.selectedVoiceID = saved
        } else {
            let best = MeditationPlayer.availableVoices.first
            self.selectedVoiceID = best?.identifier ?? AVSpeechSynthesisVoice(language: "en-US")!.identifier
        }

        let savedRate = UserDefaults.standard.float(forKey: "speakingRate")
        self.speakingRate = savedRate > 0 ? savedRate : 0.45
        super.init()
        configureAudioSession()
        setupRemoteCommands()
        observeInterruptions()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if isPlaying { pause() }
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && !userPaused {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        if reason == .oldDeviceUnavailable {
            // Headphones unplugged — pause
            if isPlaying { pause() }
        }
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePause()
            return .success
        }
    }

    // MARK: - Now Playing

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle
        info[MPMediaItemPropertyArtist] = "Brownie"
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let player = streamingPlayer {
            info[MPMediaItemPropertyPlaybackDuration] = player.totalDuration
            if let elapsed = player.currentTime() {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Controls

    func play(_ meditation: Meditation, sourceURL: URL? = nil) {
        stop()
        currentSourceURL = sourceURL
        currentTitle = meditation.title
        isPaused = false
        userPaused = false

        // Expand all countdowns eagerly into a flat step list
        var flatSteps: [MeditationStep] = []
        for step in meditation.steps {
            if case .countdown(let seconds) = step {
                flatSteps.append(contentsOf: renderer.expandCountdown(seconds))
            } else {
                flatSteps.append(step)
            }
        }

        totalSteps = flatSteps.count
        stepIndex = 0
        isPlaying = true
        playbackStarted = false

        let player = StreamingPlayer(format: renderer.format)
        self.streamingPlayer = player

        player.onPlaybackFinished = { [weak self] in
            self?.handlePlaybackFinished()
        }

        do {
            try player.setup()
        } catch {
            print("StreamingPlayer setup error: \(error)")
            stop()
            return
        }

        updateNowPlayingInfo()

        // Render and schedule buffers in background
        let voice = self.voice
        let rate = self.speakingRate

        renderTask = Task { [weak self, renderer] in
            for (i, step) in flatSteps.enumerated() {
                guard !Task.isCancelled else { return }

                let buffer: AVAudioPCMBuffer
                let text: String

                switch step {
                case .speak(let speakText):
                    text = speakText
                    do {
                        buffer = try await renderer.renderSpeech(text: speakText, voice: voice, rate: rate)
                    } catch {
                        print("Render error for step \(i): \(error)")
                        continue
                    }
                case .pause(let duration):
                    text = ""
                    buffer = renderer.renderSilence(duration: duration)
                case .countdown:
                    // Should never reach here — countdowns were expanded above
                    continue
                }

                guard !Task.isCancelled else { return }

                let marker = StepMarker(
                    sampleOffset: player.scheduledFrames,
                    stepIndex: i,
                    displayText: text
                )

                let isFinal = (i == flatSteps.count - 1)
                await MainActor.run {
                    if isFinal {
                        player.scheduleFinalBuffer(buffer, marker: marker)
                    } else {
                        player.scheduleBuffer(buffer, marker: marker)
                    }

                    // Start playback after first buffer is scheduled
                    if let self = self, !self.playbackStarted {
                        self.playbackStarted = true
                        player.play()
                        self.startPositionTracking()
                    }
                }
            }
        }
    }

    func togglePause() {
        if isPaused {
            userPaused = false
            resume()
        } else {
            userPaused = true
            pause()
        }
    }

    func pause() {
        isPaused = true
        isPlaying = false
        streamingPlayer?.pause()
        updateNowPlayingInfo()
    }

    func resume() {
        isPaused = false
        isPlaying = true
        configureAudioSession()
        streamingPlayer?.resume()
        updateNowPlayingInfo()
    }

    func stop() {
        renderTask?.cancel()
        renderTask = nil
        stopPositionTracking()
        streamingPlayer?.stop()
        streamingPlayer = nil

        isPaused = false
        userPaused = false
        isPlaying = false
        currentSourceURL = nil
        stepIndex = 0
        totalSteps = 0
        currentText = ""
        currentTitle = ""
        playbackStarted = false
        elapsedSeconds = 0
        clearNowPlayingInfo()
    }

    // MARK: - Position Tracking

    private func startPositionTracking() {
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }

    private func stopPositionTracking() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func updatePosition() {
        guard let player = streamingPlayer,
              let position = player.currentPlaybackPosition() else { return }

        if let elapsed = player.currentTime() {
            let secs = Int(elapsed)
            if elapsedSeconds != secs { elapsedSeconds = secs }
        }

        if let marker = player.stepMarker(at: position) {
            if stepIndex != marker.stepIndex {
                stepIndex = marker.stepIndex
            }
            if currentText != marker.displayText {
                currentText = marker.displayText
            }
        }
    }

    // MARK: - Completion

    private func handlePlaybackFinished() {
        isPlaying = false
        currentText = ""
        elapsedSeconds = 0
        stopPositionTracking()
        clearNowPlayingInfo()
    }
}
