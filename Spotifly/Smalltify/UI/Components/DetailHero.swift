import Observation
import SwiftUI

struct DetailHero<Artwork: View, Metadata: View, Actions: View>: View {
    let kind: String
    let title: String
    @ViewBuilder let artwork: Artwork
    @ViewBuilder let metadata: Metadata
    @ViewBuilder let actions: Actions

    var body: some View {
        DetailHeroLayout {
            artwork
            DetailHeroText(kind: kind, title: title, metadata: metadata, actions: actions)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

/// Choose from the proposed width, so a table measuring its header cannot alternate between layouts.
private struct DetailHeroLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? 300
        let art = subviews[0].sizeThatFits(.unspecified)
        let stacked = width < 700
        let text = subviews[1].sizeThatFits(.init(width: stacked ? width : max(0, width - art.width - 22), height: nil))
        return CGSize(width: width, height: stacked ? art.height + 16 + text.height : max(art.height, text.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let art = subviews[0].sizeThatFits(.unspecified)
        let stacked = bounds.width < 700
        let textProposal = ProposedViewSize(width: stacked ? bounds.width : max(0, bounds.width - art.width - 22), height: nil)
        let text = subviews[1].sizeThatFits(textProposal)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: stacked ? bounds.minY : bounds.maxY - art.height),
                          anchor: .topLeading, proposal: .init(art))
        subviews[1].place(at: CGPoint(x: stacked ? bounds.minX : bounds.minX + art.width + 22,
                                     y: stacked ? bounds.minY + art.height + 16 : bounds.maxY - text.height),
                          anchor: .topLeading, proposal: textProposal)
    }
}

private struct DetailHeroText<Metadata: View, Actions: View>: View {
    let kind: String
    let title: String
    let metadata: Metadata
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind).font(.caption).foregroundStyle(.secondary)
            Text(title).font(.largeTitle).bold().lineLimit(2).help(title)
            metadata.font(.callout).foregroundStyle(.secondary)
            actions.padding(.top, 8)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
}

struct DetailShareMenu: View {
    let url: URL?
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        Menu("更多", systemImage: "ellipsis") {
            Button("复制链接") { model.copyLink(url) }
            Button("在 Spotify 中打开") { model.openInSpotify(url) }
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .help("更多")
    }
}

struct DetailLibraryButton: View {
    let state: LibraryWrites
    var artist = false

    var body: some View {
        if state.isSaved == nil, state.failure != nil {
            Button("重试", systemImage: "arrow.clockwise") { state.refresh() }
                .help("重新读取收藏状态")
        } else {
            Button(artist ? (state.isSaved == true ? "已关注" : "关注") : (state.isSaved == true ? "取消收藏专辑" : "收藏专辑"),
                   systemImage: state.isSaved == true ? "checkmark" : "plus") {
                Task { await state.toggle() }
            }
            .labelStyle(DetailLibraryLabelStyle(artist: artist))
            .task(id: state.isSaved != nil) {
                #if DEBUG
                    if DebugFixtures.opens("detail-toggle"), state.isSaved != nil {
                        try? await Task.sleep(for: .milliseconds(700))
                        await state.toggle()
                    }
                #endif
            }
            .disabled(state.isSaved == nil || state.checking || state.writing)
            .help(artist ? (state.isSaved == true ? "取消关注" : "关注") : (state.isSaved == true ? "取消收藏专辑" : "收藏专辑"))
        }
    }
}

private struct DetailLibraryLabelStyle: LabelStyle {
    let artist: Bool
    func makeBody(configuration: Configuration) -> some View {
        if artist { configuration.title } else { configuration.icon }
    }
}

struct DetailPlayButtons: View {
    let item: CatalogItem
    @Environment(SmalltifyModel.self) private var model
    @State private var starting = false

    var body: some View {
        Button(item.kind == "playlist" ? "播放整张" : "播放", systemImage: "play.fill") { model.play(uri: item.uri) }
            .buttonStyle(.borderedProminent)
            .disabled(model.player.starting || starting)
        Button("随机播放", systemImage: "shuffle") {
            guard model.ensurePlayerReady() else { return }
            starting = true
            Task {
                defer { starting = false }
                do {
                    try await model.player.send("set_shuffle", enabled: true)
                    try await model.player.send("play", uri: item.uri)
                } catch { model.report(error); model.notices.toast(error.localizedDescription, isError: true) }
            }
        }
        .disabled(model.player.starting || starting)
    }
}

/// Header loads survive view teardown, and a refresh cannot be overwritten by an older request.
@MainActor @Observable final class DetailItemLoader: Refreshable {
    private(set) var item: CatalogItem
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var failure: String?
    private let fetch: @Sendable () async throws -> CatalogItem
    private let report: (Error) -> Void
    private var generation = 0

    init(item: CatalogItem, fetch: @escaping @Sendable () async throws -> CatalogItem,
         report: @escaping (Error) -> Void = { _ in }) {
        self.item = item
        self.fetch = fetch
        self.report = report
    }

    convenience init(item: CatalogItem, model: SmalltifyModel) {
        self.init(item: item, fetch: { [api = model.api] in
            #if DEBUG
                await FixtureData.delayDetailLoad()
            #endif
            let url = try OfficialWebAPI.apiURL(path: "/\(item.kind)s/\(item.spotifyID)", query: [.init(name: "market", value: "from_token")])
            return try Self.parse(await api.get(url), expectedURI: item.uri)
        }, report: { [weak model] in model?.report($0) })
    }

    nonisolated static func parse(_ data: Data, expectedURI: String) throws -> CatalogItem {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = CatalogItem.parse(object), item.uri == expectedURI else {
            throw SmalltifyError("Spotify 详情响应格式无效。")
        }
        return item
    }

    func loadIfNeeded() { if !loaded, !loading, failure == nil { refresh() } }

    func refresh() {
        generation += 1
        let run = generation
        loading = true
        failure = nil
        Task {
            defer { if run == generation { loading = false } }
            do {
                let item = try await fetch()
                guard run == generation else { return }
                self.item = item
                loaded = true
            } catch {
                guard run == generation else { return }
                failure = error.localizedDescription
                report(error)
            }
        }
    }
}

/// Retains the reason for a rejected playlist without interpreting localized error text.
@MainActor @Observable final class DetailTracksLoader: Refreshable {
    let loader: PagedLoader

    init(url: URL, api: OfficialWebAPI, report: @escaping (Error) -> Void) {
        let rejection = DetailTrackRejection()
        self.rejection = rejection
        loader = PagedLoader(api: api, url: url) { error in
            rejection.forbidden = (error as? SmalltifyError)?.reason == .forbidden
            report(error)
        }
    }

    private let rejection: DetailTrackRejection
    var isForbidden: Bool { loader.failure != nil && rejection.forbidden }
    func refresh() { rejection.forbidden = false; loader.refresh() }
}

@MainActor @Observable private final class DetailTrackRejection {
    var forbidden = false
}

struct DetailRefreshNotice: View {
    let message: String?
    let retry: () -> Void

    var body: some View {
        if let message {
            HStack {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("重试", action: retry)
            }
            .padding(.vertical, 8)
        }
    }
}
