import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @ObservedObject private var settings = Settings.shared

    @State private var draft = ""
    @State private var pending: [Attachment] = []
    @State private var showSettings = false

    private var accent: Color { settings.accent.color }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(accent: accent)
                conversation
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("狗头军师")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .alert("出错了", isPresented: Binding(
                get: { self.store.lastError != nil },
                set: { if !$0 { self.store.lastError = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(self.store.lastError ?? "")
            }
        }
        .tint(accent)
    }

    // MARK: - 会话区

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if !settings.isConfigured {
                        setupHint
                    }

                    if store.messages.isEmpty && !store.isStreaming {
                        EmptyStateView(accent: accent) { template in
                            self.draft = template
                        }
                        .padding(.top, 12)
                    }

                    ForEach(store.messages) { message in
                        MessageRow(message: message, accent: accent)
                            .id(message.id)
                    }

                    if store.isStreaming {
                        MessageRow(
                            message: Message(
                                role: .assistant,
                                text: store.streamingText,
                                docs: store.pendingDocs
                            ),
                            accent: accent,
                            isStreaming: true
                        )
                        .id("streaming")
                    }

                    Color.clear
                        .frame(height: 6)
                        .id("bottom")
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { _, _ in
                self.scroll(proxy, animated: true)
            }
            .onChange(of: store.streamingText.count / 40) { _, _ in
                self.scroll(proxy, animated: false)
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: - 输入区

    private var composer: some View {
        ComposerBar(
            text: $draft,
            pending: $pending,
            accent: accent,
            isStreaming: store.isStreaming
        ) {
            guard !store.isStreaming else { return }
            self.store.send(text: self.draft, attachments: self.pending)
            self.draft = ""
            self.pending = []
        } onStop: {
            self.store.stop()
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                self.store.newChat()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .disabled(store.messages.isEmpty || store.isStreaming)
            .accessibilityLabel("新对话")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                self.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("设置")
        }
    }

    // MARK: - 未配置提示

    private var setupHint: some View {
        Button {
            self.showSettings = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("还没接上模型")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("点这里填 API 地址和 Key")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

// MARK: - 空态

struct EmptyStateView: View {
    var accent: Color
    var onPickTemplate: (String) -> Void

    private struct Template: Identifiable {
        var id: String { title }
        let icon: String
        let title: String
        let subtitle: String
        let body: String
    }

    private var templates: [Template] {
        [
            Template(
                icon: "bolt.fill",
                title: "快速说清",
                subtitle: "三句话讲明白局面",
                body: """
                对象：代号 / 现在是什么关系（认识、暧昧、在一起、已分手）
                最近一件事：（什么时候 + 对方原话 + 你当时怎么反应）
                我想要：推进 / 确认关系 / 修复 / 退出
                现在最难受的是：
                """
            ),
            Template(
                icon: "list.bullet.rectangle",
                title: "完整档案",
                subtitle: "含 MBTI、投入比、关键事件",
                body: """
                你：MBTI / 主观综合评分 0–100 / 主要优势和短板
                对象A：代号 / MBTI / 主观综合评分 0–100 / 当前关系
                对象B（如有）：同上
                经过：怎么认识的、发展多久、最近三件关键事件、平时谁先联系、双方投入大概几比几
                目标：推进 / 确认关系 / 修复 / 比较选择 / 退出
                情绪：最难受的点是什么、强度 0–10；眼下有没有必须马上回的话
                """
            ),
            Template(
                icon: "text.bubble",
                title: "只回这一句",
                subtitle: "先给一条能发出去的成品",
                body: """
                对方刚说：「」
                我的处境：
                我想要的效果：（拉近距离 / 划清边界 / 先稳住 / 直接问清楚）
                """
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("先让我认识你和局面")
                    .font(.system(size: 20, weight: .semibold))
                Text("挑一个模板，或者直接把事情讲一遍")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(templates) { t in
                    Button {
                        self.onPickTemplate(t.body)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: t.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(accent)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(accent.opacity(0.12)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(t.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 11))
                Text("也可以直接贴截图，我只把看得见的原文当事实")
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
    }
}
