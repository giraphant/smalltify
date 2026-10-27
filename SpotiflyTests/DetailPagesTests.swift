import Foundation
@testable import Spotifly
import Synchronization
import Testing

@MainActor @Suite(.serialized) struct DetailPagesTests {
    private let id = "1234567890123456789012"

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Detail state did not settle")
    }

    private func album(name: String = "潮汐电台") -> CatalogItem {
        CatalogItem(uri: "spotify:album:\(id)", name: name, subtitle: "", kind: "album", durationMS: 0, imageURL: nil)
    }

    @Test func descriptionRemovesHTMLWithoutLoadingResourcesAndDecodesEntitiesOnce() {
        #expect(PlaylistDescription.plainText("<p>海风 &amp; <a href='https://example.com'>沙滩</a></p><br>周末&nbsp;&#x1F30A; &#20013;") == "海风 & 沙滩 周末 🌊 中")
        #expect(PlaylistDescription.plainText("<script>bad()</script><style>body {}</style>安全 &lt;b&gt; &amp;amp; &unknown;") == "安全 <b> &amp; &unknown;")
        #expect(PlaylistDescription.plainText("&quot;周末&quot; &#39;歌&#39; &mdash; &#x110000;") == "\"周末\" '歌' — &#x110000;")
    }

    @Test func releaseLabelsDistinguishEPAndAppearances() {
        var item = album()
        item.releaseDate = "2024-03-01"
        item.albumType = "album"
        #expect(ArtistReleaseGroup.all.detail(item) == "专辑 · 2024")
        item.albumType = "single"
        item.trackCount = 2
        #expect(ArtistReleaseGroup.singles.detail(item) == "单曲 · 2024")
        item.trackCount = 3
        #expect(ArtistReleaseGroup.singles.detail(item) == "EP · 2024")
        item.artists = [CatalogArtist(uri: "spotify:artist:\(id)", name: "索尔")]
        #expect(ArtistReleaseGroup.appearances.detail(item) == "索尔 · 2024")
        #expect(ArtistReleaseGroup.allCases.map(\.rawValue) == ["album,single", "album", "single", "appears_on"])
    }

    @Test func detailParsingHydratesStubAndRejectsWrongIdentity() throws {
        let object: [String: Any] = ["uri": album().uri, "name": "完整标题", "type": "album", "release_date": "2024",
                                     "total_tracks": 10, "images": [["url": "https://i.scdn.co/image/cover", "width": 640]],
                                     "artists": [["uri": "spotify:artist:\(id)", "name": "马洛·韦尔"]]]
        let data = try JSONSerialization.data(withJSONObject: object)
        let parsed = try DetailItemLoader.parse(data, expectedURI: album().uri)
        #expect(parsed.name == "完整标题")
        #expect(parsed.trackCount == 10 && parsed.releaseYear == "2024")
        #expect(parsed.artists.first?.name == "马洛·韦尔")
        #expect(parsed.imageURL != nil)
        #expect(throws: SmalltifyError.self) { try DetailItemLoader.parse(data, expectedURI: "spotify:album:abcdefghijklmnopqrstuv") }
    }

    @Test func totalDurationIsOnlyShownAfterEveryTrackLoads() {
        var item = album()
        item.releaseDate = "2024"
        let track = CatalogItem(uri: "spotify:track:\(id)", name: "曲目", subtitle: "", kind: "track", durationMS: 234_000, imageURL: nil)
        #expect(AlbumDetailFormatting.footer(album: item, tracks: Array(repeating: track, count: 10), complete: true) == "2024 · 10 首，39 分钟")
        #expect(AlbumDetailFormatting.footer(album: item, tracks: [track], complete: false) == nil)
    }

    @Test func failedWriteRollsBackOptimismAndBlocksDuplicateToggles() async throws {
        let gate = DetailWriteGate()
        var toasts: [String] = []
        let state = LibraryWrites(uri: album().uri, contains: { false }, write: { _ in try await gate.wait() }, toast: { toasts.append($0) })
        state.loadIfNeeded()
        try await waitUntil { state.isSaved != nil }
        let first = Task { await state.toggle() }
        try await waitUntil { state.writing }
        #expect(state.isSaved == true)
        await state.toggle()
        #expect(await gate.calls == 1)
        await gate.finish(error: SmalltifyError("无法收藏"))
        await first.value
        #expect(state.isSaved == false && !state.writing)
        #expect(toasts == ["无法收藏"])
    }

    @Test func savesAndFollowsUseURIQueryOnCurrentLibraryEndpoints() async throws {
        DetailTestProtocol.requests.withLock { $0 = [] }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DetailTestProtocol.self]
        let grant = OfficialGrant(clientID: "test", tokens: KeymasterTokens(accessToken: "test", refreshToken: "test", expiresAt: .distantFuture, username: ""))
        let api = OfficialWebAPI(grant: grant, session: URLSession(configuration: config), persist: { _ in })
        let model = SmalltifyModel(restoreCredentials: false, api: api)
        for kind in ["album", "artist"] {
            let uri = "spotify:\(kind):\(id)"
            let state = LibraryWrites(uri: uri, model: model)
            state.loadIfNeeded()
            try await waitUntil { state.isSaved != nil }
            #expect(state.isSaved == false)
            await state.toggle()
            #expect(state.isSaved == true)
            await state.toggle()
            #expect(state.isSaved == false)
        }
        let requests = DetailTestProtocol.requests.withLock { $0 }
        #expect(requests.map(\.httpMethod) == ["GET", "PUT", "DELETE", "GET", "PUT", "DELETE"])
        #expect(requests.map { $0.url?.path } == ["/v1/me/library/contains", "/v1/me/library", "/v1/me/library", "/v1/me/library/contains", "/v1/me/library", "/v1/me/library"])
        for (index, request) in requests.enumerated() {
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.first?.name == "uris")
            #expect(query?.first?.value == "spotify:\(index < 3 ? "album" : "artist"):\(id)")
            #expect(request.httpBody == nil)
        }
    }

    @Test func successfulTogglesHaveTheFourExpectedToasts() async throws {
        var messages: [String] = []
        var changes = 0
        for kind in ["album", "artist"] {
            let state = LibraryWrites(uri: "spotify:\(kind):\(id)", contains: { false }, write: { _ in },
                                      toast: { messages.append($0) }, changed: { changes += 1 })
            state.loadIfNeeded()
            try await waitUntil { state.isSaved != nil }
            await state.toggle()
            await state.toggle()
        }
        #expect(messages == ["已收藏专辑", "已移出收藏", "已关注", "已取消关注"])
        #expect(changes == 4)
    }

    @Test func failedContainsDoesNotGuessUnsavedAndCanRetry() async throws {
        let calls = Mutex(0)
        let state = LibraryWrites(uri: album().uri, contains: {
            let count = calls.withLock { $0 += 1; return $0 }
            if count == 1 { throw SmalltifyError("网络中断") }
            return true
        }, write: { _ in Issue.record("Unknown state must not be written") })
        state.loadIfNeeded()
        try await waitUntil { !state.checking }
        #expect(state.isSaved == nil && state.failure == "网络中断")
        await state.toggle()
        state.refresh()
        try await waitUntil { !state.checking }
        #expect(state.isSaved == true && state.failure == nil)
    }

    @Test func refreshedHeaderCannotBeOverwrittenByOldRequest() async throws {
        let gate = DetailHeaderGate()
        let state = DetailItemLoader(item: album()) { try await gate.load() }
        state.loadIfNeeded()
        for _ in 0 ..< 100 {
            if await gate.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        state.refresh()
        for _ in 0 ..< 100 {
            if await gate.count == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await gate.finish(index: 1, item: album(name: "新结果"))
        try await waitUntil { state.loaded }
        await gate.finish(index: 0, item: album(name: "旧结果"))
        try await Task.sleep(for: .milliseconds(20))
        #expect(state.item.name == "新结果")
    }

    @Test func fixtureWritesAreReflectedByContains() throws {
        let uri = "spotify:artist:abcdefghijklmnopqrstuv"
        let query = [URLQueryItem(name: "uris", value: uri)]
        let contains = try OfficialWebAPI.apiURL(path: "/me/library/contains", query: query)
        let write = try OfficialWebAPI.apiURL(path: "/me/library", query: query)
        _ = FixtureData.respond(method: "DELETE", url: write)
        #expect(try JSONDecoder().decode([Bool].self, from: FixtureData.respond(method: "GET", url: contains).1) == [false])
        _ = FixtureData.respond(method: "PUT", url: write)
        #expect(try JSONDecoder().decode([Bool].self, from: FixtureData.respond(method: "GET", url: contains).1) == [true])
        _ = FixtureData.respond(method: "DELETE", url: write)
        #expect(try JSONDecoder().decode([Bool].self, from: FixtureData.respond(method: "GET", url: contains).1) == [false])
    }

    @Test func forbiddenPlaylistIsDifferentFromOrdinaryFailure() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DetailTestProtocol.self]
        let grant = OfficialGrant(clientID: "test", tokens: KeymasterTokens(accessToken: "test", refreshToken: "test", expiresAt: .distantFuture, username: ""))
        let api = OfficialWebAPI(grant: grant, session: URLSession(configuration: config), persist: { _ in })
        for (path, forbidden) in [("/playlists/denied/items", true), ("/playlists/failed/items", false)] {
            let tracks = DetailTracksLoader(url: try OfficialWebAPI.apiURL(path: path), api: api, report: { _ in })
            tracks.loader.loadIfNeeded()
            try await waitUntil { tracks.loader.failure != nil }
            #expect(tracks.isForbidden == forbidden)
        }
    }
}

private actor DetailWriteGate {
    private var continuation: CheckedContinuation<Void, Error>?
    var calls = 0
    func wait() async throws {
        calls += 1
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(error: Error) { continuation?.resume(throwing: error); continuation = nil }
}

private actor DetailHeaderGate {
    private var continuations: [CheckedContinuation<CatalogItem, Error>] = []
    var count: Int { continuations.count }
    func load() async throws -> CatalogItem {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func finish(index: Int, item: CatalogItem) { continuations[index].resume(returning: item) }
}

private final class DetailTestProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.requests.withLock { $0.append(request) }
        let status = url.path.contains("denied") ? 403 : url.path.contains("failed") ? 500 : 200
        let data = request.httpMethod == "GET" ? Data("[false]".utf8) : Data()
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
