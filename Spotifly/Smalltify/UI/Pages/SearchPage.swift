import SwiftUI

nonisolated enum DiscoverSearchScope: String, CaseIterable, Identifiable {
    case all, track, artist, album, playlist

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .track: "歌曲"
        case .artist: "歌手"
        case .album: "专辑"
        case .playlist: "歌单"
        }
    }

    func url(query: String) throws -> URL {
        try OfficialWebAPI.apiURL(path: "/search", query: [
            .init(name: "q", value: query),
            .init(name: "type", value: self == .all ? "track,artist,album,playlist" : rawValue),
            .init(name: "limit", value: "10"), .init(name: "market", value: "from_token"),
            .init(name: "offset", value: "0"),
        ])
    }
}

nonisolated struct DiscoverSearchResults: Sendable {
    let pages: [DiscoverSearchScope: CatalogPage]
    var isEmpty: Bool { pages.values.allSatisfy { $0.items.isEmpty } }

    static func parse(_ data: Data) throws -> Self {
        var pages: [DiscoverSearchScope: CatalogPage] = [:]
        for scope in DiscoverSearchScope.allCases where scope != .all {
            pages[scope] = try CatalogPage.parse(data, searchType: scope.rawValue)
        }
        return Self(pages: pages)
    }
}

/// The request outlives a view; a refresh supersedes its result before it can be published.
@MainActor @Observable final class DiscoverLoader<Value: Sendable>: Refreshable {
    private(set) var value: Value?
    private(set) var failure: String?
    private(set) var needsAuthorization = false
    private(set) var isLoading = false
    private var started = false
    private var generation = 0
    private var task: Task<Void, Never>?
    private let fetch: @Sendable (Bool) async throws -> Value
    private let report: @MainActor (Error) -> Void

    init(report: @escaping @MainActor (Error) -> Void = { _ in },
         fetch: @escaping @Sendable (Bool) async throws -> Value) {
        self.report = report
        self.fetch = fetch
    }

    func loadIfNeeded() {
        if !started { load(refresh: false) }
    }

    func refresh() { load(refresh: true) }
    func waitForLoad() async { await task?.value }

    private func load(refresh: Bool) {
        started = true
        generation += 1
        let run = generation
        failure = nil
        needsAuthorization = false
        isLoading = true
        task = Task {
            defer { if generation == run { isLoading = false } }
            do {
                #if DEBUG
                    if DebugFixtures.opens("discover-loading") { try await Task.sleep(for: .seconds(30)) }
                #endif
                let result = try await fetch(refresh)
                try Task.checkCancellation()
                guard generation == run else { return }
                value = result
            } catch {
                guard generation == run, !(error is CancellationError) else { return }
                failure = error.localizedDescription
                let reason = (error as? SmalltifyError)?.reason
                needsAuthorization = reason == .authExpired || reason == .forbidden
                report(error)
            }
        }
    }
}

/// 搜索「…」: every kind at once, or one kind with paging, for the toolbar's query.
struct SearchPage: View {
    let query: String
    @Environment(SmalltifyModel.self) private var model
    @State private var scope = DiscoverSearchScope.all

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("搜索类型", selection: $scope) {
                ForEach(DiscoverSearchScope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            if !model.signedIn {
                SignedOutView()
            } else if scope == .all {
                DiscoverMixedSearch(query: query, scope: $scope)
                    .id(query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiscoverScopedSearch(query: query, scope: scope)
                    .id("\(query)/\(scope.rawValue)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("搜索「\(query)」")
        .navigationSubtitle("")
        .task(id: query) {
            scope = .all
            #if DEBUG
                if let fixtureScope = DiscoverSearchScope.allCases.first(where: { DebugFixtures.opens("search-" + $0.rawValue) }) {
                    scope = fixtureScope
                }
            #endif
        }
    }
}

private struct DiscoverMixedSearch: View {
    let query: String
    @Binding var scope: DiscoverSearchScope
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        let loader: DiscoverLoader<DiscoverSearchResults> = model.pages.loader("\(Destination.search(query).key)/all") {
            DiscoverLoader(report: { [weak model] in model?.report($0) }) { [api = model.api] _ in
                try DiscoverSearchResults.parse(await api.get(DiscoverSearchScope.all.url(query: query)))
            }
        }
        Group {
            if let failure = loader.failure {
                PageFailureView(title: "没能加载搜索结果", message: failure) { loader.refresh() }
            } else if let results = loader.value {
                if results.isEmpty {
                    DiscoverSearchEmpty(query: query)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            ForEach(DiscoverSearchScope.allCases.filter { $0 != .all }) { section in
                                if let items = results.pages[section]?.items, !items.isEmpty {
                                    PageSection(title: section.title, showAll: { scope = section }) {
                                        if section == .track {
                                            DiscoverTrackRows(tracks: Array(items.prefix(4)), showsAlbum: true)
                                        } else {
                                            CatalogShelf(items: Array(items.prefix(section == .artist ? 4 : 5)),
                                                         size: section == .artist ? 80 : 150,
                                                         detail: DiscoverCardDetail.search)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(24)
                        .padding(.top, -10)
                    }
                    #if DEBUG
                        .defaultScrollAnchor(DebugFixtures.opens("search-bottom") ? .bottom : .top)
                    #endif
                }
            } else {
                LoadingRows()
            }
        }
        .task { loader.loadIfNeeded() }
    }
}

private struct DiscoverScopedSearch: View {
    let query: String
    let scope: DiscoverSearchScope
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        // The path is fixed and URLComponents escapes the query text.
        let url = try! scope.url(query: query)
        let loader: PagedLoader = model.pages.loader("\(Destination.search(query).key)/\(scope.rawValue)") {
            PagedLoader(firstURL: url, report: { [weak model] in model?.report($0) }) { [api = model.api] url, _ in
                #if DEBUG
                    let offset = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value
                    let slowPage = await DebugFixtures.opens("discover-more-loading")
                    if offset != "0", slowPage {
                        try await Task.sleep(for: .seconds(30))
                    }
                #endif
                return try CatalogPage.parse(await api.get(url), searchType: scope.rawValue)
            }
        }
        LoadedContent(loader: loader, emptyTitle: "没有找到「\(query)」", emptyDescription: "换个关键词，或切换到「全部」。") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if scope == .track {
                        DiscoverTrackRows(tracks: loader.items, showsAlbum: true)
                    } else {
                        CatalogGrid(items: loader.items, size: scope == .artist ? 80 : 150,
                                    detail: DiscoverCardDetail.search)
                    }
                    LoaderFooter(loader: loader, unit: "条", pageSize: 10, moreTitle: "加载更多 10 条")
                }
                .padding(24)
            }
        }
        .task {
            loader.loadIfNeeded()
            #if DEBUG
                if DebugFixtures.opens("search-more") {
                    while loader.phase == .loading { try? await Task.sleep(for: .milliseconds(10)) }
                    loader.loadMore()
                }
            #endif
        }
    }
}

private struct DiscoverSearchEmpty: View {
    let query: String
    var body: some View {
        ContentUnavailableView("没有找到「\(query)」", systemImage: "magnifyingglass",
                               description: Text("换个关键词，或切换到「全部」。"))
    }
}

nonisolated enum DiscoverCardDetail {
    static func search(_ item: CatalogItem) -> String? {
        switch item.kind {
        case "album": [item.subtitle, item.releaseYear].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case "playlist": item.ownerName ?? item.subtitle
        default: nil
        }
    }

    static func kind(_ item: CatalogItem) -> String? {
        switch item.kind {
        case "album": "专辑"
        case "playlist": "歌单"
        case "artist": "歌手"
        case "episode": "播客单集"
        default: nil
        }
    }
}

struct DiscoverTrackRows: View {
    let tracks: [CatalogItem]
    var showsAlbum = false
    var numbered = false
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks.enumerated(), id: \.offset) { index, track in
                HStack(spacing: 10) {
                    if numbered {
                        Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                    }
                    CoverArt(item: track, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.name).lineLimit(1).help(track.name)
                        HStack(spacing: 4) {
                            ArtistLinks(artists: track.artists, fallback: track.subtitle)
                            if showsAlbum, track.album != nil {
                                Text("·")
                                AlbumLink(album: track.album)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(Formatting.duration(milliseconds: track.durationMS))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 46)
                .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025), in: .rect(cornerRadius: 8))
                .contentShape(.rect)
                .onTapGesture(count: 2) { model.play(track, in: nil) }
                .contextMenu { TrackMenu(track: track) }
                .accessibilityAction(named: "播放") { model.play(track, in: nil) }
            }
        }
    }
}
