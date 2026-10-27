import SwiftUI

/// Which of a track list's optional columns show. Number, title and duration always do.
struct TrackColumns: OptionSet, Hashable {
    let rawValue: Int
    static let cover = TrackColumns(rawValue: 1 << 0)
    static let artist = TrackColumns(rawValue: 1 << 1)
    static let album = TrackColumns(rawValue: 1 << 2)
    static let added = TrackColumns(rawValue: 1 << 3)
    /// Artists under the title instead of a column, as an album's tracks show featured artists.
    static let artistsUnderTitle = TrackColumns(rawValue: 1 << 4)

    static let library: TrackColumns = [.cover, .artist, .album, .added]
    static let playlist: TrackColumns = [.cover, .artist, .album, .added]
    static let albumTracks: TrackColumns = [.artistsUnderTitle]
}

/// What a sortable track list can be sorted by; nil keeps Spotify's order.
enum TrackSortKey: Hashable {
    case title, artist, album, added, duration
}

struct TrackSort: Hashable {
    var key: TrackSortKey
    var ascending: Bool
}

/// A track's row data: its place in the list as loaded, which numbers it even when sorted.
struct TrackListRow: Identifiable, Hashable {
    let id: Int
    let item: CatalogItem
    var number: Int { id + 1 }
}

/// The app's one track list: liked songs, playlists, albums and search results.
///
/// A `List`, so selection, keyboard navigation and the context menu are native: a click
/// selects, a double click or Return plays, a right click opens `TrackMenu`. The page's header
/// scrolls with the rows, and a `PagedLoader` adds a footer that loads more as it comes into view.
struct TrackList<Header: View>: View {
    let tracks: [CatalogItem]
    var columns: TrackColumns = .library
    /// Played through after a track is started, where the list has one.
    var context: PlaybackContext?
    /// Case-insensitive filter on title, artists and album.
    var filter = ""
    /// Shows sortable column headers; nil hides the header row entirely.
    var sort: Binding<TrackSort?>?
    var loader: PagedLoader?
    /// For "没有匹配「…」的歌曲" and empty pages.
    var emptyMessage = "没有歌曲"
    @ViewBuilder var header: () -> Header

    @Environment(SmalltifyModel.self) private var model
    @State private var selection: Set<TrackListRow.ID> = []

    var body: some View {
        List(selection: $selection) {
            header()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .selectionDisabled()
            if sort != nil || columns.contains(.album) || columns.contains(.artist) {
                TrackHeaderRow(columns: columns, sort: sort)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
            }
            ForEach(rows) { row in
                TrackRowView(row: row, columns: columns, isPlaying: model.player.displaySnapshot.uri == row.item.uri) {
                    model.play(row.item, in: context)
                }
                .onAppear { if row.id == tracks.count - 1 { loader?.loadMore() } }
            }
            if rows.isEmpty, !(loader?.isLoading ?? false) {
                Text(filter.isEmpty ? emptyMessage : "没有匹配「\(filter)」的歌曲")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .selectionDisabled()
            }
            if let loader {
                LoaderFooter(loader: loader, unit: "首")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: TrackListRow.ID.self) { ids in
            if let id = ids.first, tracks.indices.contains(id) {
                TrackMenu(track: tracks[id], context: context)
            }
        } primaryAction: { ids in
            if let id = ids.first, tracks.indices.contains(id) {
                model.play(tracks[id], in: context)
            }
        }
    }

    private var rows: [TrackListRow] {
        var rows = tracks.enumerated().map { TrackListRow(id: $0.offset, item: $0.element) }
        let query = filter.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            rows = rows.filter { row in
                row.item.name.localizedCaseInsensitiveContains(query)
                    || row.item.subtitle.localizedCaseInsensitiveContains(query)
                    || (row.item.album?.name.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        if let sort = sort?.wrappedValue {
            rows.sort { lhs, rhs in
                let ordered = Self.precedes(lhs.item, rhs.item, by: sort.key)
                return sort.ascending ? ordered : Self.precedes(rhs.item, lhs.item, by: sort.key)
            }
        }
        return rows
    }

    private static func precedes(_ lhs: CatalogItem, _ rhs: CatalogItem, by key: TrackSortKey) -> Bool {
        switch key {
        case .title: lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .artist: lhs.subtitle.localizedStandardCompare(rhs.subtitle) == .orderedAscending
        case .album: (lhs.album?.name ?? "").localizedStandardCompare(rhs.album?.name ?? "") == .orderedAscending
        case .added: (lhs.addedAt ?? .distantPast) < (rhs.addedAt ?? .distantPast)
        case .duration: lhs.durationMS < rhs.durationMS
        }
    }
}

extension TrackList where Header == EmptyView {
    init(tracks: [CatalogItem], columns: TrackColumns = .library, context: PlaybackContext? = nil,
         filter: String = "", sort: Binding<TrackSort?>? = nil, loader: PagedLoader? = nil,
         emptyMessage: String = "没有歌曲") {
        self.init(tracks: tracks, columns: columns, context: context, filter: filter, sort: sort,
                  loader: loader, emptyMessage: emptyMessage) { EmptyView() }
    }
}

/// One track: number or playing indicator, cover, title, and the columns the list shows.
struct TrackRowView: View {
    let row: TrackListRow
    let columns: TrackColumns
    let isPlaying: Bool
    let play: () -> Void

    var body: some View {
        ColumnsLayout {
            Button(action: play) {
                if isPlaying {
                    Image(systemName: "chart.bar.fill")
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("正在播放")
                } else {
                    Text("\(row.number)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .help("播放 \(row.item.name)")
            .column(.fixed(32))

            HStack(spacing: 10) {
                if columns.contains(.cover) {
                    CoverArt(item: row.item, size: 34)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.item.name)
                        .fontWeight(isPlaying ? .semibold : .regular)
                        .lineLimit(1)
                        .help(row.item.name)
                    if columns.contains(.artistsUnderTitle), !row.item.artists.isEmpty {
                        ArtistLinks(artists: row.item.artists).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .column(.flexible(2))

            if columns.contains(.artist) {
                ArtistLinks(artists: row.item.artists, fallback: row.item.subtitle)
                    .foregroundStyle(.secondary)
                    .column(.flexible(1))
            }
            if columns.contains(.album) {
                AlbumLink(album: row.item.album)
                    .foregroundStyle(.secondary)
                    .column(.flexible(1))
            }
            if columns.contains(.added) {
                Text(row.item.addedAt.map { Formatting.added($0) } ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .column(.fixed(84))
            }
            Text(row.item.durationMS > 0 ? Formatting.duration(milliseconds: row.item.durationMS) : "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .column(.fixed(48))
        }
        .frame(minHeight: columns.contains(.cover) ? 38 : 30)
    }
}

/// The column titles; with a sort binding, clicking one sorts by it, a second click reverses.
struct TrackHeaderRow: View {
    let columns: TrackColumns
    let sort: Binding<TrackSort?>?

    var body: some View {
        ColumnsLayout {
            Text("#").column(.fixed(32))
            title("歌名", .title).column(.flexible(2))
            if columns.contains(.artist) { title("歌手", .artist).column(.flexible(1)) }
            if columns.contains(.album) { title("专辑", .album).column(.flexible(1)) }
            if columns.contains(.added) { title("添加时间", .added).column(.fixed(84)) }
            title("时长", .duration)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .column(.fixed(48))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func title(_ text: String, _ key: TrackSortKey) -> some View {
        if let sort {
            let current = sort.wrappedValue?.key == key ? sort.wrappedValue : nil
            Button {
                // Ascending, then descending, then Spotify's own order again.
                switch current?.ascending {
                case nil: sort.wrappedValue = TrackSort(key: key, ascending: key != .added)
                case (key != .added)?: sort.wrappedValue = TrackSort(key: key, ascending: key == .added)
                default: sort.wrappedValue = nil
                }
            } label: {
                HStack(spacing: 3) {
                    Text(text).fontWeight(current == nil ? .regular : .semibold)
                    if let current {
                        Image(systemName: current.ascending ? "chevron.up" : "chevron.down").imageScale(.small)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(current == nil ? .secondary : .primary)
        } else {
            Text(text)
        }
    }
}

/// The actions on one track, for its context menu and the "…" buttons.
struct TrackMenu: View {
    let track: CatalogItem
    var context: PlaybackContext?
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        Button("播放") { model.play(track, in: context) }
        Button("加入队列") { model.enqueue(track) }
            .disabled(track.kind != "track" && track.kind != "episode")
        Divider()
        if track.artists.count > 1 {
            Menu("去歌手页") {
                ForEach(track.artists) { artist in
                    Button(artist.name) { model.open(artist) }
                }
            }
        } else if let artist = track.artists.first {
            Button("去歌手页") { model.open(artist) }
        }
        if let album = track.album {
            Button("去专辑页") { model.open(album) }
        }
        Divider()
        Button("复制链接") { model.copyLink(track.openURL) }
        Button("在 Spotify 中打开") { model.openInSpotify(track.openURL) }
    }
}
