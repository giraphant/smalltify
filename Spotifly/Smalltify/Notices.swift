import Foundation
import Observation

/// The window's two ways of telling the user something: one error banner at the top of the
/// content, and one toast above the player bar that goes away by itself.
@MainActor @Observable final class Notices {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        let perform: @MainActor () -> Void
    }

    struct Banner: Identifiable {
        enum Tone { case error, warning }
        let id = UUID()
        let message: String
        var tone = Tone.error
        var actions: [Action] = []
    }

    private(set) var banner: Banner?
    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?
    static let toastDuration = Duration.milliseconds(2500)

    /// Replaces the banner showing, if any: there is only ever one.
    func show(_ banner: Banner) {
        self.banner = banner
    }

    func dismissBanner() {
        banner = nil
    }

    /// Shows a short confirmation such as「已加入队列」, replacing the one showing.
    func toast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: Self.toastDuration)
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}
