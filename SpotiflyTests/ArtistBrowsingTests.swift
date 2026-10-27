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

    @Test func albumBackRestoresArtistFilterAndOriginalLibrary() {
        let model = SmalltifyModel(restoreCredentials: false)
        model.navigate("liked")
        let artist = CatalogArtist(uri: "spotify:artist:\(firstID)", name: "Artist")
        model.openArtist(artist)
        model.artistGroup = "single"
        model.openCollection(CatalogItem(uri: "spotify:album:\(secondID)", name: "Album", subtitle: "Artist", kind: "album", durationMS: 0, imageURL: nil))
        #expect(model.artist == nil)
        #expect(model.collection?.name == "Album")
        model.goBack()
        #expect(model.artist == artist)
        #expect(model.artistGroup == "single")
        #expect(model.collection == nil)
        model.goBack()
        #expect(model.selected == "liked")
        #expect(model.artist == nil)
        #expect(model.history.isEmpty)
    }

    @Test func openingArtistFromSettingsCanReturnToSettings() {
        let model = SmalltifyModel(restoreCredentials: false)
        model.navigate("settings")
        model.openArtist(CatalogArtist(uri: "spotify:artist:\(firstID)", name: "Artist"))
        #expect(model.selected != "settings")
        model.goBack()
        #expect(model.selected == "settings")
        #expect(model.history.isEmpty)
    }
}
