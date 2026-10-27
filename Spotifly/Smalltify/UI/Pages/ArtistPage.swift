import SwiftUI

/// Placeholder until the page is built. W2：歌手头部与作品分类。
struct ArtistPage: View {
    let artist: CatalogArtist

    var body: some View {
        ContentUnavailableView("建设中", systemImage: "hammer", description: Text("W2：歌手头部与作品分类。"))
            .navigationTitle(artist.name)
    }
}
