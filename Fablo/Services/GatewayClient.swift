import Foundation

enum GatewayError: LocalizedError {
    case http(Int, String)
    case emptyResponse
    case badPayload(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let message): "请求失败（\(code)）：\(message)"
        case .emptyResponse: "AI 没有返回内容"
        case .badPayload(let detail): "无法解析 AI 返回的数据：\(detail)"
        }
    }
}

/// Thin client for Vercel AI Gateway: chat completions, image generation and speech.
struct GatewayClient: Sendable {
    static let shared = GatewayClient()

    enum Model {
        static let text = "google/gemini-3.8-flash"
        static let image = "openai/gpt-image-2.5-sunburst"
        static let speech = "google/gemini-3.8-flash-tts"
        /// Gemini 3.5 Transcribe returns no timestamps; MAI-Transcribe 2 gives per-word
        /// (English) or per-character (Japanese) timings.
        static let transcription = "microsoft/mai-transcribe-2"
    }

    private let base = URL(string: "https://ai-gateway.vercel.sh")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    // MARK: Chat with structured output

    func structured<T: Decodable>(
        _ type: T.Type,
        system: String,
        user: String,
        schemaName: String,
        schema: [String: Any]
    ) async throws -> T {
        let body: [String: Any] = [
            "model": Model.text,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "strict": true, "schema": schema],
            ],
            "reasoning": ["effort": "low"],
        ]
        let data = try await post("/v1/chat/completions", body: body)

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard var content = response.choices.first?.message.content, !content.isEmpty else {
            throw GatewayError.emptyResponse
        }
        // Some providers still wrap JSON in a code fence.
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.hasPrefix("```") {
            content = content
                .replacingOccurrences(of: "^```(json)?", with: "", options: .regularExpression)
                .replacingOccurrences(of: "```$", with: "", options: .regularExpression)
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(content.utf8))
        } catch {
            throw GatewayError.badPayload(error.localizedDescription)
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    // MARK: Image

    func image(prompt: String, size: String = "1536x1024") async throws -> Data {
        let body: [String: Any] = [
            "model": Model.image,
            "prompt": prompt,
            "n": 1,
            "size": size,
            "quality": "medium",
        ]
        let data = try await post("/v1/images/generations", body: body)

        struct Response: Decodable {
            struct Item: Decodable { let b64_json: String?; let url: String? }
            let data: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let item = response.data.first else { throw GatewayError.emptyResponse }
        if let b64 = item.b64_json, let image = Data(base64Encoded: b64) {
            return image
        }
        if let urlString = item.url, let url = URL(string: urlString) {
            return try await session.data(from: url).0
        }
        throw GatewayError.emptyResponse
    }

    // MARK: Speech (returns WAV data)

    func speech(text: String, voice: String, instructions: String) async throws -> Data {
        let body: [String: Any] = [
            "text": text,
            "voice": voice,
            "outputFormat": "wav",
            "instructions": instructions,
        ]
        let headers = [
            "ai-gateway-protocol-version": "0.0.1",
            "ai-speech-model-specification-version": "4",
            "ai-model-id": Model.speech,
        ]
        let data = try await post("/v4/ai/speech-model", body: body, headers: headers)

        struct Response: Decodable { let audio: String }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let audio = Data(base64Encoded: response.audio) else { throw GatewayError.emptyResponse }
        return audio
    }

    // MARK: Transcription with word timings

    struct TimedWord: Decodable {
        let text: String
        let offsetMilliseconds: Double
        let durationMilliseconds: Double
    }

    func transcribeWords(wav: Data) async throws -> [TimedWord] {
        let body: [String: Any] = [
            "audio": wav.base64EncodedString(),
            "mediaType": "audio/wav",
            "providerOptions": ["azure": ["timestamps": "word", "transcribeStyle": "verbatim"]],
        ]
        let headers = [
            "ai-gateway-protocol-version": "0.0.1",
            "ai-transcription-model-specification-version": "4",
            "ai-model-id": Model.transcription,
        ]
        let data = try await post("/v4/ai/transcription-model", body: body, headers: headers)

        struct Response: Decodable {
            struct Metadata: Decodable {
                struct Azure: Decodable {
                    struct Phrase: Decodable { let words: [TimedWord]? }
                    let phrases: [Phrase]?
                }
                let azure: Azure?
            }
            let providerMetadata: Metadata?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let words = response.providerMetadata?.azure?.phrases?.flatMap { $0.words ?? [] } ?? []
        guard !words.isEmpty else { throw GatewayError.emptyResponse }
        return words
    }

    // MARK: Transport

    private func post(_ path: String, body: [String: Any], headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.aiGatewayKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct ErrorBody: Decodable {
                struct Inner: Decodable { let message: String? }
                let error: Inner?
            }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw GatewayError.http(status, message)
        }
        return data
    }
}
