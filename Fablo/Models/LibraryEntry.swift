import Foundation

/// One library card per story, including its pending generation and resource jobs.
struct LibraryEntry: Identifiable {
    let id: UUID
    let story: Story?
    let jobs: [BackendJob]

    var request: BackendGenerationRequest? {
        story?.generationRequest ?? jobs.first { $0.kind == "story" }?.request ?? jobs.compactMap(\.request).first
    }
    var language: StoryLanguage? { story?.language ?? request?.language }
    private var createdAt: Date { story?.createdAt ?? jobs.map { Story.date($0.createdAt) }.min() ?? .distantPast }

    static func make(stories: [Story], jobs: [BackendJob], language: StoryLanguage?) -> [LibraryEntry] {
        let grouped = Dictionary(grouping: jobs, by: \.storyId)
        let knownIDs = Set(stories.map(\.id))
        var entries = stories.map { story in
            let tasks = (grouped[story.id] ?? []).filter { job in
                if job.isActive { return true }
                if job.kind == "cover" { return story.coverStatus == "failed" }
                if job.kind == "audio" { return story.audioStatus == "failed" }
                return true
            }
            return LibraryEntry(id: story.id, story: story, jobs: ordered(tasks))
        }
        for (id, tasks) in grouped where !knownIDs.contains(id) {
            entries.append(LibraryEntry(id: id, story: nil, jobs: ordered(tasks)))
        }
        return entries.filter { language == nil || $0.language == language }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func ordered(_ jobs: [BackendJob]) -> [BackendJob] {
        let order = ["story": 0, "cover": 1, "audio": 2, "analysis": 3]
        return jobs.sorted {
            if order[$0.kind] != order[$1.kind] { return (order[$0.kind] ?? 4) < (order[$1.kind] ?? 4) }
            return $0.createdAt < $1.createdAt
        }
    }
}
