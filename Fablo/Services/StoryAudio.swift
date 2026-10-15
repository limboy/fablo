import CryptoKit
import Foundation

/// When each sentence and word starts in a story's narration.
struct StoryAudioTimeline: Codable {
    /// Bump when voice, instructions or alignment change so old audio is regenerated.
    static let currentVersion = 3

    var version: Int
    var duration: Double
    /// `wordStarts[sentence][word]`, words flattened across chunks in display order;
    /// nil for words that aren't spoken (punctuation).
    var wordStarts: [[Double?]]
    var sentenceStarts: [Double]
    /// When the last spoken sound of each sentence ends (before the pause that follows).
    var sentenceEnds: [Double]
    /// False when transcription failed and timings were estimated from text length.
    var isAligned: Bool

    /// Where to start a single sentence: inside the pause before it, so nothing of the
    /// previous sentence is heard and the first syllable isn't clipped.
    func clipStart(_ sentence: Int) -> Double {
        guard sentenceStarts.indices.contains(sentence) else { return 0 }
        let start = sentenceStarts[sentence]
        let previousEnd = sentence > 0 ? sentenceEnds[sentence - 1] : 0
        return max(previousEnd, start - min(0.15, (start - previousEnd) / 2))
    }

    /// Where to stop a single sentence: inside the pause after it, before the next one begins.
    func clipEnd(_ sentence: Int) -> Double {
        guard sentenceEnds.indices.contains(sentence) else { return duration }
        let end = sentenceEnds[sentence]
        let nextStart = sentence + 1 < sentenceStarts.count ? sentenceStarts[sentence + 1] : duration
        return min(nextStart, end + min(0.25, max(nextStart - end, 0) / 2))
    }

    func sentence(at time: Double) -> Int {
        sentenceStarts.lastIndex { $0 <= time } ?? 0
    }

    func word(at time: Double, in sentence: Int) -> Int? {
        guard wordStarts.indices.contains(sentence) else { return nil }
        return wordStarts[sentence].indices.last { index in
            wordStarts[sentence][index].map { $0 <= time } ?? false
        }
    }
}

/// A snapshot of the server connection and the word layout used by the player.
struct StoryAudioSource: Sendable {
    let storyID: UUID
    let client: BackendClient
    let title: String
    let coverData: Data?
    let wordCounts: [Int]

    init(story: Story, content: StoryContent) {
        storyID = story.id
        client = story.client
        title = story.title
        coverData = story.coverData
        wordCounts = content.allSentences.map { $0.sentence.chunks.reduce(0) { $0 + $1.words.count } }
    }
}

/// Downloads immutable server audio and its matching timeline. Nothing is generated here.
actor StoryAudioStore {
    static let shared = StoryAudioStore()
    private var inFlight: [String: Task<(URL, StoryAudioTimeline), Error>] = [:]

    func audio(for source: StoryAudioSource) async throws -> (URL, StoryAudioTimeline) {
        let key = source.client.connection.baseURL.absoluteString + source.storyID.uuidString
        if let task = inFlight[key] { return try await task.value }
        let task = Task { try await Self.download(source) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    nonisolated func prepare(_ source: StoryAudioSource) {
        Task { _ = try? await audio(for: source) }
    }

    private static func download(_ source: StoryAudioSource) async throws -> (URL, StoryAudioTimeline) {
        var version: String?
        for _ in 0..<900 {
            try Task.checkCancellation()
            let record = try await source.client.story(source.storyID, statusOnly: true)
            if let ready = record.audioVersion { version = ready; break }
            if record.audioStatus == "failed" {
                throw BackendError.message("音频生成失败，请在书库中重新生成音频")
            }
            try await Task.sleep(for: .seconds(2))
        }
        guard let version, UUID(uuidString: version) != nil else {
            throw BackendError.message("音频仍在服务端处理，请稍后重试")
        }
        let namespace = SHA256.hash(data: Data(source.client.connection.baseURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let directory = URL.cachesDirectory.appending(path: "ServerAudio/\(namespace)/\(source.storyID.uuidString)/\(version)", directoryHint: .isDirectory)
        let audioURL = directory.appending(path: "audio.m4a")
        let timelineURL = directory.appending(path: "timeline.json")
        if FileManager.default.fileExists(atPath: audioURL.path),
           let data = try? Data(contentsOf: timelineURL),
           let timeline = try? JSONDecoder().decode(StoryAudioTimeline.self, from: data),
           (try? validate(timeline, wordCounts: source.wordCounts)) != nil {
            return (audioURL, timeline)
        }
        let staging = directory.deletingLastPathComponent().appending(path: ".download-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        async let download: Void = source.client.downloadAudio(storyID: source.storyID, version: version, to: staging.appending(path: "audio.m4a"))
        let data = try await source.client.asset("timeline", storyID: source.storyID, version: version)
        let timeline = try JSONDecoder().decode(StoryAudioTimeline.self, from: data)
        try validate(timeline, wordCounts: source.wordCounts)
        try data.write(to: staging.appending(path: "timeline.json"), options: .atomic)
        try await download
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.moveItem(at: staging, to: directory)
        return (audioURL, timeline)
    }

    private static func validate(_ timeline: StoryAudioTimeline, wordCounts: [Int]) throws {
        let count = wordCounts.count
        guard timeline.version == StoryAudioTimeline.currentVersion,
              timeline.duration.isFinite, timeline.duration > 0,
              timeline.sentenceStarts.count == count, timeline.sentenceEnds.count == count,
              timeline.wordStarts.count == count else { throw BackendError.message("音频时间轴与短文不匹配") }
        for index in 0..<count {
            let start = timeline.sentenceStarts[index], end = timeline.sentenceEnds[index]
            guard start.isFinite, end.isFinite, start >= 0, end >= start, end <= timeline.duration,
                  index == 0 || start >= timeline.sentenceEnds[index - 1],
                  timeline.wordStarts[index].count == wordCounts[index] else { throw BackendError.message("音频时间轴无效") }
            var previous = start
            for time in timeline.wordStarts[index].compactMap({ $0 }) {
                guard time.isFinite, time >= previous, time <= end else { throw BackendError.message("单词时间轴无效") }
                previous = time
            }
        }
    }
}
