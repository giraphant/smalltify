import CryptoKit
import Foundation
import Observation
import Security

@MainActor @Observable final class SoloistController {
    static let binarySHA256 = "3317fccefe7ea2379f9caad6d0c9daddecf69f82736d874c68fd4f464d5aab94"
    static let version = "1.3.10.19 · 2026-10-27"
    var snapshot = SoloistSnapshot()
    var connect: SpotifyConnectController?
    private(set) var connected = false
    private(set) var running = false
    private(set) var starting = false
    private(set) var stopping = false
    var error: String?
    private var process: Process?
    private var receiver: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var generation = UUID()
    private let session = SmalltifyHTTPDelegate.session()
    var displaySnapshot: SoloistSnapshot {
        if let connect, connect.usesRemote, let state = connect.playback { return state.snapshot }
        return snapshot
    }
    var canControl: Bool {
        guard connect?.transferring != true else { return false }
        if let connect, connect.usesRemote { return connect.canControl }
        return connected && snapshot.loggedIn
    }
    var canSetVolume: Bool {
        canControl && (connect?.usesRemote != true || connect?.playback?.device.supportsVolume == true)
    }
    var outputDescription: String {
        if connect?.transferring == true { return "正在切换播放设备…" }
        if let connect, connect.usesRemote, let device = connect.playback?.device { return "当前设备：" + device.name }
        if connected {
            return snapshot.loggedIn ? (snapshot.active ? "当前设备：Smalltify" : "已配对 · 播放器待命") : "等待配对：请在官方 Spotify 的设备列表中选择 Smalltify"
        }
        return running ? "正在连接 Soloist…" : "播放器未启动 · 请打开设置"
    }

    static var dataDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Smalltify/Soloist", directoryHint: .isDirectory)
    }
    static var cacheDirectory: URL {
        URL.cachesDirectory.appending(path: "Smalltify/Soloist", directoryHint: .isDirectory)
    }

    func start(cacheMB: Int) async {
        guard process == nil, !starting, !stopping else { return }
        starting = true
        error = nil
        let run = UUID()
        generation = run
        defer { if generation == run { starting = false } }
        do {
            guard let keyData = SmalltifySecrets.load("soloist-key"),
                  let key = String(data: keyData, encoding: .utf8), !key.isEmpty else {
                throw SmalltifyError("请先在设置中保存 Soloist API Key。")
            }
            let executable = Bundle.main.bundleURL.appending(path: "Contents/Helpers/soloist")
            try Self.verifyBinary(executable)
            for directory in [Self.dataDirectory, Self.cacheDirectory] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            }
            // Never connect to an endpoint left by a previous run.
            for filename in ["ws.addr", "ws.port"] {
                let url = Self.dataDirectory.appending(path: filename)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            let child = Process()
            child.executableURL = executable
            child.arguments = ["--device-name", "Smalltify", "--api-key", key,
                               "--data-dir", Self.dataDirectory.path,
                               "--cache-dir", Self.cacheDirectory.path,
                               "--cache-size", String(min(102400, max(100, cacheMB))),
                               "--initial-volume", "40", "--ws", "127.0.0.1:0"]
            // Soloist's CLI currently requires the key in argv; do not log argv or vendor output.
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            child.terminationHandler = { [weak self] child in
                let status = child.terminationStatus
                Task { @MainActor in self?.didExit(status: status, run: run) }
            }
            try child.run()
            process = child
            running = true
            for _ in 0 ..< 100 {
                try Task.checkCancellation()
                guard run == generation, child.isRunning else { throw SmalltifyError("Soloist 未能启动，请检查 API Key 或更新播放器。") }
                if let portText = try? String(contentsOf: Self.dataDirectory.appending(path: "ws.port"), encoding: .utf8),
                   let address = try? String(contentsOf: Self.dataDirectory.appending(path: "ws.addr"), encoding: .utf8),
                   address.trimmingCharacters(in: .whitespacesAndNewlines) == "127.0.0.1",
                   let port = UInt16(portText.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0,
                   let url = URL(string: "ws://127.0.0.1:\(port)") {
                    receiver = Task { [weak self] in await self?.receiveLoop(url: url, run: run) }
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw SmalltifyError("Soloist 的本机控制接口启动超时，请重试。")
        } catch {
            guard run == generation else { return }
            let message = error.localizedDescription
            await stop()
            self.error = message
        }
    }

    private static func verifyBinary(_ url: URL) throws {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw SmalltifyError("本地构建缺少官方 Soloist，请按 SMALLTIFY.md 的构建说明安装。")
        }
        let digest = SHA256.hash(data: data).map { String($0, radix: 16).leftPaddedHex }.joined()
        guard digest == binarySHA256 else { throw SmalltifyError("Soloist 文件校验失败，已拒绝运行。") }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and identifier \"com.spotify.soloist\" and certificate leaf[subject.OU] = \"2FNC3A47ZF\""
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw SmalltifyError("Soloist 的 Spotify 官方签名验证失败。")
        }
    }

    private func receiveLoop(url: URL, run: UUID) async {
        var delay = 1
        while !Task.isCancelled, generation == run, process?.isRunning == true {
            let task = session.webSocketTask(with: url)
            task.maximumMessageSize = 2 * 1024 * 1024
            socket = task
            debugLog("Soloist", "[WS] connect loopback")
            task.resume()
            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    guard generation == run else { return }
                    let data: Data
                    switch message {
                    case let .string(text): data = Data(text.utf8)
                    case let .data(bytes): data = bytes
                    @unknown default: continue
                    }
                    let wasLoggedIn = snapshot.loggedIn
                    if let message = try snapshot.apply(data) { error = message }
                    if !connected, error == "播放器连接中断，正在重新连接。" { error = nil }
                    connected = true
                    delay = 1
                    if !wasLoggedIn, snapshot.loggedIn {
                        try await send("get_state")
                    }
                }
            } catch {
                if !Task.isCancelled, generation == run {
                    self.error = "播放器连接中断，正在重新连接。"
                }
            }
            task.cancel(with: .goingAway, reason: nil)
            guard generation == run else { return }
            connected = false
            try? await Task.sleep(for: .seconds(delay))
            delay = min(15, delay * 2)
        }
    }

    func send(_ command: String, uri: String? = nil, value: Double? = nil, enabled: Bool? = nil) async throws {
        let playbackCommands = ["play", "pause", "skip_next", "skip_prev", "seek", "set_volume", "set_shuffle", "add_to_queue"]
        if playbackCommands.contains(command), let connect {
            guard !connect.transferring else { throw SmalltifyError("请等待设备切换完成。") }
            if connect.usesRemote {
                try await connect.send(command, uri: uri, value: value, enabled: enabled)
                return
            }
        }
        guard connected, let socket else { throw SmalltifyError("请先启动播放器并完成配对。") }
        var object: [String: Any] = ["type": "command", "command": command]
        if let uri {
            guard CatalogItem.validURI(uri) else { throw SmalltifyError("请输入有效的 Spotify 曲目、专辑或歌单链接。") }
            object["uri"] = uri
        }
        if let value {
            guard value.isFinite else { throw SmalltifyError("无效的播放器参数。") }
            object[command == "seek" ? "position_ms" : "volume"] = Int(max(0, min(value, command == "seek" ? snapshot.durationMS : 100)))
        }
        if let enabled { object["enabled"] = enabled }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { return }
        debugLog("Soloist", "[WS] \(command)")
        try await socket.send(.string(text))
    }

    func control(_ command: String, uri: String? = nil, value: Double? = nil, enabled: Bool? = nil) {
        Task {
            do {
                error = nil
                try await send(command, uri: uri, value: value, enabled: enabled)
            } catch { self.error = error.localizedDescription }
        }
    }

    func stop() async {
        guard !stopping else { return }
        stopping = true
        generation = UUID()
        starting = false
        receiver?.cancel()
        receiver = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        snapshot = SoloistSnapshot()
        let child = process
        if let child, child.isRunning {
            child.terminate()
            for _ in 0 ..< 30 {
                if !child.isRunning { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
        process = nil
        running = false
        stopping = false
    }

    private func didExit(status: Int32, run: UUID) {
        guard generation == run else { return }
        process = nil
        running = false
        starting = false
        connected = false
        receiver?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        snapshot = SoloistSnapshot()
        error = status == 10 ? "Soloist 构建已过期，需要手动更新官方播放器。" : "Soloist 已退出（\(status)），可在设置中重新启动。"
    }
}

private extension String {
    var leftPaddedHex: String { count == 1 ? "0" + self : self }
}

#if DEBUG
    extension SoloistController {
        /// Fixture mode: shows the player as running and paired, with no Soloist process.
        func debugPretendConnected() {
            running = true
            connected = true
        }

        /// Fixture mode: puts the controller in any lifecycle state, with no Soloist process.
        func debugSetLifecycle(running: Bool, starting: Bool = false, stopping: Bool = false, connected: Bool) {
            self.running = running
            self.starting = starting
            self.stopping = stopping
            self.connected = connected
        }
    }
#endif
