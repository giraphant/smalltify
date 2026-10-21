//
//  NowPlayingBarView.swift
//  Spotifly
//
//  Persistent now playing bar at the bottom of the window
//

import AppKit
import SwiftUI

struct NowPlayingBarView: View {
    @Environment(AppStore.self) private var store
    @Environment(PlayerModel.self) private var player
    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    @Environment(TrackService.self) private var trackService
    @Environment(\.displayScale) private var displayScale
    @Environment(PlaybackViewModel.self) private var playbackViewModel
    @Environment(WindowState.self) private var windowState

    @State private var cachedAlbumArtImage: Image?
    private let network = NetworkMonitor.shared
    @State private var cachedAlbumArtURL: String?
    @State private var isHoveringSeekBar = false
    @State private var showNewPlaylistDialog = false
    @State private var showPlaylistAddedSuccess = false
    /// The bar's own width, which decides what fits.
    @State private var barWidth: CGFloat = Self.maxBarWidth

    @State private var showFullErrorMessage = false

    /// Whether something is currently playing or queued
    private var hasPlayback: Bool {
        playbackViewModel.currentTrackUri != nil
    }

    // The capsule is `min(780, container − 40)` wide and 64 high, 14 above the window's edge.
    private static let maxBarWidth: CGFloat = 780
    private static let barHeight: CGFloat = 64
    private static let barBottomPadding: CGFloat = 14
    /// Under these widths the volume, then the time, make room for the title.
    private static let volumeMinBarWidth: CGFloat = 680
    private static let timeMinBarWidth: CGFloat = 640

    /// The room a scrolling page leaves under its end, which the bar floats over, with 20 to spare.
    static let contentClearance = barHeight + barBottomPadding + 20

    private var isMini: Bool {
        windowState.isMiniPlayerMode
    }

    var body: some View {
        playerLayout
            .frame(height: isMini ? nil : Self.barHeight)
            .frame(maxWidth: isMini ? .infinity : Self.maxBarWidth, maxHeight: isMini ? .infinity : nil)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
            .modifier(NowPlayingBarBackground(isMiniPlayerMode: isMini))
            .padding(.horizontal, isMini ? 0 : 20)
            .padding(.bottom, isMini ? 0 : Self.barBottomPadding)
            .newPlaylistPrompt(
                isPresented: $showNewPlaylistDialog,
                trackId: playbackViewModel.currentTrack?.id,
                onAdded: showSuccessFeedback,
            )
            .task(id: playbackViewModel.currentTrackId) {
                await resolveCurrentTrackMetadataIfNeeded()
            }
            .task(id: playbackViewModel.currentTrackId) {
                await resolveCurrentTrackFavoriteStatusIfNeeded()
            }
    }

    // MARK: - Player Layout

    /// The handoff's three groups: transport, the track, and the track's and output's controls.
    private var playerLayout: some View {
        HStack(spacing: 6) {
            playbackControls

            HStack(spacing: 10) {
                albumArt(size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        trackInfo
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if barWidth >= Self.timeMinBarWidth {
                            timeLabel
                        }
                    }

                    seekSlider
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)

            trailingControls
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
    }

    private var trailingControls: some View {
        HStack(spacing: 2) {
            favoriteButton

            trackMenu

            Button {
                exitMiniPlayerIfNeeded()
                navigationCoordinator.selectNavigationItem(.speakers)
            } label: {
                Image(systemName: "airplay.audio")
            }
            .named("now_playing.playing_on")

            if barWidth >= Self.volumeMinBarWidth {
                volumeControl
            }

            // Its only way back to the full window that is not in a menu.
            if isMini {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        windowState.toggleMiniPlayerMode()
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .named("mini_player.restore")
            }
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func albumArt(size: CGFloat) -> some View {
        if let url = playbackViewModel.currentTrack?.images.url(for: size, scale: displayScale) {
            let urlString = url.absoluteString
            if let cachedImage = cachedAlbumArtImage, cachedAlbumArtURL == urlString {
                // Use cached image
                cachedImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                // Load new image
                RetryingAsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        // Offline, nothing loads until the network returns; see `Artwork`.
                        if network.isOnline {
                            ProgressView()
                                .frame(width: size, height: size)
                        } else {
                            placeholderAlbumArt(size: size)
                        }
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(.rect(cornerRadius: 6))
                            .onAppear {
                                cachedAlbumArtImage = image
                                cachedAlbumArtURL = urlString
                            }
                    case .failure:
                        placeholderAlbumArt(size: size)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        } else {
            placeholderAlbumArt(size: size)
        }
    }

    private func placeholderAlbumArt(size: CGFloat) -> some View {
        Image(systemName: "music.note")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 6))
    }

    /// The track's title and artist, or `PlaybackViewModel.errorMessage` in their place while
    /// it is set — the one place it is shown. Two caption lines fit the same height, and the
    /// mini player has no room above the bar for a banner.
    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let message = playbackViewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    // Without it the row offers one line's height, and the second line the
                    // bar has room for went unused.
                    .fixedSize(horizontal: false, vertical: true)
                    // The full text at once, not as a tooltip: a tooltip waits for the
                    // pointer to rest, and the error was often gone before it appeared.
                    .onHover { hovering in
                        playbackViewModel.isErrorMessageHeld = hovering
                        showFullErrorMessage = hovering
                    }
                    // Removed under the pointer, as when a new play clears the error, the
                    // label gets no hover exit, and a hold left on would keep later errors up.
                    .onDisappear {
                        playbackViewModel.isErrorMessageHeld = false
                        showFullErrorMessage = false
                    }
                    .popover(isPresented: $showFullErrorMessage, arrowEdge: .top) {
                        Text(message)
                            .font(.callout)
                            .frame(width: 280, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                    }
            } else if let track = playbackViewModel.currentTrack {
                Text(track.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: playbackViewModel.errorMessage)
    }

    private var playbackControls: some View {
        HStack(spacing: 2) {
            shuffleToggle

            Button {
                playbackViewModel.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .named("menu.previous_track")
            .disabled(!hasPlayback)

            Button {
                if playbackViewModel.isPlaying {
                    playbackViewModel.pause()
                } else {
                    playbackViewModel.resume()
                }
            } label: {
                Image(systemName: playbackViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .frame(width: 38, height: 38)
                    .contentShape(.circle)
            }
            .named(playbackViewModel.isPlaying ? "action.pause" : "action.play")

            Button {
                playbackViewModel.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .named("menu.next_track")
            .disabled(!playbackViewModel.hasNext)

            repeatButton
        }
        .buttonStyle(.borderless)
    }

    private var shuffleName: LocalizedStringKey {
        playbackViewModel.isShuffleEnabled ? "shuffle.disable" : "shuffle.enable"
    }

    private var shuffleToggle: some View {
        Toggle(isOn: Binding(
            get: { playbackViewModel.isShuffleEnabled },
            set: { _ in playbackViewModel.toggleShuffle() },
        )) {
            Image(systemName: "shuffle")
        }
        .toggleStyle(.button)
        .disabled(!hasPlayback || !playbackViewModel.canShuffle)
        .accessibilityLabel(shuffleName)
        // Greyed out, it says why; a radio cannot be shuffled.
        .help(playbackViewModel.canShuffle ? shuffleName : "shuffle.unavailable")
    }

    /// Three states, so a button that steps through them rather than a toggle: off, the
    /// context, the track, as on Spotify's clients.
    private var repeatButton: some View {
        let mode = playbackViewModel.repeatMode
        return Button {
            playbackViewModel.cycleRepeat()
        } label: {
            Image(systemName: mode == .track ? "repeat.1" : "repeat")
                .foregroundStyle(mode == .off ? Color.primary : Color.accentColor)
        }
        .disabled(!hasPlayback)
        .named(repeatName(mode))
    }

    private func repeatName(_ mode: PlaybackQueue.RepeatMode) -> LocalizedStringKey {
        switch mode {
        case .off: "repeat.off"
        case .context: "repeat.context"
        case .track: "repeat.track"
        }
    }

    /// Current playback position (interpolated for smooth display)
    private var currentPositionMs: UInt32 {
        playbackViewModel.interpolatedPositionMs
    }

    /// The position and the length, "m:ss / m:ss". It ticks once a second, and not while
    /// nothing plays: each tick costs the main thread ~5 ms of SwiftUI update, all of the app's
    /// CPU when idle. A seek or a new position still redraws it, through the view model.
    private var timeLabel: some View {
        TimelineView(.animation(minimumInterval: 1.0, paused: !playbackViewModel.isPlaying)) { _ in
            Text(verbatim: "\(formatTrackTime(milliseconds: Int(currentPositionMs))) / \(formatTrackTime(milliseconds: Int(playbackViewModel.displayedDurationMs ?? 0)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var seekSlider: some View {
        // 10 FPS under the pointer, where a drag wants it, 1 FPS otherwise; paused while nothing
        // plays, as `timeLabel` is.
        TimelineView(.animation(minimumInterval: isHoveringSeekBar ? 0.1 : 1.0, paused: !playbackViewModel.isPlaying)) { _ in
            // The length Control Center shows too, 0 while none is known.
            let durationMs = playbackViewModel.displayedDurationMs ?? 0
            Slider(
                value: Binding(
                    get: { Double(currentPositionMs) },
                    set: { newValue in
                        playbackViewModel.seek(to: UInt32(newValue))
                    },
                ),
                in: 0 ... Double(max(durationMs, 1)),
            )
            .controlSize(.mini)
            // Its value is milliseconds, which accessibility would read out as they are.
            .accessibilityLabel("now_playing.position")
            .accessibilityValue(Text("now_playing.position_value \(formatTrackTime(milliseconds: Int(currentPositionMs))) \(formatTrackTime(milliseconds: Int(durationMs)))"))
            .onHover { hovering in
                isHoveringSeekBar = hovering
            }
        }
        .frame(height: 10)
    }

    /// Whether the current track is favorited (from global store)
    private var isCurrentTrackFavorited: Bool {
        guard let trackId = playbackViewModel.currentTrackId else { return false }
        return store.isFavorite(trackId)
    }

    private var favoriteButton: some View {
        Button {
            Task {
                await playbackViewModel.toggleCurrentTrackFavorite()
            }
        } label: {
            Image(systemName: isCurrentTrackFavorited ? "heart.fill" : "heart")
                .foregroundStyle(isCurrentTrackFavorited ? Color.red : Color.primary)
        }
        .named(.favoriteToggle(isFavorited: isCurrentTrackFavorited))
    }

    private func resolveCurrentTrackMetadataIfNeeded() async {
        guard let trackId = playbackViewModel.currentTrackId else { return }

        do {
            try await trackService.ensureTracksLoaded(trackIds: [trackId])
            // The task may have outlived this ID. The update is still safe because it
            // resolves PlaybackViewModel's current logical URI rather than `trackId`.
            playbackViewModel.updateNowPlayingInfo()
        } catch {
            debugLog("NowPlayingBarView", "Failed to load metadata for \(trackId): \(error)")
        }
    }

    /// Resolves the heart for whatever is playing.
    ///
    /// `ensureFavoriteStatuses`, not `refreshFavoriteStatuses`: this runs from `.task(id:)`,
    /// which restarts every time the view *appears*, not only when the track changes — and this
    /// bar re-appears often, since it is an overlay on a region that swaps between two- and
    /// three-column layouts as you navigate. A forced refresh made each of those a real
    /// `/me/tracks/contains` request: one continuously playing track drew seven of them in under
    /// two minutes, all returning the same answer.
    ///
    /// What that costs is picking up a favorite toggled on another device while this track plays.
    /// It is a fair trade — every other list in the app already resolves statuses through the
    /// cache, so this makes the bar consistent rather than uniquely stale — and the real fix is
    /// Spotify's collection change feed, which the Rust path received over Mercury and dropped
    /// unread, and which nothing subscribes to at all now (`plans/done/single-grant-partner-api.md`,
    /// task 12). Polling on view re-appearance was never going to be the right mechanism for that.
    private func resolveCurrentTrackFavoriteStatusIfNeeded() async {
        guard let trackId = playbackViewModel.currentTrackId else { return }

        await trackService.ensureFavoriteStatuses(trackIds: [trackId])
    }

    /// The slider's value, 0–100; see `PlaybackViewModel.sliderVolume`.
    private var currentVolume: Double {
        playbackViewModel.sliderVolume * 100
    }

    private var volumeIconName: String {
        if currentVolume == 0 {
            "speaker.fill"
        } else if currentVolume < 50 {
            "speaker.wave.1.fill"
        } else {
            "speaker.wave.3.fill"
        }
    }

    private var volumeRefused: Bool {
        playbackViewModel.sliderRefused
    }

    /// The icon and a 72 pt slider. A device that controls its own volume greys it, and says so
    /// as the tooltip: a greyed-out slider says "not now", not that the device is the reason.
    private var volumeControl: some View {
        HStack(spacing: 4) {
            Image(systemName: volumeIconName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { currentVolume },
                    set: { playbackViewModel.setVolumeFromSlider($0 / 100) },
                ),
                in: 0 ... 100,
            )
            .controlSize(.small)
            .frame(width: 72)
            .disabled(volumeRefused)
            .accessibilityLabel("volume.title")
            .accessibilityValue(Text(currentVolume / 100, format: .percent.precision(.fractionLength(0))))
        }
        .padding(.horizontal, 4)
        .help(volumeRefused ? Text("volume.device_controls_itself \(player.activeDevice?.name ?? "")") : Text("volume.title"))
    }

    @ViewBuilder
    private var trackMenu: some View {
        if let track = playbackViewModel.currentTrack {
            Menu {
                TrackContextMenu(
                    track: track,
                    currentSection: .queue,
                    selectionId: nil,
                    // The now-playing bar knows the song, never which playlist row it came
                    // from — and with no playlist selected there is nothing to remove from
                    // anyway.
                    itemUid: nil,
                    showNewPlaylistDialog: $showNewPlaylistDialog,
                    onPlaylistAdded: showSuccessFeedback,
                    onNavigate: exitMiniPlayerIfNeeded,
                )
            } label: {
                // A menu takes its accessibility name from its label, not from a modifier.
                Label("action.more", systemImage: showPlaylistAddedSuccess ? "checkmark.circle.fill" : "ellipsis")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(showPlaylistAddedSuccess ? Color.accentColor : Color.primary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .animation(.easeInOut(duration: 0.2), value: showPlaylistAddedSuccess)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(showPlaylistAddedSuccess)
            .help("action.more")
        }
    }

    private func exitMiniPlayerIfNeeded() {
        if windowState.isMiniPlayerMode {
            windowState.toggleMiniPlayerMode()
        }
    }

    private func showSuccessFeedback() {
        showPlaylistAddedSuccess = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showPlaylistAddedSuccess = false
        }
    }
}

// MARK: - Glass Effect Background

/// Applies either a solid background (mini player) or liquid glass effect (expanded mode)
private struct NowPlayingBarBackground: ViewModifier {
    let isMiniPlayerMode: Bool

    func body(content: Content) -> some View {
        if isMiniPlayerMode {
            content
                .background(Color(NSColor.windowBackgroundColor))
        } else {
            content
                .glassEffect(.regular, in: .capsule)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
    }
}
