import Foundation
@testable import Spotifly
import Testing

@MainActor @Suite(.serialized) struct SpotifyConnectTests {
    private func api() -> OfficialWebAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConnectFixtureProtocol.self]
        let grant = OfficialGrant(clientID: "fixture", tokens: KeymasterTokens(
            accessToken: "fixture-token", refreshToken: "fixture-refresh", expiresAt: .distantFuture, username: ""), connectEnabled: true)
        return OfficialWebAPI(grant: grant, session: URLSession(configuration: config), persist: { _ in })
    }

    private var speaker: OfficialConnectDevice {
        OfficialConnectDevice(id: "speaker-id", name: "Living Room", type: "speaker", active: true,
                      restricted: false, supportsVolume: true, volume: 35)
    }

    @Test func transferTargetsOneDeviceAndPreservesPlaybackState() throws {
        let command = try OfficialConnectCommand.transfer(to: speaker)
        let data = try #require(command.body)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(command.method == "PUT" && command.path == "/me/player")
        #expect(object["device_ids"] as? [String] == ["speaker-id"])
        #expect(object["play"] == nil)
    }

    @Test func remoteCommandsTargetDeviceAndUseCorrectContextShape() throws {
        let uri = "spotify:playlist:1234567890123456789012"
        let command = try OfficialConnectCommand.playback("play", device: speaker, uri: uri)
        let commandBody = try #require(command.body)
        let object = try #require(JSONSerialization.jsonObject(with: commandBody) as? [String: Any])
        #expect(command.query.first { $0.name == "device_id" }?.value == "speaker-id")
        #expect(object["context_uri"] as? String == uri)
        let track = try OfficialConnectCommand.playback("play", device: speaker, uri: "spotify:track:1234567890123456789012")
        let trackBody = try #require(track.body)
        let trackObject = try #require(JSONSerialization.jsonObject(with: trackBody) as? [String: Any])
        #expect(trackObject["uris"] as? [String] == ["spotify:track:1234567890123456789012"])
        #expect(try OfficialConnectCommand.playback("skip_next", device: speaker).method == "POST")
    }

    @Test func restrictedAndUnidentifiedDevicesCannotBeSelected() {
        let restricted = OfficialConnectDevice.parse(["id": "locked", "name": "TV", "is_restricted": true])
        let unidentified = OfficialConnectDevice.parse(["name": "Unavailable"])
        #expect(!restricted.selectable && !unidentified.selectable)
        #expect(throws: SmalltifyError.self) { try OfficialConnectCommand.transfer(to: restricted) }
        #expect(throws: SmalltifyError.self) { try OfficialConnectCommand.transfer(to: unidentified) }
        #expect(throws: SmalltifyError.self) { try OfficialConnectCommand.playback("seek", device: speaker, value: .nan) }
    }

    @Test func webPlaybackProgressUsesResponseTimeNotOldChangeTimestamp() throws {
        ConnectFixtureProtocol.state.reset()
        let parsed = try OfficialConnectPlayback.parse(ConnectFixtureProtocol.state.playbackData(), now: Date(timeIntervalSince1970: 1000))
        let state = try #require(parsed)
        #expect(state.snapshot.position(at: Date(timeIntervalSince1970: 1002)) == 7000)
        #expect(state.snapshot.title == "Connect Song")
        #expect(state.snapshot.coverURL?.host == "i.scdn.co")
        #expect(try OfficialConnectPlayback.parse(Data()) == nil)
    }

    @Test func localControllerRoutesRemotePauseToWebAPI() async throws {
        ConnectFixtureProtocol.state.reset()
        let connect = SpotifyConnectController(api: api(), authorized: true)
        let local = SoloistController()
        connect.local = local
        local.connect = connect
        await connect.refreshPlayback()
        #expect(local.displaySnapshot.title == "Connect Song")
        #expect(local.canControl)
        try await local.send("pause")
        let request = try #require(ConnectFixtureProtocol.state.commands().last)
        #expect(request.url?.path == "/v1/me/player/pause")
        let requestURL = try #require(request.url)
        #expect(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "device_id" }?.value == "speaker-id")
        #expect(local.displaySnapshot.status == "paused")
        local.snapshot.active = true
        #expect(local.displaySnapshot.uri == local.snapshot.uri)
    }

    @Test func transferIsConfirmedByPlaybackResponse() async throws {
        ConnectFixtureProtocol.state.reset()
        let connect = SpotifyConnectController(api: api(), authorized: true)
        await connect.refreshDevices()
        #expect(connect.devices.count == 2)
        #expect(connect.devices.last?.selectable == false)
        await connect.transfer(to: speaker)
        #expect(connect.error == nil)
        #expect(connect.playback?.device.id == "speaker-id")
        #expect(!connect.transferring)
        #expect(ConnectFixtureProtocol.state.commands().contains { $0.url?.path == "/v1/me/player" })
    }

    @Test func missingConnectGrantDoesNotFetchDevices() async {
        ConnectFixtureProtocol.state.reset()
        let connect = SpotifyConnectController(api: api())
        await connect.refreshDevices()
        await connect.refreshPlayback()
        #expect(ConnectFixtureProtocol.state.requestCount() == 0)
        #expect(!connect.authorized && !connect.canControl)
    }

    @Test func oldStoredGrantStillDecodesWithoutConnectPermission() throws {
        let original = OfficialGrant(clientID: "own", tokens: KeymasterTokens(accessToken: "token", refreshToken: "refresh", expiresAt: .distantFuture, username: ""))
        let restored = try JSONDecoder().decode(OfficialGrant.self, from: JSONEncoder().encode(original))
        #expect(restored.connectEnabled == nil)
    }
}

private final class ConnectFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var playing = true
    func reset() { lock.withLock { requests = []; playing = true } }
    func requestCount() -> Int { lock.withLock { requests.count } }
    func commands() -> [URLRequest] { lock.withLock { requests.filter { $0.httpMethod != "GET" } } }
    func playbackData() -> Data { lock.withLock { stateData() } }
    private func stateData() -> Data {
        Data("""
        {"device":{"id":"speaker-id","name":"Living Room","type":"speaker","is_active":true,"is_restricted":false,"supports_volume":true,"volume_percent":35},
        "is_playing":\(playing),"timestamp":100,"progress_ms":5000,"item":{"uri":"spotify:track:1234567890123456789012","name":"Connect Song","duration_ms":200000,
        "album":{"images":[{"url":"https://i.scdn.co/image/test"}]},"artists":[]}}
        """.utf8)
    }
    func response(_ request: URLRequest) -> (Int, Data) {
        lock.withLock {
            requests.append(request)
            if request.httpMethod == "GET", request.url?.path.hasSuffix("/devices") == true {
                return (200, Data(#"{"devices":[{"id":"speaker-id","name":"Living Room","is_active":true,"supports_volume":true},{"id":null,"name":"Unavailable"}]}"#.utf8))
            }
            if request.httpMethod == "GET" { return (200, stateData()) }
            if request.url?.path.hasSuffix("/pause") == true { playing = false }
            return (204, Data())
        }
    }
}

private final class ConnectFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = ConnectFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let (status, data) = Self.state.response(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
