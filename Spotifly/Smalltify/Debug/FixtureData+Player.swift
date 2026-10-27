#if DEBUG
    import Foundation

    nonisolated extension FixtureData {
        /// Fixture responses for the player bar, queue, devices and mini player, checked before the shared ones in `respond`.
        /// Owned by W4 播放器; return nil for anything not handled here.
        static func respondPlayer(_ request: FixtureRequest) -> (Int, Data, String)? {
            nil
        }
    }
#endif
