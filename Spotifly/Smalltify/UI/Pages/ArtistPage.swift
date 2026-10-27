import Observation
import SwiftUI

struct ArtistPage: View {
    let artist: CatalogArtist
    @Environment(SmalltifyModel.self) private var model
    @State private var group = ArtistReleaseGroup.all

    var body: some View {
        let key = Destination.artist(artist).key
        let profile = model.pages.loader(key + "/profile") { DetailArtistLoader(artist: artist, catalog: model.artistCatalog) }
        let library = model.pages.loader(key + "/followed") { LibraryWrites(uri: artist.uri, model: model) }
        Group {
            if !model.signedIn {
                SignedOutView()
            } else if let loader = try? model.artistAlbumsLoader(artist, group: group.rawValue) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DetailHero(kind: "歌手", title: profile.artist.name) {
                            CoverArt(artist: profile.artist, size: 176)
                        } metadata: {
                            EmptyView()
                        } actions: {
                            HStack {
                                DetailLibraryButton(state: library, artist: true)
                                DetailShareMenu(url: profile.artist.openURL)
                            }
                        }
                        if profile.failed {
                            HStack {
                                Text("没能加载歌手资料").foregroundStyle(.secondary)
                                Button("重试") { profile.refresh() }
                            }
                        }
                        Picker("作品分类", selection: $group) {
                            ForEach(ArtistReleaseGroup.allCases) { group in Text(group.title).tag(group) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        LoadedContent(loader: loader, emptyTitle: "这里还没有作品") {
                            CatalogGrid(items: loader.items) { group.detail($0) }
                            LoaderFooter(loader: loader, pageSize: 10)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .task(id: group) { profile.loadIfNeeded(); library.loadIfNeeded(); loader.loadIfNeeded() }
            }
        }
        .navigationTitle(profile.artist.name)
        .navigationSubtitle("歌手")
        .task {
            #if DEBUG
                for candidate in ArtistReleaseGroup.allCases where DebugFixtures.opens("detail-" + candidate.rawValue) {
                    group = candidate
                }
            #endif
        }
    }
}

nonisolated enum ArtistReleaseGroup: String, CaseIterable, Identifiable {
    case all = "album,single"
    case albums = "album"
    case singles = "single"
    case appearances = "appears_on"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "专辑与单曲"
        case .albums: "专辑"
        case .singles: "单曲/EP"
        case .appearances: "参与作品"
        }
    }

    func detail(_ album: CatalogItem) -> String {
        let kind = self == .appearances ? Formatting.artistNames(album.artists, fallback: album.subtitle)
            : album.albumType == "single" ? ((album.trackCount ?? 0) >= 3 ? "EP" : "单曲") : "专辑"
        return [kind, album.releaseYear].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

@MainActor @Observable final class DetailArtistLoader: Refreshable {
    private(set) var artist: CatalogArtist
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var failed = false
    private let catalog: ArtistCatalogLoader
    private var generation = 0

    init(artist: CatalogArtist, catalog: ArtistCatalogLoader) {
        self.artist = artist
        self.catalog = catalog
    }

    func loadIfNeeded() { if !loaded, !loading, !failed { load(refresh: false) } }
    func refresh() { load(refresh: true) }

    private func load(refresh: Bool) {
        generation += 1
        let run = generation
        loading = true
        failed = false
        Task {
            #if DEBUG
                await FixtureData.delayDetailLoad()
            #endif
            let result = await catalog.profile(artistID: artist.spotifyID, refresh: refresh)
            guard run == generation else { return }
            if let result { artist = result; loaded = true } else { failed = true }
            loading = false
        }
    }
}
