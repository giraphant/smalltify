import Foundation

nonisolated enum Formatting {
    /// `3:58`, or `1:02:03` past an hour.
    static func duration(milliseconds: Double) -> String {
        let seconds = max(0, Int(milliseconds / 1000))
        let (hours, minutes, rest) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        let tail = String(format: "%02d", rest)
        return hours > 0 ? "\(hours):\(String(format: "%02d", minutes)):\(tail)" : "\(minutes):\(tail)"
    }

    /// `39 分钟`, or `1 小时 12 分钟`, for a list's total length.
    static func totalDuration(milliseconds: Double) -> String {
        let minutes = max(0, Int((milliseconds / 60000).rounded()))
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }

    /// `今天`, `3 天前`, `2 周前` within four weeks, else `2026/9/18`.
    static func added(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "今天"
        case 1 ..< 7: return "\(days) 天前"
        case 7 ..< 28: return "\(days / 7) 周前"
        default:
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return "\(parts.year ?? 0)/\(parts.month ?? 0)/\(parts.day ?? 0)"
        }
    }

    /// The artist names of an item, joined as the design lists them.
    static func artistNames(_ artists: [CatalogArtist], fallback: String) -> String {
        artists.isEmpty ? fallback : artists.map(\.name).joined(separator: "、")
    }
}
