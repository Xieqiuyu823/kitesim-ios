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
        var solved = try await solveCaptcha(log: log)

        log("[5/5] 提交注册...")
        let password = KiteSimAPI.genPassword()
        for attempt in 1...2 {
            do {
                return try await api.register(
                    email: mail.address,
                    password: password,
                    emailCode: emailCode,
                    captchaKey: solved.key,
                    captchaCode: solved.code,
                    invite: invite
                )
            } catch {
                // 服务端也可能判「验证码不正确」（图片本身难认），换一张再提交一次
                let text = error.localizedDescription
                guard attempt == 1, text.contains("验证码") else { throw error }
                log("  服务端判定验证码不正确，换一张重试...")
                solved = try await solveCaptcha(log: log)
            }
        }
        throw KSError.api("注册失败")
    }

    /// 抓 2~3 张验证码分别识别，取「4 位且置信度最高」的那一张提交。
    /// 单张识别不理想时自动换图，比死磕同一张的成功率高很多。
    private func solveCaptcha(log: @escaping (String) -> Void) async throws -> (key: String, code: String) {
        let recognizer = try engine()
        var best: (key: String, code: String, score: Float)?
        var lastText = ""

        for i in 1...3 {
            let captcha = try await api.getCaptcha()
            let result = try recognizer.recognizeDetailed(captcha.imageData)
            let shown = result.code.isEmpty ? "(空)" : result.code
            log("  识别(\(i)/3): \(shown)  置信度 \(String(format: "%.2f", result.score))")

            if result.code.count == KiteSimCaptcha.length {
                if best == nil || result.score > best!.score {
                    best = (captcha.key, result.code, result.score)
                }
                // 够可信就不再浪费一次请求
                if result.score >= 0.80 { break }
            } else {
                lastText = shown
            }
        }

        guard let solved = best else {
            throw KSError.api("图形验证码识别失败：3 次都没读出 \(KiteSimCaptcha.length) 位字符（最后一次：\(lastText)）")
        }
        return (solved.key, solved.code)
    }

    /// 自检用：抓一张验证码并识别，返回原图与结果，方便肉眼对照
    func recognizeOne() async throws -> (image: Data, recognition: CaptchaOCR.Recognition) {
        let captcha = try await api.getCaptcha()
        let result = try engine().recognizeDetailed(captcha.imageData)
        return (captcha.imageData, result)
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
