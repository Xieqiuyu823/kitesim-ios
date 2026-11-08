import Foundation

struct Captcha {
    let key: String
    let imageData: Data
}

/// KiteSim 接口封装。接口来自 h5.kitesim.co 前端逆向，详见项目根目录《项目交接说明（给AI）.md》§4。
///
/// ⚠️ 最重要的一条：**注册 / 登录提交明文密码**。
/// 前端 SimpleCrypto（字符串反转 + 每字符 charCode+3）只用于「记住密码」的本地缓存，
/// 用它处理提交值会导致服务端存入加密串，之后在官方页面永远提示「密码不正确」。
final class KiteSimAPI {

    static let shared = KiteSimAPI()

    private let base = "https://api.kitesim.co"
    private let h5 = "https://h5.kitesim.co"
    private let http = HTTPClient.kitesim

    /// 8~20 位，含大小写字母 + 数字；刻意排除易混淆字符 0 O o 1 l I
    static func genPassword() -> String {
        let lower = Array("abcdefghijkmnpqrstuvwxyz")
        let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let digits = Array("23456789")
        let all = lower + upper + digits
        while true {
            let pw = String((0..<12).compactMap { _ in all.randomElement() })
            if pw.contains(where: { $0.isLowercase }),
               pw.contains(where: { $0.isUppercase }),
               pw.contains(where: { $0.isNumber }) {
                return pw
            }
        }
    }

    /// 对齐 uni.getSystemInfoSync().deviceId 的 32 位十六进制串
    static func genDeviceId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    // MARK: 验证码

    func getCaptcha() async throws -> Captcha {
        let (_, body) = try await http.request(
            "\(base)/index/captcha-image-base64", label: "获取验证码"
        )
        guard let obj = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let key = obj["captchaKey"] as? String,
              var b64 = obj["captchaImageBase64"] as? String else {
            throw KSError.api("验证码响应格式异常")
        }
        // 兼容 data:image/png;base64,xxxx 形式
        if let comma = b64.firstIndex(of: ",") {
            b64 = String(b64[b64.index(after: comma)...])
        }
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
            throw KSError.api("验证码图片 base64 解码失败")
        }
        return Captcha(key: key, imageData: data)
    }

    // MARK: 注册

    func sendEmailCode(_ email: String) async throws {
        let obj = try await http.json(
            "\(base)/index/send-email",
            method: "POST",
            json: ["email": email],
            label: "发送验证码"
        )
        guard JSONInt(obj["code"]) == 200 else {
            throw KSError.api("发送验证码失败: \(JSONStr(obj["message"]))")
        }
    }

    func register(
        email: String,
        password: String,
        emailCode: String,
        captchaKey: String,
        captchaCode: String,
        invite: String
    ) async throws -> Account {
        let payload: [String: Any] = [
            "email": email,
            "pass": password,              // 明文提交
            "code": emailCode,
            "invite": invite,
            "captchaCode": captchaCode,
            "captchaKey": captchaKey,
            "deviceId": KiteSimAPI.genDeviceId(),
        ]
        let obj = try await http.json(
            "\(base)/index/sign-up", method: "POST", json: payload, label: "注册"
        )
        guard JSONInt(obj["code"]) == 200 else {
            throw KSError.api("注册失败: \(JSONStr(obj["message"]))")
        }
        return Account(
            email: email,
            password: password,
            invite: invite,
            createdAt: KiteSimAPI.now()
        )
    }

    // MARK: 登录

    /// 自动识别图形验证码，失败自动换图重试；返回 token
    func login(
        email: String,
        password: String,
        ocr: CaptchaOCR,
        maxTry: Int = 8,
        log: @escaping (String) -> Void = { _ in }
    ) async throws -> String {
        var lastError = ""
        for i in 0..<maxTry {
            let captcha = try await getCaptcha()
            let code = try ocr.recognize(captcha.imageData)
            if code.count != 4 { continue }

            let obj = try await http.json(
                "\(base)/index/sign-in",
                method: "POST",
                json: [
                    "email": email,
                    "pass": password,      // 明文提交
                    "captchaCode": code,
                    "captchaKey": captcha.key,
                ],
                label: "登录"
            )
            if JSONInt(obj["code"]) == 200 {
                log("  登录成功")
                return JSONStr(obj["data"])
            }
            let msg = JSONStr(obj["message"])
            lastError = "\(msg)（code=\(JSONInt(obj["code"]))）"
            // 密码错误等确定性错误直接抛出，不浪费重试次数
            if !msg.contains("验证码") { break }
            log("  验证码识别偏差，换一张重试（\(i + 1)/\(maxTry)）")
        }
        throw KSError.api("登录失败: \(lastError)")
    }

    func userInfo(token: String) async throws -> [String: Any] {
        let obj = try await http.json(
            "\(base)/user/info", headers: ["token": token], label: "获取账号信息"
        )
        return obj["data"] as? [String: Any] ?? [:]
    }

    // MARK: 网络自检（对应安卓 v1.4 的「网络自检」按钮）

    func selfTest() async -> String {
        let targets: [(url: String, label: String, expectJSON: Bool)] = [
            ("\(h5)/", "官网页面(应为 HTML)", false),
            ("\(base)/index/captcha-image-base64", "KiteSim 接口(应为 JSON)", true),
            ("https://api.mail.tm/domains", "临时邮箱接口(应为 JSON)", true),
        ]
        var report = ""
        for target in targets {
            do {
                let (status, body) = try await HTTPClient.plain.request(
                    target.url, label: target.label, requireJSON: false
                )
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                let kind = HTTPClient.isJSON(body)
                    ? "JSON"
                    : (trimmed.hasPrefix("<") ? "HTML" : "其他")
                report += "\(target.label)\n  HTTP \(status)  类型=\(kind)\n"
                if target.expectJSON && kind != "JSON" {
                    report += "  内容: \(trimmed.prefix(120).replacingOccurrences(of: "\n", with: " "))\n"
                }
            } catch {
                report += "\(target.label)\n  异常: \(error.localizedDescription)\n"
            }
        }
        return report
    }

    // MARK: 地区检测（KiteSim 对部分地区返回 403「该地区暂不提供服务」）

    func checkRegion(token: String) async -> (ok: Bool, detail: [String]) {
        var detail: [String] = []
        var ok = false
        do {
            let headers = [
                "token": token,
                "Referer": "\(h5)/",
                "Origin": h5,
            ]
            let list = try await http.json(
                "\(base)/esimIpCountry/page?pageNumber=1&pageSize=100",
                headers: headers, label: "国家列表"
            )
            let data = list["data"] as? [String: Any] ?? [:]
            let records = data["records"] as? [[String: Any]] ?? []
            guard !records.isEmpty else {
                return (false, ["国家列表异常: \(String(describing: list).prefix(120))"])
            }
            for item in records.prefix(4) {
                let cc = JSONStr(item["twoWordsCode"])
                let cid = JSONStr(item["categoryId"])
                let name = JSONStr(item["countryZhCn"]).isEmpty ? cc : JSONStr(item["countryZhCn"])
                do {
                    let r = try await http.json(
                        "\(base)/esimPackage/esimPackageListByCategoryId" +
                        "?categoryId=\(cid)&type=0&countryCode=\(cc)&packageType=0",
                        headers: headers, label: "套餐-\(name)"
                    )
                    let code = JSONInt(r["code"])
                    if code == 200 {
                        ok = true
                        detail.append("\(name): 可用（code=200）")
                    } else {
                        detail.append("\(name): \(JSONStr(r["message"]))（code=\(code)）")
                    }
                } catch {
                    detail.append("\(name): 请求异常 \(error.localizedDescription)")
                }
            }
        } catch {
            detail.append("检测失败: \(error.localizedDescription)")
        }
        return (ok, detail)
    }
}
