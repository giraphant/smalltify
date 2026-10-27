#if DEBUG
    import Foundation

    extension FixtureData {
        /// Puts the fixture model in the state its environment asks for, after the shared setup.
        /// Owned by W4 播放器; document the variables it reads here.
        @MainActor static func configurePlayer(_ model: SmalltifyModel) {}
    }
#endif
