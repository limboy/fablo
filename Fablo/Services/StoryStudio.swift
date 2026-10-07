import Foundation
import Observation
import SwiftData
import UIKit

/// Tracks in-flight story and cover generations so the library can show progress.
@MainActor
@Observable
final class StoryStudio {
    struct Job: Identifiable {
        let id = UUID()
        let request: StoryRequest
        let startedAt = Date()
        var error: String?
    }

    private(set) var jobs: [Job] = []
    private(set) var coversInProgress: Set<UUID> = []

    func start(_ request: StoryRequest, in context: ModelContext) {
        let job = Job(request: request)
        jobs.insert(job, at: 0)
        run(job.id, context: context)
    }

    func retry(_ jobID: UUID, in context: ModelContext) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].error = nil
        run(jobID, context: context)
    }

    func dismiss(_ jobID: UUID) {
        jobs.removeAll { $0.id == jobID }
    }

    private func run(_ jobID: UUID, context: ModelContext) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        Task {
            do {
                let content = try await StoryGenerator.generate(job.request, avoiding: existingStories(in: context))
                let story = try Story(content: content, request: job.request)
                context.insert(story)
                try? context.save()
                jobs.removeAll { $0.id == jobID }
                generateCover(for: story, in: context)
            } catch {
                if let index = jobs.firstIndex(where: { $0.id == jobID }) {
                    jobs[index].error = error.localizedDescription
                }
            }
        }
    }

    /// Titles and summaries are stored with each story, so this reads them locally — no extra AI call.
    private func existingStories(in context: ModelContext) -> [String] {
        let stories = (try? context.fetch(FetchDescriptor<Story>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return stories.map { "\($0.title)（\($0.titleZh)）：\($0.summaryZh)" }
    }

    func generateCover(for story: Story, in context: ModelContext) {
        guard !coversInProgress.contains(story.id) else { return }
        coversInProgress.insert(story.id)
        story.coverFailed = false
        let prompt = StoryGenerator.coverPrompt(for: story.coverPrompt)
        Task {
            defer { coversInProgress.remove(story.id) }
            do {
                let data = try await GatewayClient.shared.image(prompt: prompt)
                story.coverData = await Task.detached { Self.compress(data) }.value
            } catch {
                story.coverFailed = true
            }
            try? context.save()
        }
    }

    /// The gateway returns large PNGs; store a JPEG sized for the screen.
    nonisolated private static func compress(_ data: Data, maxWidth: CGFloat = 1200) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let scale = min(1, maxWidth / image.size.width)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82) ?? data
    }
}
