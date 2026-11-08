import SwiftUI

#if os(iOS)
import WebKit

// MARK: - 内置浏览器（注入 AppToken，免登录进入 KiteSim）

struct BrowserView: View {
    @EnvironmentObject private var state: AppState
    let token: String
    let email: String

    @State private var showLogoutConfirm = false
    @State private var reloadToken = UUID()
    @State private var homeToken = UUID()

    var body: some View {
        NavigationStack {
            WebContentView(
                token: token,
                reloadToken: reloadToken,
                homeToken: homeToken
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(email.isEmpty ? "KiteSim" : "KiteSim · \(email)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        state.showBrowser = false
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            homeToken = UUID()
                        } label: {
                            Label("首页", systemImage: "house")
                        }
                        Button {
                            reloadToken = UUID()
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            Label("退出并清除", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("退出登录", isPresented: $showLogoutConfirm) {
                Button("退出并清除（保留支付宝）", role: .destructive) {
                    Task {
                        await WebViewCleaner.clearKeepingAlipay()
                        await MainActor.run {
                            state.logout()
                            state.showBrowser = false
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除 KiteSim 的登录态、Cookie 与本地缓存；支付宝的 Cookie 与本地存储会保留，下次支付无需重新登录。")
            }
        }
    }
}

// MARK: - WKWebView 封装

struct WebContentView: UIViewRepresentable {
    let token: String
    let reloadToken: UUID
    let homeToken: UUID

    private static let homeURL = URL(string: "https://h5.kitesim.co/")!

    func makeCoordinator() -> Coordinator {
        Coordinator(token: token)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        if !token.isEmpty {
            // atDocumentStart 注入：页面脚本初始化之前就写好登录态，
            // 比安卓端在 onPageStarted 里 evaluateJavascript 更可靠。
            // uni-app H5 对字符串类型直接裸存 localStorage，不做包装。
            let js = "(function(){try{localStorage.setItem('AppToken','\(Self.escape(token))');}" +
                     "catch(e){}})();"
            controller.addUserScript(
                WKUserScript(
                    source: js,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        context.coordinator.lastReload = reloadToken
        context.coordinator.lastHome = homeToken
        webView.load(URLRequest(url: Self.homeURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.lastReload != reloadToken {
            coordinator.lastReload = reloadToken
            webView.reload()
        }
        if coordinator.lastHome != homeToken {
            coordinator.lastHome = homeToken
            webView.load(URLRequest(url: Self.homeURL))
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "")
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let token: String
        weak var webView: WKWebView?
        var lastReload: UUID?
        var lastHome: UUID?
        var reloadedOnce = false

        init(token: String) {
            self.token = token
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 兜底：若首屏仍停在登录页，用站点自身的 uni API 写入并刷新一次
            guard !token.isEmpty, !reloadedOnce,
                  let url = webView.url?.absoluteString,
                  url.contains("/pages/login/login") else { return }
            reloadedOnce = true
            let safe = WebContentView.escape(token)
            let js = "(function(){try{uni.setStorageSync('AppToken','\(safe)');}" +
                     "catch(e){localStorage.setItem('AppToken','\(safe)');}" +
                     "location.reload();})();"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

// MARK: - 退出清理：只清 KiteSim，保留支付宝
//
// iOS 比安卓更方便：WKHTTPCookieStore 能枚举所有 Cookie，
// 所以不需要安卓端「备份支付宝 → removeAllCookies → 回填」的绕路，
// 直接跳过支付宝 Cookie 删除即可（不会丢失 Domain/Path/Secure 等属性）。
// 同理，websiteDataStore 只按 KiteSim 的 origin 记录删除，
// 绝不能调 removeData(ofTypes:modifiedSince:) —— 那会连支付宝的 localStorage 一起清掉。

enum WebViewCleaner {

    private static let alipaySuffixes = [
        "alipay.com",
        "alipayobjects.com",
        "alipay.cn",
    ]

    private static func isAlipay(_ domain: String) -> Bool {
        let d = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return alipaySuffixes.contains { d == $0 || d.hasSuffix("." + $0) }
    }

    @MainActor
    static func clearKeepingAlipay() async {
        let store = WKWebsiteDataStore.default()
        let cookieStore = store.httpCookieStore

        // 1) 删除所有非支付宝 Cookie
        let cookies = await withCheckedContinuation {
            (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where !isAlipay(cookie.domain) {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<Void, Never>) in
                // iOS 26 SDK 将 deleteCookie(_:completionHandler:) 更名为 delete(_:completionHandler:)
                cookieStore.delete(cookie) { continuation.resume() }
            }
        }

        // 2) 只清除 KiteSim 相关 origin 的 localStorage / IndexedDB / 缓存
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await withCheckedContinuation {
            (continuation: CheckedContinuation<[WKWebsiteDataRecord], Never>) in
            store.fetchDataRecords(ofTypes: types) {
                continuation.resume(returning: $0)
            }
        }
        let kiteRecords = records.filter { record in
            let name = record.displayName.lowercased()
            return name.contains("kitesim.co") || name.contains("mail.tm")
        }
        guard !kiteRecords.isEmpty else { return }
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: types, for: kiteRecords) {
                continuation.resume()
            }
        }
    }
}

#else

// macOS 仅作占位（xtool 构建目标是 iOS）
struct BrowserView: View {
    let token: String
    let email: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.largeTitle)
            Text("内置浏览器仅支持 iOS")
        }
        .navigationTitle("KiteSim")
    }
}

#endif
