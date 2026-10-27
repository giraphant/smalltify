import SwiftUI

struct AlbumPage: View {
    let album: CatalogItem
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        let key = Destination.album(album).key
        let details = model.pages.loader(key + "/details") { DetailItemLoader(item: album, model: model) }
        let library = model.pages.loader(key + "/saved") { LibraryWrites(uri: album.uri, model: model) }
        Group {
            if !model.signedIn {
                SignedOutView()
            } else if let url = try? OfficialWebAPI.apiURL(path: "/albums/\(album.spotifyID)/tracks", query: [
                .init(name: "limit", value: "50"), .init(name: "market", value: "from_token"),
            ]) {
                let tracks = model.pagedLoader(key + "/tracks", url: url)
                AlbumDetailContent(details: details, library: library, tracks: tracks)
                    .task { details.loadIfNeeded(); library.loadIfNeeded(); tracks.loadIfNeeded() }
            }
        }
        .navigationTitle(details.item.name)
        .navigationSubtitle("专辑")
    }
}

private struct AlbumDetailContent: View {
    let details: DetailItemLoader
    let library: LibraryWrites
    let tracks: PagedLoader

    var body: some View {
        if let failure = details.failure, !details.loaded {
            PageFailureView(title: "没能加载专辑", message: failure) { details.refresh() }
        } else if !details.loaded {
            LoadingRows()
        } else if let failure = tracks.failure, tracks.items.isEmpty {
            ScrollView {
                AlbumHero(album: details.item, library: library).padding(.horizontal, 24)
                PageFailureView(title: "没能加载专辑", message: failure) { tracks.refresh() }
            }
        } else if tracks.items.isEmpty, tracks.phase != .loaded {
            ScrollView {
                AlbumHero(album: details.item, library: library).padding(.horizontal, 24)
                LoadingRows()
            }
        } else {
            TrackList(tracks: tracks.items, columns: .albumTracks, context: PlaybackContext(uri: details.item.uri),
                      loader: tracks, albumArtists: details.item.artists,
                      footerText: AlbumDetailFormatting.footer(album: details.item, tracks: tracks.items,
                                                               complete: tracks.next == nil && tracks.phase == .loaded)) {
                AlbumHero(album: details.item, library: library)
                DetailRefreshNotice(message: details.failure) { details.refresh() }
                DetailRefreshNotice(message: tracks.failure) { tracks.refresh() }
            }
        }
    }
}

private struct AlbumHero: View {
    let album: CatalogItem
    let library: LibraryWrites

    var body: some View {
        DetailHero(kind: "专辑", title: album.name) {
            CoverArt(item: album, size: 176)
        } metadata: {
            HStack(spacing: 4) {
                ArtistLinks(artists: album.artists, fallback: album.subtitle)
                if let year = album.releaseYear { Text("· \(year)") }
                if let count = album.trackCount { Text("· \(count) 首") }
            }
        } actions: {
            HStack {
                DetailPlayButtons(item: album)
                DetailLibraryButton(state: library)
                DetailShareMenu(url: album.openURL)
            }
        }
    }
}

nonisolated enum AlbumDetailFormatting {
    static func footer(album: CatalogItem, tracks: [CatalogItem], complete: Bool) -> String? {
        guard complete else { return nil }
        let count = tracks.count
        let duration = Formatting.totalDuration(milliseconds: tracks.reduce(0) { $0 + $1.durationMS })
        return [album.releaseYear, "\(count) 首，\(duration)"].compactMap { $0 }.joined(separator: " · ")
    }
}
