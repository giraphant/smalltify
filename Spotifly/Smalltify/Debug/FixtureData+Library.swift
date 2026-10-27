#if DEBUG
    import Foundation

    nonisolated extension FixtureData {
        /// Fixture responses for liked songs, playlists, albums, followed artists, checked before the shared ones in `respond`.
        /// Owned by W1 文库列表页; return nil for anything not handled here.
        static func respondLibrary(_ request: FixtureRequest) -> (Int, Data, String)? {
            nil
        }
    }
#endif
