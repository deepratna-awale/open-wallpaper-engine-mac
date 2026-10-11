import Foundation
import IOSurface

/// A frame for a view: the surface the app drew it into and the rect of it the view shows.
struct LiveFrame {
    let surface: IOSurface
    /// The rect of the frame to show; nil for the whole frame.
    let crop: ScreenSaverManifest.Crop?
    let stamp: ScreenSaverLiveStamp
    /// The rate frames come at, per second.
    let frameRate: Int
}

/// What a saver process knows of the app's live frames: the rings (the manifest and their
/// surfaces) and each ring's newest stamp. Its transport (`GlobalSurfaceFrameSource`, or the
/// extension's XPC source) fills it; every view of the process reads it. Thread-safe: XPC
/// delivers on its own queue.
final class LiveFrameStore: @unchecked Sendable { // `lock` owns every field.
    private let lock = NSLock()
    private var manifest = ScreenSaverLiveManifest()
    private var surfaces: [Int: [IOSurface]] = [:]
    private var stamps: [Int: ScreenSaverLiveStamp] = [:]

    /// New rings: stamps of the old ones are dropped.
    func use(_ manifest: ScreenSaverLiveManifest, surfaces: [Int: [IOSurface]]) {
        lock.withLock {
            self.manifest = manifest
            self.surfaces = surfaces
            stamps = [:]
        }
    }

    var current: ScreenSaverLiveManifest { lock.withLock { manifest } }

    /// A ring's newest stamp; ignored when it is of other rings or older.
    func show(ring: Int, stamp: ScreenSaverLiveStamp) {
        lock.withLock {
            guard stamp.generation == ScreenSaverLiveStamp.generation(manifest.generation),
                  stamp.isNewer(than: stamps[ring]) else { return }
            stamps[ring] = stamp
        }
    }

    /// The newest frame for a view on `display` of `pixels`; nil while there is none.
    func newestFrame(display: String?, pixels: (width: Int, height: Int)) -> LiveFrame? {
        lock.withLock {
            guard manifest.isLive, let entry = manifest.entry(forDisplay: display, pixels: pixels),
                  let stamp = stamps[entry.ring.id], let ring = surfaces[entry.ring.id],
                  Int(stamp.slot) < ring.count else { return nil }
            return LiveFrame(surface: ring[Int(stamp.slot)], crop: entry.display.crop, stamp: stamp,
                             frameRate: manifest.frameRate)
        }
    }
}
