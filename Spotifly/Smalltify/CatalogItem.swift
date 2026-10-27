import Foundation

/// One of an entity's images, as Spotify lists them: several sizes of the same artwork.
nonisolated struct CatalogImage: Sendable, Hashable {
    let url: URL
    /// Pixels; nil when Spotify does not say, as for some playlist mosaics.
    let width: Int?
}

/// The album a track belongs to, for its album column and the "去专辑页" action.
nonisolated struct CatalogAlbumRef: Sendable, Hashable {
    let uri: String
    let name: String
}

nonisolated struct CatalogItem: Identifiable, Sendable, Hashable {
    let uri: String
    let name: String
    let subtitle: String
    let kind: String
    let durationMS: Double
    /// The smallest image; `imageURL(minPixels:)` picks one for a size.
    let imageURL: URL?
    var artists: [CatalogArtist] = []
    /// Every size Spotify offered, smallest first.
    var images: [CatalogImage] = []
    var album: CatalogAlbumRef?
    /// When the item was saved or added, for library and playlist entries.
    var addedAt: Date?
    /// Albums: `YYYY`, `YYYY-MM` or `YYYY-MM-DD`, as Spotify gives it.
    var releaseDate: String?
    /// Albums: `album`, `single` or `compilation`.
    var albumType: String?
    var ownerName: String?
    var ownerID: String?
    var collaborative = false
    var trackCount: Int?
    /// Playlists' descriptions, which Spotify returns with HTML entities.
    var summary: String?

    var id: String { uri }
    var spotifyID: String { uri.split(separator: ":").last.map(String.init) ?? "" }
    var isCollection: Bool { kind == "album" || kind == "playlist" }
    var isPlayable: Bool { Self.validURI(uri) }
    var releaseYear: String? { releaseDate.map { String($0.prefix(4)) } }
    var openURL: URL? { URL(string: "https://open.spotify.com/\(kind)/\(spotifyID)") }

    /// The smallest image at least `pixels` wide, else the largest there is.
    func imageURL(minPixels pixels: CGFloat) -> URL? {
        let sized = images.filter { $0.width != nil }
        return sized.first { CGFloat($0.width ?? 0) >= pixels }?.url ?? sized.last?.url ?? images.first?.url ?? imageURL
    }

    static func validURI(_ uri: String) -> Bool {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "spotify"
            && ["track", "album", "playlist", "episode"].contains(parts[1])
            && parts[2].count == 22 && parts[2].utf8.allSatisfy {
                (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0)
            }
    }

    static func parseImages(_ value: Any?) -> [CatalogImage] {
        let objects = value as? [[String: Any]] ?? []
        let images = objects.compactMap { image -> CatalogImage? in
            guard let text = image["url"] as? String, let url = URL(string: text),
                  url.scheme == "https", url.user == nil, url.password == nil else { return nil }
            return CatalogImage(url: url, width: image["width"] as? Int)
        }
        return images.sorted { ($0.width ?? .max) < ($1.width ?? .max) }
    }

    static func parse(_ object: [String: Any], addedAt: Date? = nil) -> Self? {
        guard let uri = object["uri"] as? String, validURI(uri) || CatalogArtist.validURI(uri),
              let name = object["name"] as? String else { return nil }
        let kind = object["type"] as? String ?? String(uri.split(separator: ":")[1])
        let artistObjects = object["artists"] as? [[String: Any]] ?? []
        let artistNames = artistObjects.compactMap { $0["name"] as? String }
        var seenArtists = Set<String>()
        let artists = artistObjects.compactMap(CatalogArtist.parse).filter { seenArtists.insert($0.uri).inserted }
        let albumObject = object["album"] as? [String: Any]
        let owner = object["owner"] as? [String: Any]
        let images = parseImages(object["images"] ?? albumObject?["images"])
        var album: CatalogAlbumRef?
        if let albumURI = albumObject?["uri"] as? String, validURI(albumURI), let albumName = albumObject?["name"] as? String {
            album = CatalogAlbumRef(uri: albumURI, name: albumName)
        }
        let tracks = object["tracks"] as? [String: Any] ?? object["items"] as? [String: Any]
        let ownerName = owner?["display_name"] as? String
        return Self(uri: uri, name: name,
                    subtitle: artistNames.isEmpty ? (ownerName ?? (kind == "artist" ? "歌手" : "")) : artistNames.joined(separator: "、"),
                    kind: kind, durationMS: object["duration_ms"] as? Double ?? 0, imageURL: images.first?.url,
                    artists: artists, images: images, album: album, addedAt: addedAt,
                    releaseDate: object["release_date"] as? String, albumType: object["album_type"] as? String,
                    ownerName: ownerName, ownerID: owner?["id"] as? String,
                    collaborative: object["collaborative"] as? Bool ?? false,
                    trackCount: object["total_tracks"] as? Int ?? tracks?["total"] as? Int,
                    summary: (object["description"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }
}

nonisolated struct CatalogPage: Sendable {
    let items: [CatalogItem]
    let next: URL?
    /// What Spotify reports the whole list holds, where it says.
    var total: Int?

    static func parse(_ data: Data, searchType: String? = nil) throws -> Self {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SmalltifyError("Spotify 文库响应格式无效。")
        }
        if let searchType {
            guard let nested = object[searchType + "s"] as? [String: Any] else {
                throw SmalltifyError("Spotify 搜索响应格式无效。")
            }
            object = nested
        }
        guard let entries = object["items"] as? [Any] else { throw SmalltifyError("Spotify 曲目列表格式无效。") }
        let items = entries.compactMap { value -> CatalogItem? in
            guard let entry = value as? [String: Any] else { return nil }
            let entity = (entry["item"] as? [String: Any]) ?? (entry["track"] as? [String: Any])
                ?? (entry["album"] as? [String: Any]).flatMap { entry["uri"] == nil ? $0 : nil } ?? entry
            let addedAt = (entry["added_at"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
            return CatalogItem.parse(entity, addedAt: addedAt)
        }
        let next = (object["next"] as? String).flatMap(URL.init(string:))
        if let next, !OfficialWebAPI.allowedAPIURL(next) {
            throw SmalltifyError("拒绝读取非 Spotify 地址的下一页。")
        }
        return Self(items: items, next: next, total: object["total"] as? Int)
    }
}
