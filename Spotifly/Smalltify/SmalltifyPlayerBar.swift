import SwiftUI

struct SmalltifyPlayerBar: View {
    @Bindable var player: SoloistController
    let openArtist: (CatalogArtist) -> Void
    @State private var seeking: Double?
    @State private var volume: Double?

    var body: some View {
        VStack {
            if let error = player.error {
                SmalltifyMessage(message: error, isError: true) { player.error = nil }
            }
            HStack {
                AsyncImage(url: player.snapshot.coverURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "music.note")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
                .frame(width: 48, height: 48)
                .accessibilityLabel("当前歌曲封面")
                VStack(alignment: .leading) {
                    Text(player.snapshot.title).lineLimit(1).bold()
                    ArtistLinks(artists: player.snapshot.artists, fallback: player.snapshot.artist, open: openArtist)
                        .font(.caption)
                }
                .frame(minWidth: 140, maxWidth: 260, alignment: .leading)
                Spacer()
                Button("上一首", systemImage: "backward.end.fill") { player.control("skip_prev") }
                    .labelStyle(.iconOnly).disabled(!player.canControl)
                Button(player.snapshot.status == "playing" ? "暂停" : "播放", systemImage: player.snapshot.status == "playing" ? "pause.fill" : "play.fill") {
                    player.control(player.snapshot.status == "playing" ? "pause" : "play")
                }
                .labelStyle(.iconOnly).disabled(!player.canControl)
                Button("下一首", systemImage: "forward.end.fill") { player.control("skip_next") }
                    .labelStyle(.iconOnly).disabled(!player.canControl)
                Button("随机播放", systemImage: "shuffle") { player.control("set_shuffle", enabled: !player.snapshot.shuffle) }
                    .labelStyle(.iconOnly).tint(player.snapshot.shuffle ? .accentColor : .secondary).disabled(!player.canControl)
                Spacer()
                Image(systemName: "speaker.wave.2")
                Slider(value: Binding(get: { volume ?? player.snapshot.volume }, set: { volume = $0 }), in: 0 ... 100) { editing in
                    if !editing, let volume {
                        player.control("set_volume", value: volume)
                        self.volume = nil
                    }
                }
                .frame(width: 100).disabled(!player.canControl).accessibilityLabel("音量")
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack {
                    Text(Self.time(player.snapshot.position(at: timeline.date))).monospacedDigit()
                    Slider(value: Binding(get: { seeking ?? player.snapshot.position(at: timeline.date) }, set: { seeking = $0 }),
                           in: 0 ... max(1, player.snapshot.durationMS)) { editing in
                        if !editing, let seeking {
                            player.control("seek", value: seeking)
                            self.seeking = nil
                        }
                    }
                    .disabled(!player.canControl || player.snapshot.durationMS <= 0).accessibilityLabel("播放进度")
                    Text(Self.time(player.snapshot.durationMS)).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Circle().fill(player.canControl ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(player.connected ? (player.snapshot.loggedIn ? (player.snapshot.active ? "当前设备：Smalltify" : "已配对 · 播放器待命") : "等待配对：请在官方 Spotify 的设备列表中选择 Smalltify") : (player.running ? "正在连接 Soloist…" : "播放器未启动 · 请打开设置"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .onChange(of: player.snapshot.uri) { seeking = nil }
    }

    private static func time(_ milliseconds: Double) -> String {
        let seconds = max(0, Int(milliseconds / 1000))
        let remainder = seconds % 60
        return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
    }
}
