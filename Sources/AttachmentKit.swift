import Foundation
import UIKit
import UniformTypeIdentifiers

/// 图片压缩 + 文本文件读取
enum AttachmentKit {

    /// 长边压到 maxSide，JPEG 质量 quality。聊天截图 1179×2556 压完大约 150–250 KB，
    /// 既能看清气泡文字，又不至于把上下文撑爆。
    static func makeImage(from data: Data, name: String = "截图",
                          maxSide: CGFloat = 1280, quality: CGFloat = 0.72) -> Attachment? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = resize(image, maxSide: maxSide)
        guard let jpeg = resized.jpegData(compressionQuality: quality) else { return nil }
        return Attachment(kind: .image, name: name, imageData: jpeg, text: nil)
    }

    static func resize(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// 读取用户选中的文本文件（聊天导出、粘贴记录等）
    static func makeText(from url: URL) -> Attachment? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? Data(contentsOf: url) else { return nil }
        let name = url.lastPathComponent

        // 文本类直接按 UTF-8，失败再试 GB18030（很多安卓导出的聊天记录是这个编码）
        if let s = decodeUTF8(raw) {
            return Attachment(kind: .text, name: name, imageData: nil, text: clip(s))
        }
        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let s = String(data: raw, encoding: String.Encoding(rawValue: gb)) {
            return Attachment(kind: .text, name: name, imageData: nil, text: clip(s))
        }
        return nil
    }

    private static func decodeUTF8(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }

    private static func clip(_ s: String) -> String {
        s.count > 120_000 ? String(s.prefix(120_000)) : s
    }

    /// 可读的文本类型
    static var readableTextTypes: [UTType] {
        var t: [UTType] = [.plainText, .utf8PlainText, .text, .json, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") { t.append(markdown) }
        return t
    }
}
