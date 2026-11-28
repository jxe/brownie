import AVFoundation
import MediaPlayer
import UIKit

@Observable
class MeditationPlayer: NSObject {
    enum State {
        case idle
        case preparing
        case playing
        case paused
        case finished
    }

    let listeningHistory = ListeningHistory()
    private(set) var state: State = .idle {
        didSet {
            if oldValue == .playing && state != .playing {
                listeningHistory.end()
            } else if state == .playing && oldValue != .playing, let currentSourceURL {
                listeningHistory.begin(filename: currentSourceURL.deletingPathExtension().lastPathComponent)
            }
        }
    }

    var isPlaying: Bool { state == .playing }
    var isPreparing: Bool { state == .preparing }

    var currentText = ""
    var stepIndex = 0
    var totalSteps = 0
    var currentSourceURL: URL?
    var elapsedSeconds: Int = 0
    /// Set when a meditation couldn't start because iOS gave no speech for its first line.
    /// The list shows it as an alert and clears it.
    var speechFailure: String?
    /// Total length of the current meditation, set once every step has been rendered.
    private(set) var totalSeconds: Int?

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
    /// The playing meditation's title, for the now-playing bar and the lock screen.
    private(set) var currentTitle = ""
    @ObservationIgnored private var playbackStarted = false
    @ObservationIgnored private var playbackGeneration = 0
    @ObservationIgnored private var isAppInForeground = true

    /// The app's one player. Shared so a widget's play intent, which can run before any
    /// view exists, reaches the same player the now-playing bar shows.
    static let shared = MeditationPlayer()

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
        observeAppLifecycle()
    }

    // MARK: - App Lifecycle

    /// Nothing can see playback position while the app is backgrounded (e.g. the phone is
    /// locked), so stop the position timer then; the lock screen extrapolates from Now Playing info.
    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        isAppInForeground = false
        streamingPlayer?.isPositionTrackingEnabled = false
    }

    @objc private func appWillEnterForeground() {
        isAppInForeground = true
        streamingPlayer?.isPositionTrackingEnabled = true
        updateNowPlayingInfo()
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
        player.isPositionTrackingEnabled = isAppInForeground
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

        // Render and schedule buffers in background
        let voice = self.voice
        let rate = self.speakingRate

        renderTask = Task { [weak self, renderer] in
            guard let owner = self else { return }

            // Activating the audio session and starting the engine can each block for tens of
            // milliseconds. Doing them off the main thread keeps the row's tap animation smooth.
            let setupError: Error?
            do {
                owner.configureAudioSession()
                try player.setup()
                setupError = nil
            } catch {
                setupError = error
            }
            let shouldContinue = await MainActor.run { () -> Bool in
                guard owner.playbackGeneration == generation else {
                    // Replaced or stopped while we were starting up; don't leave this engine
                    // (or the audio session) running behind it.
                    player.stop()
                    if owner.state == .idle {
                        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    }
                    return false
                }
                if let setupError {
                    print("StreamingPlayer setup error: \(setupError)")
                    owner.stop()
                    return false
                }
                owner.updateNowPlayingInfo()
                return true
            }
            guard shouldContinue else { return }

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
                                owner.speechFailure = "\(error)"
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
                guard owner.playbackGeneration == generation else { return }
                if !owner.playbackStarted {
                    owner.stop()
                } else if owner.state != .finished {
                    owner.totalSeconds = Int(player.totalDuration.rounded())
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
        totalSeconds = nil
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
        totalSeconds = nil
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

/// How long each meditation was listened to, by day, and a live interval for the playing file.
@Observable
final class ListeningHistory {
    struct Record: Codable {
        var lastPlayed: Date
        /// Listening per local calendar day ("yyyy-MM-dd"), split at midnight. The main record.
        var days: [String: TimeInterval] = [:]
        /// Listening counted before days were kept, which can't be split into days. It counts
        /// toward the total, never toward a day.
        var beforeDaily: TimeInterval = 0
        /// The last 24 hours' intervals, only for the "last 24 hours" stat; older ones are
        /// dropped (their time is already in `days`).
        var intervals: [DateInterval] = []

        init(lastPlayed: Date) {
            self.lastPlayed = lastPlayed
        }

        private enum CodingKeys: String, CodingKey {
            case lastPlayed, days, beforeDaily, intervals
            /// The old shape's folded-in total, read once to migrate.
            case olderSeconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            lastPlayed = try container.decode(Date.self, forKey: .lastPlayed)
            intervals = try container.decodeIfPresent([DateInterval].self, forKey: .intervals) ?? []
            if let days = try container.decodeIfPresent([String: TimeInterval].self, forKey: .days) {
                self.days = days
                beforeDaily = try container.decodeIfPresent(TimeInterval.self, forKey: .beforeDaily) ?? 0
            } else {
                // The old shape: a total of everything older than 24 hours, plus the last
                // 24 hours' intervals, which seed the days.
                beforeDaily = try container.decodeIfPresent(TimeInterval.self, forKey: .olderSeconds) ?? 0
                for interval in intervals { addToDays(interval) }
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(lastPlayed, forKey: .lastPlayed)
            try container.encode(days, forKey: .days)
            try container.encode(beforeDaily, forKey: .beforeDaily)
            try container.encode(intervals, forKey: .intervals)
        }

        /// All listening time recorded. Counting began with the rolling history, so plays
        /// from before it aren't included.
        var totalSeconds: TimeInterval {
            beforeDaily + days.values.reduce(0, +)
        }

        /// Listening on the last `days` local days, today included.
        func seconds(inLastDays days: Int, at now: Date) -> TimeInterval {
            let first = ListeningHistory.dayKey(now.addingTimeInterval(-Double(days - 1) * 86400))
            return self.days.filter { $0.key >= first }.values.reduce(0, +)
        }

        func seconds(inLastDayAt now: Date) -> TimeInterval {
            let cutoff = now.addingTimeInterval(-86400)
            return intervals.reduce(0) { sum, interval in
                sum + max(0, min(now, interval.end).timeIntervalSince(max(cutoff, interval.start)))
            }
        }

        /// Adds a finished interval: to its day (or days, split at midnight) and to the
        /// recent intervals.
        mutating func add(_ interval: DateInterval) {
            intervals.append(interval)
            addToDays(interval)
        }

        private mutating func addToDays(_ interval: DateInterval) {
            let calendar = Calendar.current
            var start = interval.start
            while start < interval.end {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? interval.end
                let end = min(nextDay, interval.end)
                days[ListeningHistory.dayKey(start), default: 0] += end.timeIntervalSince(start)
                start = end
            }
        }
    }

    /// A day's listening to one meditation.
    struct DayListening {
        let filename: String
        let day: Date
        let seconds: TimeInterval
        /// When that day's listening ended, as near as is known: the last play if it was that
        /// day, else the day's end.
        let lastListened: Date
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// The day listening time started being counted. Plays of a meditation made before then
    /// weren't measured, so how much it was listened to is unknown.
    static let countedSince = "2026-11-21"

    private let key = "meditationListeningHistory"
    private var records: [String: Record]
    private(set) var activeFile: String?
    private var started = Date.distantPast
    @ObservationIgnored private var checkpoint: Timer?

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = saved
        } else {
            let legacy = defaults.dictionary(forKey: "recentMeditationPlays") as? [String: Date] ?? [:]
            records = legacy.mapValues { Record(lastPlayed: $0) }
        }
        // Writes an old shape back in the new one.
        save()
    }

    /// Every day on which a meditation was listened to for at least `minimum`, the playing
    /// one included.
    func days(atLeast minimum: TimeInterval, at now: Date = Date()) -> [DayListening] {
        let calendar = Calendar.current
        var result: [DayListening] = []
        for filename in Set(records.keys).union(activeFile.map { [$0] } ?? []) {
            guard let record = record(for: filename, at: now) else { continue }
            for (key, seconds) in record.days where seconds >= minimum {
                guard let day = Self.dayFormatter.date(from: key).map({ calendar.startOfDay(for: $0) }) else { continue }
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)?.addingTimeInterval(-1) ?? day
                let last = calendar.isDate(record.lastPlayed, inSameDayAs: day) ? record.lastPlayed : dayEnd
                result.append(DayListening(filename: filename, day: day, seconds: seconds, lastListened: last))
            }
        }
        return result
    }

    func record(for filename: String, at now: Date) -> Record? {
        guard activeFile == filename else { return records[filename] }
        var record = records[filename] ?? Record(lastPlayed: started)
        record.lastPlayed = max(now, started)
        record.add(DateInterval(start: started, end: record.lastPlayed))
        return record
    }

    /// Moves a meditation's listening to its new filename.
    func rename(_ old: String, to new: String) {
        guard old != new, let record = records.removeValue(forKey: old) else { return }
        records[new] = record
        if activeFile == old { activeFile = new }
        save()
    }

    func begin(filename: String) {
        started = Date()
        activeFile = filename
        save()
        // Bound lost listening time if iOS terminates the app during playback.
        checkpoint = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.save()
        }
    }

    /// Filenames by when they were last played, latest first, the playing one included.
    func recentlyPlayed(at now: Date = Date()) -> [String] {
        var last = records.mapValues(\.lastPlayed)
        if let activeFile { last[activeFile] = now }
        return last.sorted { $0.value > $1.value }.map(\.key)
    }

    func end() {
        checkpoint?.invalidate()
        checkpoint = nil
        if let activeFile {
            records[activeFile] = record(for: activeFile, at: Date())
        }
        activeFile = nil
        save()
    }

    private func save() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-86400)
        var snapshot = records
        if let activeFile { snapshot[activeFile] = record(for: activeFile, at: now) }
        for filename in snapshot.keys {
            guard var record = snapshot[filename] else { continue }
            // Their time is already in `days`; only the last 24 hours' stat needs them.
            guard record.intervals.contains(where: { $0.end <= cutoff }) else { continue }
            record.intervals.removeAll { $0.end <= cutoff }
            snapshot[filename] = record
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
        if activeFile == nil { records = snapshot }
    }
}
