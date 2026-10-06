import AppKit
import ImageIO

/// The Workshop cards' preview images, downloaded once and decoded at card size: paging back and
/// forth shows them from memory instead of downloading and decoding full-size previews again.
/// Owned by `WorkshopViewModel`, so the Workshop and Discover tabs share one cache.
///
/// `@unchecked Sendable`: the cache is an `NSCache`, which is thread-safe, and nothing else is
/// mutable.
final class WorkshopThumbnailLoader: @unchecked Sendable {
    private let cache = NSCache<NSURL, NSImage>()
    private let session: URLSession
    /// The longer side of a decoded thumbnail, in pixels: a card at its largest on a Retina display.
    let maxPixelSize: Int

    init(session: URLSession = .shared, maxPixelSize: Int = 640, memoryLimit: Int = 96 * 1024 * 1024) {
        self.session = session
        self.maxPixelSize = maxPixelSize
        cache.totalCostLimit = memoryLimit
    }

    /// The thumbnail already in memory, for drawing without waiting.
    func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// The thumbnail of the image at `url`; nil (logged) when it can't be downloaded or decoded.
    /// A load the card no longer needs still finishes into the cache.
    func image(for url: URL) async -> NSImage? {
        if let cached = cachedImage(for: url) { return cached }
        let task = Task.detached(priority: .utility) { [session, maxPixelSize] () -> CGImage? in
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    OWELog.debug(.workshop, "Workshop preview \(url.absoluteString) answered HTTP \(http.statusCode)")
                    return nil
                }
                return Self.downsample(data, maxPixelSize: maxPixelSize)
            } catch {
                OWELog.debug(.workshop, "Workshop preview \(url.absoluteString) didn't load: \(error.localizedDescription)")
                return nil
            }
        }
        guard let cgImage = await task.value else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: url as NSURL, cost: cgImage.bytesPerRow * cgImage.height)
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
