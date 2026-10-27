#if DEBUG
    import Foundation

    extension FixtureData {
        /// Puts the fixture model in the state its environment asks for, after the shared setup.
        /// Owned by W5 设置与输入; document the variables it reads here.
        @MainActor static func configureSettings(_ model: SmalltifyModel) {}
    }
#endif
