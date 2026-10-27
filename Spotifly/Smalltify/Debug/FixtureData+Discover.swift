#if DEBUG
    import Foundation

    nonisolated extension FixtureData {
        /// Fixture responses for search and the home page, checked before the shared ones in `respond`.
        /// Owned by W3 搜索与首页; return nil for anything not handled here.
        static func respondDiscover(_ request: FixtureRequest) -> (Int, Data, String)? {
            nil
        }
    }
#endif
