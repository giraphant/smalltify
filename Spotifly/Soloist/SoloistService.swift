//
//  SoloistService.swift
//  Spotifly
//
//  Runs Spotify Soloist beside the app, as the Connect device that plays lossless.
//

import Foundation
import Observation
import Security

/// Spotify Soloist, Spotify's own headless Connect player, run as a child process.
///
/// Spotifly's own player streams Ogg Vorbis at 320 kbit/s at most: Spotify hands out the keys
/// to its lossless files only to its own players, through its DRM. Soloist is one of them. With
/// it running and preferred, plays go to it over connect-state
/// (`PlaybackViewModel.playbackTarget`), so this app browses and controls while Soloist plays.
///
/// It joins the account this app is signed in to by itself (`SoloistPairing`), as it would when
/// chosen in an official Spotify app's device list, and keeps its own session in `dataDirectory`
/// after that. Its quality, lossless included, is set in an official app, as for any Connect
/// device.
@MainActor @Observable final class SoloistService {
    static let shared = SoloistService()

    /// The name it has in every device list, and how this app finds it in the cluster's.
    static let deviceName = "Smalltify"
    static let cacheSizesGB = [2, 5, 10, 20]

    enum State: Equatable {
        case notConfigured
        case stopped
        case starting
        case waitingForPairing
        case ready
        case failed(String)
    }

    private(set) var state = State.stopped
    private(set) var hasKey = false
    private(set) var pairing = false
    private(set) var pairingError: String?
    var preferred: Bool {
        didSet { UserDefaults.standard.set(preferred, forKey: Self.preferredKey) }
    }

    var cacheGB: Int {
        didSet { UserDefaults.standard.set(cacheGB, forKey: Self.cacheKey) }
    }

    var isRunning: Bool { process != nil }

    private static let preferredKey = "soloistPreferred"
    private static let cacheKey = "soloistCacheGB"
    private var process: Process?
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var generation = UUID()
    private var stopping = false
    /// The WebSocket's port, beside which the pairing server listens.
    private var socketPort: UInt16?
    /// Whether this run has tried signing Soloist in by itself, which it does once.
    private var triedPairing = false
    private let session: URLSession = {
        // Loopback only: no proxy, no cookies, nothing kept.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    private init() {
        let defaults = UserDefaults.standard
        preferred = defaults.object(forKey: Self.preferredKey) as? Bool ?? true
        let saved = defaults.integer(forKey: Self.cacheKey)
        cacheGB = Self.cacheSizesGB.contains(saved) ? saved : 10
        hasKey = !SpotiflyApp.hostsUnitTests && KeychainManager.loadSoloistKey() != nil
        state = hasKey ? .stopped : .notConfigured
    }

    /// The same directories, in the same container, as the earlier Smalltify's: Soloist's device
    /// identity and session live there, so its pairing, and the quality chosen for it, carry over.
    static var dataDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Smalltify/Soloist", directoryHint: .isDirectory)
    }

    static var cacheDirectory: URL {
        URL.cachesDirectory.appending(path: "Smalltify/Soloist", directoryHint: .isDirectory)
    }

    /// The Soloist device to play on, when it is preferred, signed in and in the device list.
    func preferredDeviceId(in devices: [Device]) -> String? {
        guard preferred, state == .ready else { return nil }
        return devices.first { $0.name == Self.deviceName }?.id
    }

    /// Stores a new key, when one is given, and starts Soloist with the stored one.
    func save(key: String) async {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            do {
                try KeychainManager.saveSoloistKey(key)
                hasKey = true
            } catch {
                state = .failed(error.localizedDescription)
                return
            }
        }
        await stop()
        await start()
    }

    func start() async {
        guard !SpotiflyApp.hostsUnitTests, process == nil, state != .starting, !stopping else { return }
        // Soloist's command line takes the key only as an argument, so it is visible to other
        // processes of this user while it runs. It is never logged, nor is Soloist's output.
        guard let key = KeychainManager.loadSoloistKey(), !key.isEmpty else {
            state = .notConfigured
            return
        }
        let run = UUID()
        generation = run
        state = .starting
        do {
            let executable = Bundle.main.bundleURL.appending(path: "Contents/Helpers/soloist")
            try Self.verify(executable)
            for directory in [Self.dataDirectory, Self.cacheDirectory] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            }
            // Never connect to an endpoint a previous run left behind.
            for name in ["ws.addr", "ws.port"] {
                try? FileManager.default.removeItem(at: Self.dataDirectory.appending(path: name))
            }
            let child = Process()
            child.executableURL = executable
            child.arguments = [
                "--device-name", Self.deviceName, "--api-key", key,
                "--data-dir", Self.dataDirectory.path, "--cache-dir", Self.cacheDirectory.path,
                "--cache-size", String(cacheGB * 1024), "--ws", "127.0.0.1:0",
            ]
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            child.terminationHandler = { [weak self] child in
                let status = child.terminationStatus
                Task { @MainActor in self?.exited(status: status, run: run) }
            }
            try child.run()
            process = child
            debugLog("Soloist", "Started")
            for _ in 0 ..< 100 {
                guard run == generation, child.isRunning else { throw SoloistError.didNotStart }
                if let url = Self.socketURL() {
                    socketPort = url.port.flatMap(UInt16.init(exactly:))
                    triedPairing = false
                    pairingError = nil
                    state = .waitingForPairing
                    receiver = Task { [weak self] in await self?.receive(from: url, run: run) }
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw SoloistError.didNotStart
        } catch {
            guard run == generation else { return }
            await stop()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard !stopping else { return }
        stopping = true
        defer { stopping = false }
        generation = UUID()
        receiver?.cancel()
        receiver = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if let child = process, child.isRunning {
            child.terminate()
            for _ in 0 ..< 15 where child.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            debugLog("Soloist", "Stopped")
        }
        process = nil
        socketPort = nil
        state = hasKey ? .stopped : .notConfigured
    }

    /// Signs Soloist in with this app's login, when it is waiting for one.
    func pair() async {
        guard state == .waitingForPairing, !pairing, let socketPort else { return }
        pairing = true
        pairingError = nil
        defer { pairing = false }
        guard let login = StoredCredentialsStore().load() else {
            pairingError = SoloistError.noLogin.localizedDescription
            return
        }
        do {
            try await SoloistPairing.pair(nextTo: socketPort, deviceName: Self.deviceName, login: login, session: session)
            debugLog("Soloist", "Paired")
        } catch {
            debugLog("Soloist", "Pairing failed: \(error.localizedDescription)")
            pairingError = error.localizedDescription
        }
    }

    /// Forgets Soloist's device and session, and starts it again to sign in afresh. Spotify sees
    /// a new device, whose quality is back to its default.
    func reset() async {
        await stop()
        try? FileManager.default.removeItem(at: Self.dataDirectory)
        await start()
    }

    // MARK: - Private

    /// The loopback WebSocket Soloist names in its data directory once it listens.
    private static func socketURL() -> URL? {
        func read(_ name: String) -> String? {
            (try? String(contentsOf: dataDirectory.appending(path: name), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard read("ws.addr") == "127.0.0.1", let port = read("ws.port").flatMap(UInt16.init), port > 0 else {
            return nil
        }
        return URL(string: "ws://127.0.0.1:\(port)")
    }

    /// Follows Soloist's events for whether it is signed in, reconnecting while it runs.
    private func receive(from url: URL, run: UUID) async {
        var delay = 1
        while !Task.isCancelled, run == generation, process?.isRunning == true {
            let task = session.webSocketTask(with: url)
            socket = task
            task.resume()
            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    guard run == generation else { return }
                    let data = switch message {
                    case let .string(text): Data(text.utf8)
                    case let .data(bytes): bytes
                    @unknown default: Data()
                    }
                    if let signedIn = Self.signedIn(fromEvent: data) {
                        state = signedIn ? .ready : .waitingForPairing
                        if !signedIn, !triedPairing {
                            triedPairing = true
                            Task { await pair() }
                        }
                    }
                    delay = 1
                }
            } catch {}
            task.cancel(with: .goingAway, reason: nil)
            guard run == generation else { return }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(15, delay * 2)
        }
    }

    /// Whether an event says Soloist is signed in, for the one event that says: `auth_state`.
    nonisolated static func signedIn(fromEvent data: Data) -> Bool? {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["type"] as? String == "auth_state" else { return nil }
        return event["logged_in"] as? Bool ?? false
    }

    private func exited(status: Int32, run: UUID) {
        guard run == generation else { return }
        generation = UUID()
        receiver?.cancel()
        receiver = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        process = nil
        debugLog("Soloist", "Exited with status \(status)")
        // Soloist builds expire after about 90 days, and say so with status 10.
        state = .failed(status == 10 ? SoloistError.expired.localizedDescription
            : SoloistError.exited(Int(status)).localizedDescription)
    }

    /// Runs only a build carrying Spotify's own signature, as `scripts/stage-soloist.py` checks it.
    /// Not a pinned hash: Spotify rebuilds Soloist every few days, and each build expires 90 days on.
    private static func verify(_ url: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw SoloistError.missing }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = #"anchor apple generic and identifier "com.spotify.soloist" and certificate leaf[subject.OU] = "2FNC3A47ZF""#
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
        else { throw SoloistError.untrusted }
    }
}

nonisolated enum SoloistError: LocalizedError {
    case missing
    case untrusted
    case didNotStart
    case expired
    case exited(Int)
    case noLogin

    var errorDescription: String? {
        switch self {
        case .missing: String(localized: "soloist.error.missing")
        case .untrusted: String(localized: "soloist.error.untrusted")
        case .didNotStart: String(localized: "soloist.error.did_not_start")
        case .expired: String(localized: "soloist.error.expired")
        case let .exited(status): String(localized: "soloist.error.exited \(status)")
        case .noLogin: String(localized: "soloist.error.no_login")
        }
    }
}
