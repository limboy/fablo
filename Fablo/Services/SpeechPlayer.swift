import AVFoundation
import Foundation
import Observation

/// Plays a story's narration and reports which sentence and word are being spoken.
@MainActor
@Observable
final class SpeechPlayer: NSObject, AVAudioPlayerDelegate {
    /// Story + sentence/word currently being read, so views only react to their own playback.
    private(set) var storyID: UUID?
    private(set) var currentID: Int?
    private(set) var currentWord: Int?
    private(set) var isLoading = false
    private(set) var isPlayingAll = false
    private(set) var isPaused = false
    private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timeline: StoryAudioTimeline?
    private var stopTime: Double?
    private var startSentence = 0
    private var rate: Double = 1
    private var loadTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    /// Plays from `sentence`; reads to the end when `continuous`, otherwise just that sentence.
    func play(_ source: StoryAudioSource, from sentence: Int, rate: Double, continuous: Bool) {
        stop()
        self.rate = rate
        storyID = source.storyID
        currentID = sentence
        isPlayingAll = continuous
        isLoading = true
        errorMessage = nil

        loadTask = Task {
            do {
                let (url, timeline) = try await StoryAudioStore.shared.audio(for: source)
                guard !Task.isCancelled else { return }
                try start(url: url, timeline: timeline, sentence: sentence, continuous: continuous)
            } catch {
                guard !Task.isCancelled else { return }
                reset()
                errorMessage = "朗读失败：\(error.localizedDescription)"
            }
        }
    }

    func stop() {
        loadTask?.cancel()
        player?.stop()
        reset()
    }

    func pause() {
        // Nothing to hold on to yet while the narration is still being prepared.
        guard let player, !isLoading else { return stop() }
        player.pause()
        isPaused = true
    }

    func resume() {
        guard let player else { return }
        player.rate = Float(rate)
        player.play()
        isPaused = false
    }

    /// Applies to what is being read right now.
    func setRate(_ rate: Double) {
        self.rate = rate
        player?.rate = Float(rate)
    }

    private func start(url: URL, timeline: StoryAudioTimeline, sentence: Int, continuous: Bool) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)

        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.enableRate = true
        player.rate = Float(rate)
        player.currentTime = timeline.clipStart(sentence)
        self.player = player
        self.timeline = timeline
        stopTime = continuous ? nil : timeline.clipEnd(sentence)
        startSentence = sentence
        isLoading = false
        player.play()

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private func tick() {
        guard let player, let timeline else { return }
        let time = player.currentTime
        // Ticks are ~40ms apart; stop on the tick that would otherwise overshoot.
        if let stopTime, time + 0.04 * rate >= stopTime {
            stop()
            return
        }
        // Playback starts slightly before the sentence; don't report the previous one meanwhile.
        let sentence = max(timeline.sentence(at: time), startSentence)
        if currentID != sentence { currentID = sentence }
        let word = timeline.word(at: time, in: sentence)
        if currentWord != word { currentWord = word }
    }

    private func reset() {
        loadTask = nil
        tickTask?.cancel()
        tickTask = nil
        player = nil
        timeline = nil
        stopTime = nil
        storyID = nil
        currentID = nil
        currentWord = nil
        isLoading = false
        isPlayingAll = false
        isPaused = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.stop() }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            if self.player === player { self.stop() }
        }
    }
}
