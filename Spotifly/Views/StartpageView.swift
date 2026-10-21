//
//  StartpageView.swift
//  Spotifly
//
//  The start page: what was played last, the listener's top tracks and artists, and playlists.
//

import SwiftUI

/// The start page, in the redesign's four sections (`plans/done/redesign-home.md`).
///
/// "Zuletzt gehört" is one shelf of Spotify's own `home` page, the one that lists the contexts
/// last played; the top tracks and artists come from `userTopContent`, a range at a time; the
/// playlists are the library's.
struct StartpageView: View {
    @Environment(AppStore.self) private var store
    @Environment(HomeService.self) private var homeService
    @Environment(PlaylistService.self) private var playlistService
    @Environment(PlaybackViewModel.self) private var playbackViewModel
    @Environment(NavigationCoordinator.self) private var navigationCoordinator

    /// The top tracks' range, kept across launches.
    @AppStorage("startpageTopTracksRange") private var range: TopContentRange = .mid

    /// How many playlists the row shows; "Alle anzeigen" opens the rest.
    private static let playlistLimit = 9

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let recent = store.recentlyPlayedSection {
                    header("home.recently_played")
                    cardRow {
                        ForEach(recent.items) { item in
                            card(for: item)
                        }
                    }
                }

                header("home.top_tracks") {
                    Picker("home.range", selection: $range) {
                        Text("home.range.short").tag(TopContentRange.short)
                        Text("home.range.mid").tag(TopContentRange.mid)
                        Text("home.range.long").tag(TopContentRange.long)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                topTracks

                if !topArtists.isEmpty {
                    header("home.top_artists")
                    cardRow {
                        ForEach(topArtists) { artist in
                            ArtistCard(artist: artist, size: 130)
                        }
                    }
                }

                if !playlists.isEmpty {
                    header("home.your_playlists") {
                        Button("home.show_all") {
                            navigationCoordinator.selectNavigationItem(.playlists)
                        }
                        .buttonStyle(.link)
                    }
                    cardRow {
                        ForEach(playlists) { playlist in
                            PlaylistCard(playlist: playlist, subtitle: subtitle(for: playlist), size: 150)
                        }
                    }
                }

                if store.homeSections.isEmpty, store.topContent.isEmpty {
                    placeholder
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable {
            await homeService.refresh()
        }
        // The artists' range, whichever the tracks show, and the library's playlists, which
        // otherwise load only when Playlists opens.
        .task {
            async let playlists: Void? = try? playlistService.loadUserPlaylists()
            await homeService.loadTopContent(range: .mid)
            _ = await playlists
        }
        .task(id: range) {
            await homeService.loadTopContent(range: range)
        }
    }

    // MARK: - Sections

    private func header(_ title: LocalizedStringKey) -> some View {
        header(title) { EmptyView() }
    }

    private func header(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.title2.bold())
            Spacer()
            trailing()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    /// A horizontal row of cards, 16 pt apart.
    private func cardRow(@ViewBuilder content: () -> some View) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 16) {
                content()
            }
            .padding(.horizontal, 28)
        }
        .scrollIndicators(.hidden)
    }

    /// An id with no entity draws nothing: the shelf is stored as ids, and a card cannot be drawn
    /// from one alone.
    @ViewBuilder
    private func card(for item: HomeItem) -> some View {
        switch item {
        case let .album(id):
            if let album = store.albums[id] {
                AlbumCard(album: album, size: 150)
            }
        case let .playlist(id):
            if let playlist = store.playlists[id] {
                PlaylistCard(playlist: playlist, subtitle: subtitle(for: playlist), size: 150)
            }
        case let .artist(id):
            if let artist = store.artists[id] {
                ArtistCard(artist: artist, size: 150)
            }
        }
    }

    // MARK: - Top tracks

    private var topTrackList: [Track] {
        (store.topContent[range]?.trackIds ?? []).compactMap { store.tracks[$0] }
    }

    private var topArtists: [Artist] {
        (store.topContent[.mid]?.artistIds ?? []).compactMap { store.artists[$0] }
    }

    @ViewBuilder
    private var topTracks: some View {
        let tracks = topTrackList
        if tracks.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 2) {
                ForEach(tracks.enumerated(), id: \.element.id) { index, track in
                    TopTrackRow(rank: index + 1, track: track)
                        .onTapGesture(count: 2) {
                            play(tracks, from: index)
                        }
                }
            }
            .padding(.horizontal, 28)
        }
    }

    /// Plays the top tracks as a list, from the one double-clicked. One Spotify will not play
    /// starts nothing, as in every list.
    private func play(_ tracks: [Track], from index: Int) {
        if let message = tracks[index].unplayableMessage {
            playbackViewModel.errorMessage = message
            return
        }
        Task {
            await playbackViewModel.playTracks(tracks[index...].map(\.uri))
        }
    }

    // MARK: - Playlists

    private var playlists: [Playlist] {
        store.userPlaylistIds.prefix(Self.playlistLimit).compactMap { store.playlists[$0] }
    }

    /// The listener's own playlist by its track count, anyone else's by its owner, as the
    /// handoff's cards say it. A count is known only once the tracks are: the library and the
    /// home page name none, and record that as 0, so until then the owner stands in.
    private func subtitle(for playlist: Playlist) -> String {
        playlist.ownerId == store.userId && playlist.tracksLoaded
            ? localizedNumberString("metadata.tracks", playlist.trackCount)
            : String(localized: "home.playlist_by \(playlist.ownerName)")
    }

    // MARK: - Empty

    /// Loading, failure and "Spotify sent nothing" share a frame rather than three blocks.
    private var placeholder: some View {
        Group {
            if store.homeIsLoading {
                ProgressView()
            } else if let error = store.homeErrorMessage {
                ContentUnavailableView {
                    Label("startpage.error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("action.try_again") {
                        Task { await homeService.refresh() }
                    }
                }
            } else {
                ContentUnavailableView(
                    "startpage.empty",
                    systemImage: "house",
                    description: Text("startpage.empty.description"),
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Top track row

/// One of the top tracks: its rank, a 36 pt cover, title over artist, and a separator under it.
private struct TopTrackRow: View {
    let rank: Int
    let track: Track

    var body: some View {
        HStack(spacing: 10) {
            Text(rank, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 18, alignment: .trailing)

            Artwork(
                images: track.images,
                size: 36,
                shape: Self.artworkShape,
                symbol: "music.note",
                symbolFont: .caption,
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                Text(track.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .contentShape(.rect)
        .opacity(track.isPlayable ? 1 : 0.5)
        .help(ifAny: track.unplayableMessage)
    }

    /// Built once rather than on every redraw, as `TrackRow`'s is.
    private static let artworkShape = AnyShape(.rect(cornerRadius: 4))
}
