import SwiftUI

struct PlaybackButtons: View {
    let player: SoloistController
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            if !compact {
                Button("随机播放", systemImage: "shuffle") {
                    player.control("set_shuffle", enabled: !player.displaySnapshot.shuffle)
                }
                .foregroundStyle(player.displaySnapshot.shuffle ? Color.accentColor : .secondary)
                .accessibilityValue(player.displaySnapshot.shuffle ? "开" : "关")
            }
            Button("上一首", systemImage: "backward.end.fill") { player.control("skip_prev") }
                .help("上一首（⌘←）")
            if player.starting || (player.running && !player.connected) {
                ProgressView().controlSize(.small).frame(width: 38, height: 38)
                    .accessibilityLabel("播放器启动中…")
            } else {
                Button {
                    player.control(player.displaySnapshot.status == "playing" ? "pause" : "play")
                } label: {
                    Label(player.displaySnapshot.status == "playing" ? "暂停" : "播放",
                          systemImage: player.displaySnapshot.status == "playing" ? "pause.fill" : "play.fill")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .frame(width: 38, height: 38)
                .help("播放 / 暂停（空格）")
            }
            Button("下一首", systemImage: "forward.end.fill") { player.control("skip_next") }
                .help("下一首（⌘→）")
            if !compact {
                Button("循环：\(player.displaySnapshot.repeatLabel)",
                       systemImage: player.displaySnapshot.repeatMode == "track" ? "repeat.1" : "repeat") {
                    player.cycleRepeat()
                }
                .foregroundStyle(player.displaySnapshot.repeatMode == "off" ? Color.secondary : .accentColor)
                .help("循环：\(player.displaySnapshot.repeatLabel)")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(!player.canControl || !player.displaySnapshot.hasTrack)
        .fixedSize()
    }
}
