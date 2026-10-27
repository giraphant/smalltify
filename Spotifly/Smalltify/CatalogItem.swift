import Foundation

nonisolated struct CatalogItem: Identifiable, Sendable, Equatable {
    let uri: String
    let name: String
    let subtitle: String
    let kind: String
    let durationMS: Double
    let imageURL: URL?
    var artists: [CatalogArtist] = []
    var id: String { uri }
    var spotifyID: String { uri.split(separator: ":").last.map(String.init) ?? "" }
    var isCollection: Bool { kind == "album" || kind == "playlist" }

    static func validURI(_ uri: String) -> Bool {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "spotify"
            && ["track", "album", "playlist", "episode"].contains(parts[1])
            && parts[2].count == 22 && parts[2].utf8.allSatisfy {
                (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0)
            }
    }

    static func parse(_ object: [String: Any]) -> Self? {
        guard let uri = object["uri"] as? String, (validURI(uri) || CatalogArtist.validURI(uri)),
              let name = object["name"] as? String else { return nil }
        let kind = object["type"] as? String ?? String(uri.split(separator: ":")[1])
        let artistObjects = object["artists"] as? [[String: Any]] ?? []
        let artistNames = artistObjects.compactMap { $0["name"] as? String }
        var seenArtists = Set<String>()
        let artists = artistObjects.compactMap(CatalogArtist.parse).filter { seenArtists.insert($0.uri).inserted }
        let album = object["album"] as? [String: Any]
        let owner = object["owner"] as? [String: Any]
        let images = (object["images"] ?? album?["images"]) as? [[String: Any]] ?? []
        let image = images.last?["url"] as? String
        let imageURL = image.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        return Self(uri: uri, name: name,
                    subtitle: artistNames.isEmpty ? (owner?["display_name"] as? String ?? (kind == "artist" ? "歌手" : "")) : artistNames.joined(separator: " · "),
                    kind: kind, durationMS: object["duration_ms"] as? Double ?? 0, imageURL: imageURL, artists: artists)
    }
}

nonisolated struct CatalogPage: Sendable {
    let items: [CatalogItem]
    let next: URL?

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
            return CatalogItem.parse(entity)
        }
        let next = (object["next"] as? String).flatMap(URL.init(string:))
        if let next, !OfficialWebAPI.allowedAPIURL(next) {
            throw SmalltifyError("拒绝读取非 Spotify 地址的下一页。")
        }
        return Self(items: items, next: next)
    }
}
