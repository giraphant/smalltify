import Foundation
@testable import Spotifly
import Testing

@MainActor struct SmalltifyShellTests {
    let firstID = "1234567890123456789012"
    let secondID = "abcdefghijklmnopqrstuv"

    private func page(_ names: [String], next: String?, total: Int? = nil) -> CatalogPage {
        CatalogPage(items: names.enumerated().map { index, name in
            CatalogItem(uri: "spotify:track:\(String(repeating: "\(index)", count: 22))", name: name,
                        subtitle: "", kind: "track", durationMS: 0, imageURL: nil)
        }, next: next.flatMap(URL.init(string:)), total: total)
    }

    private func settle(_ loader: PagedLoader) async throws {
        for _ in 0 ..< 200 {
            if loader.phase != .loading, !loader.loadingMore { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Loader did not settle")
    }

    @Test func loaderAppendsPagesAndRefreshStartsOver() async throws {
        let first = try OfficialWebAPI.apiURL(path: "/me/tracks")
        let pages = [page(["A", "B"], next: "https://api.spotify.com/v1/me/tracks?offset=2", total: 3), page(["C"], next: nil)]
        let calls = Counter()
        let loader = PagedLoader(firstURL: first) { url, _ in
            calls.increment()
            return url == first ? pages[0] : pages[1]
        }
        loader.loadIfNeeded()
        try await settle(loader)
        #expect(loader.items.map(\.name) == ["A", "B"])
        #expect(loader.total == 3)
        loader.loadIfNeeded()
        loader.loadMore()
        try await settle(loader)
        #expect(loader.items.map(\.name) == ["A", "B", "C"])
        #expect(loader.next == nil)
        #expect(calls.value == 2)
        loader.refresh()
        try await settle(loader)
        #expect(loader.items.map(\.name) == ["A", "B"])
    }

    @Test func loaderReportsFailuresAndKeepsTheFirstPageWhenMoreFails() async throws {
        let first = try OfficialWebAPI.apiURL(path: "/me/tracks")
        var reported: [String] = []
        let loader = PagedLoader(firstURL: first, report: { reported.append($0.localizedDescription) }) { url, _ in
            guard url == first else { throw SmalltifyError("下一页失败") }
            return CatalogPage(items: [], next: URL(string: "https://api.spotify.com/v1/me/tracks?offset=50"))
        }
        loader.loadIfNeeded()
        try await settle(loader)
        loader.loadMore()
        try await settle(loader)
        #expect(loader.phase == .loaded)
        #expect(loader.loadMoreError == "下一页失败")
        #expect(reported == ["下一页失败"])
    }

    @Test func pageStoreKeepsLoadersAndRefreshesOnlyTheRoutesOwn() throws {
        let store = PageStore(capacity: 2)
        let a = Probe(), b = Probe()
        #expect(store.loader("liked/tracks") { a } === a)
        #expect(store.loader("liked/tracks") { Probe() } === a)
        _ = store.loader("likedx/other") { b }
        store.refresh(route: "liked")
        #expect(a.refreshes == 1 && b.refreshes == 0)
        _ = store.loader("albums") { Probe() }
        _ = store.loader("artists") { Probe() }
        #expect(store.loader("liked/tracks") { Probe() } !== a)
    }

    @Test func libraryEntriesKeepAddedDateAlbumAndEveryImageSize() throws {
        let data = Data("""
        {"total":321,"next":null,"items":[{"added_at":"2026-09-18T08:00:00Z","track":{
          "uri":"spotify:track:\(firstID)","name":"潮汐电台","type":"track","duration_ms":238000,
          "artists":[{"uri":"spotify:artist:\(secondID)","name":"马洛·韦尔"}],
          "album":{"uri":"spotify:album:\(secondID)","name":"潮汐电台","release_date":"2024-03-01",
            "images":[{"url":"https://i.scdn.co/image/640","width":640},{"url":"https://i.scdn.co/image/64","width":64},
                      {"url":"https://i.scdn.co/image/300","width":300}]}}}]}
        """.utf8)
        let page = try CatalogPage.parse(data)
        #expect(page.total == 321)
        let track = try #require(page.items.first)
        #expect(track.addedAt == (try Date("2026-09-18T08:00:00Z", strategy: .iso8601)))
        #expect(track.album == CatalogAlbumRef(uri: "spotify:album:\(secondID)", name: "潮汐电台"))
        #expect(track.images.map(\.width) == [64, 300, 640])
        #expect(track.imageURL?.lastPathComponent == "64")
        #expect(track.imageURL(minPixels: 68)?.lastPathComponent == "300")
        #expect(track.imageURL(minPixels: 1000)?.lastPathComponent == "640")
        #expect(track.subtitle == "马洛·韦尔")
    }

    @Test func formattingMatchesTheDesign() throws {
        #expect(Formatting.duration(milliseconds: 238_000) == "3:58")
        #expect(Formatting.duration(milliseconds: 3_723_000) == "1:02:03")
        #expect(Formatting.totalDuration(milliseconds: 39 * 60000) == "39 分钟")
        #expect(Formatting.totalDuration(milliseconds: 72 * 60000) == "1 小时 12 分钟")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try Date("2026-10-27T12:00:00Z", strategy: .iso8601)
        #expect(Formatting.added(now, now: now, calendar: calendar) == "今天")
        #expect(Formatting.added(now.addingTimeInterval(-3 * 86400), now: now, calendar: calendar) == "3 天前")
        #expect(Formatting.added(now.addingTimeInterval(-15 * 86400), now: now, calendar: calendar) == "2 周前")
        #expect(Formatting.added(try Date("2026-09-18T08:00:00Z", strategy: .iso8601), now: now, calendar: calendar) == "2026/9/18")
    }

    @Test func connectionStatusNamesWhatIsMissingFirst() {
        let model = SmalltifyModel(restoreCredentials: false)
        #expect(model.connectionStatus == ConnectionStatus(text: "未连接 Spotify", tone: .warn))
        model.signedIn = true
        #expect(model.connectionStatus.text == "播放器未设置")
    }

    @Test func scopeUpgradeIsAskedOfGrantsFromBeforeTheNewFeatures() {
        let tokens = KeymasterTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, username: "")
        #expect(OfficialGrant(clientID: "c", tokens: tokens).needsScopeUpgrade)
        #expect(!OfficialGrant(clientID: "c", tokens: tokens, scopeVersion: OfficialWebAPI.scopeVersion).needsScopeUpgrade)
    }
}

@MainActor private final class Probe: Refreshable {
    var refreshes = 0
    func refresh() { refreshes += 1 }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
