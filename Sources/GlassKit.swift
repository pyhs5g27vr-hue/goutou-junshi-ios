import SwiftUI

// MARK: - 液态玻璃适配层
//
// iOS 26 的 Liquid Glass 通过 `glassEffect` / `GlassEffectContainer` 暴露。
// 这里做两件事：
//   1. 用 `#if compiler(>=6.2)` 兜住 SDK：Xcode 25 及更早的编译器看不到这些符号，整段会被剔掉；
//   2. 在 iOS 17–25 上降级为 ultraThinMaterial + 细描边，保证观感一致。

enum GlassKit {
    #if compiler(>=6.2)
    /// 组装玻璃样式：默认 + 可选着色 + 可选触摸响应
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

    /// iOS 17–25 的视觉近似：磨砂 + 一圈极细的描边
    func legacyGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil) -> some View {
        self
            .background {
                shape.fill(.ultraThinMaterial)
                if let tint {
                    shape.fill(tint.opacity(0.14))
                }
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}
