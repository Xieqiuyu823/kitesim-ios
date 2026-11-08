import Foundation

// MARK: - 账号模型（字段与 PC 端 accounts.jsonl 完全一致，方便互导）

struct Account: Codable, Identifiable, Equatable {
    var email: String
    var password: String
    var invite: String
    var createdAt: String

    var id: String { email }

    enum CodingKeys: String, CodingKey {
        case email, password, invite
        case createdAt = "created_at"
    }

    var clipboardText: String { "\(email) / \(password)" }
}

// MARK: - 账号持久化（JSONL，清空前自动备份）

final class AccountStore {
    private let fileURL: URL
    private(set) var accounts: [Account] = []

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("accounts.jsonl")
        load()
    }

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        accounts = text.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? decoder.decode(Account.self, from: data)
        }
    }

    func add(_ account: Account) {
        accounts.insert(account, at: 0)
        persist()
    }

    func clear() {
        if !accounts.isEmpty, FileManager.default.fileExists(atPath: fileURL.path) {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd-HHmmss"
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("accounts.backup-\(fmt.string(from: Date())).jsonl")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
        accounts = []
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func persist() {
        let encoder = JSONEncoder()
        let lines = accounts.compactMap { account -> String? in
            guard let data = try? encoder.encode(account),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        }
        let body = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? body.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - App 资源定位（兼容资源位于 bundle 根目录或 Resources/ 子目录）

// Xcode App target 不会生成 SwiftPM 的 Bundle.module；统一从 Bundle.main 查找，
// 同一份源码因此既能用于 Xcode/xcodebuild，也保留对 SwiftPM App 打包的兼容性。
enum BundleResource {
    static func url(_ name: String, _ ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle.main.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Resources"
        )
    }
}
