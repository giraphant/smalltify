import Foundation

nonisolated struct SavedPlaylist: Codable, Identifiable, Equatable {
    var id: String { uri }
    let uri: String
    var name: String
}
