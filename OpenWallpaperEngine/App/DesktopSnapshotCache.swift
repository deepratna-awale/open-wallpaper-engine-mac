import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The still pictures OWE sets as each display's desktop picture while a wallpaper plays, so the
/// menu bar's tint (and anything else macOS samples from the desktop picture) follows the
/// wallpaper: a web page's snapshot, or a video's first frame. The picture is only seen when OWE
/// isn't drawing over it, and OWE restores the user's own picture on quit.
///
/// Each display has one small JPEG under a stable name in OWE's own folder
/// (`<Caches>/Open Wallpaper Engine/DesktopSnapshots`), so snapshots can't pile up across launches.
/// The name alternates between two slots, because macOS ignores `setDesktopImageURL` with the URL
/// it already shows; the slot it no longer shows is removed. Full-screen TIFFs (20–60 MB each)
/// written under a per-launch name (`staticWP_<hash>.tiff`) by earlier versions are moved to the
/// Trash.
struct DesktopSnapshotCache {
    /// The longest side a snapshot is stored at: plenty for a tint, a fraction of a display's size.
    static let maxPixelSize = 1024
    static let jpegQuality: CGFloat = 0.8
    static let legacyPrefix = "staticWP_"
    /// Set to `1` to let an isolated copy change the desktop picture anyway (a test of that path).
    static let allowInIsolationKey = "OWE_ALLOW_DESKTOP_PICTURE"

    /// Whether this process may change the system desktop picture. The picture belongs to the
    /// user's session, not to OWE's state, so an isolated copy (`AppStorageLocation`) never sets,
    /// saves or restores it unless `allowInIsolationKey` asks for it: otherwise a test run leaves
    /// its snapshots as the desktop picture, and the user's own copy saves them as "the user's".
    static func allowsDesktopPicture(isIsolated: Bool, environment: [String: String]) -> Bool {
        !isIsolated || environment[allowInIsolationKey] == "1"
    }

    static let mayChangeDesktopPicture = allowsDesktopPicture(
        isIsolated: AppStorageLocation.current.isIsolated, environment: ProcessInfo.processInfo.environment)

    /// Where snapshots are written; only files in it are ever removed.
    let directory: URL
    /// The folder earlier versions wrote `staticWP_*.tiff` into.
    let legacyDirectory: URL

    static var current: DesktopSnapshotCache {
        DesktopSnapshotCache(cachesDirectory: AppStorageLocation.current.cachesDirectory)
    }

    init(cachesDirectory: URL) {
        directory = cachesDirectory.appending(path: "Open Wallpaper Engine/DesktopSnapshots", directoryHint: .isDirectory)
        legacyDirectory = cachesDirectory
    }

    // MARK: Names

    /// A display's snapshot in `slot` (0 or 1).
    func url(display: CGDirectDisplayID, slot: Int) -> URL {
        directory.appending(path: "desktop-\(display)-\(slot == 0 ? "a" : "b").jpg", directoryHint: .notDirectory)
    }

    /// The slot to write next: the one the display doesn't show now.
    func nextSlot(display: CGDirectDisplayID, showing: URL?) -> Int {
        guard let showing else { return 0 }
        return showing.standardizedFileURL == url(display: display, slot: 0).standardizedFileURL ? 1 : 0
    }

    /// Whether `url` is a picture OWE set, not the user's own (current or legacy name).
    /// Any copy's snapshot counts, an isolated copy's included, so one is never saved as the
    /// user's picture.
    func isSnapshot(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        return parent.path == directory.standardizedFileURL.path
            || Self.isAnySnapshotFolder(parent)
            || url.lastPathComponent.hasPrefix(Self.legacyPrefix)
    }

    /// `<Caches>[/Open Wallpaper Engine (isolated <tag>)]/Open Wallpaper Engine/DesktopSnapshots`.
    private static func isAnySnapshotFolder(_ folder: URL) -> Bool {
        let components = folder.pathComponents
        return components.count >= 2 && components.suffix(2) == ["Open Wallpaper Engine", "DesktopSnapshots"]
    }

    /// The display's snapshot on disk, the newer slot if both exist.
    func existingURL(display: CGDirectDisplayID) -> URL? {
        let candidates = [url(display: display, slot: 0), url(display: display, slot: 1)].compactMap { url -> (URL, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate else { return nil }
            return (url, date)
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    // MARK: Writing

    /// `image` downscaled to `maxPixelSize` on its longest side, as JPEG; nil if it can't be encoded.
    static func jpegData(_ image: CGImage) -> Data? {
        let longest = max(image.width, image.height)
        let scale = longest > maxPixelSize ? Double(maxPixelSize) / Double(longest) : 1
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, scaled,
                                   [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Writes `jpeg` as the display's next slot and returns its URL.
    func write(_ jpeg: Data, display: CGDirectDisplayID, showing: URL?) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = url(display: display, slot: nextSlot(display: display, showing: showing))
        try jpeg.write(to: target, options: .atomic)
        return target
    }

    /// Removes the display's other slot once `url` is shown.
    func removeOtherSlot(than url: URL, display: CGDirectDisplayID) {
        for slot in 0...1 {
            let other = self.url(display: display, slot: slot)
            guard other.standardizedFileURL != url.standardizedFileURL else { continue }
            try? FileManager.default.removeItem(at: other)
        }
    }

    // MARK: Cleanup

    /// Removes every snapshot in OWE's own folder (the user's pictures are back on quit).
    func removeAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                       options: .skipsHiddenFiles) else { return }
        for file in files where (file.pathExtension == "jpg" && file.lastPathComponent.hasPrefix("desktop-"))
            || file.lastPathComponent.hasPrefix(LockScreenPicture.prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The `staticWP_*.tiff` files earlier versions left in the Caches folder.
    func legacySnapshots() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil,
                                                                  options: .skipsHiddenFiles)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(Self.legacyPrefix) && $0.pathExtension == "tiff" }
    }

    /// Moves the legacy snapshots to the Trash (they sit in the shared Caches folder, so they are
    /// never deleted outright). `dispose` is the move (tests pass their own).
    func trashLegacySnapshots(dispose: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        for url in legacySnapshots() {
            do { try dispose(url) } catch {
                OWELog.error(.app, "Moving an old desktop snapshot to the Trash failed: \(error)")
            }
        }
    }

    // MARK: Applying

    /// The display id of `screen`.
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static let queue = DispatchQueue(label: "OWE.DesktopSnapshotCache", qos: .utility)
    @MainActor private static var sweptLegacy = false

    /// Encodes `image` off the main thread, writes it as each screen's snapshot and sets it as
    /// that screen's desktop picture.
    @MainActor
    static func setDesktopPicture(_ image: CGImage, for screens: [NSScreen]) {
        guard mayChangeDesktopPicture else { return }
        let cache = DesktopSnapshotCache.current
        if !sweptLegacy {
            sweptLegacy = true
            queue.async { cache.trashLegacySnapshots() }
        }
        let targets = screens.compactMap { screen -> (CGDirectDisplayID, URL?)? in
            guard let id = displayID(screen) else { return nil }
            return (id, NSWorkspace.shared.desktopImageURL(for: screen))
        }
        guard !targets.isEmpty else { return }
        let strips = DesktopPictureTheming.strips()
        queue.async {
            guard let jpeg = jpegData(image) else {
                OWELog.error(.app, "Desktop snapshot could not be encoded")
                return
            }
            var written: [(CGDirectDisplayID, URL)] = []
            for (id, showing) in targets {
                do {
                    let url = try cache.write(jpeg, display: id, showing: showing)
                    DesktopPictureTheming.draw(strips, into: url, display: id)
                    written.append((id, url))
                } catch {
                    OWELog.error(.app, "Writing the desktop snapshot failed: \(error)")
                }
            }
            DispatchQueue.main.async {
                for (id, url) in written {
                    guard let screen = NSScreen.screens.first(where: { displayID($0) == id }) else { continue }
                    do {
                        try NSWorkspace.shared.setDesktopImageURL(url, for: screen)
                        cache.removeOtherSlot(than: url, display: id)
                    } catch {
                        OWELog.error(.app, "Setting the desktop picture failed: \(error)")
                    }
                }
            }
        }
    }

    /// Shows each screen's existing snapshot again (the menu bar tint was turned back on).
    @MainActor
    static func restoreDesktopPicture(for screens: [NSScreen]) {
        guard mayChangeDesktopPicture else { return }
        let cache = DesktopSnapshotCache.current
        for screen in screens {
            guard let id = displayID(screen), let url = cache.existingURL(display: id) else { continue }
            do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen) } catch {
                OWELog.error(.settings, "Menu bar tint wallpaper update failed: \(error)")
            }
        }
    }
}
