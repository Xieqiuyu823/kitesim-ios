import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "simcard.2.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(KSDesign.accent)
                        Text("KiteSim 助手")
                            .font(.title2.bold())
                        Text("iOS 26 原生版 · SwiftUI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "实现方式", systemImage: "hammer")
                            aboutLine("临时邮箱", "mail.tm 公开 API，带限流重试")
                            aboutLine("图形验证码", "ddddocr common_old.onnx，端上 ONNX Runtime 推理 + CTC 解码，不联网打码")
                            aboutLine("登录", "sign-in 拿 token 后注入 WKWebView 的 AppToken")
                            aboutLine("界面", "SwiftUI + iOS 26 Liquid Glass 玻璃控件")
                            aboutLine("数据", "账号存 App 的 Documents/accounts.jsonl，清空前自动备份")
                        }
                    }

                    GlassPanel(tint: .orange) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "合规提示", systemImage: "exclamationmark.shield")
                            Text("本工具仅供技术学习与自动化测试使用。请遵守 KiteSim 服务条款，勿用于转售账号、薅取平台资产等违规行为。临时邮箱注册的账号无法找回密码，请自行保管账号文件。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
            .liquidScreenBackground()
            .navigationTitle("关于")
        }
    }

    private func aboutLine(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption.bold())
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
    }
}
