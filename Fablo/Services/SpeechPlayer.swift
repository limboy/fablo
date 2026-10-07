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
    private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timeline: StoryAudioTimeline?
    private var stopTime: Double?
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
        // Start a hair early so the first syllable isn't clipped.
        let begin = timeline.sentenceStarts.indices.contains(sentence) ? timeline.sentenceStarts[sentence] : 0
        player.currentTime = max(0, begin - 0.15)
        self.player = player
        self.timeline = timeline
        stopTime = continuous ? nil : timeline.sentenceEnd(sentence)
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
        if let stopTime, time >= stopTime - 0.05 {
            stop()
            return
        }
        let sentence = timeline.sentence(at: time)
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
