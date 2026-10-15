import CryptoKit
import Foundation

/// Disposable copies of server data, isolated by server and credential.
actor BackendCache {
    static let shared = BackendCache()
    nonisolated let root: URL
    private var generations: [String: UUID] = [:]

    init(root: URL = URL.cachesDirectory.appending(path: "FabloServer/v1", directoryHint: .isDirectory)) {
        self.root = root
    }

    nonisolated static func namespace(for connection: BackendConnection) -> String {
        SHA256.hash(data: Data((connection.baseURL.absoluteString + "\n" + connection.token).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    nonisolated func directory(for connection: BackendConnection) -> URL {
        root.appending(path: Self.namespace(for: connection), directoryHint: .isDirectory)
    }

    private nonisolated func storyDirectory(_ id: UUID, for connection: BackendConnection) -> URL {
        directory(for: connection).appending(path: "stories/\(id.uuidString)", directoryHint: .isDirectory)
    }

    nonisolated func audioDirectory(_ id: UUID, version: String, for connection: BackendConnection) -> URL? {
        guard let version = UUID(uuidString: version) else { return nil }
        return storyDirectory(id, for: connection).appending(path: "audio/\(version.uuidString)", directoryHint: .isDirectory)
    }

    private nonisolated func assetURL(_ name: String, id: UUID, version: String, for connection: BackendConnection) -> URL? {
        guard let version = UUID(uuidString: version) else { return nil }
        switch name {
        case "cover": return storyDirectory(id, for: connection).appending(path: "covers/\(version.uuidString).jpg")
        case "timeline": return audioDirectory(id, version: version.uuidString, for: connection)?.appending(path: "timeline.json")
        default: return nil
        }
    }

    func generation(for connection: BackendConnection) -> UUID {
        let key = Self.namespace(for: connection)
        if let generation = generations[key] { return generation }
        let generation = UUID()
        generations[key] = generation
        return generation
    }

    func library(for connection: BackendConnection) -> [BackendStory] {
        let records: [BackendStory] = read(directory(for: connection).appending(path: "library.json")) ?? []
        return records.map { merging($0, previous: story($0.id, for: connection)) }
    }

    func story(_ id: UUID, for connection: BackendConnection) -> BackendStory? {
        let record: BackendStory? = read(storyDirectory(id, for: connection).appending(path: "record.json"))
        return record?.id == id ? record : nil
    }

    /// Only a complete, consistent server listing can replace the offline library.
    func saveLibrary(_ records: [BackendStory], for connection: BackendConnection, generation: UUID) -> Bool {
        guard generation == self.generation(for: connection) else { return false }
        let previous = library(for: connection)
        for record in records { write(merging(record, previous: story(record.id, for: connection)), to: storyDirectory(record.id, for: connection).appending(path: "record.json")) }
        write(records, to: directory(for: connection).appending(path: "library.json"))
        let ids = Set(records.map(\.id))
        let stories = directory(for: connection).appending(path: "stories", directoryHint: .isDirectory)
        var removedDirectory = false
        for child in (try? FileManager.default.contentsOfDirectory(at: stories, includingPropertiesForKeys: nil)) ?? [] {
            if let id = UUID(uuidString: child.lastPathComponent), !ids.contains(id) {
                removedDirectory = true
                try? FileManager.default.removeItem(at: child)
            }
        }
        if removedDirectory || previous.contains(where: { !ids.contains($0.id) }) { invalidate(for: connection) }
        return true
    }

    func saveStory(_ record: BackendStory, for connection: BackendConnection, generation: UUID) -> BackendStory? {
        guard generation == self.generation(for: connection) else { return nil }
        let merged = merging(record, previous: story(record.id, for: connection))
        write(merged, to: storyDirectory(record.id, for: connection).appending(path: "record.json"))
        return merged
    }

    func saveAnalysis(_ analysis: SentenceAnalysis, id: UUID, sentence: Int, for connection: BackendConnection, generation: UUID) {
        guard generation == self.generation(for: connection), var record = story(id, for: connection) else { return }
        var analyses = record.analyses ?? [:]
        analyses[String(sentence)] = analysis
        record.analyses = analyses
        write(record, to: storyDirectory(id, for: connection).appending(path: "record.json"))
    }

    func asset(_ name: String, id: UUID, version: String, for connection: BackendConnection) -> Data? {
        guard let url = assetURL(name, id: id, version: version, for: connection), let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }

    func saveAsset(_ data: Data, name: String, id: UUID, version: String, for connection: BackendConnection, generation: UUID) {
        guard generation == self.generation(for: connection), !data.isEmpty,
              let url = assetURL(name, id: id, version: version, for: connection) else { return }
        write(data, to: url)
    }

    func removeAsset(_ name: String, id: UUID, version: String, for connection: BackendConnection) {
        guard let url = assetURL(name, id: id, version: version, for: connection) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func publishAudio(from staging: URL, id: UUID, version: String, for connection: BackendConnection, generation: UUID) throws -> URL {
        guard generation == self.generation(for: connection) else { throw CancellationError() }
        guard let destination = audioDirectory(id, version: version, for: connection) else { throw BackendError.message("音频版本无效") }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination.appending(path: "audio.m4a")
    }

    func removeStory(_ id: UUID, for connection: BackendConnection) {
        invalidate(for: connection)
        let records = library(for: connection).filter { $0.id != id }
        write(records, to: directory(for: connection).appending(path: "library.json"))
        try? FileManager.default.removeItem(at: storyDirectory(id, for: connection))
    }

    func removeAll(for connection: BackendConnection) {
        invalidate(for: connection)
        try? FileManager.default.removeItem(at: directory(for: connection))
    }

    private func invalidate(for connection: BackendConnection) { generations[Self.namespace(for: connection)] = UUID() }

    private func merging(_ record: BackendStory, previous: BackendStory?) -> BackendStory {
        guard let previous, previous.id == record.id else { return record }
        // A slow detail response must not roll back newer resource metadata.
        var merged = record.updatedAt < previous.updatedAt ? previous : record
        let fallback = record.updatedAt < previous.updatedAt ? record : previous
        if merged.content == nil { merged.content = fallback.content }
        if merged.analyses == nil { merged.analyses = fallback.analyses }
        return merged
    }

    private func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        write(data, to: url)
    }

    private func write(_ data: Data, to url: URL) {
        // Cache failures never prevent displaying a successful server response.
        do {
            if (try? Data(contentsOf: url)) == data { return }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch { }
    }
}
