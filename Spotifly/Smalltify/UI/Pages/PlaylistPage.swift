import SwiftUI

struct PlaylistPage: View {
    let playlist: CatalogItem
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        let key = Destination.playlist(playlist).key
        let details = model.pages.loader(key + "/details") { DetailItemLoader(item: playlist, model: model) }
        Group {
            if !model.signedIn {
                SignedOutView()
            } else if let url = try? OfficialWebAPI.apiURL(path: "/playlists/\(playlist.spotifyID)/items", query: [
                .init(name: "limit", value: "50"), .init(name: "market", value: "from_token"),
            ]) {
                let tracks = model.pages.loader(key + "/tracks") {
                    DetailTracksLoader(url: url, api: model.api) { [weak model] in model?.report($0) }
                }
                PlaylistDetailContent(details: details, tracks: tracks)
                    .task { details.loadIfNeeded(); tracks.loader.loadIfNeeded() }
            }
        }
        .navigationTitle(details.item.name)
        .navigationSubtitle("歌单")
    }
}

private struct PlaylistDetailContent: View {
    let details: DetailItemLoader
    let tracks: DetailTracksLoader

    var body: some View {
        if let failure = details.failure, !details.loaded {
            PageFailureView(title: "没能加载歌单", message: failure) { details.refresh() }
        } else if !details.loaded {
            LoadingRows()
        } else if tracks.isForbidden {
            ScrollView {
                VStack(spacing: 16) {
                    PlaylistHero(playlist: details.item)
                    DetailRefreshNotice(message: details.failure) { details.refresh() }
                    ContentUnavailableView {
                        Label("看不到这个歌单的曲目", systemImage: "lock")
                    } description: {
                        Text("Spotify 只向第三方应用开放你创建或协作的歌单曲目。整张播放不受影响。")
                            .frame(maxWidth: 400)
                    }
                    .frame(maxWidth: .infinity, minHeight: 330)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [3])))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        } else if let failure = tracks.loader.failure, tracks.loader.items.isEmpty {
            ScrollView {
                PlaylistHero(playlist: details.item).padding(.horizontal, 24)
                PageFailureView(title: "没能加载歌单", message: failure) { tracks.refresh() }
            }
        } else if tracks.loader.items.isEmpty, tracks.loader.phase != .loaded {
            ScrollView {
                PlaylistHero(playlist: details.item).padding(.horizontal, 24)
                LoadingRows()
            }
        } else {
            TrackList(tracks: tracks.loader.items, columns: .playlist, context: PlaybackContext(uri: details.item.uri),
                      loader: tracks.loader) {
                PlaylistHero(playlist: details.item)
                DetailRefreshNotice(message: details.failure) { details.refresh() }
                DetailRefreshNotice(message: tracks.loader.failure) { tracks.refresh() }
            }
        }
    }
}

private struct PlaylistHero: View {
    let playlist: CatalogItem
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        let saved = model.playlistShortcuts.playlists.contains { $0.uri == playlist.uri }
        DetailHero(kind: "歌单 · 由 \(playlist.ownerName ?? playlist.ownerID ?? "…") 创建", title: playlist.name) {
            CoverArt(item: playlist, size: 176)
        } metadata: {
            if let description = playlist.summary {
                Text(PlaylistDescription.plainText(description)).lineLimit(2)
            }
        } actions: {
            ViewThatFits(in: .horizontal) {
                HStack {
                    DetailPlayButtons(item: playlist)
                    PlaylistShortcutButton(playlist: playlist, saved: saved)
                    DetailShareMenu(url: playlist.openURL)
                }
                VStack(alignment: .leading) {
                    HStack { DetailPlayButtons(item: playlist) }
                    HStack {
                        PlaylistShortcutButton(playlist: playlist, saved: saved)
                        DetailShareMenu(url: playlist.openURL)
                    }
                }
            }
        }
    }
}

private struct PlaylistShortcutButton: View {
    let playlist: CatalogItem
    let saved: Bool
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        Button(saved ? "已在常用歌单" : "存到常用歌单", systemImage: saved ? "checkmark" : "bookmark") {
            do {
                try model.playlistShortcuts.save(name: playlist.name, link: playlist.uri)
                model.notices.toast("已存到常用歌单")
            } catch { model.notices.toast(error.localizedDescription, isError: true) }
        }
        .disabled(saved)
        .task {
            #if DEBUG
                if DebugFixtures.opens("detail-shortcut"), !saved {
                    try? model.playlistShortcuts.save(name: playlist.name, link: playlist.uri)
                    model.notices.toast("已存到常用歌单")
                }
            #endif
        }
    }
}

nonisolated enum PlaylistDescription {
    /// Decode after removing markup, so escaped angle brackets remain text and no remote resource loads.
    static func plainText(_ html: String) -> String {
        let stripped = html.replacing(/(?is)<(script|style)\b[^>]*>.*?<\/\1\s*>/, with: "")
            .replacing(/(?i)<\s*(br\b[^>]*|\/p\s*|\/div\s*)>/, with: " ")
            .replacing(/<[^>]*>/, with: "")
        let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
                        "copy": "©", "reg": "®", "trade": "™", "eacute": "é"]
        let decoded = stripped.replacing(/&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[a-zA-Z]+);/) { match in
            let name = String(match.1)
            if let value = entities[name] { return value }
            if name.hasPrefix("#") {
                let hex = name.dropFirst().hasPrefix("x") || name.dropFirst().hasPrefix("X")
                if let number = UInt32(name.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                   let scalar = Unicode.Scalar(number) { return String(scalar) }
            }
            return String(match.0)
        }
        return decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
