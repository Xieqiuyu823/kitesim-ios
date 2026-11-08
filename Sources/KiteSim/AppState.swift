import Foundation
import SwiftUI

/// 全局状态。@MainActor 保证所有 @Published 变更都在主线程，
/// 网络请求用 async/await 挂起，不会阻塞界面。
@MainActor
final class AppState: ObservableObject {

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var logs: [String] = ["等待开始..."]
    @Published var isBusy = false
    @Published var ocrReady = false
    @Published var invite = "IMWDGC"
    @Published var proxy = ""

    @Published var token = ""
    @Published var loggedInEmail = ""
    @Published var info: [String: Any] = [:]
    @Published var showBrowser = false

    @Published var selfTestReport = "点「网络自检」开始探测。"
    @Published var isSelfTesting = false
    @Published var regionReport = ""
    @Published var isCheckingRegion = false

    private let store = AccountStore()
    private let registrar = Registrar.shared
    private let api = KiteSimAPI.shared

    init() {
        accounts = store.accounts
        let saved = UserDefaults.standard.string(forKey: "proxy") ?? ""
        proxy = saved
        applyProxy(saved, log: false)
    }

    // MARK: 日志

    func appendLog(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        logs.append("[\(f.string(from: Date()))] \(message)")
    }

    // MARK: 模型

    func preloadOCR() {
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try Registrar.shared.preloadOCR() }
            await MainActor.run {
                switch outcome {
                case .success:
                    self.ocrReady = true
                    self.appendLog("验证码识别模型加载完成，可以开始注册")
                case .failure(let error):
                    self.appendLog("模型加载失败: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: 注册 / 登录

    func register() {
        guard !isBusy else { return }
        isBusy = true
        logs = []
        appendLog("===== 开始注册 =====")
        let code = invite
        Task {
            do {
                let account = try await registrar.register(invite: code) { [weak self] message in
                    Task { @MainActor in self?.appendLog(message) }
                }
                store.add(account)
                accounts = store.accounts
                appendLog("注册成功: \(account.email)")
            } catch {
                appendLog("失败: \(error.localizedDescription)")
            }
            isBusy = false
        }
    }

    func login(_ account: Account) {
        guard !isBusy else { return }
        isBusy = true
        logs = []
        let target = account
        Task {
            do {
                let (value, details) = try await registrar.login(target) { [weak self] message in
                    Task { @MainActor in self?.appendLog(message) }
                }
                token = value
                loggedInEmail = target.email
                info = details
                appendLog("登录成功，正在打开 KiteSim ...")
                showBrowser = true
            } catch {
                appendLog("登录失败: \(error.localizedDescription)")
            }
            isBusy = false
        }
    }

    func logout() {
        token = ""
        loggedInEmail = ""
        info = [:]
        appendLog("已退出并清除 KiteSim 登录态与 Cookie（支付宝已保留）")
    }

    // MARK: 账号

    func clearAccounts() {
        guard !accounts.isEmpty else { return }
        store.clear()   // 内部会自动备份到 accounts.backup-*.jsonl
        accounts = []
        appendLog("已清空全部账号（已自动备份）")
    }

    // MARK: 网络

    private func applyProxy(_ value: String, log: Bool) {
        HTTPClient.kitesim.setProxy(value)
        HTTPClient.mailtm.setProxy(value)
        HTTPClient.plain.setProxy(value)
        if log {
            appendLog(value.isEmpty ? "已关闭代理（直连）" : "代理已设为 \(value)")
        }
    }

    func saveProxy() {
        let value = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        applyProxy(value, log: true)
        UserDefaults.standard.set(value, forKey: "proxy")
    }

    func selfTest() {
        guard !isSelfTesting else { return }
        isSelfTesting = true
        selfTestReport = "检测中..."
        Task {
            let report = await api.selfTest()
            selfTestReport = report
            isSelfTesting = false
        }
    }

    func checkRegion() {
        guard !token.isEmpty else {
            regionReport = "请先登录一个账号，再检测当前地区。"
            return
        }
        guard !isCheckingRegion else { return }
        isCheckingRegion = true
        regionReport = "检测中..."
        let current = token
        Task {
            let (ok, detail) = await api.checkRegion(token: current)
            let title = ok
                ? "当前网络可用，可正常购买套餐"
                : "当前网络无法购买套餐（KiteSim 按地区限制）"
            regionReport = title + "\n" + detail.joined(separator: "\n")
            isCheckingRegion = false
        }
    }
}
