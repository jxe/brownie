import AVFoundation
import Combine

class MeditationPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentText = ""
    @Published var stepIndex = 0
    @Published var totalSteps = 0

    private let synthesizer = AVSpeechSynthesizer()
    private var steps: [MeditationStep] = []
    private var pauseWorkItem: DispatchWorkItem?
    private var isPaused = false

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
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
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
        pauseWorkItem?.cancel()
        pauseWorkItem = nil
    }

    func resume() {
        isPaused = false
        isPlaying = true
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else {
            runCurrentStep()
        }
    }

    func stop() {
        isPaused = false
        isPlaying = false
        synthesizer.stopSpeaking(at: .immediate)
        pauseWorkItem?.cancel()
        pauseWorkItem = nil
        steps = []
        stepIndex = 0
        totalSteps = 0
        currentText = ""
    }

    // MARK: - Step Execution

    private func runCurrentStep() {
        guard isPlaying, stepIndex < steps.count else {
            isPlaying = false
            currentText = ""
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
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.isPlaying else { return }
                DispatchQueue.main.async {
                    self.stepIndex += 1
                    self.runCurrentStep()
                }
            }
            pauseWorkItem = work
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + duration, execute: work
            )

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
