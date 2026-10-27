import SwiftUI

struct SmalltifyPlayerBar: View {
    @Bindable var player: SoloistController
    let authorizeConnect: () -> Void
    @State private var showingDevices = false
    @State private var seeking: Double?
    @State private var volume: Double?

    var body: some View {
        VStack {
            HStack {
                AsyncImage(url: player.displaySnapshot.coverURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "music.note")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
                .frame(width: 48, height: 48)
                .accessibilityLabel("当前歌曲封面")
                VStack(alignment: .leading) {
                    Text(player.displaySnapshot.title).lineLimit(1).bold()
                    ArtistLinks(artists: player.displaySnapshot.artists, fallback: player.displaySnapshot.artist)
                        .font(.caption)
                }
                .frame(minWidth: 140, maxWidth: 260, alignment: .leading)
                Spacer()
                Button("上一首", systemImage: "backward.end.fill") { player.control("skip_prev") }
                    .labelStyle(.iconOnly).disabled(!player.canControl)
                Button(player.displaySnapshot.status == "playing" ? "暂停" : "播放", systemImage: player.displaySnapshot.status == "playing" ? "pause.fill" : "play.fill") {
                    player.control(player.displaySnapshot.status == "playing" ? "pause" : "play")
                }
                .labelStyle(.iconOnly).disabled(!player.canControl)
                Button("下一首", systemImage: "forward.end.fill") { player.control("skip_next") }
                    .labelStyle(.iconOnly).disabled(!player.canControl)
                Button("随机播放", systemImage: "shuffle") { player.control("set_shuffle", enabled: !player.displaySnapshot.shuffle) }
                    .labelStyle(.iconOnly).tint(player.displaySnapshot.shuffle ? .accentColor : .secondary).disabled(!player.canControl)
                Spacer()
                Image(systemName: "speaker.wave.2")
                Slider(value: Binding(get: { volume ?? player.displaySnapshot.volume }, set: { volume = $0 }), in: 0 ... 100) { editing in
                    if !editing, let volume {
                        player.control("set_volume", value: volume)
                        self.volume = nil
                    }
                }
                .frame(width: 100).disabled(!player.canSetVolume).accessibilityLabel("音量")
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack {
                    Text(Self.time(player.displaySnapshot.position(at: timeline.date))).monospacedDigit()
                    Slider(value: Binding(get: { seeking ?? player.displaySnapshot.position(at: timeline.date) }, set: { seeking = $0 }),
                           in: 0 ... max(1, player.displaySnapshot.durationMS)) { editing in
                        if !editing, let seeking {
                            player.control("seek", value: seeking)
                            self.seeking = nil
                        }
                    }
                    .disabled(!player.canControl || player.displaySnapshot.durationMS <= 0).accessibilityLabel("播放进度")
                    Text(Self.time(player.displaySnapshot.durationMS)).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Circle().fill(player.canControl ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(player.outputDescription)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let connect = player.connect {
                    Button("设备", systemImage: "hifispeaker.and.homepod") { showingDevices.toggle() }
                        .popover(isPresented: $showingDevices) {
                            ConnectDevicePicker(connect: connect, player: player) {
                                showingDevices = false
                                authorizeConnect()
                            }
                        }
                }
            }
        }
        .padding()
        .onChange(of: player.displaySnapshot.uri) { seeking = nil }
    }

    private static func time(_ milliseconds: Double) -> String {
        let seconds = max(0, Int(milliseconds / 1000))
        let remainder = seconds % 60
        return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
    }
}
