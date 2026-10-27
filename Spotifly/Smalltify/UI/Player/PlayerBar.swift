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
///
/// Not a ContentUnavailableView: its wrapping text, sized against the inspector column, looped
/// AppKit's constraint passes until the window threw.
struct NowPlayingPanel: View {
    var body: some View {
        VStack {
            Text("正在播放").font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
