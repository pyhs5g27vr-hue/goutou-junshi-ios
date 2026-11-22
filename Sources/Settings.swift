import Foundation
import SwiftUI

/// 全局配置：API 端点 / 密钥 / 模型 / 采样参数 / 主题色。存 UserDefaults。
/// 刻意不加 @MainActor：属性默认值初始化器在属性包装器里跑，隔离标记会让它和 SwiftUI 打架。
/// 所有读写都发生在 UI 主线程。
final class Settings: ObservableObject {
    static let shared = Settings()

    private let store = UserDefaults.standard

    @Published var baseURL: String
    @Published var apiKey: String
    @Published var model: String
    @Published var temperature: Double
    @Published var topDocs: Int
    @Published var showDocChips: Bool
    @Published var accent: AccentColor

    private init() {
        baseURL = store.string(forKey: "baseURL") ?? "https://api.deepseek.com/v1"
        apiKey = store.string(forKey: "apiKey") ?? ""
        model = store.string(forKey: "model") ?? "deepseek-chat"
        temperature = store.object(forKey: "temperature") as? Double ?? 0.6
        topDocs = store.object(forKey: "topDocs") as? Int ?? 3
        showDocChips = store.object(forKey: "showDocChips") as? Bool ?? true

        if let data = store.data(forKey: "accent"),
           let decoded = try? JSONDecoder().decode(AccentColor.self, from: data) {
            accent = decoded
        } else {
            accent = .default
        }
    }

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() {
        store.set(baseURL, forKey: "baseURL")
        store.set(apiKey, forKey: "apiKey")
        store.set(model, forKey: "model")
        store.set(temperature, forKey: "temperature")
        store.set(topDocs, forKey: "topDocs")
        store.set(showDocChips, forKey: "showDocChips")
        if let data = try? JSONEncoder().encode(accent) {
            store.set(data, forKey: "accent")
        }
    }

    /// 常见服务商预设，设置页一键切换
    struct Preset: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let baseURL: String
        let model: String
        var needsVisionNote: String? = nil
    }

    static let presets: [Preset] = [
        .init(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
        .init(name: "DeepSeek 视觉", baseURL: "https://api.deepseek.com/v1", model: "deepseek-vl2",
              needsVisionNote: "需要你的账号已开通视觉模型"),
        .init(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o"),
        .init(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: "google/gemini-2.5-pro"),
        .init(name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1", model: "Qwen/Qwen2.5-VL-72B-Instruct"),
        .init(name: "本地/自建", baseURL: "http://192.168.1.10:1234/v1", model: "local-model"),
    ]
}
