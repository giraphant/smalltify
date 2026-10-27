import SwiftUI

/// 歌手: the followed artists, paged by Spotify's cursor rather than an offset.
struct ArtistsPage: View {
    @Environment(SmalltifyModel.self) private var model

    var body: some View {
        let loader = model.pages.loader("\(Destination.artists.key)/items") {
            Self.makeLoader(api: model.api) { [weak model] in model?.report($0) }
        }
        LoadedContent(loader: loader, emptyTitle: "还没有关注的歌手",
                      emptyDescription: "在 Spotify 里关注的歌手会出现在这里。") {
            ScrollView {
                CatalogGrid(items: loader.items)
                LoaderFooter(loader: loader, unit: "位")
            }
            .padding()
        }
        .navigationTitle("歌手")
        .task(id: model.signedIn) {
            guard model.signedIn else { return }
            await LibraryPageLoading.load(loader)
        }
    }

    static func makeLoader(api: OfficialWebAPI, report: @escaping @MainActor (Error) -> Void = { _ in }) -> PagedLoader {
        PagedLoader(firstURL: url, report: report) { url, _ in
            #if DEBUG
                try await FixtureData.libraryRequestDelay(url)
            #endif
            return try CatalogPage.parse(try await api.get(url), searchType: "artist")
        }
    }

    static let url = try! OfficialWebAPI.apiURL(path: "/me/following", query: [
        .init(name: "type", value: "artist"), .init(name: "limit", value: "50"),
    ])
}
