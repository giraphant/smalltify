import SwiftUI

/// Placeholder until the page is built. W1：我的歌单，卡片网格，可加载更多。
struct PlaylistsPage: View {

    var body: some View {
        ContentUnavailableView("建设中", systemImage: "hammer", description: Text("W1：我的歌单，卡片网格，可加载更多。"))
            .navigationTitle("歌单")
    }
}
