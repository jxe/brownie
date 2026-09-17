import AVFoundation
import MediaPlayer

@Observable
class MeditationPlayer: NSObject {
    enum State {
        case idle
        case preparing
        case playing
        case paused
        case finished
    }

    private(set) var state: State = .idle

    var isPlaying: Bool { state == .playing }
    var isPreparing: Bool { state == .preparing }

    var currentText = ""
    var stepIndex = 0
    var totalSteps = 0
    var currentSourceURL: URL?
    var elapsedSeconds: Int = 0
    private(set) var estimatedEndTime: Date?

    var selectedVoiceID: String {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: "selectedVoiceID") }
    }

    var speakingRate: Float {
        didSet { UserDefaults.standard.set(speakingRate, forKey: "speakingRate") }
    }

    static let autoVoiceID = "__auto__"

    var isAutoVoice: Bool { selectedVoiceID == Self.autoVoiceID }

    var voice: AVSpeechSynthesisVoice? {
        if isAutoVoice { return Self.bestAutoVoice() }
        return AVSpeechSynthesisVoice(identifier: selectedVoiceID)
    }

    var resolvedVoiceDisplayName: String {
        guard let v = voice else { return "Unavailable" }
        let quality: String
        switch v.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Default"
        }
        let base = "\(v.name) – \(quality)"
        return isAutoVoice ? "Auto (\(base))" : base
    }

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    static var hasGoodVoice: Bool {
        availableVoices.contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    static func bestAutoVoice() -> AVSpeechSynthesisVoice? {
        let voices = availableVoices
        let currentLocale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        let langCode = Locale.current.language.languageCode?.identifier ?? "en"

        func pick(quality: AVSpeechSynthesisVoiceQuality, matchingLocale: Bool) -> AVSpeechSynthesisVoice? {
            voices.first { v in
                guard v.quality == quality else { return false }
                if matchingLocale {
                    return v.language.caseInsensitiveCompare(currentLocale) == .orderedSame
                        || v.language.hasPrefix(langCode)
                }
                return true
            }
        }

        return pick(quality: .premium, matchingLocale: true)
            ?? pick(quality: .premium, matchingLocale: false)
            ?? pick(quality: .enhanced, matchingLocale: true)
            ?? pick(quality: .enhanced, matchingLocale: false)
            ?? voices.first
    }

    @ObservationIgnored private let renderer = AudioRenderer()
    @ObservationIgnored private var streamingPlayer: StreamingPlayer?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var stateBeforeInterruption: State?
    @ObservationIgnored private var currentMeditation: Meditation?
    @ObservationIgnored private var currentTitle = ""
    @ObservationIgnored private var playbackStarted = false
    @ObservationIgnored private var playbackGeneration = 0

    override init() {
        if let saved = UserDefaults.standard.string(forKey: "selectedVoiceID"),
           saved == Self.autoVoiceID || AVSpeechSynthesisVoice(identifier: saved) != nil {
            self.selectedVoiceID = saved
        } else {
            self.selectedVoiceID = Self.autoVoiceID
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
            case .preparing:
                self.updateNowPlayingInfo()
                return .success
            default:
                DispatchQueue.main.async {
                    switch self.state {
                    case .finished: self.replay()
                    case .paused: self.resume()
                    default: self.updateNowPlayingInfo()
                    }
                }
                return .success
            }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .success }
            DispatchQueue.main.async {
                // If already paused (system thought we were playing), just confirm state
                if self.state == .playing {
                    self.pause()
                } else if self.state == .preparing {
                    self.stop()
                } else {
                    self.updateNowPlayingInfo()
                }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .success }
            DispatchQueue.main.async { self.togglePause() }
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
            let elapsed = player.currentTime() ?? TimeInterval(elapsedSeconds)
            if isPlaying {
                estimatedEndTime = Date.now.addingTimeInterval(
                    max(0, player.totalDuration - elapsed)
                )
            }
            info[MPMediaItemPropertyPlaybackDuration] = player.totalDuration
            if state == .finished {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
            } else {
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
        // Keep the audio session active while replacing playback. Deactivating it here
        // only to reactivate it below adds avoidable latency to every row tap.
        resetPlayback(deactivateAudioSession: false)
        let generation = playbackGeneration
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

        guard !flatSteps.isEmpty else {
            stop()
            return
        }

        totalSteps = flatSteps.count
        stepIndex = 0
        state = .preparing
        playbackStarted = false

        let player = StreamingPlayer(format: renderer.format)
        self.streamingPlayer = player

        player.onPlaybackFinished = { [weak self] in
            self?.handlePlaybackFinished(generation: generation)
        }
        player.onPositionUpdate = { [weak self] step, text, elapsed in
            guard let self else { return }
            if self.stepIndex != step { self.stepIndex = step }
            if self.currentText != text { self.currentText = text }
            if self.elapsedSeconds != elapsed { self.elapsedSeconds = elapsed }
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
            guard let owner = self else { return }
            struct ActiveTail { let buffer: AVAudioPCMBuffer; var frame: Int }
            var activeTails: [ActiveTail] = []
            var didReportRenderFailure = false

            for (i, step) in flatSteps.enumerated() {
                guard !Task.isCancelled else { return }

                let base: AVAudioPCMBuffer
                let text: String

                switch step {
                case .speak(let speakText):
                    text = speakText
                    do {
                        base = try await owner.renderSpeechWithRecovery(text: speakText, voice: voice, rate: rate)
                    } catch {
                        guard !Task.isCancelled else { return }
                        let shouldAbort = await MainActor.run { () -> Bool in
                            guard owner.playbackGeneration == generation else { return true }
                            if !owner.playbackStarted {
                                owner.stop()
                                return true
                            }
                            return false
                        }
                        if !didReportRenderFailure {
                            let action = shouldAbort ? "failed" : "skipped"
                            print("Brownie speech render \(action) at step \(i): \(error)")
                            didReportRenderFailure = true
                        }
                        if shouldAbort { return }
                        continue
                    }
                case .pause(let duration):
                    text = ""
                    base = renderer.renderSilence(duration: duration)
                case .bell(let id):
                    text = ""
                    let def = BellRegistry.def(for: id)
                    base = renderer.renderSilence(duration: def.occupiedDuration)
                    let bellBuffer = renderer.renderBell(id: id)
                    activeTails.append(ActiveTail(buffer: bellBuffer, frame: 0))
                case .countdown:
                    // Should never reach here — countdowns were expanded above
                    continue
                }

                guard !Task.isCancelled else { return }

                // Mix any active tails into the base buffer (including the bell
                // tail we may have just pushed, so its body plays during the
                // occupied window).
                for j in activeTails.indices {
                    let remaining = Int(activeTails[j].buffer.frameLength) - activeTails[j].frame
                    let mixLen = min(remaining, Int(base.frameLength))
                    if mixLen > 0 {
                        renderer.mixIn(
                            destination: base,
                            source: activeTails[j].buffer,
                            srcStart: activeTails[j].frame,
                            dstStart: 0,
                            count: mixLen
                        )
                        activeTails[j].frame += mixLen
                    }
                }
                activeTails.removeAll { $0.frame >= Int($0.buffer.frameLength) }

                let marker = StepMarker(
                    sampleOffset: player.scheduledFrames,
                    stepIndex: i,
                    displayText: text
                )

                let isLastStep = (i == flatSteps.count - 1)
                let needsDrain = isLastStep && !activeTails.isEmpty

                await MainActor.run {
                    guard owner.playbackGeneration == generation else { return }
                    if isLastStep && !needsDrain {
                        player.scheduleFinalBuffer(base, marker: marker)
                    } else {
                        player.scheduleBuffer(base, marker: marker)
                    }

                    // Start playback after first buffer is scheduled
                    if !owner.playbackStarted {
                        owner.playbackStarted = true
                        owner.state = .playing
                        player.play()
                    }

                    // The total duration grows as each rendered buffer is
                    // scheduled, so keep the lock-screen timeline in sync.
                    owner.updateNowPlayingInfo()
                }
            }

            // Drain any remaining tails past the end of the last step.
            guard !Task.isCancelled else { return }
            if !activeTails.isEmpty {
                let drainFrames = activeTails.map { Int($0.buffer.frameLength) - $0.frame }.max() ?? 0
                if drainFrames > 0 {
                    let drain = renderer.renderSilence(
                        duration: Double(drainFrames) / renderer.format.sampleRate
                    )
                    for j in activeTails.indices {
                        let remaining = Int(activeTails[j].buffer.frameLength) - activeTails[j].frame
                        let mixLen = min(remaining, Int(drain.frameLength))
                        if mixLen > 0 {
                            renderer.mixIn(
                                destination: drain,
                                source: activeTails[j].buffer,
                                srcStart: activeTails[j].frame,
                                dstStart: 0,
                                count: mixLen
                            )
                        }
                    }
                    let drainMarker = StepMarker(
                        sampleOffset: player.scheduledFrames,
                        stepIndex: max(flatSteps.count - 1, 0),
                        displayText: ""
                    )
                    await MainActor.run {
                        guard owner.playbackGeneration == generation else { return }
                        player.scheduleFinalBuffer(drain, marker: drainMarker)
                        owner.updateNowPlayingInfo()
                    }
                }
            }

            await MainActor.run {
                guard owner.playbackGeneration == generation, !owner.playbackStarted else { return }
                owner.stop()
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
        case .preparing:
            stop()
        case .idle:
            break
        }
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
        streamingPlayer?.pause()
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
        updateNowPlayingInfo()
    }

    func stop() {
        resetPlayback(deactivateAudioSession: true)
    }

    private func resetPlayback(deactivateAudioSession: Bool) {
        playbackGeneration += 1
        renderTask?.cancel()
        renderTask = nil
        renderer.cancelSpeechRendering()
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
        estimatedEndTime = nil
        clearNowPlayingInfo()

        if deactivateAudioSession {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("Audio session deactivation error: \(error)")
            }
        }
    }

    // MARK: - Completion

    private func handlePlaybackFinished(generation: Int) {
        guard playbackGeneration == generation else { return }
        state = .finished
        currentText = ""
        elapsedSeconds = 0
        estimatedEndTime = nil
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

    private func renderSpeechWithRecovery(
        text: String,
        voice: AVSpeechSynthesisVoice?,
        rate: Float
    ) async throws -> AVAudioPCMBuffer {
        do {
            return try await renderer.renderSpeech(text: text, voice: voice, rate: rate)
        } catch let error as AudioRendererError {
            guard case .speechTimedOut = error else { throw error }
            print("Brownie speech render timed out; resetting synthesizer and retrying: \(error)")
            await renderer.resetSpeechSynthesizer()
            return try await renderer.renderSpeech(text: text, voice: voice, rate: rate)
        }
    }
}
