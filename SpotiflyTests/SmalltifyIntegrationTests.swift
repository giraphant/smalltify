import Darwin
import Foundation
@testable import Spotifly
import Testing

struct SmalltifyProtocolTests {
    let trackID = "1234567890123456789012"

    @Test func ownClientUsesPKCEAndReadOnlyScopes() throws {
        let url = try OfficialWebAPI.authorizationURL(clientID: "own-client", port: SmalltifyOAuth.callbackPort, verifier: "verifier", state: "state")
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["client_id"] == "own-client")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == PKCE.codeChallenge(for: "verifier"))
        #expect(query["redirect_uri"] == "http://127.0.0.1:43821/login")
        #expect(query["scope"]?.contains("modify") == false)
        #expect(query["client_secret"] == nil)
    }

    @Test func dashboardAndAuthorizationUseTheSameExplicitPort() throws {
        #expect(SmalltifyOAuth.redirectURI == "http://127.0.0.1:43821/login")
        let url = try OfficialWebAPI.authorizationURL(clientID: "own-client", port: SmalltifyOAuth.callbackPort, verifier: "v", state: "s")
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.queryItems?.first { $0.name == "redirect_uri" }?.value == SmalltifyOAuth.redirectURI)
    }

    @Test func loopbackListenerHonorsAnExplicitPort() async throws {
        // A synchronous socket close avoids racing NWListener's asynchronous cancellation.
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let allocated = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, length) == 0 && getsockname(descriptor, socketAddress, &length) == 0
            }
        }
        let port = UInt16(bigEndian: address.sin_port)
        close(descriptor)
        #expect(allocated && port != 0)
        guard allocated, port != 0 else { return }
        let server = LoopbackCallbackServer()
        do {
            let actual = try await server.start(port: port)
            #expect(actual == port)
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    @Test func searchQueryIsEncodedAsOneValue() throws {
        let text = "Björk & type=playlist / ?#"
        let url = try OfficialWebAPI.apiURL(path: "/search", query: [.init(name: "q", value: text)])
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.queryItems?.count == 1)
        #expect(parts.queryItems?.first?.value == text)
    }

    @Test(arguments: ["http://api.spotify.com/v1/me", "https://api.spotify.com.evil.test/v1/me", "https://user@api.spotify.com/v1/me", "https://api.spotify.com:444/v1/me", "https://api.spotify.com/v1/../token", "https://evil.test/v1/me"])
    func unsafePaginationURLsAreRejected(_ text: String) throws {
        #expect(!OfficialWebAPI.allowedAPIURL(try #require(URL(string: text))))
    }

    @Test func officialPlaylistItemsAndRelinkedTracksKeepMarketIdentity() throws {
        let data = Data("""
        {"items":[null,{"item":null},{"item":{"uri":"spotify:track:\(trackID)","id":"\(trackID)","name":"Song","type":"track","linked_from":{"id":"original"}}},{"track":{"uri":"spotify:track:\(trackID)","name":"Duplicate","type":"track"}}],"next":"https://api.spotify.com/v1/me/tracks?offset=50"}
        """.utf8)
        let page = try CatalogPage.parse(data)
        #expect(page.items.count == 2)
        #expect(page.items.first?.spotifyID == trackID)
        #expect(page.next?.host == "api.spotify.com")
    }

    @Test func maliciousPaginationDoesNotEscapeAPIHost() {
        #expect(throws: SmalltifyError.self) {
            try CatalogPage.parse(Data(#"{"items":[],"next":"https://evil.test/collect"}"#.utf8))
        }
    }

    @Test func savedAlbumWrapperDoesNotReplaceTrackWithItsAlbum() throws {
        let data = Data("""
        {"items":[{"album":{"uri":"spotify:album:\(trackID)","name":"Album","type":"album"}},{"uri":"spotify:track:\(trackID)","name":"Song","type":"track","album":{"uri":"spotify:album:\(trackID)","name":"Album","type":"album"}}]}
        """.utf8)
        #expect(try CatalogPage.parse(data).items.map(\.kind) == ["album", "track"])
    }

    @Test func pastedSpotifyLinksAreRestrictedToPlayableTypesAndExactHost() {
        #expect(SmalltifyModel.spotifyURI(from: "https://open.spotify.com/intl-de/playlist/\(trackID)?si=example") == "spotify:playlist:\(trackID)")
        #expect(SmalltifyModel.spotifyURI(from: "https://open.spotify.com.evil.test/track/\(trackID)") == nil)
        #expect(SmalltifyModel.spotifyURI(from: "spotify:artist:\(trackID)") == nil)
        #expect(SmalltifyModel.spotifyURI(from: "spotify:track:../../x") == nil)
    }

    @Test func coverFollowsCurrentTrackAndRejectsNonHTTPSImages() throws {
        var state = SoloistSnapshot()
        _ = try state.apply(Data(#"{"type":"track_changed","item":{"decorations":{"visual_identity":{"cover":[{"url":"file:///tmp/image.png"},{"url":"https://i.scdn.co/image/test","size":"large"}]}}}}"#.utf8))
        #expect(state.coverURL?.absoluteString == "https://i.scdn.co/image/test")
        _ = try state.apply(Data(#"{"type":"track_changed","item":{"decorations":{"identity":{"name":"Next track"}}}}"#.utf8))
        #expect(state.coverURL == nil)
    }

    @Test func positionInterpolatesClampsAndFreezesOnPause() throws {
        var state = SoloistSnapshot()
        let now = Date(timeIntervalSince1970: 1000)
        _ = try state.apply(Data(#"{"type":"playback_state","status":"playing","item":{"uri":"spotify:track:1234567890123456789012","decorations":{"identity":{"name":"Test"},"playback":{"duration_ms":10000}}},"position":{"position_ms":2000,"timestamp_ms":1000000,"speed":1}}"#.utf8), now: now)
        #expect(state.position(at: now.addingTimeInterval(3)) == 5000)
        #expect(state.position(at: now.addingTimeInterval(100)) == 10000)
        _ = try state.apply(Data(#"{"type":"playback_changed","status":"paused"}"#.utf8), now: now.addingTimeInterval(3))
        #expect(state.position(at: now.addingTimeInterval(8)) == 5000)
    }

    @Test func commandAckDoesNotPretendPlaybackSucceeded() throws {
        var state = SoloistSnapshot()
        _ = try state.apply(Data(#"{"type":"command_result","command":"play"}"#.utf8))
        #expect(state.status == "idle")
        #expect(!state.loggedIn)
    }

    @Test func emptySnapshotAndLogoutClearOldTrack() throws {
        var state = SoloistSnapshot()
        state.title = "Old track"
        state.uri = "spotify:track:\(trackID)"
        _ = try state.apply(Data(#"{"type":"playback_state","status":"idle","item":{}}"#.utf8))
        #expect(state.uri.isEmpty)
        #expect(state.title == "尚未播放")
        state.loggedIn = true
        state.active = true
        _ = try state.apply(Data(#"{"type":"auth_state","logged_in":false,"is_active":false}"#.utf8))
        #expect(!state.loggedIn && !state.active)
    }
}

/// In-memory transport and persistence. No real network or user Keychain is touched.
@Suite(.serialized)
struct SmalltifyHTTPTests {
    func client(expired: Bool = false) -> OfficialWebAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SmalltifyMockProtocol.self]
        let grant = OfficialGrant(clientID: "own-client", tokens: KeymasterTokens(accessToken: "old-token", refreshToken: "refresh-token", expiresAt: expired ? .distantPast : .distantFuture, username: ""))
        return OfficialWebAPI(grant: grant, session: URLSession(configuration: config), persist: { _ in })
    }

    @Test func concurrentRequestsShareOneTokenRefresh() async throws {
        SmalltifyMockProtocol.state.reset(mode: .success)
        let api = client(expired: true)
        let url = try OfficialWebAPI.apiURL(path: "/me/tracks")
        async let first = api.get(url)
        async let second = api.get(url)
        _ = try await (first, second)
        #expect(SmalltifyMockProtocol.state.counts().tokens == 1)
        #expect(SmalltifyMockProtocol.state.counts().api == 2)
    }

    @Test func unauthorizedRefreshesAndRetriesOnlyOnce() async throws {
        SmalltifyMockProtocol.state.reset(mode: .unauthorized)
        let api = client()
        await #expect(throws: SmalltifyError.self) {
            try await api.get(OfficialWebAPI.apiURL(path: "/me/tracks"))
        }
        #expect(SmalltifyMockProtocol.state.counts().tokens == 1)
        #expect(SmalltifyMockProtocol.state.counts().api == 2)
    }

    @Test func rateLimitBlocksImmediateRepeatedRequests() async throws {
        SmalltifyMockProtocol.state.reset(mode: .limited)
        let api = client()
        let url = try OfficialWebAPI.apiURL(path: "/me/tracks")
        for _ in 0 ..< 2 {
            await #expect(throws: SmalltifyError.self) { try await api.get(url) }
        }
        #expect(SmalltifyMockProtocol.state.counts().api == 1)
    }

    @Test func unauthorizedHostIsRejectedBeforeSendingToken() async throws {
        SmalltifyMockProtocol.state.reset(mode: .success)
        let api = client()
        let url = try #require(URL(string: "https://evil.test/v1/me"))
        await #expect(throws: SmalltifyError.self) { try await api.get(url) }
        #expect(SmalltifyMockProtocol.state.counts().api == 0)
        #expect(SmalltifyMockProtocol.state.counts().tokens == 0)
    }
}

private final class SmalltifyMockState: @unchecked Sendable {
    enum Mode { case success, unauthorized, limited }
    private let lock = NSLock()
    private var mode = Mode.success
    private var apiCount = 0
    private var tokenCount = 0

    func reset(mode: Mode) {
        lock.withLock { self.mode = mode; apiCount = 0; tokenCount = 0 }
    }

    func counts() -> (api: Int, tokens: Int) { lock.withLock { (apiCount, tokenCount) } }

    func response(for request: URLRequest) -> (Int, Data, [String: String]) {
        lock.withLock {
            if request.url?.host == "accounts.spotify.com" {
                tokenCount += 1
                return (200, Data(#"{"access_token":"fresh-token","refresh_token":"rotated-token","expires_in":3600}"#.utf8), [:])
            }
            apiCount += 1
            switch mode {
            case .success: return (200, Data(#"{"items":[]}"#.utf8), [:])
            case .unauthorized: return (401, Data(), [:])
            case .limited: return (429, Data(), ["Retry-After": "60"])
            }
        }
    }
}

private final class SmalltifyMockProtocol: URLProtocol, @unchecked Sendable {
    static let state = SmalltifyMockState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data, headers) = Self.state.response(for: request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
