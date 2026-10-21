//
//  ArtistDetailView.swift
//  Spotifly
//
//  Shows an artist and their discography, using normalized store
//

import SwiftUI

struct ArtistDetailView: View {
    let artistId: String

    @Environment(PlaybackViewModel.self) private var playbackViewModel
    @Environment(AppStore.self) private var store
    @Environment(ArtistService.self) private var artistService

    @State private var isLoadingAlbums = false
    @State private var failure: LoadFailure?
    @State private var group: DiscographyGroup = .albums
    @State private var showUnfollowConfirmation = false

    /// The artist from the store — the only copy. Whatever a load puts there shows
    /// up here, including a load whose original view was torn down mid-flight.
    private var artist: Artist? {
        store.artists[artistId]
    }

    var body: some View {
        // A ZStack, not a Group: a Group hands its `.task` to each branch, so switching
        // between loading and the error started the load again, forever.
        ZStack {
            if let artist {
                artistContent(artist)
            } else if let failure {
                InlineLoadError(failure: failure) { await loadArtist() }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(artist?.name ?? "")
        .task(id: artistId) {
            await loadArtist()
        }
        .alert("artist.unfollow.title", isPresented: $showUnfollowConfirmation) {
            Button("action.cancel", role: .cancel) {}
            Button("artist.unfollow.action", role: .destructive) {
                unfollowArtist()
            }
        } message: {
            Text("artist.unfollow.message \(artist?.name ?? "")")
        }
        .onToolbarAction(.showArtistUnfollowConfirmation, addressedTo: artistId) {
            showUnfollowConfirmation = true
        }
    }

    private func artistContent(_ artist: Artist) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(artist)

                SectionHeader(title: Text("artist.discography")) {
                    Picker("artist.discography", selection: $group) {
                        ForEach(DiscographyGroup.allCases, id: \.self) { group in
                            Text(group.title).tag(group)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                if isLoadingAlbums {
                    ProgressView("loading.albums")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let failure {
                    InlineLoadError(failure: failure) { await loadArtist() }
                } else {
                    releasesGrid
                }
            }
        }
    }

    /// The chosen group's releases, or a line saying there are none.
    @ViewBuilder
    private var releasesGrid: some View {
        let releases = (store.albums(forArtist: artistId) ?? []).filter(group.contains)

        if releases.isEmpty {
            Text("artist.discography.empty")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
        } else {
            CardGrid {
                ForEach(releases) { album in
                    AlbumCard(album: album, subtitle: album.releaseYear ?? "", size: 150)
                }
            }
        }
    }

    private func header(_ artist: Artist) -> some View {
        let isFollowed = store.userArtistIds.contains(artistId)

        return DetailHeader(kind: String(localized: "detail.kind.artist"), title: artist.name) {
            Artwork.detailHeader(artist.images, shape: AnyShape(.circle), symbol: "person.fill")
        } metadata: {
            EmptyView()
        } actions: {
            PlayAndShuffleButtons {
                Task { await playbackViewModel.play(uriOrUrl: artist.uri) }
            }

            LibraryToggleButton(isOn: isFollowed, onTitle: "detail.following", offTitle: "detail.follow") {
                Task {
                    do {
                        try await artistService.followArtist(artistId: artistId)
                    } catch {
                        failure = LoadFailure(message: String(localized: "error.follow_artist \(error.localizedDescription)"))
                    }
                }
            } confirmRemoval: {
                showUnfollowConfirmation = true
            }
        }
    }

    private func loadArtist() async {
        // Only claim to be loading when the album list is actually missing —
        // a cached artist must not flash a spinner over their albums.
        isLoadingAlbums = store.artistAlbumIds[artistId] == nil
        failure = nil

        do {
            try await artistService.ensureArtistLoaded(artistId: artistId)
        } catch {
            // A cancellation is this view going away, not a failure: the load keeps
            // running and its result is in the store for whatever replaces us.
            if !isCancellation(error) {
                failure = LoadFailure(error)
            }
        }

        isLoadingAlbums = false
    }

    private func unfollowArtist() {
        Task {
            do {
                // The page stays, as the toggle it was: the list keeps showing the artist
                // selected while it is open.
                try await artistService.unfollowArtist(artistId: artistId)
            } catch {
                failure = LoadFailure(message: String(localized: "error.unfollow_artist \(error.localizedDescription)"))
            }
        }
    }
}

/// The handoff's three groups of a discography. Spotify types a release `ALBUM`, `SINGLE`, `EP`
/// or `COMPILATION` (measured for Green Day on 2026-10-21), and files EPs under singles.
private enum DiscographyGroup: CaseIterable {
    case albums
    case singles
    case compilations

    func contains(_ album: Album) -> Bool {
        switch self {
        case .albums: album.albumType == "album"
        case .singles: album.albumType == "single" || album.albumType == "ep"
        case .compilations: album.albumType == "compilation"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .albums: "artist.discography.albums"
        case .singles: "artist.discography.singles"
        case .compilations: "artist.discography.compilations"
        }
    }
}
