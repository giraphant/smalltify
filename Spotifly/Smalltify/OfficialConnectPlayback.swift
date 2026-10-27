import Foundation

nonisolated struct OfficialConnectPlayback: Sendable {
    let device: OfficialConnectDevice
    let snapshot: SoloistSnapshot

    static func parse(_ data: Data, now: Date = Date()) throws -> Self? {
        if data.isEmpty { return nil }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceObject = object["device"] as? [String: Any] else {
            throw SmalltifyError("Spotify 播放状态格式无效。")
        }
        let device = OfficialConnectDevice.parse(deviceObject)
        var snapshot = SoloistSnapshot()
        snapshot.loggedIn = true
        snapshot.active = device.active
        snapshot.status = object["is_playing"] as? Bool == true ? "playing" : "paused"
        if let itemObject = object["item"] as? [String: Any], let item = CatalogItem.parse(itemObject) {
            snapshot.uri = item.uri
            snapshot.title = item.name
            snapshot.artist = item.subtitle
            snapshot.artists = item.artists
            snapshot.coverURL = item.imageURL
            snapshot.durationMS = item.durationMS
        }
        snapshot.positionMS = max(0, object["progress_ms"] as? Double ?? 0)
        // Spotify's timestamp is the last state change, not the sample time of progress_ms.
        snapshot.timestampMS = now.timeIntervalSince1970 * 1000
        snapshot.speed = snapshot.status == "playing" ? 1 : 0
        snapshot.volume = min(100, max(0, device.volume))
        snapshot.shuffle = object["shuffle_state"] as? Bool ?? false
        snapshot.repeatMode = object["repeat_state"] as? String ?? "off"
        return Self(device: device, snapshot: snapshot)
    }
}
