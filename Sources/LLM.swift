import Foundation

// MARK: - 线上协议（OpenAI 兼容）

struct WireMessage: Encodable {
    let role: String
    let content: Content

    enum Content: Encodable {
        case text(String)
        case parts([Part])

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .text(let s):
                try c.encode(s)
            case .parts(let p):
                try c.encode(p)
            }
        }
    }

    struct Part: Encodable {
        let type: String
        var text: String?
        var image_url: ImageURL?

        struct ImageURL: Encodable { let url: String }

        static func text(_ s: String) -> Part {
            Part(type: "text", text: s, image_url: nil)
        }

        static func image(_ data: Data) -> Part {
            Part(type: "image_url", text: nil,
                 image_url: ImageURL(url: "data:image/jpeg;base64,\(data.base64EncodedString())"))
        }
    }
}

private struct ChatBody: Encodable {
    let model: String
    let messages: [WireMessage]
    let temperature: Double
    let stream: Bool
}

// MARK: - 客户端

final class LLMClient {
    static let shared = LLMClient()

    struct Config {
        var baseURL: String
        var apiKey: String
        var model: String
        var temperature: Double
    }

    enum LLMError: LocalizedError {
        case badURL(String)
        case http(Int, String)
        case empty
        case cancelled

        var errorDescription: String? {
            switch self {
            case .badURL(let s): return "API 地址不合法：\(s)"
            case .http(let code, let body):
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                let shown = trimmed.count > 400 ? String(trimmed.prefix(400)) + "…" : trimmed
                return "HTTP \(code)\n\(shown)"
            case .empty: return "模型没有返回内容"
            case .cancelled: return "已取消"
            }
        }
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 180
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    func stream(_ messages: [WireMessage], config: Config) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(messages, config: config) { delta in
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 核心

    private func run(_ messages: [WireMessage],
                     config: Config,
                     onDelta: @escaping (String) -> Void) async throws {

        let endpoint = Self.endpoint(from: config.baseURL)
        guard let url = URL(string: endpoint) else { throw LLMError.badURL(endpoint) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        // OpenRouter 等网关要求来源标识
        req.setValue("https://github.com/goutoujunshi-ios", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Goutoujunshi iOS", forHTTPHeaderField: "X-Title")

        let body = ChatBody(
            model: config.model,
            messages: messages,
            temperature: config.temperature,
            stream: true
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw LLMError.empty }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""

        if http.statusCode >= 400 {
            var raw = Data()
            for try await b in bytes {
                raw.append(b)
                if raw.count > 8000 { break }
            }
            let text = String(data: raw, encoding: .utf8) ?? ""
            throw LLMError.http(http.statusCode, text)
        }

        if contentType.contains("event-stream") || contentType.contains("stream") {
            try await consumeSSE(bytes, onDelta: onDelta)
        } else {
            // 少数后端忽略 stream 参数，直接回整块 JSON
            try await consumeWholeJSON(bytes, onDelta: onDelta)
        }
    }

    private func consumeSSE(_ bytes: URLSession.AsyncBytes,
                            onDelta: @escaping (String) -> Void) async throws {
        var produced = false
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { break }
            guard
                let data = payload.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = obj["choices"] as? [[String: Any]],
                let first = choices.first
            else { continue }

            var chunk = ""
            if let delta = first["delta"] as? [String: Any] {
                if let c = delta["content"] as? String { chunk += c }
            }
            if let message = first["message"] as? [String: Any],
               let c = message["content"] as? String {
                chunk += c
            }
            if !chunk.isEmpty {
                produced = true
                onDelta(chunk)
            }
        }
        if !produced { throw LLMError.empty }
    }

    private func consumeWholeJSON(_ bytes: URLSession.AsyncBytes,
                                  onDelta: @escaping (String) -> Void) async throws {
        var raw = Data()
        for try await b in bytes {
            raw.append(b)
            if raw.count > 8_000_000 { break }
        }
        guard
            let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let text = message["content"] as? String,
            !text.isEmpty
        else {
            let body = String(data: raw, encoding: .utf8) ?? ""
            throw LLMError.http(200, body.isEmpty ? "响应无法解析" : String(body.prefix(600)))
        }
        onDelta(text)
    }

    // MARK: - URL 拼接

    static func endpoint(from base: String) -> String {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "https://api.deepseek.com/v1" }
        if s.hasSuffix("/chat/completions") { return s }
        while s.hasSuffix("/") { s.removeLast() }
        return s + "/chat/completions"
    }
}
