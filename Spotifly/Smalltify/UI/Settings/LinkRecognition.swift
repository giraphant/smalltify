import Foundation
import Observation

nonisolated struct SpotifyLink: Equatable, Sendable {
    let uri: String
    let kind: String
    let id: String

    init?(_ input: String) {
        guard let uri = SmalltifyModel.spotifyURI(from: input) else { return nil }
        let parts = uri.split(separator: ":")
        self.uri = uri
        kind = String(parts[1])
        id = String(parts[2])
    }

    var url: URL {
        get throws {
            try OfficialWebAPI.apiURL(path: "/\(kind)s/\(id)", query: [.init(name: "market", value: "from_token")])
        }
    }

    var label: String {
        switch kind {
        case "track": "歌曲"
        case "album": "专辑"
        case "playlist": "歌单"
        default: "播客单集"
        }
    }

    func preview(_ data: Data) throws -> LinkPreview {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = CatalogItem.parse(object), item.kind == kind else {
            throw SmalltifyError("无法读取这个链接的内容。")
        }
        let show = object["show"] as? [String: Any]
        let detail = kind == "episode" ? (show?["name"] as? String ?? "") : item.subtitle
        return LinkPreview(item: item, line: [label, item.name, detail].filter { !$0.isEmpty }.joined(separator: " · "))
    }
}

nonisolated struct LinkPreview: Sendable, Equatable {
    let item: CatalogItem
    let line: String
}

@MainActor @Observable final class LinkRecognition {
    private(set) var input = ""
    private(set) var preview: LinkPreview?
    private(set) var loading = false
    private(set) var error: String?
    private var generation = UUID()

    var link: SpotifyLink? { SpotifyLink(input) }
    var isInvalid: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && link == nil }

    func update(_ input: String) {
        guard input != self.input else { return }
        self.input = input
        generation = UUID()
        preview = nil
        error = nil
        loading = false
    }

    func load(api: OfficialWebAPI, report: (Error) -> Void) async {
        await load(fetch: { try await api.get($0) }, report: report)
    }

    func load(fetch: @Sendable (URL) async throws -> Data, report: (Error) -> Void) async {
        guard !Task.isCancelled, let link else { return }
        // SwiftUI can restart the task for the same input; cleanup belongs to this run.
        let run = UUID()
        generation = run
        loading = true
        error = nil
        defer { if generation == run { loading = false } }
        do {
            #if DEBUG
                if DebugFixtures.isEnabled, DebugFixtures.environment["SMALLTIFY_INPUT"] == "loading" {
                    try await Task.sleep(for: .seconds(10))
                }
            #endif
            try await Task.sleep(for: .milliseconds(250))
            let data = try await fetch(link.url)
            try Task.checkCancellation()
            guard generation == run else { return }
            preview = try link.preview(data)
        } catch {
            guard generation == run, !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = error.localizedDescription
            report(error)
        }
    }
}
