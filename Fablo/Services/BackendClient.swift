import Foundation

enum BackendError: LocalizedError {
    case message(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        case .http(let status, let message): "请求失败（\(status)）：\(message)"
        }
    }

    var invalidatesConnection: Bool {
        if case .http(let status, _) = self { return status == 401 || status == 403 }
        return false
    }
}

struct BackendConnection: Sendable {
    let baseURL: URL
    let token: String

    init(address: String, token: String) throws {
        guard var components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.scheme == "https" || (components.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host))
        else { throw BackendError.message("请输入 HTTPS 服务地址；本地开发可使用 http://localhost:3000") }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty { components.path = "/" + components.path }
        guard let url = components.url else { throw BackendError.message("服务地址无效") }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw BackendError.message("请填写访问令牌") }
        baseURL = url
        self.token = token
    }
}

struct BackendGenerationRequest: Codable, Sendable {
    let language: StoryLanguage
    let level: String
    let genre: String
    let length: StoryLength
    let topic: String

    init(_ request: StoryRequest) {
        language = request.language
        level = request.level.name
        genre = request.genre.rawValue
        length = request.length
        topic = request.topic
    }

    var storyRequest: StoryRequest {
        StoryRequest(language: language,
                     level: language.levels.first { $0.name == level } ?? language.levels[0],
                     genre: StoryGenre(rawValue: genre) ?? .fable, length: length, topic: topic)
    }
}

struct BackendStory: Codable, Sendable {
    let id: UUID
    let createdAt: String
    let updatedAt: String
    let language: StoryLanguage
    let level: String
    let genre: String
    let title: String
    let titleZh: String
    let summaryZh: String
    let coverPrompt: String
    let coverStatus: String
    let audioStatus: String
    let coverVersion: String?
    let audioVersion: String?
    let generationRequest: BackendGenerationRequest?
    var readingStatus: ReadingStatus?
    var readingStatusRevision: Int?
    var content: StoryContent?
    var analyses: [String: SentenceAnalysis]?
}

struct BackendJob: Decodable, Identifiable, Sendable {
    let id: UUID
    let kind: String
    let storyId: UUID
    let status: String
    let request: BackendGenerationRequest?
    let sentenceIndex: Int?
    let createdAt: String
    let error: String?

    var isActive: Bool { status == "queued" || status == "running" }
}

struct BackendClient: Sendable {
    let connection: BackendConnection
    let cache: BackendCache

    init(connection: BackendConnection, cache: BackendCache = .shared) {
        self.connection = connection
        self.cache = cache
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         query: [URLQueryItem] = [], idempotencyKey: UUID? = nil) throws -> URLRequest {
        var components = URLComponents(url: connection.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw BackendError.message("服务地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let idempotencyKey { request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key") }
        return request
    }

    private func check(_ response: URLResponse, data: Data = Data()) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct Failure: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error.message ?? "服务暂时不可用"
            throw BackendError.http(status, message)
        }
    }

    private func data(_ path: String, method: String = "GET", body: Data? = nil,
                      query: [URLQueryItem] = [], idempotencyKey: UUID? = nil) async throws -> Data {
        let request = try request(path, method: method, body: body, query: query, idempotencyKey: idempotencyKey)
        let (data, response) = try await Self.session.data(for: request)
        try await checkResponse(response, data: data)
        return data
    }

    private func checkResponse(_ response: URLResponse, data: Data = Data()) async throws {
        do { try check(response, data: data) }
        catch {
            if (error as? BackendError)?.invalidatesConnection == true { await cache.removeAll(for: connection) }
            throw error
        }
    }

    func cachedStories() async -> [BackendStory] { await cache.library(for: connection) }
    func cachedStory(_ id: UUID) async -> BackendStory? { await cache.story(id, for: connection) }

    func stories() async throws -> [BackendStory] {
        struct Page: Decodable { let stories: [BackendStory]; let revision: Int; let nextCursor: String? }
        let generation = await cache.generation(for: connection)
        // Retry a changing snapshot instead of removing records from a partial list.
        for _ in 0..<3 {
            var records: [BackendStory] = [], cursor: String?, revision: Int?
            var seenCursors: Set<String> = [], changed = false
            repeat {
                try Task.checkCancellation()
                var query = [URLQueryItem(name: "limit", value: "100")]
                if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
                let page = try JSONDecoder().decode(Page.self, from: await data("v1/stories", query: query))
                if let revision, revision != page.revision { changed = true; break }
                revision = page.revision
                records += page.stories
                cursor = page.nextCursor
                if let cursor, !seenCursors.insert(cursor).inserted { throw BackendError.message("服务返回的分页无效") }
            } while cursor != nil
            if !changed {
                try Task.checkCancellation()
                guard await cache.saveLibrary(records, for: connection, generation: generation) else { throw CancellationError() }
                return records
            }
        }
        throw BackendError.message("书库正在更新，请稍后重试")
    }

    func jobs() async throws -> [BackendJob] {
        struct Result: Decodable { let jobs: [BackendJob] }
        return try JSONDecoder().decode(Result.self, from: await data("v1/jobs")).jobs
    }

    func setReadingStatus(_ status: ReadingStatus, for id: UUID) async throws -> BackendStory {
        struct Update: Encodable { let status: ReadingStatus }
        let generation = await cache.generation(for: connection)
        let record = try JSONDecoder().decode(BackendStory.self, from: await data("v1/stories/\(id.uuidString)/reading-status",
            method: "POST", body: JSONEncoder().encode(Update(status: status))))
        try Task.checkCancellation()
        guard let saved = await cache.saveStory(record, for: connection, generation: generation) else { throw CancellationError() }
        return saved
    }

    func create(_ request: StoryRequest, idempotencyKey: UUID) async throws -> BackendJob {
        try JSONDecoder().decode(BackendJob.self, from: await data("v1/generations", method: "POST",
            body: JSONEncoder().encode(BackendGenerationRequest(request)), idempotencyKey: idempotencyKey))
    }

    func story(_ id: UUID, statusOnly: Bool = false) async throws -> BackendStory {
        let generation = await cache.generation(for: connection)
        do {
            let record = try JSONDecoder().decode(BackendStory.self, from: await data("v1/stories/\(id.uuidString)\(statusOnly ? "/status" : "")"))
            try Task.checkCancellation()
            guard let saved = await cache.saveStory(record, for: connection, generation: generation) else { throw CancellationError() }
            return saved
        } catch {
            if case BackendError.http(404, _) = error { await cache.removeStory(id, for: connection) }
            throw error
        }
    }

    func wait(for id: UUID) async throws -> BackendJob {
        for _ in 0..<900 {
            try Task.checkCancellation()
            let job = try JSONDecoder().decode(BackendJob.self, from: await data("v1/jobs/\(id.uuidString)"))
            if job.status == "completed" { return job }
            if job.status == "failed" { throw BackendError.message(job.error ?? "生成失败，请重试") }
            try await Task.sleep(for: .seconds(2))
        }
        throw BackendError.message("任务仍在服务端处理，稍后可重新查看")
    }

    func retry(_ id: UUID) async throws { _ = try await data("v1/jobs/\(id.uuidString)/retry", method: "POST") }
    func dismiss(_ id: UUID) async throws { _ = try await data("v1/jobs/\(id.uuidString)", method: "DELETE") }
    func delete(_ id: UUID) async throws {
        _ = try await data("v1/stories/\(id.uuidString)", method: "DELETE")
        await cache.removeStory(id, for: connection)
    }
    func regenerate(_ kind: String, for id: UUID) async throws { _ = try await data("v1/stories/\(id.uuidString)/\(kind)", method: "POST") }

    func analysis(for storyID: UUID, sentence: Int) async throws -> SentenceAnalysis {
        if let cached = await cachedStory(storyID)?.analyses?[String(sentence)] { return cached }
        let generation = await cache.generation(for: connection)
        struct Result: Decodable { let analysis: SentenceAnalysis?; let job: BackendJob? }
        let path = "v1/stories/\(storyID.uuidString)/analyses/\(sentence)"
        let result = try JSONDecoder().decode(Result.self, from: await data(path, method: "POST"))
        if let analysis = result.analysis {
            await cache.saveAnalysis(analysis, id: storyID, sentence: sentence, for: connection, generation: generation)
            return analysis
        }
        guard let job = result.job else { throw BackendError.message("服务没有返回解析任务") }
        _ = try await wait(for: job.id)
        let refreshed = try await story(storyID)
        guard let analysis = refreshed.analyses?[String(sentence)] else { throw BackendError.message("无法读取句子解析") }
        return analysis
    }

    func asset(_ name: String, storyID: UUID, version: String) async throws -> Data {
        if let cached = await cache.asset(name, id: storyID, version: version, for: connection) { return cached }
        let generation = await cache.generation(for: connection)
        let result = try await data("v1/stories/\(storyID.uuidString)/assets/\(name)", query: [URLQueryItem(name: "version", value: version)])
        try Task.checkCancellation()
        await cache.saveAsset(result, name: name, id: storyID, version: version, for: connection, generation: generation)
        return result
    }

    func downloadAudio(storyID: UUID, version: String, to destination: URL) async throws {
        let request = try request("v1/stories/\(storyID.uuidString)/assets/audio", query: [URLQueryItem(name: "version", value: version)])
        let (temporary, response) = try await Self.session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            try await checkResponse(response, data: (try? Data(contentsOf: temporary)) ?? Data())
        }
        try await checkResponse(response)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
