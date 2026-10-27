import Foundation

/// Small, account-scoped memory cache shared by browsing and playback prefetch.
actor ArtistCatalogLoader {
    private struct Entry {
        let data: Data
        let expires: Date
    }

    private let api: OfficialWebAPI
    private var cache: [URL: Entry] = [:]
    private var inFlight: [URL: Task<Data, Error>] = [:]
    private var prefetched: [String: Date] = [:]
    private var epoch = UUID()

    init(api: OfficialWebAPI) { self.api = api }

    nonisolated static func albumsURL(artistID: String, group: String = "album,single") throws -> URL {
        guard CatalogArtist.validURI("spotify:artist:" + artistID),
              ["album,single", "album", "single", "appears_on"].contains(group) else {
            throw SmalltifyError("无效的歌手或作品分类。")
        }
        // This endpoint allows at most 10, unlike library and album-track endpoints.
        return try OfficialWebAPI.apiURL(path: "/artists/\(artistID)/albums", query: [
            .init(name: "include_groups", value: group), .init(name: "limit", value: "10"),
        ])
    }

    func clear() {
        epoch = UUID()
        for task in inFlight.values { task.cancel() }
        inFlight = [:]
        cache = [:]
        prefetched = [:]
    }

    private func get(_ url: URL, refresh: Bool = false) async throws -> Data {
        if !refresh, let entry = cache[url], entry.expires > Date() { return entry.data }
        let generation = epoch
        if let task = inFlight[url] {
            let data = try await task.value
            guard generation == epoch else { throw CancellationError() }
            return data
        }
        let task = Task { try await api.get(url) }
        inFlight[url] = task
        defer { if epoch == generation { inFlight[url] = nil } }
        let data = try await task.value
        guard generation == epoch else { throw CancellationError() }
        cache = cache.filter { $0.value.expires > Date() }
        if cache.count >= 120, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key {
            cache[oldest] = nil
        }
        cache[url] = Entry(data: data, expires: Date().addingTimeInterval(300))
        return data
    }

    func albums(from firstURL: URL, refresh: Bool = false, background: Bool = false) async throws -> CatalogPage {
        var items: [CatalogItem] = []
        var next: URL? = firstURL
        var visited = Set<URL>()
        let generation = epoch
        for index in 0 ..< 3 {
            try Task.checkCancellation()
            guard generation == epoch else { throw CancellationError() }
            guard let url = next, url.path == firstURL.path, visited.insert(url).inserted else { break }
            do {
                let data = try await get(url, refresh: refresh)
                try Task.checkCancellation()
                guard generation == epoch else { throw CancellationError() }
                let page = try CatalogPage.parse(data)
                items.append(contentsOf: page.items)
                next = page.next
            } catch {
                if index == 0 || Task.isCancelled || generation != epoch { throw error }
                // Keep the successful prefix and its retry URL if a later page fails.
                break
            }
            if background, next != nil, index < 2 { try await Task.sleep(for: .milliseconds(300)) }
        }
        return CatalogPage(items: items, next: next)
    }

    func profile(artistID: String, refresh: Bool = false) async -> CatalogArtist? {
        do {
            let url = try OfficialWebAPI.apiURL(path: "/artists/\(artistID)")
            let data = try await get(url, refresh: refresh)
            try Task.checkCancellation()
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return CatalogArtist.parse(object)
        } catch { return nil }
    }

    func prefetch(_ artist: CatalogArtist) async {
        guard prefetched[artist.uri, default: .distantPast] <= Date() else { return }
        // Failed or cancelled work gets a short cooldown too; skipping tracks must not hammer the API.
        prefetched = prefetched.filter { $0.value > Date() }
        prefetched[artist.uri] = Date().addingTimeInterval(60)
        let generation = epoch
        do {
            let url = try Self.albumsURL(artistID: artist.spotifyID)
            _ = try await albums(from: url, background: true)
            try Task.checkCancellation()
            _ = await profile(artistID: artist.spotifyID)
            guard generation == epoch, !Task.isCancelled else { return }
            prefetched[artist.uri] = Date().addingTimeInterval(300)
        } catch {
            // Background metadata errors never interrupt playback or replace the visible page.
        }
    }
}
