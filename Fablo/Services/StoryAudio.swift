import AVFoundation
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

/// What the store needs from a story, as plain values so it can cross actor boundaries.
struct StoryAudioSource: Sendable {
    let storyID: UUID
    let language: StoryLanguage
    let level: String
    /// For the lock screen / Control Center.
    let title: String
    let coverData: Data?
    /// paragraphs → sentences → words (surface forms, in display order)
    let paragraphs: [[[String]]]

    init(story: Story, content: StoryContent) {
        storyID = story.id
        language = story.language
        level = story.level
        title = story.title
        coverData = story.coverData
        paragraphs = content.paragraphs.map { paragraph in
            paragraph.sentences.map { sentence in
                sentence.chunks.flatMap { $0.words.map(\.surface) }
            }
        }
    }

    var sentences: [[String]] { paragraphs.flatMap { $0 } }

    /// English words carry no spaces in their surface, so rebuild spacing for the narrator.
    var narrationText: String {
        paragraphs.map { paragraph in
            paragraph.map { words in
                language == .ja ? words.joined() : Self.joinEnglish(words)
            }
            .joined(separator: language == .ja ? "" : " ")
        }
        .joined(separator: "\n\n")
    }

    private static func joinEnglish(_ words: [String]) -> String {
        var text = ""
        for word in words {
            let attaches = word.count == 1 && ".,!?;:)]”’".contains(word)
            if !text.isEmpty && !attaches && !text.hasSuffix("(") && !text.hasSuffix("“") { text += " " }
            text += word
        }
        return text
    }
}

/// Narrates a whole story in one TTS call, aligns word timings with a transcription,
/// and keeps both on disk. Concurrent requests for the same story share one job.
actor StoryAudioStore {
    static let shared = StoryAudioStore()

    private let directory: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "StoryAudio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var inFlight: [UUID: Task<(URL, StoryAudioTimeline), Error>] = [:]

    func audio(for source: StoryAudioSource) async throws -> (URL, StoryAudioTimeline) {
        if let cached = cached(source.storyID) { return cached }
        if let task = inFlight[source.storyID] { return try await task.value }

        let directory = directory
        let task = Task { try await Self.produce(source, in: directory) }
        inFlight[source.storyID] = task
        defer { inFlight[source.storyID] = nil }
        return try await task.value
    }

    /// Starts narration in the background so it's ready by the time the reader presses play.
    nonisolated func prepare(_ source: StoryAudioSource) {
        Task { _ = try? await audio(for: source) }
    }

    func remove(_ storyID: UUID) {
        for ext in ["m4a", "json"] {
            try? FileManager.default.removeItem(at: directory.appending(path: "\(storyID).\(ext)"))
        }
    }

    private func cached(_ storyID: UUID) -> (URL, StoryAudioTimeline)? {
        let audioURL = directory.appending(path: "\(storyID).m4a")
        guard FileManager.default.fileExists(atPath: audioURL.path),
              let data = try? Data(contentsOf: directory.appending(path: "\(storyID).json")),
              let timeline = try? JSONDecoder().decode(StoryAudioTimeline.self, from: data),
              timeline.version == StoryAudioTimeline.currentVersion
        else { return nil }
        return (audioURL, timeline)
    }

    private static func produce(_ source: StoryAudioSource, in directory: URL) async throws -> (URL, StoryAudioTimeline) {
        let wav = try await GatewayClient.shared.speech(
            text: source.narrationText,
            voice: voice(for: source.language),
            instructions: instructions(language: source.language, level: source.level)
        )
        let wavURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).wav")
        try wav.write(to: wavURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }
        let duration = try audioDuration(wavURL)

        let timeline: StoryAudioTimeline
        if let words = try? await GatewayClient.shared.transcribeWords(wav: wav) {
            timeline = TimelineAligner.align(source.sentences, to: words, duration: duration)
        } else {
            timeline = TimelineAligner.estimate(source.sentences, duration: duration)
        }

        let audioURL = directory.appending(path: "\(source.storyID).m4a")
        try encodeAAC(from: wavURL, to: audioURL)
        try JSONEncoder().encode(timeline).write(to: directory.appending(path: "\(source.storyID).json"))
        return (audioURL, timeline)
    }

    private static func voice(for language: StoryLanguage) -> String {
        language == .ja ? "Kore" : "Zephyr"
    }

    private static func instructions(language: StoryLanguage, level: String) -> String {
        let beginner = ["A1", "A2", "N5", "N4"].contains(level)
        let pace = beginner ? "slowly and very clearly" : "at a natural, relaxed pace"
        let accent = language == .ja ? "in standard Tokyo Japanese" : "in clear standard English"
        return "Read this story aloud \(accent), \(pace), like an audiobook narrator for language learners. "
            + "Pause briefly between sentences and a little longer between paragraphs."
    }

    private static func audioDuration(_ url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// WAV from the TTS is ~10× larger than AAC; stories are kept, so store them compressed.
    private static func encodeAAC(from wavURL: URL, to url: URL) throws {
        let input = try AVAudioFile(forReading: wavURL)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 64_000,
        ]
        try? FileManager.default.removeItem(at: url)
        let output = try AVAudioFile(forWriting: url, settings: settings,
                                     commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else { return }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }
}

/// Maps transcription timings back onto the story's own words.
///
/// The transcript doesn't match the text exactly (キツネ may come back as 狐, punctuation differs),
/// so both sides are reduced to comparable characters, diffed, and unmatched stretches of our text
/// take their times from the transcript stretch they replaced.
enum TimelineAligner {
    static func align(_ sentences: [[String]], to words: [GatewayClient.TimedWord], duration: Double) -> StoryAudioTimeline {
        // Our side: comparable characters, each remembering which word it belongs to.
        var ref: [Character] = []
        var refWord: [(sentence: Int, word: Int)] = []
        for (s, sentenceWords) in sentences.enumerated() {
            for (w, surface) in sentenceWords.enumerated() {
                for character in surface {
                    if let c = comparable(character) {
                        ref.append(c)
                        refWord.append((s, w))
                    }
                }
            }
        }

        // Transcript side: characters with times spread across each recognized word.
        var hyp: [Character] = []
        var hypStart: [Double] = []
        var hypEnd: [Double] = []
        for word in words {
            let chars = word.text.compactMap(comparable)
            let step = word.durationMilliseconds / Double(max(chars.count, 1))
            for (k, c) in chars.enumerated() {
                hyp.append(c)
                hypStart.append((word.offsetMilliseconds + step * Double(k)) / 1000)
                hypEnd.append((word.offsetMilliseconds + step * Double(k + 1)) / 1000)
            }
        }
        guard !ref.isEmpty, !hyp.isEmpty else { return estimate(sentences, duration: duration) }

        let (starts, ends) = alignedTimes(ref: ref, hyp: hyp, hypStart: hypStart, hypEnd: hypEnd, end: duration)

        var wordStarts = sentences.map { [Double?](repeating: nil, count: $0.count) }
        var sentenceEnds = [Double](repeating: 0, count: sentences.count)
        for (index, owner) in refWord.enumerated() {
            if wordStarts[owner.sentence][owner.word] == nil {
                wordStarts[owner.sentence][owner.word] = starts[index]
            }
            sentenceEnds[owner.sentence] = max(sentenceEnds[owner.sentence], ends[index])
        }
        return timeline(wordStarts: wordStarts, sentenceEnds: sentenceEnds, duration: duration, isAligned: true)
    }

    /// Fallback without a transcription: spread time by character count.
    static func estimate(_ sentences: [[String]], duration: Double) -> StoryAudioTimeline {
        let lengths: [Int] = sentences.joined().map { surface in surface.compactMap(comparable).count }
        let total = Double(max(lengths.reduce(0, +), 1))
        var elapsed = 0.0
        let wordStarts: [[Double?]] = sentences.map { words in
            words.map { surface in
                let length = Double(surface.compactMap(comparable).count)
                guard length > 0 else { return nil }
                defer { elapsed += length }
                return duration * elapsed / total
            }
        }
        return timeline(wordStarts: wordStarts, sentenceEnds: nil, duration: duration, isAligned: false)
    }

    /// Without measured ends (estimated timings), a sentence is taken to run until the next one starts.
    private static func timeline(wordStarts: [[Double?]], sentenceEnds: [Double]?, duration: Double, isAligned: Bool) -> StoryAudioTimeline {
        var sentenceStarts: [Double] = []
        for words in wordStarts {
            let start = words.compactMap { $0 }.min() ?? sentenceStarts.last ?? 0
            sentenceStarts.append(max(start, sentenceStarts.last ?? 0))
        }
        let ends = sentenceStarts.indices.map { index in
            let nextStart = index + 1 < sentenceStarts.count ? sentenceStarts[index + 1] : duration
            guard let measured = sentenceEnds?[index], measured > sentenceStarts[index] else { return nextStart }
            return min(measured, nextStart)
        }
        return StoryAudioTimeline(
            version: StoryAudioTimeline.currentVersion,
            duration: duration,
            wordStarts: wordStarts,
            sentenceStarts: sentenceStarts,
            sentenceEnds: ends,
            isAligned: isAligned
        )
    }

    /// Start and end time for each of our characters.
    private static func alignedTimes(
        ref: [Character], hyp: [Character], hypStart: [Double], hypEnd: [Double], end: Double
    ) -> (starts: [Double], ends: [Double]) {
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in hyp.difference(from: ref) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        // Matched (ref, hyp) index pairs, in order.
        var anchors: [(ref: Int, hyp: Int)] = []
        var i = 0, j = 0
        while i < ref.count, j < hyp.count {
            if removed.contains(i) { i += 1; continue }
            if inserted.contains(j) { j += 1; continue }
            anchors.append((i, j))
            i += 1
            j += 1
        }

        var starts = [Double](repeating: 0, count: ref.count)
        var ends = [Double](repeating: 0, count: ref.count)
        var previous: (ref: Int, hyp: Int, end: Double)? = nil
        let sentinel = (ref: ref.count, hyp: hyp.count)
        for anchor in anchors + [sentinel] {
            let anchorTime = anchor.ref < ref.count ? hypStart[anchor.hyp] : end
            let refGap = ((previous?.ref ?? -1) + 1)..<anchor.ref
            let hypGap = ((previous?.hyp ?? -1) + 1)..<anchor.hyp
            for (k, r) in refGap.enumerated() {
                let count = Double(refGap.count)
                if !hypGap.isEmpty {
                    // Replaced stretch (e.g. キツネ ↔ 狐, きのう ↔ 昨日): spread our characters evenly
                    // over the time the narrator spent there — our kana track speech better than kanji.
                    let from = hypStart[hypGap.lowerBound]
                    let to = hypEnd[hypGap.upperBound - 1]
                    starts[r] = from + (to - from) * Double(k) / count
                    ends[r] = from + (to - from) * Double(k + 1) / count
                } else {
                    // Nothing recognized here: squeeze it in after the previous sound.
                    let from = previous?.end ?? 0
                    starts[r] = from + (anchorTime - from) * Double(k) / (count + 1)
                    ends[r] = starts[r]
                }
            }
            if anchor.ref < ref.count {
                starts[anchor.ref] = anchorTime
                ends[anchor.ref] = hypEnd[anchor.hyp]
                previous = (anchor.ref, anchor.hyp, hypEnd[anchor.hyp])
            }
        }
        return (starts, ends)
    }

    /// Letters and digits only, width/case-folded, katakana folded to hiragana.
    private static func comparable(_ character: Character) -> Character? {
        let folded = String(character).precomposedStringWithCompatibilityMapping.lowercased()
        guard let scalar = folded.unicodeScalars.first,
              folded.unicodeScalars.count == 1,
              scalar.properties.isAlphabetic || scalar.properties.numericType != nil
        else {
            return folded.count == 1 && folded.first!.isLetter ? folded.first : nil
        }
        if (0x30A1...0x30F6).contains(scalar.value), let hiragana = Unicode.Scalar(scalar.value - 0x60) {
            return Character(hiragana)
        }
        return Character(scalar)
    }
}
