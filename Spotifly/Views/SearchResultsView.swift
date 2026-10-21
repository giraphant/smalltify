//
//  SearchResultsView.swift
//  Spotifly
//
//  A search's results, all kinds a few each or one kind in full.
//

import SwiftUI

/// The results of one search, under the scope picker: "Alle" shows a few of each kind, a single
/// scope all that have loaded and "Mehr laden" for the next page. A scope is a step in the
/// history (`Route.searchScope`).
struct SearchResultsView: View {
    let query: String
    let searchResults: SearchResults
    let scope: SearchScope

    @Environment(AppStore.self) private var store
    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    @Environment(TrackService.self) private var trackService
    @Environment(SearchService.self) private var searchService
    @Environment(PlaybackViewModel.self) private var playbackViewModel

    /// How many of each kind "Alle" shows.
    private static let overviewLimit = 5

    /// The results as the tables hold them now. An id the tables no longer hold, such as a
    /// playlist deleted since the search, is left out.
    private var tracks: [Track] {
        limited(searchResults.trackIds.compactMap { store.tracks[$0] }, for: .tracks)
    }

    private var artists: [Artist] {
        limited(searchResults.artistIds.compactMap { store.artists[$0] }, for: .artists)
    }

    private var albums: [Album] {
        limited(searchResults.albumIds.compactMap { store.albums[$0] }, for: .albums)
    }

    private var playlists: [Playlist] {
        limited(searchResults.playlistIds.compactMap { store.playlists[$0] }, for: .playlists)
    }

    /// Nothing of a kind outside the scope, a few under "Alle", all of it under its own scope.
    private func limited<Entity>(_ entities: [Entity], for kind: SearchScope) -> [Entity] {
        switch scope {
        case .all: Array(entities.prefix(Self.overviewLimit))
        case kind: entities
        default: []
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Picker("search.scope", selection: Binding(
                    get: { scope },
                    set: { navigationCoordinator.showSearchScope($0) },
                )) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.horizontal, 28)
                .padding(.top, 4)

                if tracks.isEmpty, artists.isEmpty, albums.isEmpty, playlists.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "search.no_results \(query)"), systemImage: "magnifyingglass")
                    } description: {
                        Text("search.no_results_description")
                    }
                    .padding(.top, 40)
                } else {
                    results
                }
            }
            .padding(.bottom, 24)
        }
        .task(id: searchResults.trackIds) {
            await trackService.ensureFavoriteStatuses(trackIds: searchResults.trackIds)
        }
    }

    @ViewBuilder
    private var results: some View {
        if !tracks.isEmpty {
            header(SearchScope.tracks.title)
            VStack(spacing: 0) {
                ForEach(tracks.enumerated(), id: \.element.id) { index, track in
                    TrackRow(
                        track: track,
                        index: index,
                        currentlyPlayingURI: playbackViewModel.currentTrackUri,
                        currentSection: .searchResults,
                        onDoubleTap: {
                            await playbackViewModel.playRadio(trackUri: track.uri)
                        },
                    )
                }
            }
            .padding(.horizontal, 12)
        }

        if !artists.isEmpty {
            header(SearchScope.artists.title)
            cards(artists) { ArtistCard(artist: $0, size: 120) }
        }

        if !albums.isEmpty {
            header(SearchScope.albums.title)
            cards(albums) { AlbumCard(album: $0, size: 140) }
        }

        if !playlists.isEmpty {
            header(SearchScope.playlists.title)
            cards(playlists) {
                PlaylistCard(playlist: $0, subtitle: localizedTextString("metadata.by_owner", $0.ownerName), size: 140)
            }
        }

        if scope != .all, !searchResults.exhaustedScopes.contains(scope) {
            Button("search.load_more") {
                Task { await searchService.loadMore(query: query, scope: scope) }
            }
            .disabled(searchService.loadingMore.contains(scope))
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.title2.bold())
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 10)
    }

    /// A row of cards under "Alle", a wrapping grid under the kind's own scope, where there can
    /// be dozens.
    @ViewBuilder
    private func cards<Entity: Identifiable>(_ entities: [Entity], card: @escaping (Entity) -> some View) -> some View {
        if scope == .all {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(entities) { card($0) }
                }
                .padding(.horizontal, 28)
            }
            .scrollIndicators(.hidden)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], spacing: 18) {
                ForEach(entities) { card($0) }
            }
            .padding(.horizontal, 28)
        }
    }
}

extension SearchScope {
    /// What the scope picker and its heading call it.
    var title: String {
        switch self {
        case .all: String(localized: "search.scope.all")
        case .tracks: String(localized: "search.scope.tracks")
        case .artists: String(localized: "search.scope.artists")
        case .albums: String(localized: "search.scope.albums")
        case .playlists: String(localized: "search.scope.playlists")
        }
    }
}
