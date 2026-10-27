import Foundation
@testable import Spotifly
import Testing

@MainActor struct LibraryPagesTests {
    private func item(_ name: String, artist: String = "", year: String? = nil) -> CatalogItem {
        CatalogItem(uri: "spotify:album:1234567890123456789012", name: name, subtitle: artist,
                    kind: "album", durationMS: 0, imageURL: nil, releaseDate: year)
    }

    @Test func likedSubtitleDistinguishesPartialAndCompleteCollections() {
        #expect(LikedSongsPage.subtitle(total: nil, loaded: 0, hasMore: false) == "")
        #expect(LikedSongsPage.subtitle(total: 120, loaded: 50, hasMore: true) == "120 首 · 已加载 50 首")
        #expect(LikedSongsPage.subtitle(total: 120, loaded: 120, hasMore: false) == "120 首")
        #expect(LikedSongsPage.subtitle(total: 0, loaded: 0, hasMore: false) == "0 首")
    }

    @Test func playlistDetailsUseOwnershipRatherThanCollaboration() {
        var playlist = item("歌单")
        playlist.ownerID = "me"
        playlist.ownerName = "作者"
        playlist.trackCount = 16
        #expect(PlaylistsPage.detail(playlist, accountID: "me") == "16 首")
        playlist.collaborative = true
        #expect(PlaylistsPage.detail(playlist, accountID: "other") == "作者")
        #expect(PlaylistsPage.detail(playlist, accountID: nil) == "作者")
        playlist.trackCount = nil
        #expect(PlaylistsPage.detail(playlist, accountID: "me") == "作者")
        playlist.trackCount = 0
        #expect(PlaylistsPage.detail(playlist, accountID: "me") == "0 首")
    }

    @Test func albumSortPreservesSpotifyOrderAndStableTies() {
        let albums = [item("B", artist: "Z", year: "2020"), item("A", artist: "A", year: "2024-03-01"),
                      item("C", artist: "A", year: "2024"), item("D")]
        #expect(LibraryAlbumSort.recentlyAdded.sorted(albums) == albums)
        #expect(LibraryAlbumSort.name.sorted(albums).map(\.name) == ["A", "B", "C", "D"])
        #expect(LibraryAlbumSort.artist.sorted(albums).map(\.name) == ["D", "A", "C", "B"])
        #expect(LibraryAlbumSort.year.sorted(albums).map(\.name) == ["A", "C", "B", "D"])
        #expect(albums.map(\.name) == ["B", "A", "C", "D"])
    }

    @Test func albumDetailOmitsMissingParts() {
        #expect(AlbumsPage.detail(item("A", artist: "歌手", year: "2024-03-01")) == "歌手 · 2024")
        #expect(AlbumsPage.detail(item("A", artist: "歌手")) == "歌手")
        #expect(AlbumsPage.detail(item("A", year: "2024")) == "2024")
        #expect(AlbumsPage.detail(item("A")) == "")
    }

    @Test func libraryURLsUseExpectedLimitsAndMarket() throws {
        for url in [LikedSongsPage.url, PlaylistsPage.url, AlbumsPage.url, ArtistsPage.url] {
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(query.contains(.init(name: "limit", value: "50")))
            if ["/v1/me/tracks", "/v1/me/albums"].contains(url.path) {
                #expect(query.contains(.init(name: "market", value: "from_token")))
            }
        }
        #expect(ArtistsPage.url.query()?.contains("type=artist") == true)
    }

    @Test func savedAlbumsParseWrapperDateAndArtists() throws {
        let data = Data("""
        {"items":[{"added_at":"2026-10-20T10:00:00Z","album":{
        "uri":"spotify:album:1234567890123456789012","name":"潮汐电台","release_date":"2024-03",
        "artists":[{"uri":"spotify:artist:abcdefghijklmnopqrstuv","name":"马洛·韦尔"}]}}],"total":1,"next":null}
        """.utf8)
        let page = try CatalogPage.parse(data)
        let album = try #require(page.items.first)
        #expect(album.addedAt != nil)
        #expect(AlbumsPage.detail(album) == "马洛·韦尔 · 2024")
        #expect(page.total == 1)
    }

    @Test func followedArtistsFollowCursorAndRefreshThroughTheirRoute() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LibraryArtistProtocol.self]
        let grant = OfficialGrant(clientID: "fixture", tokens: KeymasterTokens(
            accessToken: "fixture-token", refreshToken: "fixture-refresh", expiresAt: .distantFuture, username: ""))
        let api = OfficialWebAPI(grant: grant, session: URLSession(configuration: config), persist: { _ in })
        let pages = PageStore()
        let loader = pages.loader("\(Destination.artists.key)/items") { ArtistsPage.makeLoader(api: api) }
        loader.loadIfNeeded()
        try await settle(loader)
        #expect(loader.items.map(\.name) == ["第一位"])
        #expect(loader.next?.query()?.contains("after=opaque-cursor") == true)
        loader.loadMore()
        try await settle(loader)
        #expect(loader.items.map(\.name) == ["第一位", "第二位"])
        #expect(loader.items.allSatisfy { $0.kind == "artist" })
        #expect(loader.next == nil)
        pages.refresh(route: Destination.artists.key)
        try await settle(loader)
        #expect(loader.items.map(\.name) == ["第一位"])
    }

    @Test func nestedArtistResponseRejectsUnexpectedShapesAndExternalNext() {
        #expect(throws: SmalltifyError.self) {
            try CatalogPage.parse(Data("{\"items\":[]}".utf8), searchType: "artist")
        }
        #expect(throws: SmalltifyError.self) {
            try CatalogPage.parse(Data("{\"artists\":{\"items\":[],\"next\":\"https://example.com/page\"}}".utf8), searchType: "artist")
        }
    }

    private func settle(_ loader: PagedLoader) async throws {
        for _ in 0 ..< 200 {
            if loader.phase != .idle, !loader.isLoading, !loader.loadingMore { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Library loader did not settle")
    }
}

private final class LibraryArtistProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.spotify.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let second = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .contains(.init(name: "after", value: "opaque-cursor")) == true
        let body: [String: Any] = ["artists": [
            "items": [["uri": "spotify:artist:" + (second ? "abcdefghijklmnopqrstuv" : "1234567890123456789012"),
                       "name": second ? "第二位" : "第一位", "type": "artist"]],
            "total": 2, "next": second ? NSNull() : "https://api.spotify.com/v1/me/following?type=artist&limit=50&after=opaque-cursor",
        ]]
        if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = try? JSONSerialization.data(withJSONObject: body) { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
