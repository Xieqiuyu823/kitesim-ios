import SwiftUI

#if os(iOS)
import UIKit
#endif

struct NetworkView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GlassPanel(tint: .blue) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "代理设置", systemImage: "globe")
                            Text("KiteSim 对部分地区返回 403「该地区暂不提供服务」。填写代理可让请求以可用地区的 IP 发出。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("http://host:port 或 socks5://host:1080", text: $state.proxy)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("保存代理") {
                                state.saveProxy()
                            }
                            .buttonStyle(.glass)
                            Text("iOS 上通过 URLSession 的 connectionProxyDictionary 生效；内置 WKWebView 需系统级代理。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GlassPanel(tint: .teal) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "网络自检", systemImage: "stethoscope")
                            Text("逐个探测官网、KiteSim 接口、临时邮箱接口，显示状态码与返回类型。接口显示 HTML 而非 JSON，说明是本机 VPN / 代理或运营商在拦截。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                state.selfTest()
                            } label: {
                                HStack {
                                    if state.isSelfTesting { ProgressView() }
                                    Text(state.isSelfTesting ? "检测中..." : "开始自检")
                                }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.teal)
                            .disabled(state.isSelfTesting)
                            Text(state.selfTestReport)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GlassPanel(tint: .indigo) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "验证码识别自检", systemImage: "text.viewfinder")
                            Text("抓一张真实验证码在本地识别，把识别结果和原图放在一起，方便肉眼核对。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                state.checkCaptcha()
                            } label: {
                                HStack {
                                    if state.isCheckingCaptcha { ProgressView() }
                                    Text(state.isCheckingCaptcha ? "识别中..." : "抓一张试试")
                                }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(KSDesign.accent)
                            .disabled(state.isCheckingCaptcha)

                            if let preview = state.captchaPreview, let ui = UIImage(data: preview) {
                                HStack(alignment: .center, spacing: 14) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .interpolation(.none)
                                        .scaledToFit()
                                        .frame(height: 44)
                                        .padding(6)
                                        .background(
                                            Color.white,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        )

                                    Text(state.captchaResult)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else if !state.captchaResult.isEmpty {
                                Text(state.captchaResult)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    GlassPanel(tint: .orange) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "地区检测", systemImage: "map")
                            Text("逐个国家试请求套餐接口，确认当前网络能否正常购买。需先登录一个账号。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                state.checkRegion()
                            } label: {
                                HStack {
                                    if state.isCheckingRegion { ProgressView() }
                                    Text(state.isCheckingRegion ? "检测中..." : "检测当前地区")
                                }
                            }
                            .buttonStyle(.glass)
                            .disabled(state.isCheckingRegion)
                            if !state.regionReport.isEmpty {
                                Text(state.regionReport)
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    Text("提示：安卓端曾出现过「接口返回 HTML」导致登录失败，最终确认是手机开着 VPN/代理。iOS 上同样先看自检结果。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .liquidScreenBackground()
            .navigationTitle("网络")
        }
    }
}
