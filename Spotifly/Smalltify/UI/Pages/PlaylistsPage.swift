import SwiftUI

struct PlaylistsPage: View {
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        let loader = LibraryPageLoading.loader(model, key: "\(Destination.playlists.key)/items", url: Self.url)
        LoadedContent(loader: loader, emptyTitle: "还没有歌单",
                      emptyDescription: "在 Spotify 里收藏的歌单会出现在这里。") {
            ScrollView {
                CatalogGrid(items: loader.items) { Self.detail($0, accountID: model.profile?.id) }
                LoaderFooter(loader: loader)
            }
            .padding()
        }
        .navigationTitle("歌单")
        .navigationSubtitle(loader.total.map { "\($0) 个歌单" } ?? "")
        .task(id: model.signedIn) {
            guard model.signedIn else { return }
            await LibraryPageLoading.load(loader)
        }
    }

    nonisolated static func detail(_ item: CatalogItem, accountID: String?) -> String {
        if let accountID, item.ownerID == accountID, let count = item.trackCount {
            return "\(count) 首"
        }
        return item.ownerName ?? item.subtitle
    }

    static let url = try! OfficialWebAPI.apiURL(path: "/me/playlists", query: [.init(name: "limit", value: "50")])
}
