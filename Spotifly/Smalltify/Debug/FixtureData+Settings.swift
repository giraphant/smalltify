#if DEBUG
    import Foundation

    nonisolated extension FixtureData {
        static let settingsEpisodeID = id("episode:海边来信")

        static func respondSettings(_ request: FixtureRequest) -> (Int, Data, String)? {
            let parts = request.path.split(separator: "/")
            guard request.method == "GET", parts.count == 2 else { return nil }
            if ["tracks", "albums", "playlists", "episodes"].contains(String(parts[0])), parts[1] == String(repeating: "x", count: 22) {
                let response = ok(["error": ["status": 404, "message": "找不到这个链接的内容。"]])
                return (404, response.1, response.2)
            }
            if parts[0] == "tracks", let track = allTracks.first(where: { $0["id"] as? String == String(parts[1]) }) {
                return ok(track)
            }
            if parts[0] == "episodes", parts[1] == settingsEpisodeID {
                return ok(["id": settingsEpisodeID, "uri": "spotify:episode:" + settingsEpisodeID,
                           "type": "episode", "name": "海边来信", "duration_ms": 1800000,
                           "images": images("3A5A78"), "show": ["name": "潮汐播客"]])
            }
            return nil
        }

        @MainActor static func settingsInput(shortcut: Bool) -> String {
            guard DebugFixtures.isEnabled else { return "" }
            let mode = DebugFixtures.environment["SMALLTIFY_INPUT"] ?? (shortcut ? "playlist" : "album")
            switch mode {
            case "empty": return ""
            case "invalid": return "https://example.com/abc"
            case "playlist": return "https://open.spotify.com/playlist/" + playlist("每周新发现").id
            case "track": return allTracks.first?["uri"] as? String ?? ""
            case "episode": return "spotify:episode:" + settingsEpisodeID
            case "loading": return shortcut ? playlist("每周新发现").uri : album("潮汐电台").uri
            case "failure": return "spotify:\(shortcut ? "playlist" : "album"):" + String(repeating: "x", count: 22)
            default: return "https://open.spotify.com/album/" + album("潮汐电台").id
            }
        }
    }
#endif
