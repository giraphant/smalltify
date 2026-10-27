#if DEBUG
    import Foundation

    nonisolated extension FixtureData {
        /// Fixture responses for album, playlist and artist pages, saving and following, checked before the shared ones in `respond`.
        /// Owned by W2 详情页; return nil for anything not handled here.
        static func respondDetail(_ request: FixtureRequest) -> (Int, Data, String)? {
            nil
        }
    }
#endif
