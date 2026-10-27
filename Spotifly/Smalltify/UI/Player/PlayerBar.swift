import SwiftUI

struct PlayerBar: View {
    @Environment(SmalltifyModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { model.inspectorPresented.toggle() } label: {
                    CoverArt(url: model.player.displaySnapshot.coverURL, size: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("正在播放与接下来播放")
                PlayerTrackTitle(snapshot: model.player.displaySnapshot)
            }
            .frame(minWidth: 100, idealWidth: 210, maxWidth: 250, alignment: .leading)
            PlaybackButtons(player: model.player)
            // Always with the times and the volume: the bar's minimum width is part of the
            // window's, and hiding them by a measured width changed that minimum as it resized.
            // Both bounds set, so the times' changing widths do not reach the minimum either.
            PlaybackProgress(player: model.player)
                .frame(minWidth: 50, maxWidth: .infinity)
            DeviceChip()
            Button("正在播放与接下来播放", systemImage: "list.bullet") { model.inspectorPresented.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(6)
                .background(model.inspectorPresented ? Color.primary.opacity(0.08) : .clear, in: .circle)
            PlaybackVolume(player: model.player)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(.bar)
        .task {
            #if DEBUG
                if DebugFixtures.opens("mini") { openWindow(id: MiniPlayerWindow.id) }
            #endif
        }
    }
}
