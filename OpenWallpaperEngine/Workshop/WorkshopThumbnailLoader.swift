import AppKit
import ImageIO
import os

/// The Workshop cards' preview images, downloaded once and decoded at card size: paging back and
/// forth shows them from memory instead of downloading and decoding full-size previews again.
/// Owned by `WorkshopViewModel`, so the Workshop and Discover tabs share one cache.
///
/// The cache keeps the most recently used thumbnails up to `memoryLimit` bytes and empties only
/// under critical memory pressure (a thumbnail costs a download and a decode to rebuild). It is
/// not an `NSCache`, which may drop entries whenever the system wants memory, so a card shown a
/// moment ago could flash its placeholder and download again.
///
/// A preview is downloaded once however many ask for it: loads of one URL share a download, and
/// the session keeps the files on disk (`previewSession`), so a thumbnail dropped from memory, or
/// a page preloaded before it is shown (`preload`), is decoded again without another download.
///
/// `@unchecked Sendable`: the cache is behind a lock, and nothing else is mutable.
final class WorkshopThumbnailLoader: @unchecked Sendable {
    private struct Entry {
        let image: NSImage
        let cost: Int
        var lastUse: UInt64
    }

    private struct Cache {
        var entries: [URL: Entry] = [:]
        var totalCost = 0
        var clock: UInt64 = 0
        /// The downloads under way, so a second request for a URL waits for the first.
        var downloads: [URL: Task<Data?, Never>] = [:]
    }

    /// Previews are around 1 MB each. `URLSession.shared`'s cache keeps no response over 5 % of its
    /// small capacity, so through it every preview was downloaded again each time it was wanted.
    /// This one holds them on disk (up to 25 MB each), in the app's caches folder.
    static let previewSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024,
            directory: AppStorageLocation.current.appCachesDirectory.appending(path: "WorkshopPreviews"))
        return URLSession(configuration: configuration)
    }()

    private let cache = OSAllocatedUnfairLock(initialState: Cache())
    private let session: URLSession
    private let memoryLimit: Int
    private var memoryPressure: SceneMemoryPressure?
    /// The longer side of a decoded thumbnail, in pixels: a card at its largest on a Retina display.
    let maxPixelSize: Int

    init(session: URLSession = WorkshopThumbnailLoader.previewSession, maxPixelSize: Int = 640, memoryLimit: Int = 96 * 1024 * 1024) {
        self.session = session
        self.maxPixelSize = maxPixelSize
        self.memoryLimit = memoryLimit
        memoryPressure = SceneMemoryPressure(queue: .global(qos: .utility)) { [weak self] level in
            if level == .critical { self?.removeAll() }
        }
    }

    /// The thumbnail already in memory, for drawing without waiting.
    func cachedImage(for url: URL) -> NSImage? {
        cache.withLock { cache in
            guard var entry = cache.entries[url] else { return nil }
            cache.clock += 1
            entry.lastUse = cache.clock
            cache.entries[url] = entry
            return entry.image
        }
    }

    /// Empties the cache. Downloads under way still finish.
    func removeAll() {
        cache.withLock { cache in
            cache.entries = [:]
            cache.totalCost = 0
        }
    }

    /// Downloads the previews not in memory, without decoding them: a page the user may turn to
    /// next then shows from the session's disk cache. Decoding them here would push the shown
    /// page's thumbnails out of memory.
    func preload(_ urls: [URL]) {
        for url in urls where !cache.withLock({ $0.entries[url] != nil }) {
            _ = download(url)
        }
    }

    /// The download of the file at `url`, started now unless one is already under way, which is
    /// then shared. Its value is nil (logged) when the file can't be downloaded.
    private func download(_ url: URL) -> Task<Data?, Never> {
        cache.withLock { cache -> Task<Data?, Never> in
            if let running = cache.downloads[url] { return running }
            let task = Task.detached(priority: .utility) { [session, weak self] () -> Data? in
                // Waits for the lock held here, so it runs after the task is registered.
                defer { self?.cache.withLock { $0.downloads[url] = nil } }
                do {
                    let (data, response) = try await session.data(from: url)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        OWELog.debug(.workshop, "Workshop preview \(url.absoluteString) answered HTTP \(http.statusCode)")
                        return nil
                    }
                    return data
                } catch {
                    OWELog.debug(.workshop, "Workshop preview \(url.absoluteString) didn't load: \(error.localizedDescription)")
                    return nil
                }
            }
            cache.downloads[url] = task
            return task
        }
    }

    /// Keeps `image`, dropping the least recently used thumbnails while the total is over the limit.
    private func store(_ image: NSImage, cost: Int, for url: URL) {
        cache.withLock { cache in
            cache.clock += 1
            if let old = cache.entries.updateValue(Entry(image: image, cost: cost, lastUse: cache.clock), forKey: url) {
                cache.totalCost -= old.cost
            }
            cache.totalCost += cost
            while cache.totalCost > memoryLimit, cache.entries.count > 1,
                  let oldest = cache.entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
                cache.entries[oldest.key] = nil
                cache.totalCost -= oldest.value.cost
            }
        }
    }

    /// The thumbnail of the image at `url`; nil (logged) when it can't be downloaded or decoded.
    /// A load the card no longer needs still finishes into the cache.
    func image(for url: URL) async -> NSImage? {
        if let cached = cachedImage(for: url) { return cached }
        guard let data = await download(url).value else { return nil }
        let task = Task.detached(priority: .utility) { [maxPixelSize] in
            Self.downsample(data, maxPixelSize: maxPixelSize)
        }
        guard let cgImage = await task.value else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        store(image, cost: cgImage.bytesPerRow * cgImage.height, for: url)
        return image
    }

    /// `data` decoded with its longer side at most `maxPixelSize` pixels, or nil when it isn't an image.
    static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
