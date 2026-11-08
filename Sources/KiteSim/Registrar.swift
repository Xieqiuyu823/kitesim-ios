import Foundation

/// 注册 / 登录的编排层，与安卓 MainActivity.doRegister / startLogin 一一对应。
/// 不放 UI 代码，便于单独调用与测试。
final class Registrar {

    static let shared = Registrar()

    private let api = KiteSimAPI.shared
    private var ocr: CaptchaOCR?

    func preloadOCR() throws {
        if ocr == nil { ocr = try CaptchaOCR() }
    }

    private func engine() throws -> CaptchaOCR {
        if let cached = ocr { return cached }
        let created = try CaptchaOCR()
        ocr = created
        return created
    }

    /// 完整注册流程，返回账号
    func register(
        invite: String,
        log: @escaping (String) -> Void
    ) async throws -> Account {
        log("[1/5] 创建临时邮箱...")
        let mail = TempMail()
        try await mail.create { log($0) }
        log("  邮箱: \(mail.address)")

        log("[2/5] 发送邮箱验证码...")
        try await api.sendEmailCode(mail.address)

        log("[3/5] 等待验证码邮件...")
        let emailCode = try await mail.waitForCode()
        log("  邮箱验证码: \(emailCode)")

        log("[4/5] 识别图形验证码...")
        let recognizer = try engine()
        var captchaKey = ""
        var captchaCode = ""
        var lastError = ""
        for i in 1...5 {
            do {
                let captcha = try await api.getCaptcha()
                captchaKey = captcha.key
                captchaCode = try recognizer.recognize(captcha.imageData)
                log("  识别结果(第\(i)次): \(captchaCode.isEmpty ? "(空)" : captchaCode)")
                if captchaCode.count == 4 { break }
            } catch {
                lastError = error.localizedDescription
                log("  识别异常: \(lastError)")
            }
        }
        guard captchaCode.count == 4 else {
            throw KSError.api("图形验证码识别失败: \(lastError)")
        }

        log("[5/5] 提交注册...")
        let password = KiteSimAPI.genPassword()
        return try await api.register(
            email: mail.address,
            password: password,
            emailCode: emailCode,
            captchaKey: captchaKey,
            captchaCode: captchaCode,
            invite: invite
        )
    }

    /// 登录并拉取账号信息，返回 (token, info)
    func login(
        _ account: Account,
        log: @escaping (String) -> Void
    ) async throws -> (String, [String: Any]) {
        try preloadOCR()
        let recognizer = try engine()
        log("正在登录 \(account.email) ...")
        let token = try await api.login(
            email: account.email,
            password: account.password,
            ocr: recognizer,
            log: log
        )
        let info = (try? await api.userInfo(token: token)) ?? [:]
        return (token, info)
    }
}
