import Foundation
@testable import Spotifly
import Testing

@MainActor struct PlaylistShortcutsTests {
    @Test func savedLinksSurviveReloadAndDeduplicateShareParameters() throws {
        let suite = "SmalltifyShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = PlaylistShortcuts(defaults: defaults)
        let id = "1234567890123456789012"
        try shortcuts.save(name: " 每周新发现 ", link: "https://open.spotify.com/playlist/\(id)?si=first")
        try shortcuts.save(name: "新名称", link: "https://open.spotify.com/intl-zh/playlist/\(id)?si=second")
        let restored = PlaylistShortcuts(defaults: defaults)
        #expect(restored.playlists == [SavedPlaylist(uri: "spotify:playlist:\(id)", name: "新名称")])
        try restored.remove(try #require(restored.playlists.first))
        #expect(PlaylistShortcuts(defaults: defaults).playlists.isEmpty)
    }

    @Test func invalidEntriesDoNotChangeSavedPlaylists() throws {
        let suite = "SmalltifyShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = PlaylistShortcuts(defaults: defaults)
        let id = "1234567890123456789012"
        try shortcuts.save(name: "新歌雷达", link: "spotify:playlist:\(id)")
        let saved = shortcuts.playlists
        for link in ["spotify:track:\(id)", "https://example.com/playlist/\(id)", "spotify:playlist:invalid"] {
            #expect(throws: SmalltifyError.self) { try shortcuts.save(name: "无效", link: link) }
        }
        #expect(throws: SmalltifyError.self) { try shortcuts.save(name: "  ", link: "spotify:playlist:\(id)") }
        #expect(PlaylistShortcuts(defaults: defaults).playlists == saved)
    }
}
