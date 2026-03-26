import AVFoundation
import Combine
import MediaPlayer

class MeditationPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentText = ""
    @Published var stepIndex = 0
    @Published var totalSteps = 0

    private let synthesizer = AVSpeechSynthesizer()
    private var steps: [MeditationStep] = []
    private var pauseTimer: Timer?
    private var isPaused = false
    private var silencePlayer: AVAudioPlayer?
    private var currentTitle = ""

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
        synthesizer.delegate = self
        configureAudioSession()
        setupRemoteCommands()
    }

    private func makeSilencePlayer() -> AVAudioPlayer? {
        // Generate a short silent WAV that loops indefinitely
        let sampleRate: Double = 44100
        let seconds: Double = 1
        let numSamples = Int(sampleRate * seconds)
        let dataSize = numSamples * 2 // 16-bit mono

        var wav = Data()
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var chunkSize = UInt32(36 + dataSize)
        wav.append(Data(bytes: &chunkSize, count: 4))
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var subchunk1Size: UInt32 = 16
        wav.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1
        wav.append(Data(bytes: &audioFormat, count: 2))
        var numChannels: UInt16 = 1
        wav.append(Data(bytes: &numChannels, count: 2))
        var sr = UInt32(sampleRate)
        wav.append(Data(bytes: &sr, count: 4))
        var byteRate = UInt32(sampleRate * 2)
        wav.append(Data(bytes: &byteRate, count: 4))
        var blockAlign: UInt16 = 2
        wav.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample: UInt16 = 16
        wav.append(Data(bytes: &bitsPerSample, count: 2))
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var subchunk2Size = UInt32(dataSize)
        wav.append(Data(bytes: &subchunk2Size, count: 4))
        wav.append(Data(count: dataSize))

        let player = try? AVAudioPlayer(data: wav)
        player?.numberOfLoops = -1 // loop forever
        return player
    }

    private func startSilence() {
        guard silencePlayer == nil else { return }
        silencePlayer = makeSilencePlayer()
        silencePlayer?.play()
    }

    private func stopSilence() {
        silencePlayer?.stop()
        silencePlayer = nil
    }

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
        center.togglePlayPauseCommand.isEnabled = false
    }

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle
        info[MPMediaItemPropertyArtist] = "Brownie"
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // MARK: - Controls

    func play(_ meditation: Meditation) {
        stop()
        steps = meditation.steps
        totalSteps = steps.count
        stepIndex = 0
        isPlaying = true
        isPaused = false
        currentTitle = meditation.title
        startSilence()
        updateNowPlayingInfo()
        runCurrentStep()
    }

    func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    func pause() {
        isPaused = true
        isPlaying = false
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
        pauseTimer?.invalidate()
        pauseTimer = nil
        stopSilence()
        updateNowPlayingInfo()
    }

    func resume() {
        isPaused = false
        isPlaying = true
        startSilence()
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else {
            runCurrentStep()
        }
        updateNowPlayingInfo()
    }

    func stop() {
        isPaused = false
        isPlaying = false
        synthesizer.stopSpeaking(at: .immediate)
        pauseTimer?.invalidate()
        pauseTimer = nil
        stopSilence()
        steps = []
        stepIndex = 0
        totalSteps = 0
        currentText = ""
        currentTitle = ""
        clearNowPlayingInfo()
    }

    // MARK: - Step Execution

    private func runCurrentStep() {
        guard isPlaying, stepIndex < steps.count else {
            isPlaying = false
            currentText = ""
            stopSilence()
            clearNowPlayingInfo()
            return
        }

        let step = steps[stepIndex]

        switch step {
        case .speak(let text):
            currentText = text
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = speakingRate
            utterance.voice = voice
            utterance.pitchMultiplier = 1.0
            synthesizer.speak(utterance)

        case .pause(let duration):
            currentText = ""
            pauseTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                self.stepIndex += 1
                self.runCurrentStep()
            }

        case .countdown(let totalSeconds):
            expandAndRunCountdown(totalSeconds)
        }
    }

    private func expandAndRunCountdown(_ seconds: TimeInterval) {
        var countdownSteps: [MeditationStep] = []

        if seconds >= 120 {
            var t = seconds
            while t > 60 {
                countdownSteps.append(.speak(formatCountdownNumber(t)))
                countdownSteps.append(.pause(30))
                t -= 30
            }
            countdownSteps.append(.speak("60"))
            countdownSteps.append(.pause(20))
            countdownSteps.append(.speak("40"))
            countdownSteps.append(.pause(20))
        } else if seconds >= 60 {
            countdownSteps.append(.speak("60"))
            countdownSteps.append(.pause(20))
            countdownSteps.append(.speak("40"))
            countdownSteps.append(.pause(20))
        } else if seconds >= 30 {
            countdownSteps.append(.speak(formatCountdownNumber(seconds)))
            countdownSteps.append(.pause(seconds - 20))
        }

        if seconds >= 20 {
            countdownSteps.append(.speak("20"))
            countdownSteps.append(.pause(10))
        }

        countdownSteps.append(.speak("10"))
        countdownSteps.append(.pause(5))
        countdownSteps.append(.speak("5"))
        countdownSteps.append(.pause(5))
        countdownSteps.append(.speak("Done."))

        steps.replaceSubrange(stepIndex...stepIndex, with: countdownSteps)
        totalSteps = steps.count
        runCurrentStep()
    }

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
}

// MARK: - AVSpeechSynthesizerDelegate

extension MeditationPlayer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard isPlaying else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stepIndex += 1
            self.runCurrentStep()
        }
    }
}
