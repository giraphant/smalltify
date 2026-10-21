//
//  SearchService.swift
//  Spotifly
//
//  Service for search functionality.
//  Performs searches and stores returned entities in AppStore.
//

import Foundation

@MainActor
@Observable
final class SearchService {
    private let store: AppStore
    private let partner: PartnerAPI
    private let defaults: UserDefaults

    /// The queries searched last, newest first, kept on this Mac only.
    private(set) var recentSearches: [String]

    /// How many recent searches are kept.
    static let recentSearchesLimit = 10
    private static let recentSearchesKey = "recentSearches"

    /// How many results a further page of one scope asks for.
    static let pageSize = 20

    /// The scopes whose further page is loading, so a second press does not ask again.
    private(set) var loadingMore: Set<SearchScope> = []

    init(store: AppStore, partner: PartnerAPI = PartnerAPI(), defaults: UserDefaults = .standard) {
        self.store = store
        self.partner = partner
        self.defaults = defaults
        recentSearches = defaults.stringArray(forKey: Self.recentSearchesKey) ?? []
    }

    // MARK: - Search

    /// Takes no access token: the partner API authorizes itself from the keymaster grant, which
    /// is the point of the migration. The Web API token this used to need was minted with the
    /// user's dashboard client id, and `api-partner` rejects it.
    func search(query: String) async {
        guard !query.isEmpty, !store.searchIsLoading else { return }

        store.searchIsLoading = true

        do {
            try await store.setSearchResults(partnerSearch(query: query), for: query)
            remember(query)
        } catch {
            store.setSearchFailure(error, for: query)
        }

        store.searchIsLoading = false
    }

    // MARK: - More results

    /// Loads the next page of one scope of `query`'s results and appends it.
    func loadMore(query: String, scope: SearchScope) async {
        guard scope != .all, !loadingMore.contains(scope),
              let offset = store.searchResults(for: query)?.ids(for: scope).count
        else { return }
        loadingMore.insert(scope)
        defer { loadingMore.remove(scope) }

        do {
            let ids: [String]
            switch scope {
            case .tracks:
                let tracks = try await partner.searchTracks(query, offset: offset, limit: Self.pageSize).compactMap(Track.init(pathfinder:))
                store.upsertTracks(tracks)
                ids = tracks.map(\.id)
            case .artists:
                let artists = try await partner.searchArtists(query, offset: offset, limit: Self.pageSize).compactMap(Artist.init(pathfinder:))
                store.upsertArtists(artists)
                ids = artists.map(\.id)
            case .albums:
                let albums = try await partner.searchAlbums(query, offset: offset, limit: Self.pageSize).compactMap(Album.init(pathfinder:))
                store.upsertAlbums(albums)
                ids = albums.map(\.id)
            case .playlists:
                let playlists = try await partner.searchPlaylists(query, offset: offset, limit: Self.pageSize).compactMap(Playlist.init(pathfinder:))
                store.upsertPlaylists(playlists)
                ids = playlists.map(\.id)
            case .all:
                return
            }
            store.appendSearchResults(ids, to: scope, for: query)
        } catch {
            debugLog("SearchService", "More \(scope) for \(query) failed: \(error)")
        }
    }

    // MARK: - Recent searches

    /// Puts `query` first among the recent searches, once.
    private func remember(_ query: String) {
        recentSearches.removeAll { $0 == query }
        recentSearches.insert(query, at: 0)
        recentSearches = Array(recentSearches.prefix(Self.recentSearchesLimit))
        defaults.set(recentSearches, forKey: Self.recentSearchesKey)
    }

    func removeRecentSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        defaults.set(recentSearches, forKey: Self.recentSearchesKey)
    }

    func clearRecentSearches() {
        recentSearches = []
        defaults.removeObject(forKey: Self.recentSearchesKey)
    }

    /// The search field was emptied. A failure is about the query that was typed, so it goes
    /// with it, and the history drops its page.
    func clearFailure() {
        store.clearSearchFailure()
    }

    /// Runs the four searches together, upserts what they found, and returns the results as ids
    /// into the tables.
    ///
    /// Concurrently, because they are four separate operations where the Web API served all
    /// four categories from one request — sequentially this would be four round-trips of
    /// latency for what the user experiences as a single search.
    private func partnerSearch(query: String) async throws -> SearchResults {
        async let trackAnswer = partner.searchTracks(query, limit: 20)
        async let albumAnswer = partner.searchAlbums(query, limit: 20)
        async let artistAnswer = partner.searchArtists(query, limit: 20)
        async let playlistAnswer = partner.searchPlaylists(query, limit: 20)

        let tracks = try await trackAnswer.compactMap(Track.init(pathfinder:))
        let albums = try await albumAnswer.compactMap(Album.init(pathfinder:))
        let artists = try await artistAnswer.compactMap(Artist.init(pathfinder:))
        let playlists = try await playlistAnswer.compactMap(Playlist.init(pathfinder:))

        store.upsertTracks(tracks)
        store.upsertAlbums(albums)
        store.upsertArtists(artists)
        store.upsertPlaylists(playlists)
        return SearchResults(albums: albums, artists: artists, playlists: playlists, tracks: tracks)
    }
}
