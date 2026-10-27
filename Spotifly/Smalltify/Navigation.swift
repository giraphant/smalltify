import Foundation
import Observation

/// A page of the main window. Each case is one page view in `UI/Pages`; `DestinationView` maps them.
nonisolated enum Destination: Hashable, Sendable {
    case home
    case liked
    case playlists
    case albums
    case artists
    case search(String)
    /// The item may be a stub with only a uri and a name: the page loads the rest.
    case album(CatalogItem)
    case playlist(CatalogItem)
    case artist(CatalogArtist)

    /// The album or playlist page for an item, nil for anything else.
    static func collection(_ item: CatalogItem) -> Destination? {
        switch item.kind {
        case "album": .album(item)
        case "playlist": .playlist(item)
        default: nil
        }
    }

    /// The sidebar row highlighted while the page shows; search has none.
    var section: SidebarSection? {
        switch self {
        case .home: .home
        case .liked: .liked
        case .playlists, .playlist: .playlists
        case .albums, .album: .albums
        case .artists, .artist: .artists
        case .search: nil
        }
    }

    /// The prefix of every `PageStore` key the page uses, so ⌘R refreshes all of its loaders.
    var key: String {
        switch self {
        case .home: "home"
        case .liked: "liked"
        case .playlists: "playlists"
        case .albums: "albums"
        case .artists: "artists"
        case let .search(query): "search:\(query)"
        case let .album(item): "album:\(item.spotifyID)"
        case let .playlist(item): "playlist:\(item.spotifyID)"
        case let .artist(artist): "artist:\(artist.spotifyID)"
        }
    }
}

nonisolated enum SidebarSection: String, CaseIterable, Hashable, Sendable {
    case home, liked, playlists, albums, artists

    var route: Destination {
        switch self {
        case .home: .home
        case .liked: .liked
        case .playlists: .playlists
        case .albums: .albums
        case .artists: .artists
        }
    }

    var title: String {
        switch self {
        case .home: "首页"
        case .liked: "喜欢的歌曲"
        case .playlists: "歌单"
        case .albums: "专辑"
        case .artists: "歌手"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .liked: "heart"
        case .playlists: "music.note.list"
        case .albums: "square.stack"
        case .artists: "music.microphone"
        }
    }
}

/// The main window's history: the page showing, and what back and forward return to.
@MainActor @Observable final class Navigator {
    private(set) var current: Destination
    private(set) var backStack: [Destination] = []
    private(set) var forwardStack: [Destination] = []
    private static let depth = 50

    init(start: Destination = .home) {
        current = start
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Shows a page; going to the page already showing does nothing.
    func go(_ route: Destination) {
        guard route != current else { return }
        backStack.append(current)
        if backStack.count > Self.depth { backStack.removeFirst() }
        forwardStack = []
        current = route
    }

    func goBack() {
        guard let route = backStack.popLast() else { return }
        forwardStack.append(current)
        current = route
    }

    func goForward() {
        guard let route = forwardStack.popLast() else { return }
        backStack.append(current)
        current = route
    }

    /// Starts over at a page with no history, as signing out does.
    func reset(to route: Destination) {
        backStack = []
        forwardStack = []
        current = route
    }
}
