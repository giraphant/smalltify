import AppKit
import SwiftUI
import Synchronization

/// Square or round artwork with a glyph placeholder: albums, playlists and tracks are rounded
/// squares, artists are circles.
struct CoverArt: View {
    enum Shape {
        case rounded
        case circle
    }

    let url: URL?
    let size: CGFloat
    var shape = Shape.rounded
    var symbol = "music.note"

    @State private var loaded: (url: URL, image: NSImage)?

    var body: some View {
        Group {
            if let image = currentImage {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(clip)
        .accessibilityHidden(true)
        .task(id: url) {
            // Set even when the cache already had it: the body read the cache before it filled,
            // and reading it is not observed.
            guard let url, let image = await ArtworkLoader.shared.image(for: url) else { return }
            loaded = (url, image)
        }
    }

    /// The image for the current url: loaded by this view, or already in the shared cache.
    private var currentImage: NSImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return ArtworkLoader.shared.cached(url)
    }

    private var placeholder: some View {
        Image(systemName: shape == .circle ? "person.fill" : symbol)
            .font(.system(size: size * 0.36))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary)
    }

    private var clip: AnyShape {
        switch shape {
        case .circle: AnyShape(Circle())
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: Self.radius(for: size), style: .continuous))
        }
    }

    /// The design's radii: 5 for list thumbnails, 8 for cards, 10 for headers.
    static func radius(for size: CGFloat) -> CGFloat {
        size <= 48 ? 5 : size <= 160 ? 8 : 10
    }
}

extension CoverArt {
    /// The item's artwork at a size, picking an image large enough for the display.
    init(item: CatalogItem, size: CGFloat, scale: CGFloat = 2) {
        self.init(url: item.imageURL(minPixels: size * scale), size: size,
                  shape: item.kind == "artist" ? .circle : .rounded,
                  symbol: item.kind == "playlist" ? "music.note.list" : item.kind == "album" ? "square.stack" : "music.note")
    }

    init(artist: CatalogArtist, size: CGFloat, scale: CGFloat = 2) {
        self.init(url: artist.imageURL(minPixels: size * scale), size: size, shape: .circle)
    }
}

/// Loads artwork once per url and keeps it in memory, so scrolling a list back does not load
/// its covers again. Responses also land in `URLCache.shared`, which keeps them across launches.
nonisolated final class ArtworkLoader: Sendable {
    static let shared = ArtworkLoader()

    // NSCache is thread-safe; it is just not marked Sendable.
    nonisolated(unsafe) private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    private let inFlight = Mutex<[URL: Task<NSImage?, Never>]>([:])

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// The image at `url`, from memory, an ongoing load of it, or a new one; nil when it fails.
    func image(for url: URL) async -> NSImage? {
        if let image = cached(url) { return image }
        let task = inFlight.withLock { tasks in
            if let task = tasks[url] { return task }
            let task = Task<NSImage?, Never> {
                // One retry: CDNs answer the odd 5xx, and a list should not keep a placeholder for it.
                for attempt in 0 ..< 2 {
                    if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
                    if let (data, response) = try? await URLSession.shared.data(from: url),
                       (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) {
                        return image
                    }
                }
                return nil
            }
            tasks[url] = task
            return task
        }
        let image = await task.value
        inFlight.withLock { $0[url] = nil }
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}
