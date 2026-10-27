import SwiftUI

struct MiniPlayerWindow: View {
    static let id = "mini-player"
    let model: SmalltifyModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                CoverArt(url: model.player.displaySnapshot.coverURL, size: 84)
                VStack(alignment: .leading, spacing: 8) {
                    PlayerTrackTitle(snapshot: model.player.displaySnapshot)
                    HStack(spacing: 8) {
                        PlaybackButtons(player: model.player, compact: true)
                        Spacer(minLength: 0)
                        DeviceChip(opensFixture: false)
                    }
                }
            }
            PlaybackProgress(player: model.player)
        }
        .padding(16)
        .frame(width: 360, height: 160)
        .environment(model)
        .environment(\.openURL, OpenURLAction { model.handle($0) ? .handled : .systemAction })
    }
}
