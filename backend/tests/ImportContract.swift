import AVFoundation
import Foundation
import ImageIO

/// Uses the production native client and audio cache against the import smoke server.
@main
struct ImportContract {
    @MainActor
    static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        let connection = try BackendConnection(address: env["FABLO_TEST_URL"]!, token: env["FABLO_TEST_TOKEN"]!)
        let cache = BackendCache(root: URL(fileURLWithPath: env["FABLO_TEST_OUTPUT"]!).appending(path: "native-cache"))
        let client = BackendClient(connection: connection, cache: cache)
        let records = try await client.stories()
        precondition(records.count == Int(env["FABLO_TEST_STORIES"]!)!)
        let language = StoryLanguage(rawValue: env["FABLO_TEST_LANGUAGE"] ?? "ja")!
        var covers = 0, audio = 0, sentenceCount = 0
        for record in records {
            precondition(record.language == language && record.generationRequest != nil && !record.titleZh.isEmpty)
            let detail = try await client.story(record.id)
            let model = Story(record: detail, client: client)
            let content = detail.content!
            precondition(!content.allSentences.isEmpty)
            sentenceCount += content.allSentences.count
            for sentence in content.allSentences {
                precondition(!sentence.sentence.zh.isEmpty)
                precondition(!sentence.sentence.chunks.flatMap(\.words).isEmpty)
            }
            if let version = detail.coverVersion {
                let data = try await client.asset("cover", storyID: detail.id, version: version)
                precondition(CGImageSourceCreateWithData(data as CFData, nil) != nil)
                covers += 1
            }
            if detail.audioVersion != nil {
                let (url, timeline) = try await StoryAudioStore().audio(for: StoryAudioSource(story: model, content: content))
                let player = try AVAudioPlayer(contentsOf: url)
                precondition(abs(player.duration - timeline.duration) < 0.1)
                precondition(!timeline.isAligned && timeline.wordStarts.count == content.allSentences.count)
                audio += 1
            }
        }
        precondition(audio == Int(env["FABLO_TEST_AUDIO_COUNT"]!)!)
        if let count = env["FABLO_TEST_COVER_COUNT"] { precondition(covers == Int(count)!) }
        let restored = await BackendCache(root: cache.root).library(for: connection)
        precondition(restored.count == records.count && restored.allSatisfy { $0.content != nil })
        print("Native import contract passed: \(records.count) \(language.rawValue) stories, \(sentenceCount) sentences, \(covers) covers, \(audio) playable AAC files with matching timelines")
    }
}
