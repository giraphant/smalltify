import Foundation

nonisolated enum ClientIDValidation: Equatable {
    case empty, valid, invalid(String)

    init(_ input: String) {
        let id = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { self = .empty }
        else if id.count != 32 {
            self = .invalid("Client ID 应为 32 位十六进制字符，当前\(id.count < 32 ? "只有" : "有") \(id.count) 位。")
        } else if !id.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0) }) {
            self = .invalid("Client ID 应为 32 位十六进制字符，只能包含 0–9、a–f。")
        } else { self = .valid }
    }
}

nonisolated struct SoloistBuild: Equatable {
    let version: String
    let date: Date

    init?(_ text: String) {
        let parts = text.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty,
              let date = try? Date(parts[1], strategy: .iso8601.year().month().day().dateSeparator(.dash)) else { return nil }
        version = parts[0]
        self.date = date
    }

    func daysRemaining(at now: Date = .now) -> Int {
        Int(ceil(date.addingTimeInterval(90 * 86400).timeIntervalSince(now) / 86400))
    }
}

nonisolated struct SettingsStatus: Equatable {
    enum Tone: Equatable { case neutral, success, warning, error }
    let title: String
    let tone: Tone
    var message: String?

    static func authorization(clientID: String, signedIn: Bool, authorizing: Bool,
                              expired: Bool, name: String?, error: String?) -> Self {
        if authorizing { return Self(title: "正在浏览器中授权…", tone: .warning) }
        if case let .invalid(message) = ClientIDValidation(clientID) {
            return Self(title: "Client ID 格式不对", tone: .error, message: message)
        }
        if expired {
            return Self(title: "登录已过期", tone: .error, message: "授权已失效，文库和设备功能暂停。重新授权后继续。")
        }
        if let error { return Self(title: "授权失败", tone: .error, message: error) }
        if signedIn { return Self(title: name.map { "已授权 · \($0)" } ?? "已授权", tone: .success) }
        return Self(title: "未授权", tone: .neutral)
    }

    static func player(running: Bool, starting: Bool, stopping: Bool, hasKey: Bool,
                       expired: Bool, error: String?) -> Self {
        if stopping { return Self(title: "停止中…", tone: .warning) }
        if starting { return Self(title: "启动中…", tone: .warning) }
        if expired {
            return Self(title: "版本已过期", tone: .error,
                        message: "这个 Soloist 版本已过期（每个版本约 90 天有效）。请下载新版本后替换。")
        }
        if let error { return Self(title: "播放器出错", tone: .error, message: error) }
        if !hasKey { return Self(title: "未填写 API Key", tone: .neutral) }
        return Self(title: running ? "运行中" : "已停止", tone: running ? .success : .neutral)
    }

    static func pairing(running: Bool, starting: Bool, stopping: Bool, loggedIn: Bool) -> Self {
        if loggedIn {
            return Self(title: "已配对", tone: .success, message: "已在 Spotify 设备列表中选过「Smalltify」，配对会一直保留。")
        }
        if running, !starting, !stopping {
            return Self(title: "等待配对", tone: .warning, message: "打开官方 Spotify，在设备列表里选择「Smalltify」。只需要做一次。")
        }
        return Self(title: "等待播放器", tone: .neutral,
                    message: "播放器启动后，在官方 Spotify 的设备列表里选择「Smalltify」完成配对。只需要做一次。")
    }
}
