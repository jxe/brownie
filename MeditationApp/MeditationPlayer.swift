import AVFoundation
import Combine
import MediaPlayer

class MeditationPlayer: NSObject, ObservableObject {
    enum State {
        case idle
        case playing
        case paused
        case finished
    }

    @Published private(set) var state: State = .idle

    var isPlaying: Bool { state == .playing }

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
    private var stateBeforeInterruption: State?
    private var currentMeditation: Meditation?
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

        DispatchQueue.main.async { [self] in
            switch type {
            case .began:
                stateBeforeInterruption = state
                if state == .playing { pause() }
            case .ended:
                if stateBeforeInterruption == .playing,
                   let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        resume()
                    }
                }
                stateBeforeInterruption = nil
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        if reason == .oldDeviceUnavailable {
            DispatchQueue.main.async { [self] in
                if state == .playing { pause() }
            }
        }
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .success }
            let currentState = self.state
            switch currentState {
            case .idle:
                return .noActionableNowPlayingItem
            default:
                // Update Now Playing synchronously so Control Center sees it before handler returns
                self.setNowPlayingState(.playing)
                DispatchQueue.main.async {
                    switch self.state {
                    case .finished: self.replay()
                    case .paused: self.resume()
                    default: break
                    }
                }
                return .success
            }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .success }
            self.setNowPlayingState(.paused)
            DispatchQueue.main.async {
                // If already paused (system thought we were playing), just confirm state
                if self.state == .playing {
                    self.pause()
                } else {
                    self.updateNowPlayingInfo()
                }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .success }
            let currentState = self.state
            let newState: MPNowPlayingPlaybackState = currentState == .playing ? .paused : .playing
            self.setNowPlayingState(newState)
            DispatchQueue.main.async { self.togglePause() }
            return .success
        }
    }

    /// Thread-safe immediate update of Now Playing playback state.
    /// Called from remote command handlers before returning, so Control Center
    /// reflects the change without waiting for the main-queue dispatch.
    private func setNowPlayingState(_ playbackState: MPNowPlayingPlaybackState) {
        let center = MPNowPlayingInfoCenter.default()
        // Set nowPlayingInfo first — assigning it can reset playbackState
        if var info = center.nowPlayingInfo {
            info[MPNowPlayingInfoPropertyPlaybackRate] = playbackState == .playing ? 1.0 : 0.0
            center.nowPlayingInfo = info
        }
        center.playbackState = playbackState
    }

    // MARK: - Now Playing

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle
        info[MPMediaItemPropertyArtist] = "Brownie"
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let player = streamingPlayer {
            info[MPMediaItemPropertyPlaybackDuration] = player.totalDuration
            if state == .finished {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
            } else if let elapsed = player.currentTime() {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        switch state {
        case .playing:
            MPNowPlayingInfoCenter.default().playbackState = .playing
        case .finished, .idle:
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        case .paused:
            MPNowPlayingInfoCenter.default().playbackState = .paused
        }
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // MARK: - Controls

    func play(_ meditation: Meditation, sourceURL: URL? = nil) {
        stop()
        configureAudioSession()
        currentSourceURL = sourceURL
        currentMeditation = meditation
        currentTitle = meditation.title

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
        state = .playing
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
        switch state {
        case .finished:
            replay()
        case .paused:
            resume()
        case .playing:
            pause()
        case .idle:
            break
        }
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
        streamingPlayer?.pause()
        stopPositionTracking()
        updateNowPlayingInfo()
    }

    func resume() {
        guard state == .paused else { return }
        configureAudioSession()
        do {
            try streamingPlayer?.resume()
        } catch {
            print("Resume error: \(error)")
            return
        }
        state = .playing
        startPositionTracking()
        updateNowPlayingInfo()
    }

    func stop() {
        renderTask?.cancel()
        renderTask = nil
        stopPositionTracking()
        streamingPlayer?.stop()
        streamingPlayer = nil

        state = .idle
        currentSourceURL = nil
        currentMeditation = nil
        stepIndex = 0
        totalSteps = 0
        currentText = ""
        currentTitle = ""
        playbackStarted = false
        elapsedSeconds = 0
        clearNowPlayingInfo()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session deactivation error: \(error)")
        }
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
        state = .finished
        currentText = ""
        elapsedSeconds = 0
        stopPositionTracking()
        renderTask?.cancel()
        renderTask = nil
        streamingPlayer?.stop()
        streamingPlayer = nil
        updateNowPlayingInfo()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session deactivation error: \(error)")
        }
    }

    private func replay() {
        guard let meditation = currentMeditation else { return }
        let url = currentSourceURL
        play(meditation, sourceURL: url)
    }
}
