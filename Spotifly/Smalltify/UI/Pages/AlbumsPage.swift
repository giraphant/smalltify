import SwiftUI

/// Placeholder until the page is built. W1：收藏的专辑，卡片网格，可加载更多。
struct AlbumsPage: View {

    var body: some View {
        ContentUnavailableView("建设中", systemImage: "hammer", description: Text("W1：收藏的专辑，卡片网格，可加载更多。"))
            .navigationTitle("专辑")
    }
}
