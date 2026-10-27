import SwiftUI

/// 喜欢的歌曲: the saved tracks, filterable and sortable, loading more as the list scrolls.
///
/// The reference for the other pages: a loader from `model.pagedLoader` keyed under the route,
/// `LoadedContent` for the states before there is a list, `TrackList` for the list itself, and
/// the title and subtitle set on the page.
struct LikedSongsPage: View {
    @Environment(SmalltifyModel.self) private var model
    @State private var filter = ""
    @State private var sort: TrackSort?

    var body: some View {
        let loader = model.pagedLoader("\(Destination.liked.key)/tracks", url: Self.url)
        LoadedContent(loader: loader, emptyTitle: "还没有喜欢的歌曲",
                      emptyDescription: "在 Spotify 里点过喜欢的歌会出现在这里。") {
            TrackList(tracks: loader.items, columns: .library, context: model.collectionContext,
                      filter: filter, sort: $sort, loader: loader) {
                HStack {
                    TextField("在列表中筛选", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    Spacer()
                    Button("播放", systemImage: "play.fill") {
                        if let first = loader.items.first { model.play(first, in: model.collectionContext) }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(loader.items.isEmpty)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("喜欢的歌曲")
        .navigationSubtitle(subtitle(loader))
        .task { loader.loadIfNeeded() }
    }

    private func subtitle(_ loader: PagedLoader) -> String {
        guard let total = loader.total else { return "" }
        return loader.next == nil ? "\(total) 首" : "\(total) 首 · 已加载 \(loader.items.count) 首"
    }

    private static let url = try! OfficialWebAPI.apiURL(path: "/me/tracks", query: [
        .init(name: "limit", value: "50"), .init(name: "market", value: "from_token"),
    ])
}
