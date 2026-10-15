import Foundation
import Observation

/// Presents the server library and observes durable generation jobs.
@MainActor
@Observable
final class StoryStudio {
    private(set) var client: BackendClient?
    private(set) var stories: [Story] = []
    private(set) var jobs: [BackendJob] = []
    private(set) var isShowingCachedLibrary = false
    private(set) var connectionID = UUID()
    private let cache: BackendCache
    private var refreshingFor: UUID?
    var errorMessage: String?
    private var connectionVersion = UUID()

    init(cache: BackendCache = .shared) { self.cache = cache }

    var isConfigured: Bool { client != nil }
    var isRefreshing: Bool { refreshingFor == connectionVersion }
    var coversInProgress: Set<UUID> { Set(stories.filter { ["queued", "running"].contains($0.coverStatus) }.map(\.id)) }

    func loadConnection() async {
        guard client == nil else { return }
        do {
            if let connection = try await BackendCredentials.shared.load() { await connect(connection) }
        } catch { errorMessage = error.localizedDescription }
    }

    func connect(_ connection: BackendConnection) async {
        connectionVersion = UUID()
        connectionID = connectionVersion
        let version = connectionVersion
        let client = BackendClient(connection: connection, cache: cache)
        self.client = client
        stories = []
        jobs = []
        errorMessage = nil
        isShowingCachedLibrary = false
        let cached = await client.cachedStories()
        guard version == connectionVersion else { return }
        stories = cached.map { Story(record: $0, client: client) }
        isShowingCachedLibrary = !cached.isEmpty
    }

    func observe() async {
        await loadConnection()
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: .seconds(jobs.contains { $0.isActive } ? 2 : 10)) }
            catch { return }
        }
    }

    func refresh() async {
        guard let client, !isRefreshing else { return }
        let version = connectionVersion
        refreshingFor = version
        defer { if refreshingFor == version { refreshingFor = nil } }
        do {
            async let records = client.stories()
            async let pending = client.jobs()
            let (remote, jobs) = try await (records, pending)
            guard version == connectionVersion else { return }
            let existing = Dictionary(uniqueKeysWithValues: stories.map { ($0.id, $0) })
            stories = remote.map { record in
                if let story = existing[record.id] { story.apply(record); return story }
                return Story(record: record, client: client)
            }
            self.jobs = jobs
            isShowingCachedLibrary = false
            errorMessage = nil
        } catch {
            guard version == connectionVersion, !Task.isCancelled, !(error is CancellationError) else { return }
            if (error as? BackendError)?.invalidatesConnection == true {
                rejectConnection(error)
            } else {
                isShowingCachedLibrary = !stories.isEmpty
                errorMessage = stories.isEmpty ? error.localizedDescription : "暂时无法同步，正在显示已缓存的内容。"
            }
        }
    }

    func start(_ request: StoryRequest, idempotencyKey: UUID) async throws {
        guard let client else { throw BackendError.message("请先连接后端服务") }
        let version = connectionVersion
        let accepted = try await client.create(request, idempotencyKey: idempotencyKey)
        if version == connectionVersion, accepted.isActive, !jobs.contains(where: { $0.id == accepted.id }) {
            jobs.insert(accepted, at: 0)
        }
        await refresh()
    }

    func retry(_ id: UUID) { perform { try await $0.retry(id) } }
    func dismiss(_ id: UUID) { perform { try await $0.dismiss(id) } }
    func generateCover(for story: Story) { perform { try await $0.regenerate("cover", for: story.id) } }
    func generateAudio(for story: Story) { perform { try await $0.regenerate("audio", for: story.id) } }
    func delete(_ story: Story) {
        guard let client else { return }
        let version = connectionVersion
        Task {
            do {
                try await client.delete(story.id)
                guard version == connectionVersion else { return }
                removeMissingStory(story.id)
                await refresh()
            } catch {
                guard version == connectionVersion else { return }
                if (error as? BackendError)?.invalidatesConnection == true { rejectConnection(error) }
                else { errorMessage = error.localizedDescription }
            }
        }
    }

    func removeMissingStory(_ id: UUID) {
        connectionVersion = UUID()
        stories.removeAll { $0.id == id }
        jobs.removeAll { $0.storyId == id }
    }

    func rejectConnection(_ error: Error) {
        connectionVersion = UUID()
        stories = []
        jobs = []
        isShowingCachedLibrary = false
        errorMessage = error.localizedDescription
    }

    private func perform(_ action: @escaping (BackendClient) async throws -> Void) {
        guard let client else { return }
        let version = connectionVersion
        Task {
            do { try await action(client); await refresh() }
            catch {
                guard version == connectionVersion else { return }
                if (error as? BackendError)?.invalidatesConnection == true { rejectConnection(error) }
                else { errorMessage = error.localizedDescription }
            }
        }
    }
}
