import SwiftUI

// MARK: - 液态玻璃适配层
//
// iOS 26 的 Liquid Glass 通过 `glassEffect` / `GlassEffectContainer` 暴露。
// 这里做两件事：
//   1. 用 `#if compiler(>=6.2)` 兜住 SDK：Xcode 25 及更早的编译器看不到这些符号，整段会被剔掉；
//   2. 在 iOS 17–25 上降级为 ultraThinMaterial + 高光描边，保证观感一致。

enum GlassKit {
    #if compiler(>=6.2)
    /// 组装玻璃样式：`.` 默认 + 可选着色 + 可选触摸响应
    @available(iOS 26.0, *)
    static func make(tint: Color?, interactive: Bool) -> Glass {
        var g = Glass.regular
        if let tint {
            g = g.tint(tint)
        }
        if interactive {
            g = g.interactive()
        }
        return g
    }
    #endif
}

/// 液态玻璃容器。相邻的玻璃元素在 iOS 26 上会互相吸引、融合成一整块——
/// 这是 Liquid Glass 最有辨识度的行为，输入框和发送键靠近时会「粘」在一起。
struct GlassCluster<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

extension View {

    /// 给任意视图套一层液态玻璃
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(_ shape: S,
                               tint: Color? = nil,
                               interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassKit.make(tint: tint, interactive: interactive), in: shape)
        } else {
            self.legacyGlass(shape, tint: tint)
        }
        #else
        self.legacyGlass(shape, tint: tint)
        #endif
    }

    /// iOS 17–25 的视觉近似：磨砂 + 顶边高光
    func legacyGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil) -> some View {
        self
            .background {
                shape.fill(.ultraThinMaterial)
                if let tint {
                    shape.fill(tint.opacity(0.16))
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
    }

}

// MARK: - 背景

/// 液态玻璃需要「有东西可折射」。这层暖色光斑就是它的底片。
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            base
            if scheme == .dark {
                blob(Color(red: 0.95, green: 0.45, blue: 0.25), size: 360, x: -130, y: -300, opacity: 0.28)
                blob(Color(red: 0.55, green: 0.40, blue: 0.95), size: 320, x: 150, y: 240, opacity: 0.26)
                blob(Color(red: 0.95, green: 0.35, blue: 0.55), size: 260, x: 60, y: 620, opacity: 0.16)
            } else {
                blob(Color(red: 1.00, green: 0.62, blue: 0.36), size: 380, x: -130, y: -300, opacity: 0.55)
                blob(Color(red: 0.72, green: 0.62, blue: 1.00), size: 340, x: 150, y: 240, opacity: 0.48)
                blob(Color(red: 1.00, green: 0.55, blue: 0.72), size: 280, x: 60, y: 640, opacity: 0.35)
            }
        }
        .ignoresSafeArea()
    }

    private var base: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.06, green: 0.06, blue: 0.08), Color(red: 0.10, green: 0.09, blue: 0.12)]
                : [Color(red: 1.00, green: 0.97, blue: 0.94), Color(red: 0.95, green: 0.94, blue: 1.00)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: size * 0.32)
            .opacity(opacity)
            .offset(x: x, y: y)
    }
}
