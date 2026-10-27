import SwiftUI

/// The bar across the bottom of the window. Placeholder: the previous bar until W4 builds the
/// design's single-row bar.
struct PlayerBar: View {
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        SmalltifyPlayerBar(player: model.player, authorizeConnect: model.signIn)
            .background(.bar)
    }
}

/// The inspector's 正在播放 panel. Placeholder until W4 builds it with the queue.
struct NowPlayingPanel: View {
    var body: some View {
        ContentUnavailableView("正在播放", systemImage: "music.note", description: Text("W4：大封面、歌名、歌手、专辑，接下来播放。"))
    }
}

/// The mini player window. Placeholder until W4 builds it.
struct MiniPlayerWindow: View {
    static let id = "mini-player"
    let model: SmalltifyModel

    var body: some View {
        ContentUnavailableView("迷你播放器", systemImage: "music.note", description: Text("W4"))
            .frame(width: 360, height: 160)
    }
}
