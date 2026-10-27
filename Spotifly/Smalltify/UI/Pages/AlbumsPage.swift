import SwiftUI

struct AlbumsPage: View {
    @Environment(SmalltifyModel.self) private var model
    @State private var sort = LibraryAlbumSort.recentlyAdded

    var body: some View {
        let loader = LibraryPageLoading.loader(model, key: "\(Destination.albums.key)/items", url: Self.url)
        LoadedContent(loader: loader, emptyTitle: "还没有收藏的专辑",
                      emptyDescription: "在 Spotify 里收藏的专辑会出现在这里。") {
            ScrollView {
                HStack {
                    Spacer()
                    Menu {
                        Picker("排序", selection: $sort) {
                            ForEach(LibraryAlbumSort.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    }
                    .fixedSize()
                    .accessibilityLabel("专辑排序")
                }
                CatalogGrid(items: sort.sorted(loader.items), detail: Self.detail)
                LoaderFooter(loader: loader, unit: "张")
            }
            .padding()
        }
        .navigationTitle("专辑")
        .navigationSubtitle(loader.total.map { "\($0) 张专辑" } ?? "")
        .task(id: model.signedIn) {
            guard model.signedIn else { return }
            #if DEBUG
                if DebugFixtures.opens("albums-name") { sort = .name }
                if DebugFixtures.opens("albums-artist") { sort = .artist }
                if DebugFixtures.opens("albums-year") { sort = .year }
            #endif
            await LibraryPageLoading.load(loader)
        }
    }

    nonisolated static func detail(_ item: CatalogItem) -> String {
        [Formatting.artistNames(item.artists, fallback: item.subtitle), item.releaseYear ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static let url = try! OfficialWebAPI.apiURL(path: "/me/albums", query: [
        .init(name: "limit", value: "50"), .init(name: "market", value: "from_token"),
    ])
}

nonisolated enum LibraryAlbumSort: String, CaseIterable {
    case recentlyAdded = "最近添加"
    case name = "名称"
    case artist = "歌手"
    case year = "年份"

    func sorted(_ items: [CatalogItem]) -> [CatalogItem] {
        guard self != .recentlyAdded else { return items }
        return items.sorted { lhs, rhs in
            switch self {
            case .recentlyAdded: false
            case .name: lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .artist:
                Formatting.artistNames(lhs.artists, fallback: lhs.subtitle)
                    .localizedStandardCompare(Formatting.artistNames(rhs.artists, fallback: rhs.subtitle)) == .orderedAscending
            case .year: (lhs.releaseYear ?? "") > (rhs.releaseYear ?? "")
            }
        }
    }
}
