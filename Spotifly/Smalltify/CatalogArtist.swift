import Foundation

nonisolated struct CatalogArtist: Identifiable, Sendable, Equatable {
    let uri: String
    let name: String
    var imageURL: URL?
    var id: String { uri }
    var spotifyID: String { String(uri.dropFirst("spotify:artist:".count)) }

    static func validURI(_ uri: String) -> Bool {
        guard uri.hasPrefix("spotify:artist:") else { return false }
        return CatalogItem.validURI("spotify:track:" + uri.dropFirst("spotify:artist:".count))
    }

    static func parse(_ object: [String: Any]) -> Self? {
        guard let uri = object["uri"] as? String, validURI(uri),
              let name = object["name"] as? String else { return nil }
        let images = object["images"] as? [[String: Any]] ?? []
        let imageURL = images.compactMap { image -> URL? in
            guard let text = image["url"] as? String, let url = URL(string: text),
                  url.scheme == "https", url.user == nil, url.password == nil else { return nil }
            return url
        }.first
        return Self(uri: uri, name: name, imageURL: imageURL)
    }

    static func fromSoloist(_ entity: [String: Any]) -> Self? {
        let decorations = entity["decorations"] as? [String: Any] ?? [:]
        let identity = decorations["identity"] as? [String: Any] ?? [:]
        guard let uri = entity["uri"] as? String, validURI(uri),
              let name = identity["name"] as? String else { return nil }
        return Self(uri: uri, name: name)
    }
}
