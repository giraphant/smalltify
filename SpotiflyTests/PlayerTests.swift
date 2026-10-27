import Foundation
@testable import Spotifly
import Testing

@MainActor @Suite(.serialized) struct PlayerTests {
    private let trackURI = "spotify:track:1234567890123456789012"
    private let albumURI = "spotify:album:abcdefghijklmnopqrstuv"
    private let device = OfficialConnectDevice(id: "speaker", name: "客厅音箱", type: "Speaker", active: true,
                                              restricted: false, supportsVolume: false, volume: 70)

    @Test func contextStartRetainsMarketTrackAndUsesURIOffset() throws {
        for context in [albumURI, "spotify:playlist:abcdefghijklmnopqrstuv"] {
            let command = try OfficialConnectCommand.playback("play", device: device, uri: trackURI,
                                                             context: PlaybackContext(uri: context))
            let body = try #require(command.body)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["context_uri"] as? String == context)
            #expect((object["offset"] as? [String: String])?["uri"] == trackURI)
            #expect(object["uris"] == nil)
            #expect(command.query.contains { $0.name == "device_id" && $0.value == "speaker" })
        }
    }

    @Test func unsupportedCollectionOffsetFallsBackToSelectedTrack() throws {
        let command = try OfficialConnectCommand.playback("play", device: device, uri: trackURI,
                                                         context: PlaybackContext(uri: "spotify:user:listener:collection"))
        let body = try #require(command.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["uris"] as? [String] == [trackURI])
        #expect(object["context_uri"] == nil)
        #expect(!OfficialConnectCommand.supportsOffset("spotify:album:invalid"))
    }

    @Test func collectionAndRejectedOffsetUseVisibleUpcomingTracks() throws {
        let next = "spotify:track:abcdefghijklmnopqrstuv"
        for (uri, useOffset) in [("spotify:user:listener:collection", true), (albumURI, false)] {
            let context = PlaybackContext(uri: uri, upcoming: [trackURI, next, "invalid"])
            let request = try OfficialConnectCommand.playback("play", device: device, uri: trackURI,
                                                             context: context, useOffset: useOffset)
            let body = try #require(request.body)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["uris"] as? [String] == [trackURI, next])
            #expect(object["context_uri"] == nil)
        }
    }

    @Test func localDeviceMatchingRequiresIndependentActivationOrKnownID() {
        let own = OfficialConnectDevice(id: "local", name: "Smalltify", type: "Computer", active: true,
                                        restricted: false, supportsVolume: true, volume: 70)
        let namesake = OfficialConnectDevice(id: "other", name: "Smalltify", type: "Computer", active: true,
                                             restricted: false, supportsVolume: true, volume: 70)
        #expect(SpotifyConnectController.localDevice(in: [device, own], cachedID: nil, localActive: true)?.id == "local")
        #expect(SpotifyConnectController.localDevice(in: [own], cachedID: nil, localActive: false) == nil)
        #expect(SpotifyConnectController.localDevice(in: [own, namesake], cachedID: nil, localActive: true) == nil)
        #expect(SpotifyConnectController.localDevice(in: [own, namesake], cachedID: "local", localActive: false)?.id == "local")
        #expect(SpotifyConnectController.localDevice(in: [device], cachedID: "speaker", localActive: true) == nil)
    }

    @Test func repeatCycleAndLocalCommandOrderAgree() throws {
        var snapshot = SoloistSnapshot()
        for (mode, next, commands, enabled) in [
            ("off", "context", ["set_repeat_track", "set_repeat_context"], [false, false]),
            ("context", "track", ["set_repeat_track", "set_repeat_context"], [false, true]),
            ("track", "off", ["set_repeat_context", "set_repeat_track"], [false, true]),
        ] {
            snapshot.repeatMode = mode
            #expect(snapshot.nextRepeatMode == next)
            let steps = try SoloistController.repeatCommands(mode)
            #expect(steps.map(\.command) == commands)
            #expect(steps.map(\.enabled) == enabled)
            let remote = try OfficialConnectCommand.playback("set_repeat", device: device, repeatMode: mode)
            #expect(remote.method == "PUT" && remote.path == "/me/player/repeat")
            #expect(remote.query.contains { $0.name == "state" && $0.value == mode })
        }
        #expect(throws: SmalltifyError.self) { try SoloistController.repeatCommands("unknown") }
        #expect(throws: SmalltifyError.self) {
            try OfficialConnectCommand.playback("set_repeat", device: device, repeatMode: "unknown")
        }
    }

    @Test func queueKeepsDuplicateMarketIDsAndCapsAtTen() throws {
        let item: [String: Any] = ["uri": trackURI, "name": "潮汐电台", "type": "track",
                                   "linked_from": ["uri": "spotify:track:abcdefghijklmnopqrstuv"],
                                   "album": ["uri": albumURI, "name": "潮汐电台", "release_date": "2024-03-01"]]
        let data = try JSONSerialization.data(withJSONObject: ["currently_playing": item,
                                                               "queue": [["bad": "entry"]] + Array(repeating: item, count: 12)])
        let queue = try SpotifyConnectController.parseQueue(data)
        #expect(queue.items.count == 10)
        #expect(queue.items.allSatisfy { $0.uri == trackURI })
        #expect(queue.current?.album?.uri == albumURI)
        #expect(queue.year == "2024")
        #expect(throws: SmalltifyError.self) { try SpotifyConnectController.parseQueue(Data("{}".utf8)) }
    }

    @Test func soloistParentClearsWhenTrackChangesAndOptionsDoNotClearTrack() throws {
        var snapshot = SoloistSnapshot()
        let entity: [String: Any] = ["uri": trackURI, "decorations": [
            "identity": ["name": "潮汐电台"],
            "parent": ["entity": ["uri": albumURI, "decorations": ["identity": ["name": "专辑"]]]],
        ]]
        _ = try snapshot.apply(JSONSerialization.data(withJSONObject: ["type": "track_changed", "item": entity]))
        #expect(snapshot.album?.uri == albumURI)
        _ = try snapshot.apply(Data(#"{"type":"options_changed","options":{"repeat":"track","shuffle":true}}"#.utf8))
        #expect(snapshot.repeatMode == "track" && snapshot.shuffle)
        #expect(snapshot.uri == trackURI)
        _ = try snapshot.apply(Data(#"{"type":"track_changed","item":{}}"#.utf8))
        #expect(snapshot.album == nil && !snapshot.hasTrack)
    }

    @Test func remoteStateCarriesAlbumAndVolumeRestriction() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "device": ["id": "speaker", "is_active": true, "supports_volume": false],
            "is_playing": true, "repeat_state": "context",
            "item": ["uri": trackURI, "name": "潮汐电台", "type": "track", "duration_ms": 238_000,
                     "album": ["uri": albumURI, "name": "潮汐电台", "release_date": "2024-03-01"]],
        ])
        let state = try #require(try OfficialConnectPlayback.parse(data))
        #expect(state.snapshot.album?.name == "潮汐电台")
        #expect(state.snapshot.releaseYear == "2024")
        #expect(state.snapshot.repeatMode == "context")
        #expect(!state.device.supportsVolume)
        #expect(throws: SmalltifyError.self) { try OfficialConnectCommand.playback("set_volume", device: state.device, value: 80) }
    }

    @Test func deviceReasonsDistinguishMissingIDFromRestricted() {
        let missing = OfficialConnectDevice.parse(["name": "卧室电视", "type": "TV"])
        let restricted = OfficialConnectDevice.parse(["id": "car", "name": "车载音响", "is_restricted": true])
        #expect(missing.note == "此设备不支持远程控制")
        #expect(restricted.note == "受限设备：只能在设备本身上操作")
        #expect(!missing.selectable && !restricted.selectable)
    }
    private func controllers() -> (SoloistController, SpotifyConnectController) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlayerFixtureProtocol.self]
        let grant = OfficialGrant(clientID: "fixture", tokens: KeymasterTokens(
            accessToken: "fixture", refreshToken: "fixture", expiresAt: .distantFuture, username: ""), connectEnabled: true)
        let api = OfficialWebAPI(grant: grant, session: URLSession(configuration: configuration), persist: { _ in })
        let local = SoloistController()
        local.debugPretendConnected()
        local.snapshot = SoloistSnapshot(loggedIn: true, active: true, uri: trackURI)
        let connect = SpotifyConnectController(api: api, authorized: true)
        connect.local = local
        local.connect = connect
        return (local, connect)
    }

    private func waitForQueueRequests(_ count: Int) async throws {
        let deadline = Date().addingTimeInterval(3)
        while PlayerFixtureProtocol.state.queueCount < count, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(PlayerFixtureProtocol.state.queueCount == count)
    }

    @Test func lateQueueCannotReplaceNewTrackAndSignOutClearsPendingLoad() async throws {
        PlayerFixtureProtocol.state.reset()
        let (local, connect) = controllers()
        let first = Task { await connect.refreshQueue() }
        try await waitForQueueRequests(1)
        local.snapshot.uri = "spotify:track:abcdefghijklmnopqrstuv"
        let second = Task { await connect.refreshQueue() }
        try await waitForQueueRequests(2)
        PlayerFixtureProtocol.state.replyQueue(1, uri: local.snapshot.uri, name: "new")
        await second.value
        PlayerFixtureProtocol.state.replyQueue(0, uri: trackURI, name: "old")
        await first.value
        #expect(connect.queue.first?.name == "new")
        let pending = Task { await connect.refreshQueue() }
        try await waitForQueueRequests(3)
        connect.setAuthorized(false)
        PlayerFixtureProtocol.state.replyQueue(2, uri: local.snapshot.uri, name: "late")
        await pending.value
        #expect(connect.queue.isEmpty && !connect.queueLoading && connect.queuedCurrent == nil)
    }

    @Test func localContextPlaybackFindsThisMacAndRetriesRejectedOffsetWithVisibleList() async throws {
        PlayerFixtureProtocol.state.reset(rejectOffset: true)
        let (local, connect) = controllers()
        let context = PlaybackContext(uri: albumURI, upcoming: [trackURI, "spotify:track:abcdefghijklmnopqrstuv"])
        #expect(try await connect.playInContext(uri: trackURI, context: context))
        let commands = PlayerFixtureProtocol.state.commands
        #expect(commands.count == 2)
        #expect(commands.allSatisfy { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.contains {
                $0.name == "device_id" && $0.value == "this-mac"
            } == true
        })
        let first = try #require(commands.first?.httpBody)
        let second = try #require(commands.last?.httpBody)
        let offset = try #require(JSONSerialization.jsonObject(with: first) as? [String: Any])
        let list = try #require(JSONSerialization.jsonObject(with: second) as? [String: Any])
        #expect(offset["context_uri"] as? String == albumURI)
        #expect(list["uris"] as? [String] == context.upcoming)
        #expect(local.snapshot.active)
        #expect(connect.otherDevices.isEmpty)
    }

}


private final class PlayerFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [PlayerFixtureProtocol] = []
    private var requests: [URLRequest] = []
    private var rejectOffset = false
    var queueCount: Int { lock.withLock { queues.count } }
    var commands: [URLRequest] { lock.withLock { requests.filter { $0.httpMethod == "PUT" } } }

    func reset(rejectOffset: Bool = false) {
        lock.withLock { queues = []; requests = []; self.rejectOffset = rejectOffset }
    }

    func receive(_ client: PlayerFixtureProtocol) {
        let response: (Int, Data)? = lock.withLock {
            var request = client.request
            if request.httpBody == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                request.httpBody = data
            }
            requests.append(request)
            if request.url?.path.hasSuffix("/queue") == true {
                queues.append(client)
                return nil
            }
            if request.url?.path.hasSuffix("/devices") == true {
                return (200, Data(#"{"devices":[{"id":"this-mac","name":"Smalltify","type":"Computer","is_active":true,"supports_volume":true}]}"#.utf8))
            }
            if request.httpMethod == "PUT", rejectOffset {
                rejectOffset = false
                return (400, Data())
            }
            return (204, Data())
        }
        if let response { client.respond(status: response.0, data: response.1) }
    }

    func replyQueue(_ index: Int, uri: String, name: String) {
        let client = lock.withLock { queues.indices.contains(index) ? queues[index] : nil }
        let item = ["uri": uri, "type": "track", "name": name]
        let data = try? JSONSerialization.data(withJSONObject: ["currently_playing": item, "queue": [item]])
        client?.respond(status: 200, data: data ?? Data())
    }
}

private final class PlayerFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = PlayerFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.state.receive(self) }
    override func stopLoading() {}

    func respond(status: Int, data: Data) {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: [:]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
