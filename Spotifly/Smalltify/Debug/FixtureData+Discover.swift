#if DEBUG
    import Foundation

    nonisolated extension FixtureData {
        static func respondDiscover(_ request: FixtureRequest) -> (Int, Data, String)? {
            guard request.method == "GET" else { return nil }
            let isHome = request.path == "/me/player/recently-played" || request.path.hasPrefix("/me/top/")
            let opens = (ProcessInfo.processInfo.environment["SMALLTIFY_OPEN"] ?? "").split(separator: ",")
            if request.path == "/search", request.offset > 0, opens.contains("discover-more-failure") {
                return (500, json(["error": ["status": 500, "message": "网络连接中断。"]]), "application/json")
            }
            if isHome || request.path == "/search" {
                if opens.contains("discover-forbidden") {
                    return (403, json(["error": ["status": 403, "message": "Missing scope"]]), "application/json")
                }
                if opens.contains("discover-failure") {
                    return (500, json(["error": ["status": 500, "message": "网络连接中断。"]]), "application/json")
                }
                if opens.contains("discover-empty"), isHome {
                    return ok(["items": [], "next": NSNull(), "total": 0])
                }
            }
            let tideArtist = Artist(name: "潮汐乐团", color: "3A5A78")
            if request.path == "/artists/" + tideArtist.id { return ok(tideArtist.full) }
            if request.path == "/artists/" + tideArtist.id + "/albums" {
                return ok(page([albums[0].simple], path: request.path, offset: request.offset, limit: request.limit))
            }
            switch request.path {
            case "/me/top/tracks":
                let names = ["潮汐电台", "纸灯笼", "北方静电", "周日慢板", "灯塔"]
                var tracks = names.compactMap { name in allTracks.first { $0["name"] as? String == name } }
                if request.query["time_range"] == "medium_term" { tracks.reverse() }
                if request.query["time_range"] == "long_term" { tracks = Array(tracks.dropFirst()) + Array(tracks.prefix(1)) }
                return ok(page(tracks, path: request.path, offset: request.offset, limit: request.limit))
            case "/me/top/artists":
                var items = artists.map(\.full)
                if request.query["time_range"] == "medium_term" { items.reverse() }
                if request.query["time_range"] == "long_term" { items = Array(items.dropFirst()) + Array(items.prefix(1)) }
                return ok(page(items, path: request.path, offset: request.offset, limit: request.limit))
            case "/me/player/recently-played":
                let contexts: [[String: Any]?] = [
                    ["uri": albums[0].uri], ["uri": playlists[0].uri], ["uri": artists[1].uri],
                    ["uri": playlists[3].uri], ["uri": albums[2].uri], nil,
                ]
                let entries = contexts.enumerated().map { index, context -> [String: Any] in
                    ["context": context as Any? ?? NSNull(),
                     "track": index == 5 ? album("周日慢板").trackObjects(withAlbum: true)[0] : allTracks[index]]
                }
                return ok(["items": entries, "next": NSNull()])
            case "/search" where request.query["q"] == "潮汐":
                let names = ["潮汐电台", "退潮之后", "潮汐表", "大潮", "潮间带", "涨潮（现场版）"]
                var tracks = names.compactMap { name in allTracks.first { $0["name"] as? String == name } }
                var tide = album("北方静电").trackObjects(withAlbum: true)[0]
                tide["name"] = "大潮"
                tide["uri"] = "spotify:track:" + id("track:大潮")
                tide["duration_ms"] = 314_000
                tracks.insert(tide, at: 3)
                tracks += allTracks.filter { track in !tracks.contains { $0["uri"] as? String == track["uri"] as? String } }
                var result: [String: Any] = [:]
                for type in (request.query["type"] ?? "track").split(separator: ",") {
                    let items: [[String: Any]] = switch type {
                    case "track": tracks
                    case "artist": [tideArtist.full, artists[0].full, artists[4].full, artists[5].full]
                    case "album": albums.map(\.simple)
                    case "playlist": [playlists[1].simple, playlists[2].simple, playlists[3].simple, playlists[0].simple]
                    default: []
                    }
                    result["\(type)s"] = page(items, path: request.path, offset: request.offset,
                                             limit: min(10, request.limit), extra: request.query)
                }
                return ok(result)
            default:
                return nil
            }
        }
    }
#endif
