import Foundation

/// Each phase runs in a fresh process against the same temporary disk cache.
@main
struct CacheContract {
    @MainActor
    static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        let connection = try BackendConnection(address: env["FABLO_TEST_URL"]!, token: env["FABLO_TEST_TOKEN"]!)
        let cache = BackendCache(root: URL(fileURLWithPath: env["FABLO_TEST_CACHE"]!))
        let studio = StoryStudio(cache: cache)
        await studio.connect(connection)
        let client = studio.client!
        let id = UUID(uuidString: env["FABLO_TEST_STORY"]!)!
        let phase = env["FABLO_TEST_PHASE"]!

        switch phase {
        case "populate":
            precondition(studio.stories.isEmpty)
            await studio.refresh()
            guard let story = studio.stories.first else { fatalError(studio.errorMessage ?? "Missing server story") }
            story.apply(try await client.story(id))
            precondition(story.decodedContent()?.allSentences.count == 2)
            try await verifyAssets(story)
            let analysis = try await client.analysis(for: id, sentence: 0)
            precondition(!analysis.structure.isEmpty)
            // A summary-only poll must preserve the downloaded text and analysis.
            await studio.refresh()
            let reopened = BackendCache(root: cache.root)
            let records = await reopened.library(for: connection)
            precondition(records.count == 1 && records[0].content?.allSentences.count == 2)
            precondition(records[0].analyses?["0"]?.structure == analysis.structure)
            let otherToken = try BackendConnection(address: connection.baseURL.absoluteString, token: "different-token")
            let otherServer = try BackendConnection(address: connection.baseURL.absoluteString + "/other", token: connection.token)
            let tokenLibrary = await reopened.library(for: otherToken)
            let serverLibrary = await reopened.library(for: otherServer)
            precondition(tokenLibrary.isEmpty && serverLibrary.isEmpty)

        case "offline":
            precondition(studio.stories.count == 1 && studio.isShowingCachedLibrary)
            let story = studio.stories[0]
            precondition(story.decodedContent()?.allSentences.count == 2)
            precondition(story.analysis(for: 0) != nil)
            // The mock server is stopped. Any status/download request would fail.
            try await verifyAssets(story)
            let analysis = try await client.analysis(for: id, sentence: 0)
            precondition(!analysis.structure.isEmpty)
            await studio.refresh()
            precondition(studio.stories.count == 1 && studio.isShowingCachedLibrary)
            precondition(studio.errorMessage?.contains("缓存") == true)

        case "versions":
            precondition(studio.stories.count == 1 && studio.stories[0].title == "A Good Morning")
            let oldCover = studio.stories[0].coverVersion
            let oldAudio = studio.stories[0].audioVersion
            await studio.refresh()
            precondition(studio.errorMessage == nil && !studio.isShowingCachedLibrary)
            let story = studio.stories[0]
            precondition(story.coverVersion != oldCover && story.audioVersion != oldAudio)
            story.apply(try await client.story(id))
            precondition(story.title == "Updated Morning" && story.decodedContent()?.title == "Updated Morning")
            try await verifyAssets(story)

        case "corruption":
            precondition(studio.stories.count == 1)
            let libraryURL = cache.directory(for: connection).appending(path: "library.json")
            try Data("invalid JSON".utf8).write(to: libraryURL)
            let brokenLibrary = await client.cachedStories()
            precondition(brokenLibrary.isEmpty)
            await studio.refresh()
            precondition(studio.stories.count == 1)
            let recordURL = cache.directory(for: connection).appending(path: "stories/\(id.uuidString)/record.json")
            try Data("invalid JSON".utf8).write(to: recordURL)
            let brokenStory = await client.cachedStory(id)
            precondition(brokenStory == nil)
            let story = studio.stories[0]
            story.apply(try await client.story(id))
            let audioDirectory = cache.audioDirectory(id, version: story.audioVersion!, for: connection)!
            try Data("invalid timeline".utf8).write(to: audioDirectory.appending(path: "timeline.json"))
            try await verifyAssets(story)

        case "authorization":
            let records = await client.cachedStories()
            precondition(records.count == 1)
            let expired = try BackendConnection(address: connection.baseURL.absoluteString, token: "expired-token")
            let generation = await cache.generation(for: expired)
            _ = await cache.saveLibrary(records, for: expired, generation: generation)
            let unauthorized = StoryStudio(cache: cache)
            await unauthorized.connect(expired)
            precondition(unauthorized.stories.count == 1)
            await unauthorized.refresh()
            precondition(unauthorized.stories.isEmpty && !unauthorized.isShowingCachedLibrary)
            let cleared = await cache.library(for: expired)
            let unaffected = await cache.library(for: connection)
            precondition(cleared.isEmpty && unaffected.count == 1)
            // A response that started before invalidation cannot recreate that cache.
            let stale = await cache.saveLibrary(records, for: expired, generation: generation)
            precondition(!stale)

        case "deletion":
            precondition(studio.stories.count == 1)
            let previous = await client.cachedStories()
            let generation = await cache.generation(for: connection)
            // Directory cleanup must also fence stale responses if the index is lost.
            try Data("invalid index".utf8).write(to: cache.directory(for: connection).appending(path: "library.json"))
            await studio.refresh()
            precondition(studio.errorMessage == nil && studio.stories.isEmpty)
            let library = await client.cachedStories()
            let detail = await client.cachedStory(id)
            precondition(library.isEmpty && detail == nil)
            let directory = cache.directory(for: connection).appending(path: "stories/\(id.uuidString)")
            precondition(!FileManager.default.fileExists(atPath: directory.path))
            let staleLibrary = await cache.saveLibrary(previous, for: connection, generation: generation)
            let staleDetail = await cache.saveStory(previous[0], for: connection, generation: generation)
            precondition(!staleLibrary && staleDetail == nil)

        default: fatalError("Unknown cache test phase")
        }
        print("Cache contract passed: \(phase)")
    }

    static func verifyAssets(_ story: Story) async throws {
        let cover = try await story.client.asset("cover", storyID: story.id, version: story.coverVersion!)
        precondition(cover.count > 4 && Array(cover.prefix(4)) == [137, 80, 78, 71])
        let secondCover = try await story.client.asset("cover", storyID: story.id, version: story.coverVersion!)
        precondition(secondCover == cover)
        let source = StoryAudioSource(story: story, content: story.decodedContent()!)
        let (url, timeline) = try await StoryAudioStore().audio(for: source)
        precondition(timeline.wordStarts.count == 2 && timeline.duration == 1)
        let audio = try Data(contentsOf: url)
        precondition(audio.count > 100 && String(data: audio.prefix(4), encoding: .utf8) == "RIFF")
        let (secondURL, _) = try await StoryAudioStore().audio(for: source)
        precondition(secondURL == url)
    }
}
