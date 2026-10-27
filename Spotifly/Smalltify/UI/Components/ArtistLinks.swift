import SwiftUI

/// Artist names in secondary text, each one a link to its artist page, truncating as one line.
///
/// The links are `AppLink` urls the workspace's `openURL` handler routes, so a line naming
/// several artists still truncates like text while every name stays clickable.
struct ArtistLinks: View {
    let artists: [CatalogArtist]
    /// Shown as plain text when there are no artists to link, such as a playlist's owner.
    var fallback = ""

    var body: some View {
        Text(Self.attributed(artists, fallback: fallback))
            .lineLimit(1)
            .truncationMode(.tail)
            .quietLinks()
            .help(Formatting.artistNames(artists, fallback: fallback))
    }

    static func attributed(_ artists: [CatalogArtist], fallback: String) -> AttributedString {
        guard !artists.isEmpty else { return AttributedString(fallback) }
        var text = AttributedString()
        for (index, artist) in artists.enumerated() {
            if index > 0 { text += AttributedString("、") }
            var name = AttributedString(artist.name)
            name.link = AppLink.artist(artist)
            text += name
        }
        return text
    }
}

/// A single linked name, such as a track's album.
struct AlbumLink: View {
    let album: CatalogAlbumRef?

    var body: some View {
        if let album {
            Text(Self.attributed(album)).lineLimit(1).quietLinks().help(album.name)
        } else {
            Text("")
        }
    }

    static func attributed(_ album: CatalogAlbumRef) -> AttributedString {
        var text = AttributedString(album.name)
        text.link = AppLink.album(album)
        return text
    }
}

extension View {
    /// Shows links in secondary text color, as the design lists artists and albums, instead of
    /// the accent color every link would otherwise take. Apply to the link text only: it sets the
    /// tint, which prominent buttons and indicators also use.
    func quietLinks() -> some View {
        tint(.secondary)
    }
}
