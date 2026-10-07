import AVFoundation
import CryptoKit
import Foundation
import Observation

/// Fetches TTS audio once and keeps it on disk; concurrent requests for the same text share one download.
actor SpeechCache {
    static let shared = SpeechCache()

    private let directory: URL = {
        let dir = URL.cachesDirectory.appending(path: "tts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var inFlight: [String: Task<Data, Error>] = [:]

    func audio(text: String, voice: String, instructions: String) async throws -> Data {
        let key = SHA256.hash(data: Data("\(GatewayClient.Model.speech)|\(voice)|\(instructions)|\(text)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let file = directory.appending(path: "\(key).wav")
        if let data = try? Data(contentsOf: file) { return data }
        if let task = inFlight[key] { return try await task.value }

        let task = Task {
            try await GatewayClient.shared.speech(text: text, voice: voice, instructions: instructions)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let data = try await task.value
        try? data.write(to: file)
        return data
    }
}

@MainActor
@Observable
final class SpeechPlayer: NSObject, AVAudioPlayerDelegate {
    struct Item {
        let id: Int
        let text: String
    }

    /// Story + sentence currently being read, so views only react to their own playback.
    private(set) var storyID: UUID?
    private(set) var currentID: Int?
    private(set) var isLoading = false
    private(set) var isPlayingAll = false
    private(set) var errorMessage: String?

    var isActive: Bool { currentID != nil }

    private var task: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var rate: Double = 1
    private var finished: CheckedContinuation<Void, Never>?

    func play(_ items: [Item], from startID: Int, storyID: UUID, language: StoryLanguage, level: String, rate: Double, continuous: Bool) {
        stop()
        self.rate = rate
        guard let start = items.firstIndex(where: { $0.id == startID }) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let queue = continuous ? Array(items[start...]) : [items[start]]
        let instructions = Self.instructions(language: language, level: level)
        let voice = language == .ja ? "Kore" : "Zephyr"
        self.storyID = storyID
        isPlayingAll = continuous
        errorMessage = nil

        task = Task {
            for (offset, item) in queue.enumerated() {
                if Task.isCancelled { break }
                currentID = item.id
                // Prefetch the next sentence while this one plays.
                if offset + 1 < queue.count {
                    let next = queue[offset + 1].text
                    Task { _ = try? await SpeechCache.shared.audio(text: next, voice: voice, instructions: instructions) }
                }
                do {
                    isLoading = true
                    let data = try await SpeechCache.shared.audio(text: item.text, voice: voice, instructions: instructions)
                    isLoading = false
                    if Task.isCancelled { break }
                    try await playAndWait(data)
                } catch {
                    isLoading = false
                    if !Task.isCancelled { errorMessage = "朗读失败：\(error.localizedDescription)" }
                    break
                }
            }
            if !Task.isCancelled { reset() }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        resumeFinished()
        reset()
    }

    private func reset() {
        player = nil
        currentID = nil
        storyID = nil
        isLoading = false
        isPlayingAll = false
    }

    /// Applies to the sentence being read right now as well as the rest of the queue.
    func setRate(_ rate: Double) {
        self.rate = rate
        player?.rate = Float(rate)
    }

    private func playAndWait(_ data: Data) async throws {
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.enableRate = true
        player.rate = Float(rate)
        self.player = player
        await withCheckedContinuation { continuation in
            finished = continuation
            player.play()
        }
    }

    private func resumeFinished() {
        finished?.resume()
        finished = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resumeFinished() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.resumeFinished() }
    }

    private static func instructions(language: StoryLanguage, level: String) -> String {
        let beginner = ["A1", "A2", "N5", "N4"].contains(level)
        let pace = beginner ? "slowly and very clearly" : "at a natural, relaxed pace"
        let accent = language == .ja ? "in standard Tokyo Japanese" : "in clear standard English"
        return "Read this aloud \(accent), \(pace), like an audiobook narrator for language learners."
    }
}
