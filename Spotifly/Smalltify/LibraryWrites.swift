import Foundation
import Observation

/// One album's saved state or one artist's follow state, kept with its page across navigation.
@MainActor @Observable final class LibraryWrites: Refreshable {
    private(set) var isSaved: Bool?
    private(set) var checking = false
    private(set) var writing = false
    private(set) var failure: String?
    let uri: String
    private let contains: @Sendable () async throws -> Bool
    private let write: @Sendable (Bool) async throws -> Void
    private let report: (Error) -> Void
    private let toast: (String) -> Void
    private let errorToast: (String) -> Void
    private let changed: () -> Void
    private var generation = 0

    init(uri: String, contains: @escaping @Sendable () async throws -> Bool,
         write: @escaping @Sendable (Bool) async throws -> Void,
         report: @escaping (Error) -> Void = { _ in }, toast: @escaping (String) -> Void = { _ in },
         changed: @escaping () -> Void = {}, errorToast: ((String) -> Void)? = nil) {
        self.uri = uri
        self.contains = contains
        self.write = write
        self.report = report
        self.toast = toast
        self.errorToast = errorToast ?? toast
        self.changed = changed
    }

    convenience init(uri: String, model: SmalltifyModel) {
        self.init(uri: uri, contains: { [api = model.api] in
            let url = try OfficialWebAPI.apiURL(path: "/me/library/contains", query: [.init(name: "uris", value: uri)])
            let values = try JSONDecoder().decode([Bool].self, from: await api.get(url))
            guard values.count == 1, let value = values.first else { throw SmalltifyError("Spotify 收藏状态响应格式无效。") }
            return value
        }, write: { [api = model.api] saved in
            try await api.send(method: saved ? "PUT" : "DELETE", path: "/me/library",
                               query: [.init(name: "uris", value: uri)])
        }, report: { [weak model] in model?.report($0) }, toast: { [weak model] in model?.notices.toast($0) },
        changed: { [weak model] in
            model?.pages.refresh(route: uri.hasPrefix("spotify:artist:") ? Destination.artists.key : Destination.albums.key)
        }, errorToast: { [weak model] in model?.notices.toast($0, isError: true) })
    }

    func loadIfNeeded() {
        if isSaved == nil, failure == nil { refresh() }
    }

    func refresh() {
        guard !checking, !writing else { return }
        generation += 1
        let run = generation
        checking = true
        failure = nil
        Task {
            defer { if run == generation { checking = false } }
            do {
                let saved = try await contains()
                guard run == generation else { return }
                isSaved = saved
            } catch {
                guard run == generation else { return }
                failure = error.localizedDescription
                report(error)
                errorToast(error.localizedDescription)
            }
        }
    }

    func toggle() async {
        guard let previous = isSaved, !writing, !checking else { return }
        writing = true
        isSaved = !previous
        defer { writing = false }
        do {
            try await write(!previous)
            let artist = uri.hasPrefix("spotify:artist:")
            toast(artist ? (previous ? "已取消关注" : "已关注") : (previous ? "已移出收藏" : "已收藏专辑"))
            changed()
        } catch {
            isSaved = previous
            report(error)
            errorToast(error.localizedDescription)
        }
    }
}
