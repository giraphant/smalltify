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
    private(set) var pendingDeviceID: String?
    private(set) var queue: [CatalogItem] = []
    private(set) var queuedCurrent: CatalogItem?
    private(set) var queueYear: String?
    private(set) var queueLoading = false
    private(set) var queueError: String?
    private var queueObservation: Task<Void, Never>?
    private var queueGeneration = UUID()
    private var polling: Task<Void, Never>?
    private var refreshingPlayback = false
    private var epoch = UUID()
    private var lastState = Date.distantPast
    private var localDeviceID: String?
    var otherDevices: [OfficialConnectDevice] { devices.filter { $0.id != localDeviceID || localDeviceID == nil } }

    init(api: OfficialWebAPI, authorized: Bool = false) {
        self.api = api
        self.authorized = authorized
    }

    isolated deinit { polling?.cancel(); queueObservation?.cancel() }

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
        queueObservation?.cancel()
        queueObservation = nil
        queueGeneration = UUID()
        queue = []
        queuedCurrent = nil
        queueYear = nil
        queueError = nil
        queueLoading = false
        pendingDeviceID = nil
        localDeviceID = nil
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
        queueObservation = Task { [weak self] in
            let changes = Observations { [weak self] in self?.local?.displaySnapshot.uri ?? "" }
            var previous: String?
            for await uri in changes {
                guard let self, !Task.isCancelled else { return }
                guard uri != previous else { continue }
                previous = uri
                await refreshQueue()
            }
        }
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
            if let own = Self.localDevice(in: devices, cachedID: localDeviceID, localActive: local?.snapshot.active == true) {
                localDeviceID = own.id
            }
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
            #if DEBUG
                if DebugFixtures.isEnabled, let state {
                    var snapshot = state.snapshot
                    snapshot.speed = 0
                    playback = OfficialConnectPlayback(device: state.device, snapshot: snapshot)
                } else {
                    playback = state
                }
            #else
                playback = state
            #endif
            lastState = Date()
        } catch {
            if generation == epoch, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func transfer(to device: OfficialConnectDevice) async {
        guard authorized, !transferring, !commanding else { return }
        let generation = epoch
        transferring = true
        pendingDeviceID = device.id
        error = nil
        defer { if generation == epoch { transferring = false; pendingDeviceID = nil } }
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
            if generation == epoch { error = "\(device.name)没有确认切换。" }
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

    func send(_ command: String, uri: String?, value: Double?, enabled: Bool?, context: PlaybackContext? = nil, repeatMode: String? = nil) async throws {
        guard canControl, let device = playback?.device else { throw SmalltifyError("请刷新 Connect 设备状态后重试。") }
        let generation = epoch
        commanding = true
        defer { if generation == epoch { commanding = false } }
        let request = try OfficialConnectCommand.playback(command, device: device, uri: uri, value: value, enabled: enabled, context: context, repeatMode: repeatMode)
        try await api.sendPlayer(method: request.method, path: request.path, query: request.query, body: request.body)
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
        // HTTP 204 accepts a command; only a state response changes what the player displays.
        await refreshPlayback()
    }

    /// Returns false only when Soloist must handle the selected track without its context.
    func playInContext(uri: String, context: PlaybackContext) async throws -> Bool {
        guard authorized else { return false }
        guard !transferring, !commanding else { throw SmalltifyError("请等待设备切换或播放操作完成。") }
        let generation = epoch
        let remote = usesRemote ? playback?.device : nil
        if remote != nil, !canControl { throw SmalltifyError("请刷新 Connect 设备状态后重试。") }
        commanding = true
        defer { if generation == epoch { commanding = false } }
        let device: OfficialConnectDevice
        if let remote {
            device = remote
        } else {
            guard let local, local.connected, local.snapshot.loggedIn else { return false }
            await refreshDevices()
            if Self.localDevice(in: devices, cachedID: localDeviceID, localActive: local.snapshot.active) == nil,
               !local.snapshot.active {
                try await local.send("activate")
                for _ in 0 ..< 6 {
                    try Task.checkCancellation()
                    guard generation == epoch else { throw CancellationError() }
                    await refreshDevices()
                    if local.snapshot.active { break }
                    try await Task.sleep(for: .milliseconds(300))
                }
            }
            guard let found = Self.localDevice(in: devices, cachedID: localDeviceID, localActive: local.snapshot.active) else { return false }
            localDeviceID = found.id
            device = found
        }
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
        let request = try OfficialConnectCommand.playback("play", device: device, uri: uri, context: context)
        do {
            try await api.sendPlayer(method: request.method, path: request.path, query: request.query, body: request.body)
        } catch {
            // Only an offset rejection merits retrying with the visible list. Authentication,
            // throttling and transport failures must not silently start another request.
            guard OfficialConnectCommand.supportsOffset(context.uri), !context.upcoming.isEmpty,
                  let failure = error as? SmalltifyError,
                  failure.reason == .forbidden || failure.localizedDescription.contains("HTTP 400") || failure.localizedDescription.contains("HTTP 404") else { throw error }
            guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
            let fallback = try OfficialConnectCommand.playback("play", device: device, uri: uri, context: context, useOffset: false)
            try await api.sendPlayer(method: fallback.method, path: fallback.path, query: fallback.query, body: fallback.body)
        }
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
        await refreshPlayback()
        return true
    }

    nonisolated static func localDevice(in devices: [OfficialConnectDevice], cachedID: String?, localActive: Bool) -> OfficialConnectDevice? {
        let candidates = devices.filter { $0.selectable && $0.name == "Smalltify" && $0.type.lowercased() == "computer" }
        if let cachedID, let known = candidates.first(where: { $0.id == cachedID }) { return known }
        guard localActive else { return nil }
        let active = candidates.filter(\.active)
        // A name alone could identify another Mac running Smalltify. Trust an active match
        // only when Soloist independently says this Mac is active, and never pick an ambiguity.
        return active.count == 1 ? active.first : nil
    }

    func refreshQueue() async {
        guard authorized else { return }
        let generation = UUID()
        queueGeneration = generation
        let trackURI = local?.displaySnapshot.uri ?? ""
        queue = []
        queuedCurrent = nil
        queueYear = nil
        queueLoading = false
        queueError = nil
        guard !trackURI.isEmpty else { return }
        queueLoading = true
        defer { if queueGeneration == generation { queueLoading = false } }
        do {
            let data = try await api.get(OfficialWebAPI.apiURL(path: "/me/player/queue"))
            let result = try Self.parseQueue(data)
            guard queueGeneration == generation, !Task.isCancelled,
                  trackURI == (local?.displaySnapshot.uri ?? "") else { return }
            queue = result.items
            queuedCurrent = result.current
            queueYear = result.year
        } catch {
            if queueGeneration == generation, !Task.isCancelled, trackURI == (local?.displaySnapshot.uri ?? "") {
                queueError = error.localizedDescription
            }
        }
    }

    nonisolated static func parseQueue(_ data: Data) throws -> (items: [CatalogItem], current: CatalogItem?, year: String?) {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["queue"] as? [[String: Any]] else {
            throw SmalltifyError("Spotify 队列格式无效。")
        }
        let current = object["currently_playing"] as? [String: Any]
        let album = current?["album"] as? [String: Any]
        // Repeated tracks are separate queue entries, so their order and duplicates stay intact.
        return (Array(entries.compactMap { CatalogItem.parse($0) }.prefix(10)),
                current.flatMap { CatalogItem.parse($0) },
                (album?["release_date"] as? String).map { String($0.prefix(4)) })
    }
}

#if DEBUG
    extension SpotifyConnectController {
        func debugSetPlayback(_ playback: OfficialConnectPlayback, pending: String? = nil) {
            self.playback = playback
            lastState = .now
            pendingDeviceID = pending
            transferring = pending != nil
        }
    }
#endif
