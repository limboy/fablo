import Foundation
import Observation

/// A view of a server record, hydrated from disposable local copies when available.
@Observable
final class Story: Identifiable, Hashable {
    let id: UUID
    let client: BackendClient
    private(set) var createdAt: Date
    private(set) var updatedAt: String
    private(set) var language: StoryLanguage
    private(set) var level: String
    private(set) var genre: String
    private(set) var title: String
    private(set) var titleZh: String
    private(set) var summaryZh: String
    private(set) var generationRequest: BackendGenerationRequest?
    private(set) var coverStatus: String
    private(set) var audioStatus: String
    private(set) var coverVersion: String?
    private(set) var audioVersion: String?
    private var content: StoryContent?
    private var analyses: [String: SentenceAnalysis]
    var coverData: Data?

    init(record: BackendStory, client: BackendClient) {
        id = record.id
        self.client = client
        createdAt = Self.date(record.createdAt)
        updatedAt = record.updatedAt
        language = record.language
        level = record.level
        genre = record.genre
        title = record.title
        titleZh = record.titleZh
        summaryZh = record.summaryZh
        generationRequest = record.generationRequest
        coverStatus = record.coverStatus
        audioStatus = record.audioStatus
        coverVersion = record.coverVersion
        audioVersion = record.audioVersion
        content = record.content
        analyses = record.analyses ?? [:]
    }

    func apply(_ record: BackendStory) {
        guard record.updatedAt >= updatedAt else { restoreCachedDetails(record); return }
        createdAt = Self.date(record.createdAt)
        updatedAt = record.updatedAt
        language = record.language
        level = record.level
        genre = record.genre
        title = record.title
        titleZh = record.titleZh
        summaryZh = record.summaryZh
        generationRequest = record.generationRequest
        coverStatus = record.coverStatus
        audioStatus = record.audioStatus
        if coverVersion != record.coverVersion { coverData = nil }
        coverVersion = record.coverVersion
        audioVersion = record.audioVersion
        if let content = record.content { self.content = content }
        if let analyses = record.analyses { self.analyses = analyses }
    }

    func restoreCachedDetails(_ record: BackendStory) {
        guard record.id == id else { return }
        if content == nil { content = record.content }
        analyses.merge(record.analyses ?? [:]) { current, _ in current }
    }

    var coverFailed: Bool { coverStatus == "failed" }
    var genreSymbol: String { StoryGenre(rawValue: genre)?.symbol ?? "book.fill" }
    func decodedContent() -> StoryContent? { content }
    func analysis(for index: Int) -> SentenceAnalysis? { analyses[String(index)] }
    func setAnalysis(_ analysis: SentenceAnalysis, for index: Int) { analyses[String(index)] = analysis }

    static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) ?? .distantPast
    }

    static func == (lhs: Story, rhs: Story) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
