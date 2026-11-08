import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroCard

                    GlassPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "新账号", systemImage: "plus.circle")

                            TextField("邀请码（可留空）", text: $state.invite)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Button {
                                state.register()
                            } label: {
                                HStack(spacing: 10) {
                                    if state.isBusy {
                                        ProgressView().tint(.white)
                                    }
                                    Text(state.isBusy ? "注册中，请稍候..." : "一键获取账号")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .tint(KSDesign.accent)
                            .disabled(state.isBusy || !state.ocrReady)

                            if !state.ocrReady {
                                Text("正在加载验证码识别模型...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // 多个玻璃控件放进 Container，让它们能融合/形变并降低渲染开销
                    GlassEffectContainer(spacing: 24) {
                        HStack(spacing: 12) {
                            Button {
                                state.selfTest()
                            } label: {
                                Label("网络自检", systemImage: "stethoscope")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.regular)

                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Label("清空账号", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.regular)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "运行日志", systemImage: "terminal")
                        LogConsole(lines: state.logs)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "已获取账号 (\(state.accounts.count))",
                            systemImage: "list.bullet.rectangle"
                        )
                        if state.accounts.isEmpty {
                            ContentUnavailableView(
                                "暂无账号",
                                systemImage: "tray",
                                description: Text("点上方「一键获取账号」开始")
                            )
                            .frame(height: 150)
                        } else {
                            ForEach(state.accounts) { account in
                                AccountRow(account: account) {
                                    state.login(account)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(KSDesign.background.ignoresSafeArea())
            .navigationTitle("KiteSim")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showClearConfirm = true
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .disabled(state.accounts.isEmpty)
                }
            }
            .confirmationDialog("清空账号", isPresented: $showClearConfirm) {
                Button("清空全部账号", role: .destructive) {
                    state.clearAccounts()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("清空后无法恢复；系统会自动备份到 App 的 Documents 目录。")
            }
        }
    }

    private var heroCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "simcard.2.fill")
                .font(.system(size: 32))
                .foregroundStyle(KSDesign.accent)
                .frame(width: 56, height: 56)
                .background(KSDesign.accent.opacity(0.12), in: .rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text("KiteSim 助手")
                    .font(.title3.bold())
                Text("临时邮箱 + 本地验证码识别，注册与登录全程自动")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }
}

// MARK: - 账号行

private struct AccountRow: View {
    let account: Account
    let onLogin: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(account.email)
                .font(.system(.caption, design: .monospaced))
            Text("密码: \(account.password)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text(account.createdAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    Clipboard.copy(account.clipboardText)
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)

                Button {
                    onLogin()
                } label: {
                    Label("登录", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(KSDesign.accent)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }
}
