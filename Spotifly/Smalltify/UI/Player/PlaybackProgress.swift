import SwiftUI

struct PlaybackProgress: View {
    let player: SoloistController
    @State private var seeking: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let snapshot = player.displaySnapshot
            HStack(spacing: 8) {
                Text(snapshot.hasTrack ? Formatting.duration(milliseconds: seeking ?? snapshot.position(at: timeline.date)) : "--:--")
                Slider(value: Binding(get: { seeking ?? snapshot.position(at: timeline.date) }, set: { seeking = $0 }),
                       in: 0 ... max(1, snapshot.durationMS)) { editing in
                    if !editing, let seeking {
                        player.control("seek", value: seeking)
                        self.seeking = nil
                    }
                }
                .controlSize(.small)
                .disabled(!player.canControl || !snapshot.hasTrack || snapshot.durationMS <= 0)
                .accessibilityLabel("播放进度")
                Text(snapshot.hasTrack ? Formatting.duration(milliseconds: snapshot.durationMS) : "--:--")
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .onChange(of: player.displaySnapshot.uri) { seeking = nil }
    }
}
