import SwiftUI

/// The main window: sidebar and page side by side, the player bar across the bottom, the
/// now-playing inspector on the right. Pages come from `DestinationView`.
struct SmalltifyWorkspace: View {
    @Bindable var model: SmalltifyModel
    @State private var searchText = ""
    @State private var showingPasteLink = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SmalltifySidebar(model: model)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            } detail: {
                DestinationView(route: model.navigator.current)
                    .id(model.navigator.current)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) { BannerView(model: model) }
                    .overlay(alignment: .bottom) { ToastView(notices: model.notices) }
                    .toolbar { toolbar }
                    .inspector(isPresented: $model.inspectorPresented) {
                        NowPlayingPanel()
                            .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                    }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "搜索，回车确认")
            .onSubmit(of: .search) {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty { model.navigator.go(.search(query)) }
            }
            .onChange(of: model.navigator.current, initial: true) { _, route in
                if case let .search(query) = route { searchText = query }
            }

            Divider()
            PlayerBar()
        }
        .environment(model)
        .environment(\.openURL, OpenURLAction { url in
            model.handle(url) ? .handled : .systemAction
        })
        // The inspector takes its column from the page. Below about 560pt the page's toolbar and
        // content could not settle, and AppKit threw after too many constraint passes, so the
        // window grows instead while 正在播放 is open.
        .frame(minWidth: model.inspectorPresented ? 1120 : 900, minHeight: 600)
        #if DEBUG
            .task {
                if DebugFixtures.opens("paste") { showingPasteLink = true }
                if DebugFixtures.opens("settings") { openSettings() }
                if DebugFixtures.opens("inspector-later") {
                    try? await Task.sleep(for: .seconds(1.5))
                    model.inspectorPresented = true
                }
            }
        #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button("后退", systemImage: "chevron.left") { model.navigator.goBack() }
                    .disabled(!model.navigator.canGoBack)
                    .help("后退（⌘[）")
                Button("前进", systemImage: "chevron.right") { model.navigator.goForward() }
                    .disabled(!model.navigator.canGoForward)
                    .help("前进（⌘]）")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button("刷新", systemImage: "arrow.clockwise") { model.refreshCurrentPage() }
                    .disabled(!model.signedIn)
                    .help("刷新（⌘R）")
                Button("粘贴 Spotify 链接", systemImage: "link") { showingPasteLink = true }
                    .help("粘贴 Spotify 链接播放（⇧⌘V）")
                    .popover(isPresented: $showingPasteLink, arrowEdge: .bottom) {
                        PasteLinkPopover { showingPasteLink = false }
                            .environment(model)
                    }
            }
        }
    }
}

/// Maps a route to its page. Each page sets its own title and subtitle, and loads its own data.
struct DestinationView: View {
    let route: Destination

    var body: some View {
        switch route {
        case .home: StartPage()
        case .liked: LikedSongsPage()
        case .playlists: PlaylistsPage()
        case .albums: AlbumsPage()
        case .artists: ArtistsPage()
        case let .search(query): SearchPage(query: query)
        case let .album(album): AlbumPage(album: album)
        case let .playlist(playlist): PlaylistPage(playlist: playlist)
        case let .artist(artist): ArtistPage(artist: artist)
        }
    }
}
