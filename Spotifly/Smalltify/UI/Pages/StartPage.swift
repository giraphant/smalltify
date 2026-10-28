import SwiftUI

nonisolated enum DiscoverTimeRange: String, CaseIterable, Identifiable {
    case short = "short_term", medium = "medium_term", long = "long_term"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .short: "4 周"
        case .medium: "6 个月"
        case .long: "1 年"
        }
    }

    func url(type: String) throws -> URL {
        try OfficialWebAPI.apiURL(path: "/me/top/\(type)", query: [
            .init(name: "limit", value: type == "tracks" ? "5" : "6"),
            .init(name: "time_range", value: rawValue),
        ])
    }
}

nonisolated struct DiscoverRecentContext: Sendable, Equatable {
    let uri: String
    let kind: String
    /// Whether the card needs a request for the context. A track played outside any context
    /// is shown as its album, which the history already describes.
    let needsFetch: Bool
    /// The played track's album: the card itself when there is no context, and the stand-in
    /// for a context Spotify answers with 404, as it does for the playlists it makes.
    let fallback: CatalogItem?

    var path: String { "/\(kind)s/\(uri.split(separator: ":").last ?? "")" }

    static func parse(_ data: Data) throws -> [Self] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["items"] as? [[String: Any]] else {
            throw SmalltifyError("Spotify 最近播放响应格式无效。")
        }
        var seen = Set<String>()
        var contexts: [Self] = []
        for entry in entries {
            let context = entry["context"] as? [String: Any]
            let track = entry["track"] as? [String: Any]
            let album = track?["album"] as? [String: Any]
            let candidate = context ?? album
            guard let uri = candidate?["uri"] as? String,
                  CatalogItem.validURI(uri) || CatalogArtist.validURI(uri) else { continue }
            let kind = String(uri.split(separator: ":")[1])
            guard ["album", "playlist", "artist"].contains(kind), seen.insert(uri).inserted else { continue }
            contexts.append(Self(uri: uri, kind: kind, needsFetch: context != nil,
                                 fallback: album.flatMap { CatalogItem.parse($0) }))
            if contexts.count == 6 { break }
        }
        return contexts
    }
}

/// Resolution is concurrent, but the shelf keeps the order in the playback history.
actor DiscoverRecentCatalog {
    private let fetch: @Sendable (URL) async throws -> Data
    private var cache: [String: CatalogItem] = [:]
    /// Contexts Spotify answered with 404, so later loads show their fallback without asking again.
    private var missing: Set<String> = []
    private var generation = 0

    init(api: OfficialWebAPI) { fetch = { try await api.get($0) } }

    init(fetch: @escaping @Sendable (URL) async throws -> Data) { self.fetch = fetch }

    func load(refresh: Bool) async throws -> [CatalogItem] {
        generation += 1
        let run = generation
        let url = try OfficialWebAPI.apiURL(path: "/me/player/recently-played", query: [.init(name: "limit", value: "50")])
        let contexts = try DiscoverRecentContext.parse(await fetch(url))
        let cached = refresh ? [:] : cache
        let skipped = refresh ? [] : missing
        let resolved = try await withThrowingTaskGroup(of: (index: Int, item: CatalogItem?, missing: Bool).self) { group in
            for (index, context) in contexts.enumerated() {
                group.addTask { [fetch] in
                    if let item = cached[context.uri] { return (index, item, false) }
                    let knownMissing = skipped.contains(context.uri)
                    guard context.needsFetch, !knownMissing else { return (index, context.fallback, knownMissing) }
                    let query: [URLQueryItem] = context.kind == "artist" ? [] : [.init(name: "market", value: "from_token")]
                    let data: Data
                    do {
                        data = try await fetch(OfficialWebAPI.apiURL(path: context.path, query: query))
                    } catch let error as SmalltifyError where error.reason == .notFound {
                        // One context Spotify will not return must not cost the whole shelf.
                        return (index, context.fallback, true)
                    }
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let item = CatalogItem.parse(object) else {
                        throw SmalltifyError("Spotify 最近播放内容格式无效。")
                    }
                    return (index, item, false)
                }
            }
            var result: [(index: Int, item: CatalogItem?, missing: Bool)] = []
            for try await entry in group { result.append(entry) }
            return result.sorted { $0.index < $1.index }
        }
        // A stand-in album can be one the shelf already shows.
        var seen = Set<String>()
        let items = resolved.compactMap(\.item).filter { seen.insert($0.uri).inserted }
        if generation == run {
            if refresh { missing = [] }
            for entry in resolved {
                if entry.missing {
                    missing.insert(contexts[entry.index].uri)
                } else if let item = entry.item {
                    cache[item.uri] = item
                }
            }
        }
        return items
    }
}

/// 首页: what was played recently, and the most played tracks and artists over a time range.
struct StartPage: View {
    @Environment(SmalltifyModel.self) private var model
    @State private var range = DiscoverTimeRange.short

    var body: some View {
        Group {
            if !model.signedIn {
                SignedOutView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        DiscoverRecentShelf()
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("常听").font(.title3).bold()
                                Spacer()
                                Picker("时间范围", selection: $range) {
                                    ForEach(DiscoverTimeRange.allCases) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 220)
                            }
                            DiscoverTopLayout {
                                DiscoverTopSection(range: range, type: "tracks")
                                DiscoverTopSection(range: range, type: "artists")
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle("首页")
        .navigationSubtitle("")
        .task {
            #if DEBUG
                if let fixtureRange = DiscoverTimeRange.allCases.first(where: { DebugFixtures.opens($0.rawValue) }) {
                    range = fixtureRange
                }
            #endif
        }
    }
}

/// 歌曲 beside 歌手 when the page is wide enough, else one above the other. Decided from the
/// proposed width within one layout pass: a state set from the measured width changed the page's
/// minimum width, which resized the split view's column and flipped the state back, until AppKit
/// threw after too many constraint passes.
private struct DiscoverTopLayout: Layout {
    var sideBySideFrom: CGFloat = 732
    var trailingWidth: CGFloat = 360
    var columnSpacing: CGFloat = 28
    var rowSpacing: CGFloat = 24

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? sideBySideFrom
        let height = frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard subviews.count == 2 else { return [] }
        if width >= sideBySideFrom {
            let leading = width - columnSpacing - trailingWidth
            let sizes = [subviews[0].sizeThatFits(.init(width: leading, height: nil)),
                         subviews[1].sizeThatFits(.init(width: trailingWidth, height: nil))]
            return [CGRect(x: 0, y: 0, width: leading, height: sizes[0].height),
                    CGRect(x: leading + columnSpacing, y: 0, width: trailingWidth, height: sizes[1].height)]
        }
        let first = subviews[0].sizeThatFits(.init(width: width, height: nil)).height
        let second = subviews[1].sizeThatFits(.init(width: width, height: nil)).height
        return [CGRect(x: 0, y: 0, width: width, height: first),
                CGRect(x: 0, y: first + rowSpacing, width: width, height: second)]
    }
}

private struct DiscoverRecentShelf: View {
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        let loader: DiscoverLoader<[CatalogItem]> = model.pages.loader("\(Destination.home.key)/recent") {
            let catalog = DiscoverRecentCatalog(api: model.api)
            return DiscoverLoader(report: { [weak model] in model?.report($0) }) { refresh in
                try await catalog.load(refresh: refresh)
            }
        }
        PageSection(title: "最近播放") {
            DiscoverHomeContent(loader: loader, emptyMessage: "还没有最近播放的内容") { items in
                CatalogShelf(items: items, size: 132, detail: DiscoverCardDetail.kind)
            }
        }
        .task { loader.loadIfNeeded() }
    }
}

private struct DiscoverTopSection: View {
    let range: DiscoverTimeRange
    let type: String
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        let loader: DiscoverLoader<[CatalogItem]> = model.pages.loader("\(Destination.home.key)/\(range.rawValue)/\(type)") {
            DiscoverLoader(report: { [weak model] in model?.report($0) }) { [api = model.api] _ in
                try CatalogPage.parse(await api.get(range.url(type: type))).items
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Text(type == "tracks" ? "歌曲" : "歌手")
                .font(.caption).bold().foregroundStyle(.secondary)
            DiscoverHomeContent(loader: loader, emptyMessage: "这个时间范围还没有常听记录") { items in
                if type == "tracks" {
                    DiscoverTrackRows(tracks: Array(items.prefix(5)), numbered: true)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                        ForEach(items.prefix(6)) { item in
                            CatalogCard(item: item, size: 72)
                                .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .task(id: range) { loader.loadIfNeeded() }
    }
}

private struct DiscoverHomeContent<Content: View>: View {
    let loader: DiscoverLoader<[CatalogItem]>
    let emptyMessage: String
    @ViewBuilder let content: ([CatalogItem]) -> Content
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        if loader.needsAuthorization {
            HStack {
                Text("首页需要新的权限，请重新授权一次。")
                    .foregroundStyle(.secondary)
                Button("重新授权") { model.signIn() }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: 10))
        } else if let failure = loader.failure {
            PageFailureView(message: failure) { loader.refresh() }
        } else if let items = loader.value {
            if items.isEmpty {
                Text(emptyMessage).foregroundStyle(.secondary).padding(.vertical, 24)
            } else {
                content(items)
            }
        } else {
            LoadingRows(count: 3).frame(height: 160)
        }
    }
}
