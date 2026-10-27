import SwiftUI

/// Placeholder until the page is built. W3：混合搜索，全部 / 歌曲 / 歌手 / 专辑 / 歌单。
struct SearchPage: View {
    let query: String

    var body: some View {
        ContentUnavailableView("建设中", systemImage: "hammer", description: Text("W3：混合搜索，全部 / 歌曲 / 歌手 / 专辑 / 歌单。"))
            .navigationTitle("搜索「\(query)」")
    }
}
