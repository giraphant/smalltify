//
//  NowPlayingInspector.swift
//  Spotifly
//
//  "Now Playing": the playing track large, and what comes next
//

import SwiftUI

/// The window's inspector: the playing track's cover, title, artist and album, and the next eight
/// tracks of the queue, each of which plays on a click.
struct NowPlayingInspector: View {
    @Environment(AppStore.self) private var store
    @Environment(PlayerModel.self) private var player
    @Environment(PlaybackViewModel.self) private var playbackViewModel

    /// How many of the next tracks it lists.
    private static let upNextLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("inspector.title")
                .font(.headline)
                .padding(.horizontal, 16)
                .frame(height: 52)

            if let track = playbackViewModel.currentTrack {
                nowPlaying(track)

                Divider()

                upNext
            } else {
                ContentUnavailableView("inspector.nothing_playing", systemImage: "music.note")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Opaque, as the handoff draws it: the glass let the page's covers bleed through.
        .background(.background)
    }

    private func nowPlaying(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Artwork(
                images: track.images,
                size: 280,
                shape: AnyShape(.rect(cornerRadius: 10)),
                symbol: "music.note",
                symbolFont: .system(size: 60),
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.title2.bold())
                Text(track.artistName)
                    .foregroundStyle(.secondary)
                if let albumName = track.albumName {
                    Text(albumName)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    /// One of the next tracks, identified by its place in the queue: a track can be queued twice.
    private struct UpNextItem: Identifiable {
        let id: Int
        let row: PlaybackViewModel.QueueRow
        let track: Track
    }

    /// The queue's next tracks the store has metadata for; `QueueService` loads it on every change
    /// of the queue, as the Queue page needs it too.
    private var upNextItems: [UpNextItem] {
        Array(player.queueEntries.nextTracks.enumerated().lazy.compactMap { index, entry in
            store.tracks[entry.trackId].map { track in
                UpNextItem(id: index, row: .next(index: index, trackUri: track.uri, uid: entry.uid), track: track)
            }
        }
        .prefix(Self.upNextLimit))
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("inspector.up_next")
                    .font(.headline)
                Spacer()
                Text(localizedNumberString("metadata.tracks", player.queueEntries.nextTracks.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            List(upNextItems) { item in
                Button {
                    playbackViewModel.play(queueRow: item.row)
                } label: {
                    UpNextRow(track: item.track)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// One of the next tracks: the cover, title over artist, and the duration.
private struct UpNextRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 10) {
            Artwork(
                images: track.images,
                size: 32,
                shape: AnyShape(.rect(cornerRadius: 4)),
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

            Text(track.durationFormatted)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(.rect)
    }
}
