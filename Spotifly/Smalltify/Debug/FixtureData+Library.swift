#if DEBUG
    import Foundation

    nonisolated extension FixtureData {
        @MainActor static func libraryStateLoader(_ model: SmalltifyModel, key: String, url: URL) -> PagedLoader? {
            guard DebugFixtures.opens("library-more-loading") else { return nil }
            return model.pages.loader(key) {
                PagedLoader(firstURL: url, report: { [weak model] in model?.report($0) }) { [api = model.api] url, _ in
                    try await libraryRequestDelay(url)
                    return try CatalogPage.parse(try await api.get(url))
                }
            }
        }

        static func libraryRequestDelay(_ url: URL) async throws {
            let environment = ProcessInfo.processInfo.environment
            let states = (environment["SMALLTIFY_OPEN"] ?? "").split(separator: ",")
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if environment["SMALLTIFY_FIXTURES"] == "1", states.contains("library-more-loading"),
               query.contains(where: { $0.name == "offset" || $0.name == "after" }) {
                try await Task.sleep(for: .seconds(30))
            }
        }

        /// `SMALLTIFY_OPEN=library-empty` or `library-failure` exercises every library page.
        static func respondLibrary(_ request: FixtureRequest) -> (Int, Data, String)? {
            guard request.method == "GET", ["/me/tracks", "/me/playlists", "/me/albums", "/me/following"].contains(request.path) else {
                return nil
            }
            let environment = ProcessInfo.processInfo.environment
            guard environment["SMALLTIFY_FIXTURES"] == "1" else { return nil }
            let states = (environment["SMALLTIFY_OPEN"] ?? "").split(separator: ",")
            let isNext = request.offset > 0 || request.query["after"] != nil
            let paged = states.contains("library-paged") || states.contains("library-more-loading") || states.contains("library-more-failure")
            if states.contains("library-failure") || (states.contains("library-more-failure") && isNext) {
                return (500, json(["error": ["status": 500, "message": "暂时无法连接 Spotify，请稍后重试。"]]), "application/json")
            }
            if states.contains("library-empty") {
                let empty = page([], path: request.path, offset: 0, limit: request.limit)
                return ok(request.path == "/me/following" ? ["artists": empty] : empty)
            }
            if request.path == "/me/following" {
                // Followed artists use an opaque cursor, never an offset.
                let cursor = request.query["after"]
                let offset = cursor.flatMap { id in artists.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
                let limit = paged ? 3 : request.limit
                let slice = Array(artists.dropFirst(offset).prefix(limit))
                let after = slice.last?.id
                var next: Any = NSNull()
                if offset + slice.count < artists.count, let after {
                    var url = URLComponents(string: "https://api.spotify.com/v1/me/following")
                    url?.queryItems = [.init(name: "type", value: "artist"), .init(name: "limit", value: "\(limit)"),
                                      .init(name: "after", value: after)]
                    next = url?.url?.absoluteString ?? NSNull()
                }
                return ok(["artists": ["items": slice.map(\.full), "total": artists.count, "next": next,
                                        "cursors": ["after": after as Any? ?? NSNull()]]])
            }
            if paged {
                let entries: [[String: Any]]
                switch request.path {
                case "/me/playlists": entries = playlists.map(\.simple)
                case "/me/albums": entries = albums.enumerated().map { ["added_at": iso(daysAgo: $0.offset), "album": $0.element.simple] }
                case "/me/tracks": entries = allTracks.enumerated().map { ["added_at": iso(daysAgo: $0.offset), "track": $0.element] }
                default: return nil
                }
                return ok(page(entries, path: request.path, offset: request.offset, limit: 3, extra: request.query))
            }
            if states.contains("liked-complete"), request.path == "/me/tracks" {
                let entries = allTracks.prefix(10).enumerated().map { ["added_at": iso(daysAgo: $0.offset), "track": $0.element] }
                return ok(page(entries, path: request.path, offset: request.offset, limit: 50))
            }
            return nil
        }
    }
#endif
