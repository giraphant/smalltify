import SwiftUI

/// Placeholder until the page is built. W2：歌单头部与曲目；别人的歌单显示说明。
struct PlaylistPage: View {
    let playlist: CatalogItem

    var body: some View {
        ContentUnavailableView("建设中", systemImage: "hammer", description: Text("W2：歌单头部与曲目；别人的歌单显示说明。"))
            .navigationTitle(playlist.name)
    }
}
