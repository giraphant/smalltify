import SwiftUI

/// Placeholder until the page is built. W2：专辑头部与曲目。
struct AlbumPage: View {
    let album: CatalogItem

    var body: some View {
        ContentUnavailableView("建设中", systemImage: "hammer", description: Text("W2：专辑头部与曲目。"))
            .navigationTitle(album.name)
    }
}
