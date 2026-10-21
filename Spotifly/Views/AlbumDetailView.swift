//
//  AlbumDetailView.swift
//  Spotifly
//
//  Shows details for an album with track list, using normalized store
//

import SwiftUI

struct AlbumDetailView: View {
    let albumId: String

    @Environment(PlaybackViewModel.self) private var playbackViewModel
    @Environment(AppStore.self) private var store
    @Environment(AlbumService.self) private var albumService
    @Environment(TrackService.self) private var trackService
    @Environment(NavigationCoordinator.self) private var navigationCoordinator

    @State private var isLoading = false
    @State private var failure: LoadFailure?
    @State private var showRemoveConfirmation = false

    /// The album from the store — the only copy. Whatever a load puts there shows
    /// up here, including a load whose original view was torn down mid-flight.
    private var album: Album? {
        store.albums[albumId]
    }

    /// Tracks from the store for this album
    private var tracks: [Track] {
        album?.trackIds.compactMap { store.tracks[$0] } ?? []
    }

    var body: some View {
        // A ZStack, not a Group: a Group hands its `.task` to each branch, so switching
        // between loading and the error started the load again, forever.
        ZStack {
            if let album {
                albumContent(album)
            } else if let failure {
                InlineLoadError(failure: failure) { await loadAlbum() }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(album?.name ?? "")
        .task(id: albumId) {
            await loadAlbum()
        }
        .alert("album.remove.title", isPresented: $showRemoveConfirmation) {
            Button("action.cancel", role: .cancel) {}
            Button("album.remove.action", role: .destructive) {
                removeFromLibrary()
            }
        } message: {
            Text("album.remove.message \(album?.name ?? "")")
        }
        .onToolbarAction(.showAlbumRemoveConfirmation, addressedTo: albumId) {
            showRemoveConfirmation = true
        }
    }

    private func albumContent(_ album: Album) -> some View {
        // Looked up once per redraw, for the header and the table both.
        let tracks = tracks

        return VStack(spacing: 0) {
            header(album, tracks: tracks)

            if isLoading, tracks.isEmpty {
                ProgressView("loading.tracks")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure, tracks.isEmpty {
                InlineLoadError(failure: failure) { await loadAlbum() }
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                // A failed save or removal over the tracks there are.
                if let failure {
                    InlineLoadError(failure: failure) { await loadAlbum() }
                        .padding(.bottom, 8)
                }
                TrackTable(
                    rows: tracks.enumerated().map { TrackTableRow(id: "\($0.offset)", number: $0.offset + 1, track: $0.element) },
                    currentSection: .albums,
                    selectionId: albumId,
                    // An album is read in its own order.
                    sortable: false,
                ) { row in
                    Task {
                        await playbackViewModel.play(uriOrUrl: album.uri, trackIndex: row.number - 1, startingAtUri: row.track.uri)
                    }
                }
            }
        }
    }

    private var isSaved: Bool {
        store.userAlbumIds.contains(albumId)
    }

    private func header(_ album: Album, tracks: [Track]) -> some View {
        DetailHeader(
            kind: album.releaseDate.map { String(localized: "detail.kind.album \(String($0.prefix(4)))") }
                ?? String(localized: "detail.kind.album"),
            title: album.name,
        ) {
            Artwork(images: album.images, size: 132, shape: AnyShape(.rect(cornerRadius: 10)), symbol: "music.note", symbolFont: .system(size: 48))
        } metadata: {
            HStack(spacing: 4) {
                // Only an album that names its artist can offer the way to them.
                if let artistId = album.artistId {
                    Button(album.artistName) {
                        navigationCoordinator.navigateToArtistSection(artistId: artistId)
                    }
                    .buttonStyle(.link)
                    .fontWeight(.semibold)
                } else {
                    Text(album.artistName)
                }
                ForEach([localizedNumberString("metadata.tracks", album.trackCount), tracks.isEmpty ? nil : totalDuration(of: tracks)].compactMap(\.self), id: \.self) {
                    Text("metadata.separator")
                    Text(verbatim: $0)
                }
            }
        } actions: {
            PlayAndShuffleButtons {
                Task { await playbackViewModel.play(uriOrUrl: album.uri) }
            } shuffle: {
                Task { await playbackViewModel.playShuffled(uriOrUrl: album.uri, trackUris: tracks.map(\.uri)) }
            }
            .disabled(tracks.isEmpty)

            Button {
                if isSaved {
                    showRemoveConfirmation = true
                } else {
                    Task {
                        do {
                            try await albumService.saveAlbumToLibrary(albumId: albumId)
                        } catch {
                            failure = LoadFailure(message: String(localized: "error.save_album \(error.localizedDescription)"))
                        }
                    }
                }
            } label: {
                Label(isSaved ? "detail.in_library" : "detail.add_to_library", systemImage: isSaved ? "checkmark" : "plus")
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadAlbum() async {
        // Only claim to be loading when the track list is actually missing —
        // a cached album must not flash a spinner over its tracks.
        isLoading = album?.tracksLoaded != true
        failure = nil

        do {
            try await albumService.ensureAlbumLoaded(albumId: albumId)
        } catch {
            // A cancellation is this view going away, not a failure: the load keeps
            // running and its result is in the store for whatever replaces us.
            if !isCancellation(error) {
                failure = LoadFailure(error)
            }
        }

        isLoading = false
    }

    private func removeFromLibrary() {
        Task {
            do {
                // The page stays, as the toggle it was: the list keeps showing the album
                // selected while it is open.
                try await albumService.removeAlbumFromLibrary(albumId: albumId)
            } catch {
                failure = LoadFailure(message: String(localized: "error.remove_album \(error.localizedDescription)"))
            }
        }
    }
}
