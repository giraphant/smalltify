#if DEBUG
    import Foundation

    nonisolated extension FixtureData {
        /// Fixture responses for settings, link recognition and shortcuts, checked before the shared ones in `respond`.
        /// Owned by W5 设置与输入; return nil for anything not handled here.
        static func respondSettings(_ request: FixtureRequest) -> (Int, Data, String)? {
            nil
        }
    }
#endif
