import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct ComposerBar: View {
    @Binding var text: String
    @Binding var pending: [Attachment]
    var isStreaming: Bool
    var onSend: () -> Void
    var onStop: () -> Void

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var showMenu = false
    @State private var loading = 0
    @State private var importError: String?

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            if !pending.isEmpty { attachmentStrip }

            GlassCluster(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    self.addButton
                    self.inputField
                    self.actionButton
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .padding(.top, 6)
        .photosPicker(isPresented: $showPhotoPicker,
                      selection: $photoItems,
                      maxSelectionCount: 6,
                      matching: .images,
                      photoLibrary: .shared())
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: AttachmentKit.readableTextTypes,
                      allowsMultipleSelection: true) { result in
            self.handleFiles(result)
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            self.loadPhotos(items)
        }
        .confirmationDialog("添加素材", isPresented: $showMenu, titleVisibility: .visible) {
            Button("从相册选聊天截图") { self.showPhotoPicker = true }
            Button("选择聊天导出文件") { self.showFilePicker = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("截图会压到长边 1280 再上传，气泡里的字还看得清。")
        }
        .alert("读取失败", isPresented: Binding(
            get: { self.importError != nil },
            set: { if !$0 { self.importError = nil } }
        )) {
            Button("好", role: .cancel) { self.importError = nil }
        } message: {
            Text(self.importError ?? "")
        }
    }

    // MARK: - 输入框

    private var inputField: some View {
        TextField("说说你现在的局面…", text: $text, axis: .vertical)
            .lineLimit(1...6)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(.capsule, interactive: true)
    }

    // MARK: - 加号

    private var addButton: some View {
        Button {
            self.showMenu = true
        } label: {
            ZStack {
                if loading > 0 {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 44, height: 44)
            .liquidGlass(.circle, tint: nil, interactive: true)
        }
        .disabled(isStreaming || loading > 0)
        .opacity(isStreaming ? 0.45 : 1)
    }

    // MARK: - 发送 / 停止

    private var actionButton: some View {
        Button {
            if self.isStreaming {
                self.onStop()
            } else {
                self.onSend()
            }
        } label: {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(isStreaming ? Color.white : (canSend ? Color.white : Color.secondary))
                .frame(width: 44, height: 44)
                .liquidGlass(
                    .circle,
                    tint: isStreaming ? Color.red : (canSend ? Color.orange : nil),
                    interactive: true
                )
                .scaleEffect(isStreaming ? 0.94 : 1)
                .animation(.snappy(duration: 0.22), value: isStreaming)
        }
        .disabled(!canSend && !isStreaming)
    }

    // MARK: - 附件条

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pending) { item in
                    self.chip(item)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(height: 74)
    }

    private func chip(_ item: Attachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if item.kind == .image, let data = item.imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6)
                        }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 18, weight: .medium))
                        Text(item.name)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .frame(maxWidth: 52)
                    }
                    .frame(width: 62, height: 62)
                    .foregroundStyle(.primary)
                    .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Button {
                self.pending.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .offset(x: 5, y: -5)
        }
        .frame(width: 68, height: 68)
    }

    // MARK: - 导入

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        loading += 1
        Task {
            var built: [Attachment] = []
            for (idx, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let att = AttachmentKit.makeImage(from: data, name: "截图\(idx + 1)") {
                    built.append(att)
                }
            }
            await MainActor.run {
                self.pending.append(contentsOf: built)
                if built.isEmpty { self.importError = "这些图片读不出来，换几张试试。" }
                self.photoItems = []
                self.loading -= 1
            }
        }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            importError = err.localizedDescription
        case .success(let urls):
            loading += 1
            Task {
                // 读盘放到后台，几 MB 的聊天导出也不会卡住滚动
                let built = await Task.detached(priority: .userInitiated) { () -> [Attachment] in
                    urls.compactMap { AttachmentKit.makeText(from: $0) }
                }.value
                await MainActor.run {
                    self.pending.append(contentsOf: built)
                    if built.isEmpty {
                        self.importError = "没有读到文本内容。聊天记录请先导出成 .txt 或 .md。"
                    }
                    self.loading -= 1
                }
            }
        }
    }
}
