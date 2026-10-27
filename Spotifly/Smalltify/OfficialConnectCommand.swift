import Foundation

nonisolated struct OfficialConnectCommand: Sendable {
    let method: String
    let path: String
    var query: [URLQueryItem] = []
    var body: Data?

    // Web API offsets are documented only for albums and playlists, not the collection URI.
    static func supportsOffset(_ uri: String) -> Bool {
        CatalogItem.validURI(uri) && (uri.hasPrefix("spotify:album:") || uri.hasPrefix("spotify:playlist:"))
    }

    private struct ContextStart: Encodable {
        struct Offset: Encodable { let uri: String }
        let context_uri: String
        let offset: Offset
    }

    static func transfer(to device: OfficialConnectDevice) throws -> Self {
        guard device.selectable, let id = device.id else { throw SmalltifyError("此设备暂不支持切换播放。") }
        // Omit play to preserve paused/playing state rather than force audio to start.
        return Self(method: "PUT", path: "/me/player", body: try JSONEncoder().encode(["device_ids": [id]]))
    }

    static func playback(_ command: String, device: OfficialConnectDevice, uri: String? = nil,
                         value: Double? = nil, enabled: Bool? = nil, context: PlaybackContext? = nil,
                         repeatMode: String? = nil, useOffset: Bool = true) throws -> Self {
        guard device.selectable, let id = device.id else { throw SmalltifyError("当前设备不接受远程控制。") }
        var query = [URLQueryItem(name: "device_id", value: id)]
        var method = "PUT"
        let path: String
        var body: Data?
        switch command {
        case "play":
            path = "/me/player/play"
            if let uri {
                guard CatalogItem.validURI(uri) else { throw SmalltifyError("无效的 Spotify 播放链接。") }
                if let context, useOffset, supportsOffset(context.uri), uri.hasPrefix("spotify:track:") {
                    body = try JSONEncoder().encode(ContextStart(context_uri: context.uri, offset: .init(uri: uri)))
                } else if let context {
                    let upcoming = context.upcoming.filter { CatalogItem.validURI($0) && $0.hasPrefix("spotify:track:") }
                    let uris = upcoming.first == uri ? Array(upcoming.prefix(100)) : [uri]
                    body = try JSONEncoder().encode(["uris": uris])
                } else if supportsOffset(uri) {
                    body = try JSONEncoder().encode(["context_uri": uri])
                } else {
                    body = try JSONEncoder().encode(["uris": [uri]])
                }
            }
        case "pause": path = "/me/player/pause"
        case "skip_next": path = "/me/player/next"; method = "POST"
        case "skip_prev": path = "/me/player/previous"; method = "POST"
        case "seek", "set_volume":
            guard let value, value.isFinite else { throw SmalltifyError("无效的播放参数。") }
            guard command != "set_volume" || device.supportsVolume else { throw SmalltifyError("请在目标设备上调整音量。") }
            path = command == "seek" ? "/me/player/seek" : "/me/player/volume"
            let maximum = command == "seek" ? Double(Int32.max) : 100
            query.append(.init(name: command == "seek" ? "position_ms" : "volume_percent", value: String(Int(min(maximum, max(0, value))))))
        case "set_repeat":
            guard let repeatMode, ["off", "context", "track"].contains(repeatMode) else {
                throw SmalltifyError("无效的循环模式。")
            }
            path = "/me/player/repeat"
            query.append(.init(name: "state", value: repeatMode))
        case "set_shuffle":
            guard let enabled else { throw SmalltifyError("缺少随机播放参数。") }
            path = "/me/player/shuffle"
            query.append(.init(name: "state", value: String(enabled)))
        case "add_to_queue":
            guard let uri, CatalogItem.validURI(uri), uri.hasPrefix("spotify:track:") || uri.hasPrefix("spotify:episode:") else {
                throw SmalltifyError("只能将歌曲或播客单集加入队列。")
            }
            path = "/me/player/queue"; method = "POST"
            query.append(.init(name: "uri", value: uri))
        default: throw SmalltifyError("该远程播放操作暂不支持。")
        }
        return Self(method: method, path: path, query: query, body: body)
    }
}
