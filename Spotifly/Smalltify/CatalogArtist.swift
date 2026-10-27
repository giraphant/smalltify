import Foundation

nonisolated struct CatalogArtist: Identifiable, Sendable, Hashable {
    let uri: String
    let name: String
    var imageURL: URL?
    /// Every size Spotify offered, smallest first; empty for artists named only in a track.
    var images: [CatalogImage] = []
    var id: String { uri }
    var spotifyID: String { String(uri.dropFirst("spotify:artist:".count)) }
    var openURL: URL? { URL(string: "https://open.spotify.com/artist/\(spotifyID)") }

    /// The smallest image at least `pixels` wide, else the largest there is.
    func imageURL(minPixels pixels: CGFloat) -> URL? {
        let sized = images.filter { $0.width != nil }
        return sized.first { CGFloat($0.width ?? 0) >= pixels }?.url ?? sized.last?.url ?? imageURL
    }

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
        return Self(uri: uri, name: name, imageURL: imageURL, images: CatalogItem.parseImages(object["images"]))
    }

    static func fromSoloist(_ entity: [String: Any]) -> Self? {
        let decorations = entity["decorations"] as? [String: Any] ?? [:]
        let identity = decorations["identity"] as? [String: Any] ?? [:]
        guard let uri = entity["uri"] as? String, validURI(uri),
              let name = identity["name"] as? String else { return nil }
        return Self(uri: uri, name: name)
    }
}
