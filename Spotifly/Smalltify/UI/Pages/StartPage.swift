import SwiftUI

/// Placeholder until the page is built. W3：最近播放、常听歌曲与歌手（4 周 / 6 个月 / 1 年）。
struct StartPage: View {

    var body: some View {
        ContentUnavailableView("建设中", systemImage: "hammer", description: Text("W3：最近播放、常听歌曲与歌手（4 周 / 6 个月 / 1 年）。"))
            .navigationTitle("首页")
    }
}
