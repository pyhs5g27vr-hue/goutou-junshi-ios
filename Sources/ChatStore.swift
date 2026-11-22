import Foundation
import UIKit

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var streamingText: String = ""
    @Published private(set) var pendingDocs: [String] = []
    @Published var lastError: String?

    private var currentTask: Task<Void, Never>?
    private let fileURL: URL
    private let saveQueue = DispatchQueue(label: "goutou.chat.save", qos: .utility)

    /// 送给模型的上下文轮数上限
    private let contextWindow = 24

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("chat.json")
        load()
    }

    // MARK: - 发送

    func send(text: String, attachments: [Attachment]) {
        guard !isStreaming else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        guard Settings.shared.isConfigured else {
            lastError = "还没配置 API。点右上角齿轮，填一个地址和 Key 就能用了。"
            return
        }

        let userMsg = Message.user(trimmed, attachments: attachments)
        messages.append(userMsg)
        save()

        // 检索：文本为主，纯图片时用一句兜底查询
        let query = trimmed.isEmpty ? "聊天截图 截图分析 证据边界" : trimmed
        let hits = Knowledge.shared.search(query, limit: max(1, Settings.shared.topDocs))
        pendingDocs = hits.map(\.path)

        let system = Knowledge.shared.systemPrompt(for: hits)
        let wire = buildWire(system: system)
        let cfg = LLMClient.Config(
            baseURL: Settings.shared.baseURL,
            apiKey: Settings.shared.apiKey,
            model: Settings.shared.model,
            temperature: Settings.shared.temperature
        )

        isStreaming = true
        streamingText = ""
        lastError = nil

        currentTask = Task { [weak self] in
            guard let self else { return }
            var acc = ""
            do {
                for try await delta in LLMClient.shared.stream(wire, config: cfg) {
                    acc += delta
                    self.streamingText = acc
                }
                self.finish(acc)
            } catch {
                var cancelled = false
                if let e = error as? LLMClient.LLMError, case .cancelled = e {
                    cancelled = true
                }
                if !acc.isEmpty {
                    self.messages.append(Message.assistant(acc, docs: self.pendingDocs))
                }
                if !cancelled {
                    self.lastError = error.localizedDescription
                }
                self.streamingText = ""
                self.isStreaming = false
                self.save()
            }
        }
    }

    private func finish(_ text: String) {
        let final = Message.assistant(text, docs: pendingDocs)
        messages.append(final)
        streamingText = ""
        isStreaming = false
        save()
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - 会话管理

    func newChat() {
        stop()
        messages.removeAll()
        streamingText = ""
        pendingDocs = []
        lastError = nil
        save()
    }

    func delete(_ message: Message) {
        messages.removeAll { $0.id == message.id }
        save()
    }

    // MARK: - 组装请求

    private func buildWire(system: String) -> [WireMessage] {
        var wire: [WireMessage] = [WireMessage(role: "system", content: .text(system))]
        let recent = messages.suffix(contextWindow)
        for m in recent {
            switch m.role {
            case .user:
                wire.append(wireMessage(for: m))
            case .assistant:
                if m.failed { continue }
                wire.append(WireMessage(role: "assistant", content: .text(m.text)))
            }
        }
        return wire
    }

    private func wireMessage(for m: Message) -> WireMessage {
        let hasImage = m.attachments.contains { $0.kind == .image && $0.imageData != nil }
        let text = mergedText(for: m)
        if !hasImage {
            return WireMessage(role: "user", content: .text(text))
        }
        var parts: [WireMessage.Part] = []
        if !text.isEmpty { parts.append(.text(text)) }
        for a in m.attachments where a.kind == .image {
            if let data = a.imageData { parts.append(.image(data)) }
        }
        return WireMessage(role: "user", content: .parts(parts))
    }

    private func mergedText(for m: Message) -> String {
        var text = m.text
        for a in m.attachments where a.kind == .text {
            guard let body = a.text else { continue }
            let clipped = body.count > 20000 ? String(body.prefix(20000)) : body
            text += "\n\n【附件：\(a.name)】\n\(clipped)"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 持久化

    private func save() {
        let snapshot = messages
        let url = fileURL
        let queue = saveQueue
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            queue.async {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Message].self, from: data) {
            messages = decoded
        }
    }
}
