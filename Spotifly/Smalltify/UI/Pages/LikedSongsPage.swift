import SwiftUI

/// 喜欢的歌曲: the saved tracks, filterable and sortable, loading more as the list scrolls.
struct LikedSongsPage: View {
    @Environment(SmalltifyModel.self) private var model
    @State private var filter = ""
    @State private var sort: TrackSort?

    var body: some View {
        let loader = LibraryPageLoading.loader(model, key: "\(Destination.liked.key)/tracks", url: Self.url)
        LoadedContent(loader: loader, emptyTitle: "还没有喜欢的歌曲",
                      emptyDescription: "在 Spotify 里点过喜欢的歌会出现在这里。") {
            TrackList(tracks: loader.items, columns: .library, context: model.collectionContext,
                      filter: filter, sort: $sort, defaultSort: TrackSort(key: .added, ascending: false),
                      loader: loader, moreTitle: "加载更多 50 首") {
                HStack {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("在列表中筛选", text: $filter)
                            .textFieldStyle(.plain)
                    }
                    .padding(6)
                    .frame(maxWidth: 220)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                    Spacer()
                    Button("播放", systemImage: "play.fill") {
                        model.play(loader.items, startingAt: 0, in: model.collectionContext)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(loader.items.isEmpty)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("喜欢的歌曲")
        .navigationSubtitle(Self.subtitle(total: loader.total, loaded: loader.items.count, hasMore: loader.next != nil))
        .task(id: model.signedIn) {
            guard model.signedIn else { return }
            #if DEBUG
                if DebugFixtures.opens("liked-filter") { filter = "潮汐" }
                if DebugFixtures.opens("liked-no-match") { filter = "没有这首歌" }
            #endif
            await LibraryPageLoading.load(loader)
        }
    }

    nonisolated static func subtitle(total: Int?, loaded: Int, hasMore: Bool) -> String {
        guard let total else { return "" }
        return hasMore ? "\(total) 首 · 已加载 \(loaded) 首" : "\(total) 首"
    }

    static let url = try! OfficialWebAPI.apiURL(path: "/me/tracks", query: [
        .init(name: "limit", value: "50"), .init(name: "market", value: "from_token"),
    ])
}

/// How the library pages get and start their loaders, with the debug fixture states in one place.
@MainActor enum LibraryPageLoading {
    static func loader(_ model: SmalltifyModel, key: String, url: URL) -> PagedLoader {
        #if DEBUG
            if let loader = FixtureData.libraryStateLoader(model, key: key, url: url) { return loader }
        #endif
        return model.pagedLoader(key, url: url)
    }

    static func load(_ loader: PagedLoader) async {
        #if DEBUG
            if DebugFixtures.opens("library-loading") {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
            }
        #endif
        loader.loadIfNeeded()
        #if DEBUG
            if DebugFixtures.opens("library-more-loading") || DebugFixtures.opens("library-more-failure") {
                while loader.isLoading {
                    try? await Task.sleep(for: .milliseconds(10))
                    guard !Task.isCancelled else { return }
                }
                loader.loadMore()
            }
        #endif
    }
}
