import SwiftUI

struct ArtistLinks: View {
    let artists: [CatalogArtist]
    let fallback: String
    let open: (CatalogArtist) -> Void

    var body: some View {
        if artists.count == 1, let artist = artists.first {
            Button(artist.name) { open(artist) }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .lineLimit(1)
                .help("查看 \(artist.name) 的作品")
        } else if !artists.isEmpty {
            Menu {
                ForEach(artists) { artist in
                    Button(artist.name) { open(artist) }
                }
            } label: {
                Text(fallback).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .help("选择歌手并查看作品")
        } else {
            Text(fallback).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
