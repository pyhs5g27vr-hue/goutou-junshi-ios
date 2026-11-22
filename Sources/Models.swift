import Foundation

enum Role: String, Codable {
    case user
    case assistant
}

/// 一条可发送的附件：图片（截图）或文本（聊天导出）
struct Attachment: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case image, text }

    var id = UUID()
    var kind: Kind
    var name: String
    /// 图片：已压缩的 JPEG 数据。文本附件为 nil。
    var imageData: Data?
    /// 文本附件：正文。图片附件为 nil。
    var text: String?

    var byteSize: Int {
        imageData?.count ?? text?.utf8.count ?? 0
    }

    var sizeLabel: String {
        let b = byteSize
        if b < 1024 { return "\(b) B" }
        if b < 1024 * 1024 { return String(format: "%.0f KB", Double(b) / 1024) }
        return String(format: "%.1f MB", Double(b) / 1048576)
    }
}

struct Message: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: Role
    var text: String
    var attachments: [Attachment] = []
    /// 本轮命中的参考文档（相对路径），用于气泡下方展示
    var docs: [String] = []
    var ts = Date()
    /// 出错时记录，气泡用红色显示
    var failed: Bool = false
}

extension Message {
    static func user(_ text: String, attachments: [Attachment] = []) -> Message {
        Message(role: .user, text: text, attachments: attachments)
    }

    static func assistant(_ text: String, docs: [String] = []) -> Message {
        Message(role: .assistant, text: text, docs: docs)
    }
}
