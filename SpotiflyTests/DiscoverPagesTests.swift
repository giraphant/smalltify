import Foundation
@testable import Spotifly
import Testing

@MainActor struct DiscoverPagesTests {
    @Test func mixedSearchUnwrapsEveryTypeAndKeepsMarketIdentity() throws {
        let data = FixtureData.respond(method: "GET", url: try DiscoverSearchScope.all.url(query: "潮汐")).1
        let result = try DiscoverSearchResults.parse(data)
        #expect(!result.isEmpty)
        #expect(result.pages.count == 4)
        #expect(result.pages[.track]?.items.count == 10)
        #expect(result.pages[.track]?.items.first?.name == "潮汐电台")
        #expect(result.pages[.artist]?.items.first?.kind == "artist")
        #expect(result.pages[.album]?.items.first?.releaseYear == "2024")
        #expect(result.pages[.playlist]?.items.first?.ownerName == "测试用户")
        #expect(result.pages[.track]?.next != nil)
        var track = FixtureData.allTracks[0]
        track["linked_from"] = ["uri": "spotify:track:0000000000000000000000"]
        let page = try CatalogPage.parse(FixtureData.json(["tracks": ["items": [track]]]), searchType: "track")
        #expect(page.items.first?.uri == track["uri"] as? String)
    }

    @Test func emptySearchAndMalformedResponseAreDifferentStates() throws {
        let data = FixtureData.respond(method: "GET", url: try DiscoverSearchScope.all.url(query: "无结果")).1
        #expect(try DiscoverSearchResults.parse(data).isEmpty)
        #expect(throws: (any Error).self) { try DiscoverSearchResults.parse(Data("{}".utf8)) }
    }

    @Test func queryEscapingAndPaginationKeepTheScopeAndMarket() throws {
        let url = try DiscoverSearchScope.all.url(query: "潮汐 & # ?")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "q" }?.value == "潮汐 & # ?")
        #expect(query.first { $0.name == "type" }?.value == "track,artist,album,playlist")
        #expect(query.first { $0.name == "limit" }?.value == "10")
        #expect(query.first { $0.name == "market" }?.value == "from_token")
        let first = try DiscoverSearchScope.track.url(query: "潮汐")
        let page = try CatalogPage.parse(FixtureData.respond(method: "GET", url: first).1, searchType: "track")
        let next = try #require(page.next)
        let nextQuery = URLComponents(url: next, resolvingAgainstBaseURL: false)?.queryItems
        #expect(nextQuery?.first { $0.name == "offset" }?.value == "10")
        #expect(nextQuery?.first { $0.name == "type" }?.value == "track")
        #expect(nextQuery?.first { $0.name == "market" }?.value == "from_token")
        let second = try CatalogPage.parse(FixtureData.respond(method: "GET", url: next).1, searchType: "track")
        #expect(second.items.count == 10)
        #expect(Set(page.items.map(\.uri)).isDisjoint(with: second.items.map(\.uri)))
    }

    @Test func recentContextsDeduplicateInOrderAndFallBackToAlbum() throws {
        let album = FixtureData.albums[0]
        let playlist = FixtureData.playlists[0]
        let artist = FixtureData.artists[0]
        let entries: [[String: Any]] = [
            ["context": ["uri": playlist.uri]],
            ["context": ["uri": playlist.uri]],
            ["context": NSNull(), "track": album.trackObjects(withAlbum: true)[0]],
            ["context": ["uri": artist.uri]],
            ["context": ["uri": "spotify:artist:bad"]],
            ["context": ["uri": album.uri]],
        ]
        let contexts = try DiscoverRecentContext.parse(FixtureData.json(["items": entries]))
        #expect(contexts.map(\.uri) == [playlist.uri, album.uri, artist.uri])
        #expect(contexts.map(\.kind) == ["playlist", "album", "artist"])
        #expect(contexts[1].path == "/albums/\(album.id)")
        #expect(contexts[1].fallback?.name == album.name)
        #expect(throws: (any Error).self) { try DiscoverRecentContext.parse(Data("{}".utf8)) }
    }

    @Test func recentContextsStopAfterSixDistinctItems() throws {
        let entries = FixtureData.albums.map { ["context": ["uri": $0.uri]] }
        let contexts = try DiscoverRecentContext.parse(FixtureData.json(["items": entries]))
        #expect(contexts.map(\.uri) == FixtureData.albums.prefix(6).map(\.uri))
    }

    @Test func recentResolutionPreservesOrderAndCachesResolvedCards() async throws {
        let requests = DiscoverRequestRecorder()
        let catalog = DiscoverRecentCatalog { url in
            await requests.record(url.path)
            return FixtureData.respond(method: "GET", url: url).1
        }
        let first = try await catalog.load(refresh: false)
        #expect(first.map(\.name) == ["潮汐电台", "深夜驾驶", "朱妮珀·黑尔", "每周新发现", "北方静电", "周日慢板"])
        #expect(await requests.count == 6)
        let second = try await catalog.load(refresh: false)
        #expect(first == second)
        #expect(await requests.count == 7)
        _ = try await catalog.load(refresh: true)
        #expect(await requests.count == 13)
    }

    @Test func recentContextSpotifyWillNotReturnShowsTheTracksAlbumInstead() async throws {
        let playlist = FixtureData.playlists[0]
        let album = FixtureData.albums[0]
        let other = FixtureData.albums[1]
        let history = FixtureData.json(["items": [
            ["context": ["uri": playlist.uri], "track": album.trackObjects(withAlbum: true)[0]],
            ["context": ["uri": album.uri], "track": album.trackObjects(withAlbum: true)[1]],
            ["context": ["uri": other.uri], "track": other.trackObjects(withAlbum: true)[0]],
        ]])
        let requests = DiscoverRequestRecorder()
        let catalog = DiscoverRecentCatalog { url in
            await requests.record(url.path)
            if url.path == "/v1/me/player/recently-played" { return history }
            if url.path.hasPrefix("/v1/playlists/") { throw SmalltifyError("Resource not found", reason: .notFound) }
            return FixtureData.respond(method: "GET", url: url).1
        }
        // The playlist's stand-in is the album played next, which shows once.
        let first = try await catalog.load(refresh: false)
        #expect(first.map(\.uri) == [album.uri, other.uri])
        #expect(await requests.count == 4)
        let second = try await catalog.load(refresh: false)
        #expect(second == first)
        #expect(await requests.count == 5)
        _ = try await catalog.load(refresh: true)
        #expect(await requests.paths.suffix(4).contains("/v1/playlists/\(playlist.id)"))

        let offline = DiscoverRecentCatalog { url in
            if url.path == "/v1/me/player/recently-played" { return history }
            throw SmalltifyError("offline")
        }
        await #expect(throws: SmalltifyError.self) { try await offline.load(refresh: false) }
    }

    @Test func timeRangesUseTheirEndpointLimits() throws {
        #expect(DiscoverTimeRange.allCases.map(\.title) == ["4 周", "6 个月", "1 年"])
        for range in DiscoverTimeRange.allCases {
            for (type, limit) in [("tracks", "5"), ("artists", "6")] {
                let url = try range.url(type: type)
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                #expect(url.path == "/v1/me/top/\(type)")
                #expect(query?.first { $0.name == "time_range" }?.value == range.rawValue)
                #expect(query?.first { $0.name == "limit" }?.value == limit)
            }
        }
    }

    @Test(arguments: [SmalltifyError.Reason.forbidden, .authExpired])
    func authorizationFailureCanRetryWithoutBecomingAnEmptyResult(reason: SmalltifyError.Reason) async {
        let loader = DiscoverLoader<[CatalogItem]> { refresh in
            if !refresh { throw SmalltifyError("Missing scope", reason: reason) }
            return []
        }
        loader.loadIfNeeded()
        await loader.waitForLoad()
        #expect(loader.needsAuthorization)
        #expect(loader.value == nil)
        loader.refresh()
        await loader.waitForLoad()
        #expect(!loader.needsAuthorization)
        #expect(loader.failure == nil)
        #expect(loader.value?.isEmpty == true)
    }

    @Test func refreshSupersedesAnOlderRequestAndCacheHitDoesNotFetch() async {
        let gate = DiscoverTestGate()
        let loader = DiscoverLoader<Int> { refresh in
            if refresh { return 2 }
            return await gate.wait()
        }
        loader.loadIfNeeded()
        await gate.started()
        loader.refresh()
        await loader.waitForLoad()
        #expect(loader.value == 2)
        await gate.finish()
        for _ in 0 ..< 10 { await Task.yield() }
        #expect(loader.value == 2)
        loader.loadIfNeeded()
        #expect(!loader.isLoading)
    }
}

private actor DiscoverTestGate {
    var continuation: CheckedContinuation<Int, Never>?
    func wait() async -> Int { await withCheckedContinuation { continuation = $0 } }
    func started() async {
        while continuation == nil { await Task.yield() }
    }
    func finish() { continuation?.resume(returning: 1) }
}

private actor DiscoverRequestRecorder {
    private(set) var paths: [String] = []
    var count: Int { paths.count }
    func record(_ path: String) { paths.append(path) }
}
