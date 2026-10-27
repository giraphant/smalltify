import SwiftUI

struct PlayerTrackTitle: View {
    let snapshot: SoloistSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if snapshot.hasTrack {
                Text(snapshot.title).bold().lineLimit(1).help(snapshot.title)
                ArtistLinks(artists: snapshot.artists, fallback: snapshot.artist)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("没有在播放").foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
