import Foundation
@testable import Spotifly
import Testing

@MainActor struct ArtistBrowsingTests {
    let firstID = "1234567890123456789012"
    let secondID = "abcdefghijklmnopqrstuv"

    @Test func trackArtistsRetainDistinctIDsAndRejectInvalidReferences() throws {
        let data = Data("""
        {"items":[{"uri":"spotify:track:\(firstID)","name":"Song","artists":[
        {"uri":"spotify:artist:\(firstID)","name":"First"},
        {"uri":"spotify:artist:\(secondID)","name":"Second"},
        {"uri":"spotify:artist:\(firstID)","name":"Duplicate"},
        {"uri":"spotify:artist:../../token","name":"Invalid"}]}]}
        """.utf8)
        let track = try #require(CatalogPage.parse(data).items.first)
        #expect(track.artists.map(\.spotifyID) == [firstID, secondID])
    }

    @Test func artistSearchIsBrowsableWithoutBecomingAPlayableLink() throws {
        let data = Data("""
        {"artists":{"items":[{"uri":"spotify:artist:\(firstID)","name":"Artist","type":"artist","images":[{"url":"https://i.scdn.co/image/example"}]}],"next":null}}
        """.utf8)
        let artist = try #require(CatalogPage.parse(data, searchType: "artist").items.first)
        #expect(artist.kind == "artist")
        #expect(artist.imageURL?.host == "i.scdn.co")
        #expect(SmalltifyModel.spotifyURI(from: artist.uri) == nil)
    }

    @Test func soloistCreatorLinksClearOnTrackChange() throws {
        var snapshot = SoloistSnapshot()
        let data = Data("""
        {"type":"track_changed","item":{"decorations":{"creators":[
        {"entity":{"uri":"spotify:artist:\(firstID)","decorations":{"identity":{"name":"First"}}}},
        {"entity":{"uri":"spotify:artist:\(secondID)","decorations":{"identity":{"name":"Second"}}}}
        ]}}}
        """.utf8)
        _ = try snapshot.apply(data)
        #expect(snapshot.artists.map(\.name) == ["First", "Second"])
        #expect(snapshot.artist == "First · Second")
        _ = try snapshot.apply(Data(#"{"type":"track_changed","item":{}}"#.utf8))
        #expect(snapshot.artists.isEmpty)
        #expect(snapshot.artist.isEmpty)
    }

    @Test func backAndForwardRetraceTheVisitedPages() {
        let model = SmalltifyModel(restoreCredentials: false)
        let navigator = model.navigator
        navigator.go(.liked)
        let artist = CatalogArtist(uri: "spotify:artist:\(firstID)", name: "Artist")
        let album = CatalogItem(uri: "spotify:album:\(secondID)", name: "Album", subtitle: "Artist", kind: "album", durationMS: 0, imageURL: nil)
        model.open(artist)
        model.open(album)
        #expect(navigator.current == .album(album))
        navigator.goBack()
        #expect(navigator.current == .artist(artist))
        navigator.goBack()
        #expect(navigator.current == .liked)
        navigator.goForward()
        #expect(navigator.current == .artist(artist))
        navigator.go(.albums)
        #expect(!navigator.canGoForward)
        #expect(navigator.backStack == [.home, .liked, .artist(artist)])
    }

    @Test func goingToTheShowingPageAddsNoHistory() {
        let navigator = Navigator(start: .liked)
        navigator.go(.liked)
        #expect(!navigator.canGoBack)
        navigator.go(.search("潮汐"))
        navigator.go(.search("潮汐"))
        #expect(navigator.backStack == [.liked])
    }

    @Test func detailPagesHighlightTheirSidebarSection() {
        let album = CatalogItem(uri: "spotify:album:\(secondID)", name: "Album", subtitle: "", kind: "album", durationMS: 0, imageURL: nil)
        #expect(Destination.album(album).section == .albums)
        #expect(Destination.artist(CatalogArtist(uri: "spotify:artist:\(firstID)", name: "A")).section == .artists)
        #expect(Destination.search("x").section == nil)
        #expect(Destination.collection(album) == .album(album))
    }

    @Test func appLinksOpenArtistAndAlbumPagesAndIgnoreOtherURLs() throws {
        let model = SmalltifyModel(restoreCredentials: false)
        let artist = CatalogArtist(uri: "spotify:artist:\(firstID)", name: "马洛·韦尔")
        #expect(model.handle(try #require(AppLink.artist(artist))))
        #expect(model.navigator.current == .artist(artist))
        let album = CatalogAlbumRef(uri: "spotify:album:\(secondID)", name: "潮汐电台")
        #expect(model.handle(try #require(AppLink.album(album))))
        guard case let .album(item) = model.navigator.current else { Issue.record("Album page did not open"); return }
        #expect(item.uri == album.uri && item.name == album.name)
        #expect(!model.handle(try #require(URL(string: "https://open.spotify.com/artist/\(firstID)"))))
        #expect(model.handle(try #require(URL(string: "smalltify://artist/not-an-id?name=x"))))
        #expect(model.navigator.current == .album(item))
    }
}
