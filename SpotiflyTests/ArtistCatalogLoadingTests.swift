import Foundation
@testable import Spotifly
import Testing

@MainActor @Suite(.serialized) struct ArtistCatalogLoadingTests {
    let artist = CatalogArtist(uri: "spotify:artist:1234567890123456789012", name: "Gestalt Girl")

    private func api() -> OfficialWebAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArtistCatalogProtocol.self]
        let grant = OfficialGrant(clientID: "fixture", tokens: KeymasterTokens(
            accessToken: "fixture-token", refreshToken: "fixture-refresh", expiresAt: .distantFuture, username: ""))
        return OfficialWebAPI(grant: grant, session: URLSession(configuration: config), persist: { _ in })
    }

    private func waitForLoad(_ loader: PagedLoader) async throws {
        for _ in 0 ..< 200 {
            if loader.phase != .loading, loader.phase != .idle, !loader.loadingMore { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Artist catalog load did not finish")
    }

    @Test func realModelRequestsLegalPagesAndDisplaysThirtyAlbums() async throws {
        ArtistCatalogProtocol.state.reset(.success)
        let model = SmalltifyModel(restoreCredentials: false, api: api())
        model.signedIn = true
        let loader = try model.artistAlbumsLoader(artist, group: "album,single")
        loader.loadIfNeeded()
        try await waitForLoad(loader)
        #expect(loader.failure == nil)
        #expect(loader.items.count == 30)
        #expect(await model.artistCatalog.profile(artistID: artist.spotifyID)?.imageURL?.host == "i.scdn.co")
        let next = try #require(loader.next)
        #expect(URLComponents(url: next, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value == "30")
        let requests = ArtistCatalogProtocol.state.albumRequests()
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { url in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "limit" }?.value == "10"
        })
        loader.loadMore()
        try await waitForLoad(loader)
        #expect(loader.items.count == 40)
        #expect(loader.next == nil)
    }

    @Test func playbackDoesNotFetchTheArtistAhead() async throws {
        ArtistCatalogProtocol.state.reset(.success)
        let model = SmalltifyModel(restoreCredentials: false, api: api())
        model.signedIn = true
        await model.start()
        model.player.snapshot.artists = [artist]
        model.player.snapshot.status = "playing"
        // Longer than the 800 ms the removed prefetch waited before asking.
        try await Task.sleep(for: .milliseconds(1200))
        #expect(ArtistCatalogProtocol.state.albumRequests().isEmpty)
        model.player.snapshot.status = "paused"
    }

    @Test func browsingSharesTheCacheAndRefreshBypassesIt() async throws {
        ArtistCatalogProtocol.state.reset(.success)
        let loader = ArtistCatalogLoader(api: api())
        let url = try ArtistCatalogLoader.albumsURL(artistID: artist.spotifyID)
        _ = try await loader.albums(from: url)
        #expect(ArtistCatalogProtocol.state.albumRequests().count == 3)
        let cached = try await loader.albums(from: url)
        #expect(cached.items.count == 30)
        #expect(ArtistCatalogProtocol.state.albumRequests().count == 3)
        _ = try await loader.albums(from: url, refresh: true)
        #expect(ArtistCatalogProtocol.state.albumRequests().count == 6)
    }

    @Test func concurrentReadersShareRequestsAndLogoutClearsCache() async throws {
        ArtistCatalogProtocol.state.reset(.success)
        let loader = ArtistCatalogLoader(api: api())
        let url = try ArtistCatalogLoader.albumsURL(artistID: artist.spotifyID)
        async let first = loader.albums(from: url)
        async let second = loader.albums(from: url)
        let pages = try await (first, second)
        #expect(pages.0.items.count == 30 && pages.1.items.count == 30)
        #expect(ArtistCatalogProtocol.state.albumRequests().count == 3)
        await loader.clear()
        _ = try await loader.albums(from: url)
        #expect(ArtistCatalogProtocol.state.albumRequests().count == 6)
    }

    @Test func rateLimitKeepsLoadedPrefixAndDoesNotSendMoreRequests() async throws {
        ArtistCatalogProtocol.state.reset(.limitedOnSecondPage)
        let loader = ArtistCatalogLoader(api: api())
        let url = try ArtistCatalogLoader.albumsURL(artistID: artist.spotifyID)
        let page = try await loader.albums(from: url)
        #expect(page.items.count == 10)
        let next = try #require(page.next)
        await #expect(throws: SmalltifyError.self) { try await loader.albums(from: next) }
        #expect(ArtistCatalogProtocol.state.albumRequests().count == 2)
    }

    @Test func serverErrorDetailsAreVisibleWithoutExposingCredentials() async throws {
        ArtistCatalogProtocol.state.reset(.badRequest)
        let model = SmalltifyModel(restoreCredentials: false, api: api())
        model.signedIn = true
        let loader = try model.artistAlbumsLoader(artist, group: "album,single")
        loader.loadIfNeeded()
        try await waitForLoad(loader)
        let error = try #require(loader.failure)
        #expect(error.contains("Invalid limit"))
        #expect(error.contains("400"))
        #expect(!error.contains("fixture-token"))
        #expect(loader.items.isEmpty)
    }
}

private final class ArtistCatalogFixture: @unchecked Sendable {
    enum Mode { case success, limitedOnSecondPage, badRequest }
    private let lock = NSLock()
    private var mode = Mode.success
    private var requests: [URL] = []

    func reset(_ mode: Mode) { lock.withLock { self.mode = mode; requests = [] } }
    func albumRequests() -> [URL] { lock.withLock { requests } }

    func response(_ url: URL) -> (Int, Data, [String: String]) {
        lock.withLock {
            let artistID = "1234567890123456789012"
            guard url.path.hasSuffix("/albums") else {
                return (200, Data("""
                {"uri":"spotify:artist:\(artistID)","name":"Gestalt Girl","images":[{"url":"https://i.scdn.co/image/fixture"}]}
                """.utf8), [:])
            }
            requests.append(url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let limit = Int(query.first { $0.name == "limit" }?.value ?? "5") ?? 0
            let offset = Int(query.first { $0.name == "offset" }?.value ?? "0") ?? 0
            guard (1 ... 10).contains(limit), mode != .badRequest else {
                return (400, Data(#"{"error":{"status":400,"message":"Invalid limit: maximum is 10 fixture-token"}}"#.utf8), [:])
            }
            if mode == .limitedOnSecondPage, offset > 0 {
                return (429, Data(), ["Retry-After": "60"])
            }
            let items: [[String: Any]] = (offset ..< min(40, offset + limit)).map { index in
                ["uri": "spotify:album:" + String(repeating: "0", count: 22 - String(index).count) + String(index),
                 "type": "album", "name": "Album \(index)"]
            }
            let next: Any = offset + limit < 40
                ? "https://api.spotify.com/v1/artists/\(artistID)/albums?include_groups=album,single&limit=10&offset=\(offset + limit)" as Any
                : NSNull()
            let data = (try? JSONSerialization.data(withJSONObject: ["items": items, "next": next])) ?? Data()
            return (200, data, [:])
        }
    }
}

private final class ArtistCatalogProtocol: URLProtocol, @unchecked Sendable {
    static let state = ArtistCatalogFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let (status, data, headers) = Self.state.response(url)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
