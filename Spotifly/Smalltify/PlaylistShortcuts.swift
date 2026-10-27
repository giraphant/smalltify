import Foundation
import Observation

@MainActor @Observable final class PlaylistShortcuts {
    private(set) var playlists: [SavedPlaylist]
    private let defaults: UserDefaults
    private static let storageKey = "smalltify.playlistShortcuts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([SavedPlaylist].self, from: $0) } ?? []
        var seen = Set<String>()
        playlists = saved.filter {
            CatalogItem.validURI($0.uri) && $0.uri.hasPrefix("spotify:playlist:")
                && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && seen.insert($0.uri).inserted
        }
    }

    func save(name: String, link: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SmalltifyError("请给歌单起个名字，例如「每周新发现」。") }
        guard let uri = SmalltifyModel.spotifyURI(from: link), uri.hasPrefix("spotify:playlist:") else {
            throw SmalltifyError("请粘贴 Spotify 歌单的分享链接或 spotify:playlist: URI。")
        }
        var updated = playlists
        if let index = updated.firstIndex(where: { $0.uri == uri }) {
            updated[index].name = name
        } else {
            updated.append(SavedPlaylist(uri: uri, name: name))
        }
        try persist(updated)
    }

    func remove(_ playlist: SavedPlaylist) throws {
        try persist(playlists.filter { $0.id != playlist.id })
    }

    private func persist(_ updated: [SavedPlaylist]) throws {
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: Self.storageKey)
        playlists = updated
    }
}
