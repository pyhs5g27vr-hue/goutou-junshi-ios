import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Settings.presets) { preset in
                        Button {
                            self.settings.baseURL = preset.baseURL
                            self.settings.model = preset.model
                            self.settings.save()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .foregroundStyle(.primary)
                                    Text("\(preset.model)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if self.settings.model == preset.model && self.settings.baseURL == preset.baseURL {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("服务商")
                } footer: {
                    Text("换服务商后记得重填 Key。")
                }

                Section {
                    TextField("https://api.deepseek.com/v1", text: $settings.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("sk-...", text: $settings.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("deepseek-chat", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("连接")
                } footer: {
                    Text("地址填到 /v1 就行，App 会自己补 /chat/completions。Key 只存在本机。")
                }

                Section {
                    Button {
                        self.runTest()
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            if testing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(testing || !settings.isConfigured)

                    if let result = testResult {
                        Text(result)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(testOK ? .green : .red)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("自检")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                            ForEach(AccentColor.presets) { preset in
                                Button {
                                    self.settings.accent = preset
                                    self.settings.save()
                                } label: {
                                    Circle()
                                        .fill(preset.color)
                                        .frame(width: 30, height: 30)
                                        .overlay {
                                            if self.settings.accent == preset {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)

                        ColorPicker("自定义颜色", selection: self.accentBinding, supportsOpacity: false)
                    }
                } header: {
                    Text("外观")
                } footer: {
                    Text("主题色会用在标题栏、发送键、你的气泡和按钮强调上。")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("温度")
                            Spacer()
                            Text(String(format: "%.2f", settings.temperature))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.temperature, in: 0...1.2, step: 0.05)
                            .tint(settings.accent.color)
                    }

                    Stepper("参考文档：\(settings.topDocs) 篇", value: $settings.topDocs, in: 1...6)

                    Toggle("显示命中的参考文档", isOn: $settings.showDocChips)
                } header: {
                    Text("行为")
                } footer: {
                    Text("每次发送会从内置的 43 篇知识库里挑最相关的几篇塞进上下文。调低更省钱，调高更细。")
                }

                Section {
                    LabeledContent("开发作者", value: "村口架狙")
                    LabeledContent("知识库", value: "43 篇 · 内置离线")
                    LabeledContent("行为内核", value: "SKILL.md")
                    LabeledContent("版本", value: Bundle.main.appVersion)
                    Link("项目主页", destination: URL(string: "https://github.com/shengjidaguai-china/goutoujunshi")!)
                } header: {
                    Text("关于")
                } footer: {
                    Text("狗头军师 · 先接住情绪，再分清事实，最后给能执行的选择。")
                }

                Section {
                    Button(role: .destructive) {
                        self.settings.apiKey = ""
                        self.settings.save()
                    } label: {
                        Text("清除本机 Key")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        self.settings.save()
                        self.dismiss()
                    }
                }
            }
            .onChange(of: settings.baseURL) { _, _ in self.settings.save() }
            .onChange(of: settings.apiKey) { _, _ in self.settings.save() }
            .onChange(of: settings.model) { _, _ in self.settings.save() }
            .onChange(of: settings.temperature) { _, _ in self.settings.save() }
            .onChange(of: settings.topDocs) { _, _ in self.settings.save() }
            .onChange(of: settings.showDocChips) { _, _ in self.settings.save() }
        }
        .tint(settings.accent.color)
    }

    // MARK: - 主题色绑定

    private var accentBinding: Binding<Color> {
        Binding(
            get: { self.settings.accent.color },
            set: { newColor in
                let ui = UIColor(newColor)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
                    self.settings.accent = AccentColor(
                        r: Double(r), g: Double(g), b: Double(b), name: "自定义"
                    )
                    self.settings.save()
                }
            }
        )
    }

    // MARK: - 连通性测试

    private func runTest() {
        testing = true
        testResult = nil
        let cfg = LLMClient.Config(
            baseURL: settings.baseURL,
            apiKey: settings.apiKey,
            model: settings.model,
            temperature: 0
        )
        let probe: [WireMessage] = [
            WireMessage(role: "user", content: .text("回复两个字：可用"))
        ]
        Task {
            var acc = ""
            do {
                for try await delta in LLMClient.shared.stream(probe, config: cfg) {
                    acc += delta
                    if acc.count > 60 { break }
                }
                await MainActor.run {
                    self.testOK = !acc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    self.testResult = self.testOK ? "✓ \(cfg.model) 连通：\(acc.prefix(40))" : "返回为空，检查模型名"
                    self.testing = false
                }
            } catch {
                await MainActor.run {
                    self.testOK = false
                    self.testResult = "✗ \(error.localizedDescription)"
                    self.testing = false
                }
            }
        }
    }
}

extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
