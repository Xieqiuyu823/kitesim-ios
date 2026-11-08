import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - 剪贴板

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - iOS 26 Liquid Glass 设计系统
//
// 原则（Apple HIG / Liquid Glass）：玻璃材质用于「控件与导航层」，
// 不铺满正文内容表面；日志、账号列表等长文本仍用不透明/常规材质保证可读性。
// 系统标准控件（TabView / 工具栏 / 按钮）在 iOS 26 会自动获得玻璃外观。
//
// 玻璃要好看，前提是它后面有「东西可折射」——所以底层放了一层缓慢漂移的
// 液态色斑（LiquidBackground），玻璃卡片才会出现流动的高光与折射。

enum KSDesign {
    /// 与 App 图标同源的紫色（安卓 purple_500 #6200EE 的现代变体）
    static let accent = Color(red: 0.42, green: 0.22, blue: 0.93)
    static let accentSoft = Color(red: 0.55, green: 0.34, blue: 1.0)

    /// 浅一层的主色渐变，用于图标底、进度条等小面积元素
    static let brandGradient = LinearGradient(
        colors: [accentSoft, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: 圆角
    //
    // 全 App 只允许这三档圆角，避免出现「这块 16、那块 20、另一块 26」的参差感。
    // 层级关系：页面级卡片 > 卡片内的子块 > 小型控件/图片。

    /// 页面级卡片（玻璃面板、日志面板、首屏 Hero）
    static let cardRadius: CGFloat = 26
    /// 卡片内部的子块（账号行、嵌套容器）
    static let rowRadius: CGFloat = 20
    /// 小控件（图标底、缩略图、徽标）
    static let controlRadius: CGFloat = 12
}

// MARK: - 液态背景

/// 底色 + 三团缓慢漂移的高饱和色斑。
/// 用 `withAnimation(.repeatForever)` 让 SwiftUI 自己插值 offset，
/// 不会每帧重跑 body，性能比 TimelineView 友善得多。
struct LiquidBackground: View {
    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                LinearGradient(
                    colors: isDark
                        ? [Color(red: 0.05, green: 0.03, blue: 0.12),
                           Color(red: 0.02, green: 0.02, blue: 0.05)]
                        : [Color(red: 0.97, green: 0.96, blue: 1.0),
                           Color(red: 0.94, green: 0.95, blue: 1.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 紫色主斑：左上
                blob(
                    KSDesign.accent,
                    size: w * 0.95,
                    opacity: isDark ? 0.55 : 0.35,
                    x: drift ? -w * 0.10 : w * 0.12,
                    y: drift ? -h * 0.10 : -h * 0.04
                )

                // 青色副斑：右侧
                blob(
                    Color(red: 0.20, green: 0.85, blue: 0.90),
                    size: w * 0.85,
                    opacity: isDark ? 0.32 : 0.28,
                    x: drift ? w * 0.30 : w * 0.18,
                    y: drift ? h * 0.12 : h * 0.02
                )

                // 品红副斑：左下
                blob(
                    Color(red: 0.98, green: 0.30, blue: 0.62),
                    size: w * 0.80,
                    opacity: isDark ? 0.30 : 0.22,
                    x: drift ? -w * 0.28 : -w * 0.06,
                    y: drift ? h * 0.30 : h * 0.22
                )
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !drift else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .allowsHitTesting(false)
    }

    private func blob(_ color: Color, size: CGFloat, opacity: Double, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: size * 0.28)
            .opacity(opacity)
            .offset(x: x, y: y)
    }
}

// MARK: - 玻璃容器

/// 控件卡片：Liquid Glass 圆角矩形，可交互（随触摸响应）。
/// 另叠一圈极淡的高光描边，强化「液体厚度」。
struct GlassPanel<Content: View>: View {
    let tint: Color
    let radius: CGFloat
    let content: Content

    init(
        tint: Color = KSDesign.accent,
        radius: CGFloat = KSDesign.cardRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(tint.opacity(0.10)).interactive(),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay { GlassHighlight(radius: radius) }
    }
}

/// 玻璃边缘高光：左上强、中间透、右下弱，模拟液体表面的反射
struct GlassHighlight: View {
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.55),
                        .white.opacity(0.05),
                        .white.opacity(0.28),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

/// 日志用深色面板：不透明底色保证等宽小字可读，形状/圆角与玻璃卡片完全一致。
/// 注意 ScrollView 必须显式 clip，否则滚动时文字会顶到圆角外面，
/// 在 App 退到后台被系统缩略（App Switcher）时那块方角会特别扎眼。
struct LogConsole: View {
    let lines: [String]

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: KSDesign.cardRadius, style: .continuous)
    }

    private var text: String {
        lines.isEmpty ? "（暂无日志）" : lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(red: 0.85, green: 0.89, blue: 0.95))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .textSelection(.enabled)
        }
        .scrollIndicators(.hidden)
        .frame(height: 190)
        .clipShape(shape)
        .background(
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.09).opacity(0.92)
                // 顶部一层极淡的高光，与玻璃卡片共用同一套「液体厚度」语言
                LinearGradient(
                    colors: [.white.opacity(0.07), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            },
            in: shape
        )
        .overlay {
            shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
        }
    }
}

// MARK: - 便捷修饰符

extension View {
    /// 统一页面底板：液态背景铺满，内容浮在上面
    func liquidScreenBackground() -> some View {
        background(LiquidBackground())
    }

    /// 内容卡片：玻璃 + 边缘高光（不可交互内容用，避免多余触摸反馈）
    func glassCard(
        tint: Color = KSDesign.accent,
        radius: CGFloat = KSDesign.cardRadius
    ) -> some View {
        glassEffect(
            .regular.tint(tint.opacity(0.10)),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay { GlassHighlight(radius: radius) }
    }
}
