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

enum KSDesign {
    static let accent = Color.blue

    /// 浅浅一层蓝色渐变，叠在系统背景之上；明暗模式都成立
    static let background = LinearGradient(
        colors: [Color.blue.opacity(0.10), Color.blue.opacity(0.015)],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// 控件卡片：Liquid Glass 圆角矩形，可交互（随触摸响应）
struct GlassPanel<Content: View>: View {
    let tint: Color
    let radius: CGFloat
    let content: Content

    init(
        tint: Color = .blue,
        radius: CGFloat = 24,
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
                .regular.tint(tint.opacity(0.08)).interactive(),
                in: .rect(cornerRadius: radius)
            )
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

/// 日志用深色不透明面板，避免玻璃折射影响等宽小字的可读性
struct LogConsole: View {
    let lines: [String]

    var body: some View {
        ScrollView {
            Text(lines.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(red: 0.85, green: 0.89, blue: 0.95))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(height: 180)
        .background(
            Color(red: 0.06, green: 0.07, blue: 0.10),
            in: .rect(cornerRadius: 14)
        )
    }
}
