#if DEBUG
    import Foundation
    import Synchronization

    nonisolated extension FixtureData {
        private static let detailSaved = Mutex<[String: Bool]>([:])

        static func delayDetailLoad() async {
            let options = (ProcessInfo.processInfo.environment["SMALLTIFY_OPEN"] ?? "").split(separator: ",")
            if ProcessInfo.processInfo.environment["SMALLTIFY_FIXTURES"] == "1", options.contains("detail-loading") {
                try? await Task.sleep(for: .seconds(30))
            }
        }

        static func respondDetail(_ request: FixtureRequest) -> (Int, Data, String)? {
            let uris = (request.query["uris"] ?? "").split(separator: ",").map(String.init)
            let options = (ProcessInfo.processInfo.environment["SMALLTIFY_OPEN"] ?? "").split(separator: ",")
            let ownsURIs = !uris.isEmpty && uris.allSatisfy {
                $0.hasPrefix("spotify:album:") || $0.hasPrefix("spotify:artist:")
            }
            if ownsURIs, request.path == "/me/library/contains", request.method == "GET" {
                return (200, json(uris.map { uri in
                    detailSaved.withLock { $0[uri] } ?? options.contains("detail-saved")
                }), "application/json")
            }
            if ownsURIs, request.path == "/me/library", ["PUT", "DELETE"].contains(request.method) {
                if options.contains("detail-write-error") {
                    return (500, json(["error": ["status": 500, "message": "演示：收藏失败，请重试。"]]), "application/json")
                }
                detailSaved.withLock { saved in
                    for uri in uris {
                        saved[uri] = request.method == "PUT"
                    }
                }
                return (200, Data(), "application/json")
            }
            if request.parts.first == "albums" || request.parts.first == "playlists" || request.parts.first == "artists" {
                if options.contains("detail-error") {
                    return (500, json(["error": ["status": 500, "message": "网络连接中断。"]]), "application/json")
                }
                if request.parts.count == 3, options.contains("detail-tracks-error") {
                    return (500, json(["error": ["status": 500, "message": "网络连接中断。"]]), "application/json")
                }
                if request.parts.first == "artists", request.parts.count == 3, options.contains("detail-more") {
                    let items = (0 ..< 12).map { index in
                        var object = albums[index % albums.count].simple
                        object["uri"] = "spotify:album:" + id("detail-more:\(index)")
                        return object
                    }
                    return ok(page(items, path: request.path, offset: request.offset, limit: 2, extra: request.query))
                }
                if request.parts.count == 3, options.contains("detail-empty") {
                    return ok(page([], path: request.path, offset: 0, limit: request.limit))
                }
            }
            return nil
        }
    }
#endif
