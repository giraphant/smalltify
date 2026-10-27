import Foundation

/// Applies both full snapshots and granular events; command_result is not playback proof.
nonisolated struct SoloistSnapshot: Sendable {
    var loggedIn = false
    var active = false
    var status = "idle"
    var uri = ""
    var title = "尚未播放"
    var artist = ""
    var artists: [CatalogArtist] = []
    var album: CatalogAlbumRef?
    var releaseYear: String?
    var coverURL: URL?
    var durationMS = 0.0
    var positionMS = 0.0
    var timestampMS = 0.0
    var speed = 0.0
    var volume = 40.0
    var shuffle = false
    var repeatMode = "off"

    var hasTrack: Bool { !uri.isEmpty }
    var nextRepeatMode: String {
        switch repeatMode {
        case "context": "track"
        case "track": "off"
        default: "context"
        }
    }
    var repeatLabel: String {
        switch repeatMode {
        case "context": "列表循环"
        case "track": "单曲循环"
        default: "关"
        }
    }

    func position(at date: Date) -> Double {
        let elapsed = status == "playing" && timestampMS > 0 ? max(0, date.timeIntervalSince1970 * 1000 - timestampMS) * speed : 0
        return min(max(0, durationMS), max(0, positionMS + elapsed))
    }

    mutating func apply(_ data: Data, now: Date = Date()) throws -> String? {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { throw SmalltifyError("播放器状态格式无效。") }
        if type == "error" { return "Soloist 未能执行操作，请检查配对状态或重新启动播放器。" }
        if type == "command_result" { return nil }
        if type == "auth_state" {
            loggedIn = event["logged_in"] as? Bool ?? false
            active = event["is_active"] as? Bool ?? false
            if !loggedIn { self = Self() }
        }
        if type == "playback_state" || type == "device_changed" {
            if let active = event["is_active"] as? Bool { self.active = active }
        }
        if type == "playback_state" || type == "track_changed" {
            // Missing / empty entity clears the previous track instead of leaving stale UI.
            let entity = event["item"] as? [String: Any] ?? [:]
            let decorations = entity["decorations"] as? [String: Any] ?? [:]
            let visual = decorations["visual_identity"] as? [String: Any]
            let covers = visual?["cover"] as? [[String: Any]] ?? []
            coverURL = covers.compactMap { cover -> URL? in
                guard let text = cover["url"] as? String, let url = URL(string: text),
                      url.scheme == "https", url.user == nil, url.password == nil else { return nil }
                return url
            }.first
            album = nil
            releaseYear = nil
            if let parent = (decorations["parent"] as? [String: Any])?["entity"] as? [String: Any],
               let parentURI = parent["uri"] as? String, parentURI.hasPrefix("spotify:album:"), CatalogItem.validURI(parentURI),
               let info = parent["decorations"] as? [String: Any],
               let name = (info["identity"] as? [String: Any])?["name"] as? String {
                album = CatalogAlbumRef(uri: parentURI, name: name)
            }
            uri = entity["uri"] as? String ?? ""
            title = (decorations["identity"] as? [String: Any])?["name"] as? String ?? "尚未播放"
            let creators = decorations["creators"] as? [[String: Any]] ?? []
            var seenArtists = Set<String>()
            artists = creators.compactMap { $0["entity"] as? [String: Any] }
                .compactMap(CatalogArtist.fromSoloist).filter { seenArtists.insert($0.uri).inserted }
            artist = creators.compactMap {
                let creator = $0["entity"] as? [String: Any]
                let info = creator?["decorations"] as? [String: Any]
                return (info?["identity"] as? [String: Any])?["name"] as? String
            }.joined(separator: " · ")
            durationMS = max(0, (decorations["playback"] as? [String: Any])?["duration_ms"] as? Double ?? 0)
            positionMS = 0
            timestampMS = now.timeIntervalSince1970 * 1000
        }
        if type == "playback_state" || type == "playback_changed" {
            positionMS = position(at: now)
            timestampMS = now.timeIntervalSince1970 * 1000
            status = event["status"] as? String ?? "idle"
            speed = status == "playing" ? 1 : 0
        }
        if let position = event["position"] as? [String: Any] {
            positionMS = max(0, position["position_ms"] as? Double ?? 0)
            timestampMS = position["timestamp_ms"] as? Double ?? now.timeIntervalSince1970 * 1000
            speed = max(0, position["speed"] as? Double ?? 0)
        }
        if let volume = event["volume"] as? Double { self.volume = min(100, max(0, volume)) }
        if let options = event["options"] as? [String: Any] {
            shuffle = options["shuffle"] as? Bool ?? false
            repeatMode = options["repeat"] as? String ?? "off"
        }
        return nil
    }
}
