//
//  QueueListView.swift
//  Spotifly
//
//  Displays the player's queue, as `PlayerModel.queueEntries` gives it
//

import SwiftUI

extension Notification.Name {
    static let scrollToCurrentTrack = Notification.Name("scrollToCurrentTrack")

    // Toolbar menu actions
    static let showArtistUnfollowConfirmation = Notification.Name("showArtistUnfollowConfirmation")
    static let showPlaylistEditDetails = Notification.Name("showPlaylistEditDetails")
    static let showPlaylistCoverPicker = Notification.Name("showPlaylistCoverPicker")
    static let showPlaylistRemoveCoverConfirmation = Notification.Name("showPlaylistRemoveCoverConfirmation")
    static let showPlaylistDeleteConfirmation = Notification.Name("showPlaylistDeleteConfirmation")
    static let showPlaylistUnfollowConfirmation = Notification.Name("showPlaylistUnfollowConfirmation")
}

extension View {
    /// Runs `action` when one of the toolbar menu actions above is addressed to this view's
    /// entity.
    ///
    /// The toolbar has no way to reach the open detail view but a notification, and every
    /// detail view asks the same question of the ones it receives: is this one for me? The
    /// entity id travels as the notification's object.
    func onToolbarAction(
        _ name: Notification.Name,
        addressedTo id: String,
        perform action: @escaping () -> Void,
    ) -> some View {
        onReceive(NotificationCenter.default.publisher(for: name)) { notification in
            guard notification.object as? String == id else { return }
            action()
        }
    }
}

struct QueueListView: View {
    @Environment(AppStore.self) private var store
    @Environment(PlayerModel.self) private var player
    @Environment(DeviceService.self) private var deviceService
    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    @Environment(TrackService.self) private var trackService
    @Environment(PlaybackViewModel.self) private var playbackViewModel

    /// The id of the row for the track playing now.
    private static let currentRowId = "current"

    /// The queue as table rows, numbered over the whole queue: previous, current, next. A track
    /// whose metadata has not arrived has no row, and each row keeps the one a double-click
    /// plays, by its index in its own list.
    private func queueRows() -> [(row: TrackTableRow, queueRow: PlaybackViewModel.QueueRow)] {
        let queue = player.queueEntries
        var rows: [(TrackTableRow, PlaybackViewModel.QueueRow)] = []

        func append(_ id: String, _ track: Track, _ provider: TrackProvider, _ queueRow: PlaybackViewModel.QueueRow, isPast: Bool = false) {
            rows.append((TrackTableRow(id: id, number: rows.count + 1, track: track, isPast: isPast, tag: provider.symbol), queueRow))
        }

        for (index, entry) in queue.previousTracks.enumerated() {
            if let track = store.tracks[entry.trackId] {
                append("p\(index)", track, entry.provider, .previous(index: index, trackUri: track.uri, uid: entry.uid), isPast: true)
            }
        }
        if let entry = queue.currentTrack, let track = store.tracks[entry.trackId] {
            append(Self.currentRowId, track, entry.provider, .current)
        }
        for (index, next) in queue.nextRows(in: store.tracks).enumerated() {
            append("n\(index)", next.track, next.entry.provider, next.row)
        }
        return rows
    }

    /// The context the queue plays from: its name, and the page the name opens, where it has
    /// one. Read from the player, which says what it plays from with every queue it publishes:
    /// a copy in the store kept the last non-empty one, so a bare list of tracks played under
    /// the name of the album before it.
    ///
    /// The app's own name comes first, as the one it shows everywhere else: the store's, and
    /// for Liked Songs, which plays as a playlist the store has no entry for, the section's.
    /// The player's, from the resolver or the cluster, names the rest, such as a playlist
    /// started on another device or a radio station, which has no page to open.
    private var contextInfo: (route: Route?, name: String)? {
        guard let queue = player.queue, let uri = queue.context else { return nil }

        let route = Route(contextUri: uri)
        let ownName = if let selection = route?.selection {
            store.name(of: selection)
        } else {
            route?.section?.title
        }

        guard let name = ownName ?? queue.contextName else { return nil }
        return (route, name)
    }

    var body: some View {
        // Built once per redraw, for the table and the favorites check.
        let rows = queueRows()

        VStack(alignment: .leading, spacing: 0) {
            queueHeader

            if rows.isEmpty {
                emptyView
            } else {
                ScrollViewReader { proxy in
                    TrackTable(rows: rows.map(\.row), currentSection: .queue, sortable: false) { row in
                        if let queueRow = rows.first(where: { $0.row.id == row.id })?.queueRow {
                            playbackViewModel.play(queueRow: queueRow)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .scrollToCurrentTrack)) { _ in
                        withAnimation {
                            proxy.scrollTo(Self.currentRowId, anchor: .center)
                        }
                    }
                }
            }
        }
        // The table checks its rows' hearts when their number changes; the queue moves on with
        // the same number, so the playing track's change asks too.
        .task(id: player.queueEntries.currentTrack?.trackId) {
            await trackService.ensureFavoriteStatuses(trackIds: rows.map(\.row.track.id))
        }
    }

    // MARK: - Header

    private var queueHeader: some View {
        let queue = player.queueEntries

        return VStack(alignment: .leading, spacing: 4) {
            Text("queue.title")
                .font(.largeTitle.bold())

            if queue.length > 0 {
                Text(verbatim: [
                    localizedNumberString("metadata.tracks", queue.length),
                    String(localized: "queue.upcoming \(queue.nextTracks.count)"),
                ].joined(separator: " \(String(localized: "metadata.separator")) "))
                    .foregroundStyle(.secondary)
            }

            // "Playing from X on Y"
            if let device = player.activeDevice {
                playingFromText(device: device)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func playingFromText(device: Device) -> some View {
        let deviceIcon = deviceService.deviceIcon(for: device.type)

        HStack(spacing: 4) {
            if let context = contextInfo {
                Text("queue.playing_from")

                if let route = context.route {
                    Button {
                        navigationCoordinator.navigate(to: route)
                    } label: {
                        Text("queue.context_name \(context.name)")
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("queue.context_name \(context.name)")
                }

                Text("queue.on_device")
            } else {
                // A bare list of tracks, or a context nothing names.
                Text("queue.playing_on")
            }

            Image(systemName: deviceIcon)
            Text(device.name)
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("empty.queue_empty")
                .font(.headline)
            Text("empty.queue_empty.description")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
