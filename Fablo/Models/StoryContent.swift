import Foundation

// MARK: - Generation options

enum StoryLanguage: String, Codable, CaseIterable, Identifiable {
    case en, ja

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .en: "English"
        case .ja: "日本語"
        }
    }

    var chineseName: String {
        switch self {
        case .en: "英语"
        case .ja: "日语"
        }
    }

    var code: String {
        switch self {
        case .en: "EN"
        case .ja: "JA"
        }
    }

    var glyph: String {
        switch self {
        case .en: "Aa"
        case .ja: "あ"
        }
    }

    var levels: [StoryLevel] {
        switch self {
        case .en:
            [
                StoryLevel(id: "A1", name: "A1", summary: "入门 · 常用词、简单现在时"),
                StoryLevel(id: "A2", name: "A2", summary: "初级 · 日常话题、过去时"),
                StoryLevel(id: "B1", name: "B1", summary: "中级 · 复合句、常见短语"),
                StoryLevel(id: "B2", name: "B2", summary: "中高级 · 从句、丰富词汇"),
                StoryLevel(id: "C1", name: "C1", summary: "高级 · 地道表达、复杂结构"),
            ]
        case .ja:
            [
                StoryLevel(id: "N5", name: "N5", summary: "入门 · 基础汉字、です/ます"),
                StoryLevel(id: "N4", name: "N4", summary: "初级 · て形、简单复句"),
                StoryLevel(id: "N3", name: "N3", summary: "中级 · 日常文章、常用句型"),
                StoryLevel(id: "N2", name: "N2", summary: "中高级 · 报刊随笔、书面语"),
                StoryLevel(id: "N1", name: "N1", summary: "高级 · 复杂文体、细腻表达"),
            ]
        }
    }
}

struct StoryLevel: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
}

enum StoryGenre: String, CaseIterable, Identifiable {
    case daily = "日常生活"
    case fable = "童话寓言"
    case fantasy = "奇幻冒险"
    case scifi = "科幻"
    case mystery = "悬疑推理"
    case travel = "旅行见闻"
    case food = "美食"
    case school = "校园"
    case work = "职场"
    case history = "历史人物"
    case nature = "自然科普"
    case news = "新闻报道"
    case dialogue = "对话"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .daily: "cup.and.saucer.fill"
        case .fable: "pawprint.fill"
        case .fantasy: "wand.and.stars"
        case .scifi: "atom"
        case .mystery: "magnifyingglass"
        case .travel: "suitcase.fill"
        case .food: "fork.knife"
        case .school: "backpack.fill"
        case .work: "briefcase.fill"
        case .history: "scroll.fill"
        case .nature: "leaf.fill"
        case .news: "newspaper.fill"
        case .dialogue: "bubble.left.and.bubble.right.fill"
        }
    }
}

enum StoryLength: String, CaseIterable, Identifiable {
    case short, medium, long

    var id: String { rawValue }

    var label: String {
        switch self {
        case .short: "短篇"
        case .medium: "中篇"
        case .long: "长篇"
        }
    }

    var sentenceCount: Int {
        switch self {
        case .short: 6
        case .medium: 12
        case .long: 20
        }
    }
}

struct StoryRequest: Hashable {
    var language: StoryLanguage
    var level: StoryLevel
    var genre: StoryGenre
    var length: StoryLength
    var topic: String
}

// MARK: - Generated content (keys are short to keep the LLM output small)

struct StoryContent: Codable {
    var title: String
    var titleZh: String
    var summaryZh: String
    var coverPrompt: String
    var paragraphs: [Paragraph]

    struct Paragraph: Codable {
        var sentences: [Sentence]
    }

    /// Sentences numbered across the whole story, grouped by paragraph.
    var numberedParagraphs: [[SentenceRef]] {
        var index = 0
        return paragraphs.map { paragraph in
            paragraph.sentences.map { sentence in
                defer { index += 1 }
                return SentenceRef(id: index, sentence: sentence)
            }
        }
    }

    var allSentences: [SentenceRef] { numberedParagraphs.flatMap { $0 } }
}

struct SentenceRef: Identifiable, Hashable {
    let id: Int
    let sentence: Sentence

    static func == (a: SentenceRef, b: SentenceRef) -> Bool { a.id == b.id && a.sentence.text == b.sentence.text }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Sentence: Codable {
    var text: String
    var zh: String
    var chunks: [Chunk]

    enum CodingKeys: String, CodingKey {
        case text, zh
        case chunks = "c"
    }
}

struct Chunk: Codable {
    var role: ChunkRole
    var words: [Word]

    enum CodingKeys: String, CodingKey {
        case role
        case words = "w"
    }

    var text: String { words.map(\.surface).joined() }
}

enum ChunkRole: String, Codable, CaseIterable {
    case topic, subject, object, predicate, complement, modifier, adverbial, connector, other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChunkRole(rawValue: raw) ?? .other
    }

    var label: String {
        switch self {
        case .topic: "主题"
        case .subject: "主语"
        case .object: "宾语"
        case .predicate: "谓语"
        case .complement: "补语"
        case .modifier: "修饰"
        case .adverbial: "状语"
        case .connector: "连接"
        case .other: "其他"
        }
    }
}

struct Word: Codable {
    var surface: String
    var reading: String
    var romaji: String
    var pos: PartOfSpeech
    var gloss: String

    enum CodingKeys: String, CodingKey {
        case surface = "s"
        case reading = "r"
        case romaji = "ro"
        case pos = "p"
        case gloss = "g"
    }

    /// Furigana is only useful when the word contains kanji.
    var furigana: String? {
        guard !reading.isEmpty, reading != surface,
              surface.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) || $0.value == 0x3005 })
        else { return nil }
        return reading
    }
}

enum PartOfSpeech: String, Codable, CaseIterable {
    case noun, pronoun, verb, adjective, adverb, particle, auxiliary, conjunction
    case determiner, preposition, interjection, number, punctuation, other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PartOfSpeech(rawValue: raw) ?? .other
    }

    var label: String {
        switch self {
        case .noun: "名词"
        case .pronoun: "代词"
        case .verb: "动词"
        case .adjective: "形容词"
        case .adverb: "副词"
        case .particle: "助词"
        case .auxiliary: "助动词"
        case .conjunction: "连词"
        case .determiner: "限定词"
        case .preposition: "介词"
        case .interjection: "感叹词"
        case .number: "数词"
        case .punctuation: "标点"
        case .other: "其他"
        }
    }
}

// MARK: - Sentence analysis

struct SentenceAnalysis: Codable {
    var structure: String
    var grammar: [GrammarPoint]
    var vocabulary: [VocabItem]
    var nuance: String

    struct GrammarPoint: Codable, Hashable {
        var point: String
        var explanation: String
        var example: String
        var exampleZh: String
    }

    struct VocabItem: Codable, Hashable {
        var word: String
        var reading: String
        var meaning: String
        var note: String
    }
}
