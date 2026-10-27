import SwiftUI

struct PlaybackVolume: View {
    let player: SoloistController
    @State private var volume: Double?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2").foregroundStyle(.secondary)
            Slider(value: Binding(get: { volume ?? player.displaySnapshot.volume }, set: { volume = $0 }), in: 0 ... 100) { editing in
                if !editing, let volume {
                    player.control("set_volume", value: volume)
                    self.volume = nil
                }
            }
            .controlSize(.small)
            .frame(width: 80)
            .accessibilityLabel("音量")
        }
        .disabled(!player.canSetVolume || !player.displaySnapshot.hasTrack)
        .help(player.connect?.usesRemote == true && player.connect?.playback?.device.supportsVolume != true
              ? "此设备不允许调节音量" : "音量")
        .onChange(of: player.connect?.playback?.device.id) { volume = nil }
    }
}
