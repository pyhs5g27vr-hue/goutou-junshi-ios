import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @ObservedObject private var settings = Settings.shared

    @State private var draft = ""
    @State private var pending: [Attachment] = []
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
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
        .tint(.orange)
    }

    // MARK: - 会话区

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if !settings.isConfigured {
                        setupHint
                    }

                    if store.messages.isEmpty && !store.isStreaming {
                        EmptyStateView { template in
                            self.draft = template
                        }
                        .padding(.top, 24)
                    }

                    ForEach(store.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }

                    if store.isStreaming {
                        MessageRow(
                            message: Message(
                                role: .assistant,
                                text: store.streamingText,
                                docs: store.pendingDocs
                            ),
                            isStreaming: true
                        )
                        .id("streaming")
                    }

                    Color.clear
                        .frame(height: 8)
                        .id("bottom")
                }
                .padding(.vertical, 10)
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
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("还没接上模型")
                        .font(.system(size: 13, weight: .semibold))
                    Text("点这里填 API 地址和 Key，两分钟搞定")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous), tint: .orange)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

// MARK: - 空态

struct EmptyStateView: View {
    var onPickTemplate: (String) -> Void

    private let template = """
    你：MBTI / 主观综合评分 0–100 / 主要优势和短板
    对象A：代号 / MBTI / 主观综合评分 0–100 / 当前关系
    对象B（如有）：同上
    经过：怎么认识的、发展多久、最近三件关键事件、平时谁先联系、双方投入大概几比几
    目标：推进 / 确认关系 / 修复 / 比较选择 / 退出
    情绪：最难受的点是什么、强度 0–10；眼下有没有必须马上回的话
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 46, height: 46)
                    .liquidGlass(.circle, tint: .orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("先让我认识你和局面")
                        .font(.system(size: 17, weight: .bold))
                    Text("不知道的留空，也可以直接讲故事")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                bullet("贴聊天截图，我只把看得见的原文当事实")
                bullet("讲清楚最近发生了什么，我会帮你拆事实 / 推测 / 未知")
                bullet("只问「这句怎么回」也行，第一屏直接给可发送成品")
            }

            Button {
                self.onPickTemplate(self.template)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "text.badge.plus")
                    Text("填入问卷模板")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .liquidGlass(.capsule, tint: .orange, interactive: true)
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .liquidGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 18)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.orange.opacity(0.75))
                .frame(width: 5, height: 5)
                .padding(.top, 6.5)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
