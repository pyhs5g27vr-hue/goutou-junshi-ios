import SwiftUI
import UIKit

// MARK: - 轻量 Markdown 渲染
//
// 只做两件事：把 ``` 代码块抽出来单独排版（可复制），其余交给 AttributedString。
// 表格在窄屏塞不下，这里保持原文，靠等宽对齐也能看。

struct RichText: View {
    let text: String
    var isStreaming: Bool = false

    enum Segment {
        case prose(String)
        case code(String, String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments.indices, id: \.self) { index in
                self.segmentView(self.segments[index])
            }
            if isStreaming {
                BlinkingCursor()
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ seg: Segment) -> some View {
        switch seg {
        case .prose(let s):
            Text(attributed(s))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .code(let code, let lang):
            CodeBlock(code: code, language: lang)
        }
    }

    private var segments: [Segment] {
        guard text.contains("```") else {
            return [.prose(text)]
        }
        var out: [Segment] = []
        let parts = text.components(separatedBy: "```")
        for (i, part) in parts.enumerated() {
            if i % 2 == 0 {
                if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out.append(.prose(part))
                }
            } else {
                var body = part
                var lang = ""
                if let nl = part.firstIndex(of: "\n") {
                    lang = String(part[part.startIndex..<nl]).trimmingCharacters(in: .whitespaces)
                    body = String(part[part.index(after: nl)...])
                }
                out.append(.code(body, lang))
            }
        }
        return out.isEmpty ? [.prose(text)] : out
    }

    private func attributed(_ s: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        let base = (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
        return base
    }
}

struct CodeBlock: View {
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "代码" : language)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = self.code
                    withAnimation(.snappy) { self.copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(.snappy) { self.copied = false }
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
        }
    }
}

struct BlinkingCursor: View {
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 7, height: 15)
            .opacity(on ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    self.on = false
                }
            }
    }
}

// MARK: - 单条消息

struct MessageRow: View {
    let message: Message
    var isStreaming: Bool = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if !message.attachments.isEmpty {
                attachmentPreview
            }

            bubble

            if !isUser, Settings.shared.showDocChips, !message.docs.isEmpty {
                docChips
            }

            if !isUser, message.failed {
                Text("这一条没发成功")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    private var bubble: some View {
        Group {
            if isUser {
                Text(message.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                RichText(text: message.text, isStreaming: isStreaming)
            }
        }
        .font(.system(size: 15.5))
        .foregroundStyle(isUser ? Color.white : Color.primary)
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .frame(maxWidth: 320, alignment: .leading)
        .liquidGlass(
            RoundedRectangle(cornerRadius: 20, style: .continuous),
            tint: isUser ? .orange : nil
        )
    }

    private var attachmentPreview: some View {
        HStack(spacing: 6) {
            ForEach(message.attachments) { att in
                if att.kind == .image, let data = att.imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.6)
                        }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                        Text(att.name)
                            .lineLimit(1)
                        Text(att.sizeLabel)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .liquidGlass(.capsule)
                }
            }
        }
        .frame(maxWidth: 320, alignment: isUser ? .trailing : .leading)
    }

    private var docChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.docs, id: \.self) { path in
                    Text(self.shortName(path))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .liquidGlass(.capsule)
                }
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
        .padding(.leading, 2)
    }

    private func shortName(_ path: String) -> String {
        let file = path.split(separator: "/").last.map(String.init) ?? path
        return file
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: #"^\d+\-"#, with: "", options: .regularExpression)
    }
}
