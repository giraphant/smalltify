#if DEBUG
    import AppKit
    import CryptoKit
    import Foundation

    /// The canned catalog behind `DebugFixtures`: the artists, albums and playlists of the design
    /// mockups, served in the Web API's shapes. Add an endpoint to `respond` when a page needs one.
    nonisolated enum FixtureData {
        static let imageHost = "fixtures.smalltify.invalid"
        static let userID = "fixture-user"

        // MARK: - Catalog

        struct Artist {
            let name: String
            let color: String
            var id: String { FixtureData.id("artist:" + name) }
            var uri: String { "spotify:artist:" + id }
            var simple: [String: Any] { ["uri": uri, "id": id, "name": name, "type": "artist"] }
            var full: [String: Any] { simple.merging(["images": FixtureData.images(color), "genres": []]) { $1 } }
            var catalog: CatalogArtist { CatalogArtist.parse(full) ?? CatalogArtist(uri: uri, name: name) }
        }

        struct Album {
            let name: String
            let artists: [String]
            let date: String
            let color: String?
            var type = "album"
            /// Title, seconds, featured artists.
            let tracks: [(String, Int, [String])]
            var id: String { FixtureData.id("album:" + name) }
            var uri: String { "spotify:album:" + id }
            var simple: [String: Any] {
                ["uri": uri, "id": id, "name": name, "type": "album", "album_type": type, "release_date": date,
                 "total_tracks": tracks.count, "artists": artists.map { FixtureData.artist($0).simple },
                 "images": FixtureData.images(color)]
            }

            var stub: CatalogItem { CatalogItem(uri: uri, name: name, subtitle: "", kind: "album", durationMS: 0, imageURL: nil) }

            func trackObjects(withAlbum: Bool) -> [[String: Any]] {
                tracks.enumerated().map { index, track in
                    var object: [String: Any] = [
                        "uri": "spotify:track:" + FixtureData.id("track:\(name):\(track.0)"),
                        "id": FixtureData.id("track:\(name):\(track.0)"), "name": track.0, "type": "track",
                        "duration_ms": track.1 * 1000, "track_number": index + 1,
                        "artists": (artists + track.2).map { FixtureData.artist($0).simple },
                    ]
                    if withAlbum { object["album"] = simple }
                    return object
                }
            }
        }

        struct Playlist {
            let name: String
            let owner: String
            let ownerID: String
            let color: String
            var collaborative = false
            var summary = ""
            /// Indexes into `allTracks`.
            var trackIndexes: [Int] = []
            var id: String { FixtureData.id("playlist:" + name) }
            var uri: String { "spotify:playlist:" + id }
            var isMine: Bool { ownerID == FixtureData.userID || collaborative }
            var simple: [String: Any] {
                ["uri": uri, "id": id, "name": name, "type": "playlist", "collaborative": collaborative,
                 "description": summary, "owner": ["id": ownerID, "display_name": owner],
                 "images": FixtureData.images(color), "items": ["total": trackIndexes.count]]
            }

            var stub: CatalogItem { CatalogItem(uri: uri, name: name, subtitle: "", kind: "playlist", durationMS: 0, imageURL: nil) }
        }

        static let artists = [
            Artist(name: "马洛·韦尔", color: "3A5A78"), Artist(name: "朱妮珀·黑尔", color: "B5532E"),
            Artist(name: "艾达·布雷克", color: "2E2A3A"), Artist(name: "索尔", color: "8C4A6B"),
            Artist(name: "鹪鹩乐队", color: "7A8F9E"), Artist(name: "林间录音", color: "2F6B5B"),
        ]

        static let albums = [
            Album(name: "潮汐电台", artists: ["马洛·韦尔"], date: "2024-03-01", color: "3A5A78", tracks: [
                ("潮汐电台", 238, []), ("港口灯火", 221, []), ("盐与静电", 245, []), ("凌晨的渡轮", 192, ["索尔"]),
                ("玻璃浮球", 267, []), ("暗流", 229, []), ("长堤", 302, []), ("造雾机", 200, []),
                ("信号火", 251, ["艾达·布雷克"]), ("靠岸", 216, []),
            ]),
            Album(name: "纸灯笼", artists: ["朱妮珀·黑尔"], date: "2023-05-12", color: "B5532E", tracks: [
                ("纸灯笼", 252, []), ("灯塔", 227, []), ("雨巷", 210, []), ("晚灯", 245, []), ("旧信", 260, []),
            ]),
            Album(name: "北方静电", artists: ["艾达·布雷克"], date: "2022-11-04", color: "2E2A3A", tracks: [
                ("北方静电", 280, []), ("极光", 301, []), ("冻土", 224, []), ("无线电", 258, []),
            ]),
            Album(name: "周日慢板", artists: ["索尔"], date: "2024-08-09", color: "8C4A6B", tracks: [
                ("周日慢板", 305, ["艾达·布雷克", "林间录音"]), ("退潮之后", 242, []), ("午睡", 213, ["马洛·韦尔"]),
            ]),
            Album(name: "玻璃温室（豪华版）", artists: ["鹪鹩乐队"], date: "2021-04-16", color: "7A8F9E", tracks: [
                ("一首名字非常非常长的歌，长到在任何列宽下都必须截断显示（Live at Harbour Hall · 2024 Remaster）", 381, []),
                ("潮汐表", 211, []), ("玻璃温室", 381, []),
            ]),
            Album(name: "散步", artists: ["林间录音"], date: "2020-02-02", color: nil, tracks: [
                ("雾中散步", 178, []), ("潮间带", 167, []),
            ]),
            Album(name: "灰色海岸", artists: ["马洛·韦尔"], date: "2021-09-10", color: "7A8F9E", tracks: [("灰色海岸", 240, []), ("浪", 210, [])]),
            Album(name: "冬季航线", artists: ["马洛·韦尔"], date: "2019-12-01", color: "2E2A3A", tracks: [("冬季航线", 250, [])]),
            Album(name: "涨潮（现场版）", artists: ["马洛·韦尔"], date: "2025-01-10", color: "1F3B4D", type: "single", tracks: [("涨潮（现场版）", 273, [])]),
            Album(name: "港口三首", artists: ["马洛·韦尔"], date: "2023-06-01", color: "5B6F86", type: "single", tracks: [
                ("港口一", 180, []), ("港口二", 190, []), ("港口三", 200, []),
            ]),
            Album(name: "夜航", artists: ["马洛·韦尔"], date: "2020-07-07", color: "B5532E", type: "single", tracks: [("夜航", 230, [])]),
        ]

        /// Every track with its album, in album order.
        static var allTracks: [[String: Any]] { albums.flatMap { $0.trackObjects(withAlbum: true) } }

        static let playlists = [
            Playlist(name: "深夜驾驶", owner: "测试用户", ownerID: userID, color: "1F3B4D", summary: "适合开夜车的歌。", trackIndexes: Array(0 ..< 16)),
            Playlist(name: "听潮", owner: "测试用户", ownerID: userID, color: "2F6B5B", collaborative: true, trackIndexes: [0, 4, 9, 22, 24]),
            Playlist(name: "海边的周末", owner: "旅行电台", ownerID: "travel-radio", color: "C2185B",
                     summary: "来自 Spotify 的描述文字，最多显示两行，超出部分截断。海风、沙滩与慢节奏的周末下午。", trackIndexes: [1, 2, 3]),
            Playlist(name: "每周新发现", owner: "Spotify", ownerID: "spotify", color: "5E40BE", summary: "每周一更新的个性化推荐。"),
            Playlist(name: "新歌雷达", owner: "Spotify", ownerID: "spotify", color: "C2185B", summary: "你关注的歌手的新歌。"),
        ]

        static func artist(_ name: String) -> Artist { artists.first { $0.name == name } ?? artists[0] }
        static func album(_ name: String) -> Album { albums.first { $0.name == name } ?? albums[0] }
        static func playlist(_ name: String) -> Playlist { playlists.first { $0.name == name } ?? playlists[0] }

        static var nowPlaying: SoloistSnapshot {
            var snapshot = SoloistSnapshot()
            let track = allTracks[0]
            snapshot.loggedIn = true
            snapshot.active = true
            snapshot.status = "playing"
            snapshot.uri = track["uri"] as? String ?? ""
            snapshot.title = track["name"] as? String ?? ""
            snapshot.artists = [artist("马洛·韦尔").catalog]
            snapshot.artist = "马洛·韦尔"
            snapshot.coverURL = URL(string: "https://\(imageHost)/cover/3A5A78.png")
            snapshot.durationMS = 238_000
            snapshot.positionMS = 102_000
            snapshot.timestampMS = Date().timeIntervalSince1970 * 1000
            snapshot.speed = 1
            snapshot.volume = 70
            return snapshot
        }

        // MARK: - Responses

        static func respond(method: String, url: URL) -> (Int, Data, String) {
            let path = String(url.path.dropFirst("/v1".count))
            let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { $1 }
            let offset = Int(query["offset"] ?? "") ?? 0
            let limit = Int(query["limit"] ?? "") ?? 20
            let parts = path.split(separator: "/").map(String.init)
            debugLog("Fixtures", "[\(method)] \(path)")
            // Each area's own endpoints first; those files belong to the workers building the area.
            let request = FixtureRequest(method: method, path: path, parts: parts, query: query, offset: offset, limit: limit)
            if let response = respondLibrary(request) ?? respondDetail(request) ?? respondDiscover(request)
                ?? respondPlayer(request) ?? respondSettings(request) {
                return response
            }
            if method != "GET" { return (204, Data(), "application/json") }

            switch parts {
            case ["me"]:
                return ok(["id": userID, "display_name": "测试用户", "images": []])
            case ["me", "tracks"]:
                let entries = (0 ..< 120).map { index -> [String: Any] in
                    ["added_at": iso(daysAgo: index * 2 + 3), "track": allTracks[index % allTracks.count]]
                }
                return ok(page(entries, path: path, offset: offset, limit: limit))
            case ["me", "playlists"]:
                return ok(page(playlists.map(\.simple), path: path, offset: offset, limit: limit))
            case ["me", "albums"]:
                let entries = albums.enumerated().map { index, album -> [String: Any] in
                    ["added_at": iso(daysAgo: index * 9 + 1), "album": album.simple]
                }
                return ok(page(entries, path: path, offset: offset, limit: limit))
            case ["me", "following"]:
                return ok(["artists": page(artists.map(\.full), path: path, offset: offset, limit: limit)])
            case ["me", "top", "tracks"]:
                return ok(page(Array(allTracks.prefix(10)), path: path, offset: offset, limit: limit))
            case ["me", "top", "artists"]:
                return ok(page(artists.map(\.full), path: path, offset: offset, limit: limit))
            case ["me", "player", "recently-played"]:
                let contexts: [[String: Any]] = [
                    ["type": "album", "uri": albums[0].uri], ["type": "playlist", "uri": playlists[0].uri],
                    ["type": "artist", "uri": artists[1].uri], ["type": "playlist", "uri": playlists[3].uri],
                    ["type": "album", "uri": albums[2].uri],
                ]
                let items = contexts.enumerated().map { index, context -> [String: Any] in
                    ["track": allTracks[index * 3], "played_at": iso(daysAgo: 0), "context": context]
                }
                return ok(["items": items, "next": NSNull()])
            case ["me", "player", "queue"]:
                return ok(["currently_playing": allTracks[0], "queue": Array(allTracks[1 ..< 9])])
            case ["me", "player", "devices"]:
                return ok(["devices": [
                    device("Smalltify", type: "Computer"), device("客厅音箱", type: "Speaker", volume: false),
                    device("iPhone", type: "Smartphone"), device("书房电脑", type: "Computer"),
                    device("卧室电视", type: "TV", restricted: true),
                ]])
            case ["me", "player"]:
                return (204, Data(), "application/json")
            case ["search"]:
                let text = query["q"] ?? ""
                guard text != "无结果" else {
                    return ok(Dictionary(uniqueKeysWithValues: (query["type"] ?? "").split(separator: ",").map {
                        ("\($0)s", ["items": [], "total": 0, "next": NSNull()] as [String: Any])
                    }))
                }
                var result: [String: Any] = [:]
                for type in (query["type"] ?? "track").split(separator: ",") {
                    let items: [[String: Any]] = switch type {
                    case "track": allTracks
                    case "artist": artists.map(\.full)
                    case "album": albums.map(\.simple)
                    case "playlist": playlists.map(\.simple)
                    default: []
                    }
                    result["\(type)s"] = page(items, path: path, offset: offset, limit: min(limit, 10), extra: query)
                }
                return ok(result)
            case let parts where parts.count == 2 && parts[0] == "albums":
                guard let album = albums.first(where: { $0.id == parts[1] }) else { break }
                var object = album.simple
                object["tracks"] = page(album.trackObjects(withAlbum: false), path: path + "/tracks", offset: 0, limit: 50)
                object["label"] = NSNull()
                return ok(object)
            case let parts where parts.count == 3 && parts[0] == "albums" && parts[2] == "tracks":
                guard let album = albums.first(where: { $0.id == parts[1] }) else { break }
                return ok(page(album.trackObjects(withAlbum: false), path: path, offset: offset, limit: limit))
            case let parts where parts.count == 2 && parts[0] == "playlists":
                guard let playlist = playlists.first(where: { $0.id == parts[1] }) else { break }
                return ok(playlist.simple)
            case let parts where parts.count == 3 && parts[0] == "playlists" && parts[2] == "items":
                guard let playlist = playlists.first(where: { $0.id == parts[1] }) else { break }
                guard playlist.isMine else {
                    return (403, json(["error": ["status": 403, "message": "Forbidden"]]), "application/json")
                }
                let entries = playlist.trackIndexes.map { index -> [String: Any] in
                    ["added_at": iso(daysAgo: index + 1), "item": allTracks[index % allTracks.count]]
                }
                return ok(page(entries, path: path, offset: offset, limit: limit))
            case let parts where parts.count == 2 && parts[0] == "artists":
                guard let artist = artists.first(where: { $0.id == parts[1] }) else { break }
                return ok(artist.full)
            case let parts where parts.count == 3 && parts[0] == "artists" && parts[2] == "albums":
                guard let artist = artists.first(where: { $0.id == parts[1] }) else { break }
                let groups = (query["include_groups"] ?? "album,single").split(separator: ",").map(String.init)
                let items = albums.compactMap { album -> [String: Any]? in
                    let own = album.artists.contains(artist.name)
                    let featured = !own && album.tracks.contains { $0.2.contains(artist.name) }
                    let group = own ? album.type : featured ? "appears_on" : nil
                    guard let group, groups.contains(group) else { return nil }
                    return album.simple.merging(["album_group": group]) { $1 }
                }
                return ok(page(items, path: path, offset: offset, limit: limit, extra: query))
            default:
                break
            }
            return (404, json(["error": ["status": 404, "message": "No fixture for \(path)"]]), "application/json")
        }

        // MARK: - Helpers

        /// One request, parsed for the area responders.
        struct FixtureRequest {
            let method: String
            /// Without the `/v1` prefix, such as `/me/tracks`.
            let path: String
            let parts: [String]
            let query: [String: String]
            let offset: Int
            let limit: Int
        }

        static func id(_ seed: String) -> String {
            let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
            return String(SHA256.hash(data: Data(seed.utf8)).prefix(22).map { alphabet[Int($0) % alphabet.count] })
        }

        static func images(_ color: String?) -> [[String: Any]] {
            guard let color else { return [] }
            return [640, 300, 64].map { ["url": "https://\(imageHost)/cover/\(color).png?w=\($0)", "width": $0, "height": $0] }
        }

        static func png(hex: String) -> Data {
            let value = Int(hex, radix: 16) ?? 0x888888
            let color = NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
                                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                color.setFill()
                rect.fill()
                return true
            }
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return Data() }
            return rep.representation(using: .png, properties: [:]) ?? Data()
        }

        static func page(_ items: [[String: Any]], path: String, offset: Int, limit: Int, extra: [String: String] = [:]) -> [String: Any] {
            let slice = Array(items.dropFirst(offset).prefix(limit))
            var next: Any = NSNull()
            if offset + limit < items.count {
                var parts = URLComponents(string: "https://api.spotify.com/v1" + path)
                var query = extra
                query["offset"] = "\(offset + limit)"
                query["limit"] = "\(limit)"
                parts?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
                next = parts?.url?.absoluteString ?? NSNull()
            }
            return ["items": slice, "total": items.count, "offset": offset, "limit": limit, "next": next]
        }

        static func device(_ name: String, type: String, volume: Bool = true, restricted: Bool = false) -> [String: Any] {
            ["id": id("device:" + name), "name": name, "type": type, "is_active": false, "is_restricted": restricted,
             "supports_volume": volume, "volume_percent": 60]
        }

        static func iso(daysAgo: Int) -> String {
            Date().addingTimeInterval(TimeInterval(-daysAgo * 86400)).formatted(.iso8601)
        }

        static func ok(_ object: [String: Any]) -> (Int, Data, String) { (200, json(object), "application/json") }

        static func json(_ object: Any) -> Data {
            (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        }
    }
#endif
