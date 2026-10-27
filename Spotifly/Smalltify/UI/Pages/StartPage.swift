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
            contexts.append(Self(uri: uri, kind: kind, fallback: context == nil ? album.flatMap { CatalogItem.parse($0) } : nil))
            if contexts.count == 6 { break }
        }
        return contexts
    }
}

/// Resolution is concurrent, but the shelf keeps the order in the playback history.
actor DiscoverRecentCatalog {
    private let fetch: @Sendable (URL) async throws -> Data
    private var cache: [String: CatalogItem] = [:]
    private var generation = 0

    init(api: OfficialWebAPI) { fetch = { try await api.get($0) } }

    init(fetch: @escaping @Sendable (URL) async throws -> Data) { self.fetch = fetch }

    func load(refresh: Bool) async throws -> [CatalogItem] {
        generation += 1
        let run = generation
        let url = try OfficialWebAPI.apiURL(path: "/me/player/recently-played", query: [.init(name: "limit", value: "50")])
        let contexts = try DiscoverRecentContext.parse(await fetch(url))
        let cached = refresh ? [:] : cache
        let items = try await withThrowingTaskGroup(of: (Int, CatalogItem).self) { group in
            for (index, context) in contexts.enumerated() {
                group.addTask { [fetch] in
                    if let item = cached[context.uri] ?? context.fallback { return (index, item) }
                    let query: [URLQueryItem] = context.kind == "artist" ? [] : [.init(name: "market", value: "from_token")]
                    let data = try await fetch(OfficialWebAPI.apiURL(path: context.path, query: query))
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let item = CatalogItem.parse(object) else {
                        throw SmalltifyError("Spotify 最近播放内容格式无效。")
                    }
                    return (index, item)
                }
            }
            var result: [(Int, CatalogItem)] = []
            for try await item in group { result.append(item) }
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }
        if generation == run {
            for item in items { cache[item.uri] = item }
        }
        return items
    }
}

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
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 28) {
                                    DiscoverTopSection(range: range, type: "tracks")
                                        .frame(minWidth: 340, maxWidth: .infinity, alignment: .leading)
                                    DiscoverTopSection(range: range, type: "artists")
                                        .frame(width: 360, alignment: .leading)
                                }
                                VStack(alignment: .leading, spacing: 24) {
                                    DiscoverTopSection(range: range, type: "tracks")
                                    DiscoverTopSection(range: range, type: "artists")
                                }
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
