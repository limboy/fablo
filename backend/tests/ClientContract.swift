import Foundation

/// Runs the production Swift API client against the isolated PM2 smoke service.
@main
struct ClientContract {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let connection = try BackendConnection(address: environment["FABLO_TEST_URL"]!, token: environment["FABLO_TEST_TOKEN"]!)
        let cache = BackendCache(root: URL(fileURLWithPath: environment["FABLO_TEST_OUTPUT"]!).appending(path: "client-cache"))
        let client = BackendClient(connection: connection, cache: cache)
        let initial = try await client.stories()
        guard let first = initial.first, initial.count == 1 else { fatalError("Expected one server story") }
        let story = try await client.story(first.id)
        precondition(story.content?.allSentences.count == 2)
        precondition(story.createdAt.contains("T"))
        precondition(story.generationRequest?.language == .en)
        precondition(story.generationRequest?.level == "A2")
        precondition(story.generationRequest?.genre == "日常生活")
        precondition(story.generationRequest?.length == .short)
        precondition(story.generationRequest?.topic == "morning")
        let model = Story(record: story, client: client)
        let coverJob = BackendJob(id: UUID(), kind: "cover", storyId: story.id, status: "running", request: story.generationRequest,
                                  sentenceIndex: nil, createdAt: story.createdAt, error: nil)
        let audioJob = BackendJob(id: UUID(), kind: "audio", storyId: story.id, status: "queued", request: story.generationRequest,
                                  sentenceIndex: nil, createdAt: story.createdAt, error: nil)
        let grouped = LibraryEntry.make(stories: [model], jobs: [coverJob, audioJob], language: .en)
        precondition(grouped.count == 1 && grouped[0].jobs.count == 2 && grouped[0].id == story.id)
        precondition(LibraryEntry.make(stories: [model], jobs: [coverJob, audioJob], language: .ja).isEmpty)
        // A publication race may deliver both the story job and its readable story.
        let publishing = BackendJob(id: UUID(), kind: "story", storyId: story.id, status: "running", request: story.generationRequest,
                                    sentenceIndex: nil, createdAt: story.createdAt, error: nil)
        precondition(LibraryEntry.make(stories: [model], jobs: [publishing, coverJob, audioJob], language: nil).count == 1)
        // Resource jobs arriving before the story list still group and respect language filters.
        let japanese = BackendGenerationRequest(StoryRequest(language: .ja, level: StoryLanguage.ja.levels[1], genre: .daily, length: .short, topic: "朝の弁当"))
        let japaneseID = UUID()
        let jaCover = BackendJob(id: UUID(), kind: "cover", storyId: japaneseID, status: "running", request: japanese,
                                 sentenceIndex: nil, createdAt: story.createdAt, error: nil)
        let jaAudio = BackendJob(id: UUID(), kind: "audio", storyId: japaneseID, status: "queued", request: japanese,
                                 sentenceIndex: nil, createdAt: story.createdAt, error: nil)
        precondition(LibraryEntry.make(stories: [], jobs: [jaCover, jaAudio], language: .en).isEmpty)
        let jaEntries = LibraryEntry.make(stories: [], jobs: [jaCover, jaAudio], language: .ja)
        precondition(jaEntries.count == 1 && jaEntries[0].jobs.count == 2 && jaEntries[0].request?.level == "N4")
        let cover = try await client.asset("cover", storyID: story.id, version: story.coverVersion!)
        precondition(Array(cover.prefix(2)) == [0xff, 0xd8])
        let output = URL(fileURLWithPath: environment["FABLO_TEST_OUTPUT"]!).appending(path: "native-audio.m4a")
        try await client.downloadAudio(storyID: story.id, version: story.audioVersion!, to: output)
        let audio = try Data(contentsOf: output)
        precondition(audio.count > 100)
        let analysis = try await client.analysis(for: story.id, sentence: 0)
        precondition(!analysis.structure.isEmpty)
        let request = StoryRequest(language: .en, level: StoryLanguage.en.levels[1], genre: .daily, length: .short, topic: "Native client")
        let key = UUID()
        let job = try await client.create(request, idempotencyKey: key)
        let duplicate = try await client.create(request, idempotencyKey: key)
        precondition(duplicate.id == job.id)
        _ = try await client.wait(for: job.id)
        let refreshed = try await client.stories()
        precondition(refreshed.contains { $0.id == job.storyId })
        try await client.delete(job.storyId)
        let remaining = try await client.stories()
        precondition(remaining.count == 1)
        print("Swift client contract and library grouping passed")
    }
}
