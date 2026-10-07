import Foundation
import SwiftData

@Model
final class Story {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var languageRaw: String
    var level: String
    var genre: String
    var title: String
    var titleZh: String
    var summaryZh: String
    var coverPrompt: String
    var contentData: Data
    @Attribute(.externalStorage) var coverData: Data?
    var coverFailed: Bool = false
    var analysesData: Data?

    init(content: StoryContent, request: StoryRequest) throws {
        id = UUID()
        createdAt = .now
        languageRaw = request.language.rawValue
        level = request.level.name
        genre = request.genre.rawValue
        title = content.title
        titleZh = content.titleZh
        summaryZh = content.summaryZh
        coverPrompt = content.coverPrompt
        contentData = try JSONEncoder().encode(content)
    }

    var language: StoryLanguage { StoryLanguage(rawValue: languageRaw) ?? .en }

    var genreSymbol: String { StoryGenre(rawValue: genre)?.symbol ?? "book.fill" }

    func decodedContent() -> StoryContent? {
        try? JSONDecoder().decode(StoryContent.self, from: contentData)
    }

    // Analyses are cached per sentence index so reopening a sentence is instant.
    private var analyses: [String: SentenceAnalysis] {
        guard let analysesData else { return [:] }
        return (try? JSONDecoder().decode([String: SentenceAnalysis].self, from: analysesData)) ?? [:]
    }

    func analysis(for index: Int) -> SentenceAnalysis? {
        analyses[String(index)]
    }

    func setAnalysis(_ analysis: SentenceAnalysis, for index: Int) {
        var all = analyses
        all[String(index)] = analysis
        analysesData = try? JSONEncoder().encode(all)
    }
}
