import SwiftUI
import UIKit

/// 主题色：预设色板 + 完全自定义。存 UserDefaults（JSON）。
struct AccentColor: Codable, Equatable, Hashable, Identifiable {
    var r: Double
    var g: Double
    var b: Double
    var name: String

    var id: String { "\(name)-\(Int(r * 255))-\(Int(g * 255))-\(Int(b * 255))" }

    var color: Color { Color(red: r, green: g, blue: b) }

    /// 深色模式下用同色系但提亮一点，避免发闷
    func color(for scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return color }
        return Color(
            red: min(1, r * 0.75 + 0.25),
            green: min(1, g * 0.75 + 0.25),
            blue: min(1, b * 0.75 + 0.25)
        )
    }

    static let presets: [AccentColor] = [
        .init(r: 0.000, g: 0.478, b: 1.000, name: "蓝"),
        .init(r: 0.196, g: 0.678, b: 0.902, name: "青"),
        .init(r: 0.204, g: 0.780, b: 0.349, name: "绿"),
        .init(r: 0.345, g: 0.337, b: 0.839, name: "靛"),
        .init(r: 0.686, g: 0.321, b: 0.871, name: "紫"),
        .init(r: 1.000, g: 0.176, b: 0.333, name: "粉"),
        .init(r: 1.000, g: 0.584, b: 0.000, name: "橙"),
        .init(r: 1.000, g: 0.231, b: 0.188, name: "红"),
        .init(r: 0.470, g: 0.470, b: 0.480, name: "石墨"),
    ]

    static let `default` = AccentColor.presets[0]
}

// MARK: - 背景

/// 极简背景：系统底色 + 顶部一层主题色晕。
/// 液体玻璃需要底下的东西有颜色才成形，但不需要花哨的光斑。
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    var accent: Color

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            LinearGradient(
                stops: [
                    .init(color: accent.opacity(scheme == .dark ? 0.20 : 0.11), location: 0.0),
                    .init(color: accent.opacity(scheme == .dark ? 0.05 : 0.035), location: 0.38),
                    .init(color: accent.opacity(0.0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}
