import Foundation

// MARK: - 统一错误

enum KSError: Error, LocalizedError {
    case invalidURL(String)
    case nonJSONResponse(label: String, status: Int, preview: String)
    case badStatus(Int, String)
    case api(String)
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u):
            return "无效地址: \(u)"
        case .nonJSONResponse(let label, let status, let preview):
            return "\(label) 失败（HTTP \(status)，返回的不是 JSON，可能被网络代理或风控拦截）: \(preview)"
        case .badStatus(let code, let body):
            return "HTTP \(code): \(body)"
        case .api(let msg):
            return msg
        case .missingResource(let r):
            return "缺少资源文件: \(r)"
        }
    }
}

// MARK: - JSON 取值小工具

func JSONInt(_ value: Any?) -> Int {
    if let n = value as? NSNumber { return n.intValue }
    if let s = value as? String { return Int(s) ?? 0 }
    return 0
}

func JSONStr(_ value: Any?) -> String {
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return ""
}

enum ClientProfile {
    case kitesim
    case mailtm
    case plain
}

// MARK: - HTTP 客户端

/// 与安卓 v1.4 对齐：
///  - 浏览器风格请求头（UA / Accept / Accept-Language / Origin / Referer）
///  - 非 JSON 响应（WAF/VPN 拦截页）自动重试 3 次
///  - 报错带上 HTTP 状态码 + 拦截页前 160 字，不再只报 "Value <html>"
final class HTTPClient {

    static let kitesim = HTTPClient(profile: .kitesim)
    static let mailtm = HTTPClient(profile: .mailtm)
    static let plain = HTTPClient(profile: .plain)

    private static let h5Origin = "https://h5.kitesim.co"
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    private let profile: ClientProfile
    private var session: URLSession
    private var proxyString: String = ""

    init(profile: ClientProfile) {
        self.profile = profile
        self.session = URLSession(
            configuration: Self.makeConfiguration(profile: profile, proxy: "")
        )
    }

    private static func makeConfiguration(
        profile: ClientProfile,
        proxy: String
    ) -> URLSessionConfiguration {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 40

        var headers: [String: String] = [
            "User-Agent": userAgent,
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        ]
        if profile == .kitesim {
            headers["Origin"] = h5Origin
            headers["Referer"] = "\(h5Origin)/"
        }
        cfg.httpAdditionalHeaders = headers

        if !proxy.isEmpty, let dict = proxyDictionary(from: proxy) {
            cfg.connectionProxyDictionary = dict
        }
        return cfg
    }

    /// URLSession 的 connectionProxyDictionary（对应 PC 端的 HTTP(S)_PROXY 环境变量）
    private static func proxyDictionary(from raw: String) -> [String: Any]? {
        guard let url = URL(string: raw), let host = url.host else { return nil }
        let scheme = (url.scheme ?? "http").lowercased()
        let port = url.port ?? (scheme.hasPrefix("socks") ? 1080 : 80)
        if scheme.hasPrefix("socks") {
            return [
                "SOCKSEnable": 1,
                "SOCKSProxy": host,
                "SOCKSPort": port,
            ] as [String: Any]
        }
        return [
            "HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
            "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port,
        ] as [String: Any]
    }

    func setProxy(_ raw: String) {
        proxyString = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        session = URLSession(
            configuration: Self.makeConfiguration(profile: profile, proxy: proxyString)
        )
    }

    var currentProxy: String { proxyString }

    static func isJSON(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
    }

    /// 发起请求，返回 (HTTP 状态码, 响应文本)。
    /// requireJSON = true 时，遇到非 JSON（拦截页）自动重试并给出可读错误。
    @discardableResult
    func request(
        _ urlString: String,
        method: String = "GET",
        json: [String: Any]? = nil,
        headers: [String: String] = [:],
        label: String = "请求",
        requireJSON: Bool = true,
        retries: Int = 3
    ) async throws -> (Int, String) {
        guard let url = URL(string: urlString) else { throw KSError.invalidURL(urlString) }

        let attempts = max(1, retries)
        var lastStatus = 0
        var lastBody = ""

        for attempt in 0..<attempts {
            var req = URLRequest(url: url)
            req.httpMethod = method
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            if let json = json {
                req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])
            }

            let (data, response) = try await session.data(for: req)
            lastStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastBody = String(data: data, encoding: .utf8) ?? ""

            if !requireJSON || Self.isJSON(lastBody) {
                return (lastStatus, lastBody)
            }
            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: UInt64(800_000_000) * UInt64(attempt + 1))
            }
        }

        if requireJSON {
            let preview = lastBody
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(160)
                .replacingOccurrences(of: "\n", with: " ")
            throw KSError.nonJSONResponse(
                label: label, status: lastStatus, preview: String(preview)
            )
        }
        return (lastStatus, lastBody)
    }

    /// 请求并解析成 JSON 对象
    func json(
        _ urlString: String,
        method: String = "GET",
        json body: [String: Any]? = nil,
        headers: [String: String] = [:],
        label: String = "请求"
    ) async throws -> [String: Any] {
        let (status, text) = try await request(
            urlString, method: method, json: body, headers: headers, label: label
        )
        guard (200...299).contains(status) else {
            throw KSError.badStatus(status, String(text.prefix(120)))
        }
        guard let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw KSError.api("\(label) 返回的不是 JSON 对象")
        }
        return obj
    }
}
