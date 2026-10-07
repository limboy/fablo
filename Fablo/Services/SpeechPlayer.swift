import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

/// Plays a story's narration and reports which sentence and word are being spoken.
/// Keeps playing in the background and shows up on the lock screen / Control Center.
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
    private var lastTime: Double = 0
    private var rate: Double = 1
    /// Restart full-story playback from the beginning when it reaches the end.
    private var looping = false
    private var nowPlaying: [String: Any] = [:]
    private var loadTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    override init() {
        super.init()
        configureRemoteCommands()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil
        )
    }

    /// Plays from `sentence`; reads to the end when `continuous`, otherwise just that sentence.
    func play(_ source: StoryAudioSource, from sentence: Int, rate: Double, continuous: Bool, looping: Bool = false) {
        stop()
        self.rate = rate
        self.looping = looping
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
                publishNowPlaying(title: source.title, cover: source.coverData)
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
        updateNowPlayingProgress()
    }

    func resume() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.rate = Float(rate)
        player.play()
        isPaused = false
        updateNowPlayingProgress()
    }

    /// Applies to what is being read right now.
    func setRate(_ rate: Double) {
        self.rate = rate
        player?.rate = Float(rate)
        updateNowPlayingProgress()
    }

    /// Applies to the current full-story playback too.
    func setLooping(_ looping: Bool) {
        self.looping = looping
        if isPlayingAll { player?.numberOfLoops = looping ? -1 : 0 }
    }

    private func start(url: URL, timeline: StoryAudioTimeline, sentence: Int, continuous: Bool) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)

        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.enableRate = true
        player.rate = Float(rate)
        player.numberOfLoops = continuous && looping ? -1 : 0
        player.currentTime = timeline.clipStart(sentence)
        self.player = player
        self.timeline = timeline
        stopTime = continuous ? nil : timeline.clipEnd(sentence)
        startSentence = sentence
        lastTime = player.currentTime
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
        // Looped back to the beginning of the story.
        if time + 1 < lastTime {
            startSentence = 0
            updateNowPlayingProgress()
        }
        lastTime = time
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
        nowPlaying = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Lock screen / Control Center

    private func publishNowPlaying(title: String, cover: Data?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Fablo",
            MPMediaItemPropertyPlaybackDuration: player?.duration ?? 0,
        ]
        if let cover, let image = UIImage(data: cover) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        nowPlaying = info
        updateNowPlayingProgress()
    }

    private func updateNowPlayingProgress() {
        guard let player, !nowPlaying.isEmpty else { return }
        nowPlaying[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        nowPlaying[MPNowPlayingInfoPropertyPlaybackRate] = isPaused ? 0.0 : rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.isPaused ? self.resume() : self.pause()
            return .success
        }
    }

    /// A call or another app's audio pauses us; reflect that instead of looking stuck.
    @objc nonisolated private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began
        else { return }
        Task { @MainActor in
            if self.player != nil, !self.isPaused { self.pause() }
        }
    }

    // MARK: AVAudioPlayerDelegate

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
