import Foundation

nonisolated struct OfficialConnectDevice: Equatable, Sendable {
    let id: String?
    let name: String
    let type: String
    let active: Bool
    let restricted: Bool
    let supportsVolume: Bool
    let volume: Double
    var selectable: Bool { id?.isEmpty == false && !restricted }
    var symbol: String {
        switch type.lowercased() {
        case "computer": "desktopcomputer"
        case "smartphone": "iphone"
        case "tv": "tv"
        default: "hifispeaker"
        }
    }

    var typeLabel: String {
        switch type.lowercased() {
        case "computer": "电脑"
        case "smartphone": "手机"
        case "tv": "电视"
        default: "音箱"
        }
    }

    var note: String {
        if restricted { return "受限设备：只能在设备本身上操作" }
        if !selectable { return "此设备不支持远程控制" }
        return active ? "正在播放 · \(typeLabel)" : typeLabel
    }

    static func parse(_ object: [String: Any]) -> Self {
        Self(id: object["id"] as? String, name: object["name"] as? String ?? "Spotify 设备",
             type: object["type"] as? String ?? "", active: object["is_active"] as? Bool ?? false,
             restricted: object["is_restricted"] as? Bool ?? false,
             supportsVolume: object["supports_volume"] as? Bool ?? false,
             volume: object["volume_percent"] as? Double ?? 0)
    }
}
