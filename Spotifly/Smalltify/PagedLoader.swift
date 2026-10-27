import Foundation
import Observation

/// Something a page loads that ⌘R can load again.
@MainActor protocol Refreshable: AnyObject {
    func refresh()
}

/// One paged Spotify list: its first page on demand, more pages on request, and its state.
///
/// Loads run in unstructured tasks, so a page torn down by navigation does not cancel them;
/// `PageStore` keeps the loader, and going back shows what arrived.
@MainActor @Observable final class PagedLoader: Refreshable {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var items: [CatalogItem] = []
    private(set) var next: URL?
    /// What Spotify says the whole list holds, which can exceed what can be loaded.
    private(set) var total: Int?
    private(set) var phase = Phase.idle
    private(set) var loadingMore = false
    private(set) var loadMoreError: String?

    let firstURL: URL
    private let fetch: @Sendable (URL, Bool) async throws -> CatalogPage
    private let report: @MainActor (Error) -> Void
    private var generation = 0

    /// - Parameters:
    ///   - fetch: loads one page; the flag asks it to bypass any cache.
    ///   - report: hears every failure, so the model can offer reauthorization or a wait.
    init(firstURL: URL, report: @escaping @MainActor (Error) -> Void = { _ in },
         fetch: @escaping @Sendable (URL, Bool) async throws -> CatalogPage) {
        self.firstURL = firstURL
        self.report = report
        self.fetch = fetch
    }

    /// A plain Web API list; `searchType` unwraps a search response's `<type>s` object.
    convenience init(api: OfficialWebAPI, url: URL, searchType: String? = nil,
                     report: @escaping @MainActor (Error) -> Void = { _ in }) {
        self.init(firstURL: url, report: report) { url, _ in
            try CatalogPage.parse(try await api.get(url), searchType: searchType)
        }
    }

    var isLoading: Bool { phase == .loading }
    var failure: String? {
        if case let .failed(message) = phase { return message }
        return nil
    }

    func loadIfNeeded() {
        if phase == .idle { load(refresh: false) }
    }

    func refresh() {
        load(refresh: true)
    }

    func loadMore() {
        guard let next, !loadingMore, phase == .loaded else { return }
        let run = generation
        loadingMore = true
        loadMoreError = nil
        Task {
            defer { if run == generation { loadingMore = false } }
            do {
                let page = try await fetch(next, false)
                guard run == generation else { return }
                items.append(contentsOf: page.items)
                self.next = page.next
                total = page.total ?? total
            } catch {
                guard run == generation, !(error is CancellationError) else { return }
                loadMoreError = error.localizedDescription
                report(error)
            }
        }
    }

    private func load(refresh: Bool) {
        generation += 1
        let run = generation
        phase = .loading
        loadingMore = false
        loadMoreError = nil
        Task {
            do {
                let page = try await fetch(firstURL, refresh)
                guard run == generation else { return }
                items = page.items
                next = page.next
                total = page.total
                phase = .loaded
            } catch {
                guard run == generation, !(error is CancellationError) else { return }
                phase = .failed(error.localizedDescription)
                report(error)
            }
        }
    }
}

/// The loaders of recently shown pages, so back and forward show what was already loaded.
///
/// Not observable: pages look a loader up while building their body, and the lookup must not
/// count as a state change.
@MainActor final class PageStore {
    private var entries: [String: AnyObject] = [:]
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int = 60) {
        self.capacity = capacity
    }

    /// The loader stored under `key`, made on first use. Keys start with the page's `Destination.key`.
    func loader<Loader: AnyObject>(_ key: String, make: () -> Loader) -> Loader {
        if let existing = entries[key] as? Loader {
            order.removeAll { $0 == key }
            order.append(key)
            return existing
        }
        let loader = make()
        entries[key] = loader
        order.append(key)
        if order.count > capacity {
            entries[order.removeFirst()] = nil
        }
        return loader
    }

    /// Refreshes every loader of the page whose `Destination.key` this is.
    func refresh(route key: String) {
        for (entryKey, loader) in entries where entryKey == key || entryKey.hasPrefix(key + "/") {
            (loader as? Refreshable)?.refresh()
        }
    }

    func clear() {
        entries = [:]
        order = []
    }
}
