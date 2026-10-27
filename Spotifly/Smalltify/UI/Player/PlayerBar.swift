import SwiftUI

struct PlayerBar: View {
    @Environment(SmalltifyModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var width: CGFloat = 1000

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
            PlaybackProgress(player: model.player, showsTimes: width >= 640)
                .frame(minWidth: 50, maxWidth: .infinity)
            DeviceChip()
            Button("正在播放与接下来播放", systemImage: "list.bullet") { model.inspectorPresented.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(6)
                .background(model.inspectorPresented ? Color.primary.opacity(0.08) : .clear, in: .circle)
            if width >= 680 {
                PlaybackVolume(player: model.player)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(.bar)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task {
            #if DEBUG
                if DebugFixtures.opens("mini") { openWindow(id: MiniPlayerWindow.id) }
            #endif
        }
    }
}
