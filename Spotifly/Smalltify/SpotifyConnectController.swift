import Foundation
import Observation

@MainActor @Observable final class SpotifyConnectController {
    let api: OfficialWebAPI
    weak var local: SoloistController?
    private(set) var authorized: Bool
    private(set) var devices: [OfficialConnectDevice] = []
    private(set) var playback: OfficialConnectPlayback?
    private(set) var loading = false
    private(set) var transferring = false
    private(set) var commanding = false
    var error: String?
    private var polling: Task<Void, Never>?
    private var refreshingPlayback = false
    private var epoch = UUID()
    private var lastState = Date.distantPast

    init(api: OfficialWebAPI, authorized: Bool = false) {
        self.api = api
        self.authorized = authorized
    }

    isolated deinit { polling?.cancel() }

    var usesRemote: Bool {
        authorized && local?.snapshot.active != true && playback?.device.active == true
    }
    var canControl: Bool {
        usesRemote && playback?.device.selectable == true && Date().timeIntervalSince(lastState) < 30
            && !transferring && !commanding
    }

    func setAuthorized(_ authorized: Bool) {
        epoch = UUID()
        polling?.cancel()
        polling = nil
        self.authorized = authorized
        devices = []
        playback = nil
        lastState = .distantPast
        error = nil
        loading = false
        refreshingPlayback = false
        transferring = false
        commanding = false
        if authorized { start() }
    }

    func start() {
        guard authorized, polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refreshPlayback()
                do { try await Task.sleep(for: .seconds(usesRemote ? 5 : 15)) }
                catch { return }
            }
        }
    }

    func refreshDevices() async {
        guard authorized, !loading else { return }
        let generation = epoch
        loading = true
        error = nil
        defer { if generation == epoch { loading = false } }
        do {
            let data = try await api.get(OfficialWebAPI.apiURL(path: "/me/player/devices"))
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = object["devices"] as? [[String: Any]] else {
                throw SmalltifyError("Spotify 设备列表格式无效。")
            }
            guard generation == epoch, !Task.isCancelled else { return }
            devices = list.map(OfficialConnectDevice.parse)
            await refreshPlayback()
        } catch {
            if generation == epoch, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func refreshPlayback() async {
        guard authorized, !refreshingPlayback else { return }
        let generation = epoch
        refreshingPlayback = true
        defer { if generation == epoch { refreshingPlayback = false } }
        do {
            let data = try await api.get(OfficialWebAPI.apiURL(path: "/me/player", query: [.init(name: "additional_types", value: "track,episode")]))
            let state = try OfficialConnectPlayback.parse(data)
            guard generation == epoch, !Task.isCancelled else { return }
            playback = state
            lastState = Date()
        } catch {
            if generation == epoch, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func transfer(to device: OfficialConnectDevice) async {
        guard authorized, !transferring, !commanding else { return }
        let generation = epoch
        transferring = true
        error = nil
        defer { if generation == epoch { transferring = false } }
        do {
            let command = try OfficialConnectCommand.transfer(to: device)
            try await api.sendPlayer(method: command.method, path: command.path, query: command.query, body: command.body)
            for _ in 0 ..< 6 {
                try Task.checkCancellation()
                guard generation == epoch else { return }
                await refreshPlayback()
                if playback?.device.id == device.id, playback?.device.active == true {
                    await refreshDevices()
                    return
                }
                try await Task.sleep(for: .milliseconds(500))
            }
            if generation == epoch { error = "切换请求已发送，目标设备尚未确认。请刷新设备列表。" }
        } catch {
            if generation == epoch, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func activateLocal() async {
        guard !transferring, !commanding, let local, local.connected, local.snapshot.loggedIn else { return }
        let generation = epoch
        transferring = true
        error = nil
        defer { if generation == epoch { transferring = false } }
        do {
            try await local.send("activate")
            for _ in 0 ..< 10 {
                try Task.checkCancellation()
                guard generation == epoch else { return }
                if local.snapshot.active {
                    if authorized { await refreshDevices() }
                    return
                }
                try await Task.sleep(for: .milliseconds(300))
            }
            if generation == epoch { error = "已请求切回本机，等待 Spotify 确认。" }
        } catch {
            if generation == epoch, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func send(_ command: String, uri: String?, value: Double?, enabled: Bool?) async throws {
        guard canControl, let device = playback?.device else { throw SmalltifyError("请刷新 Connect 设备状态后重试。") }
        let generation = epoch
        commanding = true
        defer { if generation == epoch { commanding = false } }
        let request = try OfficialConnectCommand.playback(command, device: device, uri: uri, value: value, enabled: enabled)
        try await api.sendPlayer(method: request.method, path: request.path, query: request.query, body: request.body)
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
        // HTTP 204 accepts a command; only a state response changes what the player displays.
        await refreshPlayback()
    }
}
