import Foundation

/// mail.tm 临时邮箱客户端。
/// mail.tm 对建号有频率限制（间歇性 429，有时表现为「用户名不合法」），
/// 因此带 15 次递增退避重试 + 每次换随机用户名（与安卓/PC 端一致）。
final class TempMail {

    private let base = "https://api.mail.tm"
    private let http = HTTPClient.mailtm

    private(set) var address = ""
    private var password = ""
    private var token = ""

    private static func randomHex(_ count: Int) -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(count))
    }

    private func getDomain() async throws -> String {
        for i in 0..<5 {
            do {
                let (_, body) = try await http.request(
                    "\(base)/domains", label: "邮箱域名", requireJSON: true
                )
                if let obj = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                   let members = obj["hydra:member"] as? [[String: Any]] {
                    let active = members.compactMap { m -> String? in
                        guard (m["isActive"] as? Bool) == true else { return nil }
                        return m["domain"] as? String
                    }
                    if let pick = active.randomElement() { return pick }
                }
            } catch {
                // 继续重试
            }
            try? await Task.sleep(nanoseconds: UInt64(2 + i * 2) * 1_000_000_000)
        }
        throw KSError.api("获取临时邮箱域名失败（mail.tm 可能不可用）")
    }

    private func refreshToken() async throws {
        let (status, body) = try await http.request(
            "\(base)/token",
            method: "POST",
            json: ["address": address, "password": password],
            label: "邮箱令牌",
            requireJSON: false
        )
        guard (200...299).contains(status),
              let obj = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let value = obj["token"] as? String,
              !value.isEmpty else {
            throw KSError.api("获取邮箱令牌失败: HTTP \(status) \(body.prefix(120))")
        }
        token = value
    }

    func create(
        maxTry: Int = 15,
        log: @escaping (String) -> Void = { _ in }
    ) async throws {
        let domain = try await getDomain()
        var last = ""
        for attempt in 0..<maxTry {
            address = "kite\(Self.randomHex(12))@\(domain)"
            password = "Kite\(Self.randomHex(10))!"

            let (status, body) = try await http.request(
                "\(base)/accounts",
                method: "POST",
                json: ["address": address, "password": password],
                label: "创建邮箱",
                requireJSON: false
            )
            if status == 201 {
                try await refreshToken()
                return
            }
            last = "HTTP \(status) \(body.prefix(120))"
            if status == 429 || status >= 500 || body.contains("not valid") {
                let wait = (3 + attempt) * (attempt >= 4 ? 2 : 1)
                log("  邮箱创建被限流，\(wait) 秒后重试（\(attempt + 1)/\(maxTry)）...")
                try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                continue
            }
            throw KSError.api("临时邮箱创建失败: \(last)")
        }
        throw KSError.api("临时邮箱创建失败（重试 \(maxTry) 次仍被限流）: \(last)")
    }

    /// 轮询收件箱，返回 6 位邮箱验证码
    func waitForCode(
        timeout: TimeInterval = 120,
        interval: TimeInterval = 3
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var seen = Set<String>()

        while Date() < deadline {
            do {
                let auth = ["Authorization": "Bearer \(token)"]
                let (status, body) = try await http.request(
                    "\(base)/messages", headers: auth,
                    label: "收件箱", requireJSON: false
                )
                if status == 401 {
                    try await refreshToken()
                    continue
                }
                guard let obj = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                      let members = obj["hydra:member"] as? [[String: Any]] else {
                    try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                    continue
                }

                for message in members {
                    let id = JSONStr(message["id"])
                    if id.isEmpty || seen.contains(id) { continue }
                    seen.insert(id)

                    let (_, detailBody) = try await http.request(
                        "\(base)/messages/\(id)", headers: auth,
                        label: "邮件详情", requireJSON: false
                    )
                    guard let detail = try JSONSerialization.jsonObject(
                        with: Data(detailBody.utf8)
                    ) as? [String: Any] else { continue }

                    let text = JSONStr(detail["text"])
                    var html = ""
                    if let lines = detail["html"] as? [String] {
                        html = lines.joined(separator: " ")
                    } else {
                        html = JSONStr(detail["html"])
                    }
                    if let code = Self.extractCode(text + " " + html) {
                        return code
                    }
                }
            } catch {
                // 网络抖动时继续轮询
            }
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        }
        throw KSError.api("等待验证码邮件超时")
    }

    /// 邮件正文含 "Your verification code is XXXXXX"
    static func extractCode(_ content: String) -> String? {
        let patterns = [
            "verification code is\\s*([0-9]{6})",
            "\\b([0-9]{6})\\b",
        ]
        let range = NSRange(content.startIndex..., in: content)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: content, range: range),
                  match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: content) else { continue }
            return String(content[swiftRange])
        }
        return nil
    }
}
