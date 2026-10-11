import Foundation
import IOSurface
import Metal

/// The live screen saver's frames, for both of the savers' transports: each loop of the screen
/// saver's layout gets a ring of `ringSize` global IOSurfaces at its pixel size. A new set of rings
/// (a new generation) is listed in `live.json` (`ScreenSaverLiveManifest`) for the `.saver` and
/// handed to the XPC service (`onRings`) for the extension; each drawn frame is stamped
/// (`ScreenSaverLiveStamp`) on its ring's Darwin notification and handed on (`onStamp`).
///
/// The renderer asks for the slot to draw into (`target(ring:)`), the one after the newest, so the
/// newest frame a saver shows is never drawn over, and reports it once the GPU is done (`drawn`).
/// Thread-safe: render threads draw, the main thread publishes and clears.
final class ScreenSaverFramePublisher: @unchecked Sendable { // `lock` owns `rings`, `manifest`.
    static let ringSize = 3

    /// A display's entry: the ring it shows and, for a stretch, its rect of it.
    struct DisplayEntry: Equatable {
        var display: String?
        var ring: Int
        var crop: ScreenSaverManifest.Crop?
    }

    private struct Ring {
        let surfaces: [IOSurface]
        let textures: [MTLTexture]
        let notifyName: String
        var next = 0
        var frame: UInt32 = 0
    }

    /// Where `live.json` goes; nil writes none.
    let manifestURL: URL?
    private let notifier: ScreenSaverFrameNotifier
    private let device: MTLDevice
    private let lock = NSLock()
    private var rings: [Int: Ring] = [:]
    private var manifest = ScreenSaverLiveManifest()
    /// The extension's side: the rings whenever they change, and each frame's stamp. Set before
    /// publishing.
    var onRings: (@Sendable (LiveSaverFramesMessage) -> Void)?
    var onStamp: (@Sendable (_ ring: Int, _ stamp: UInt64) -> Void)?

    init(manifestURL: URL?, notifier: ScreenSaverFrameNotifier, device: MTLDevice) {
        self.manifestURL = manifestURL
        self.notifier = notifier
        self.device = device
        // Not 0: a stamp left in a notification by an earlier run never matches a new manifest.
        manifest.generation = Int(UInt16(truncatingIfNeeded: Int(Date().timeIntervalSince1970)) | 1)
    }

    var current: ScreenSaverLiveManifest { lock.withLock { manifest } }

    /// The rings and their surfaces as the extension gets them.
    var framesMessage: LiveSaverFramesMessage {
        lock.withLock {
            LiveSaverFramesMessage(manifest: manifest,
                                   surfaces: manifest.rings.flatMap { rings[$0.id]?.surfaces ?? [] })
        }
    }

    /// New rings of `sizes` (pixels; ring `i` is `sizes[i]`) shown as `displays` say, drawn at
    /// `frameRate`. Allocates the surfaces and lists them; the previous rings are let go.
    func publish(sizes: [SIMD2<Int>], displays: [DisplayEntry], frameRate: Int) throws {
        var made: [Int: Ring] = [:]
        var listed: [ScreenSaverLiveManifest.Ring] = []
        for (id, size) in sizes.enumerated() {
            var surfaces: [IOSurface] = []
            var textures: [MTLTexture] = []
            for _ in 0..<Self.ringSize {
                let made = try WallpaperTransitionSurface.make(size, device: device, global: true)
                surfaces.append(made.surface)
                textures.append(made.texture)
            }
            let name = ScreenSaverLiveNames.frameNotification(ring: id)
            made[id] = Ring(surfaces: surfaces, textures: textures, notifyName: name)
            listed.append(ScreenSaverLiveManifest.Ring(id: id, width: size.x, height: size.y,
                                                       surfaces: surfaces.map { IOSurfaceGetID($0) }, notifyName: name))
        }
        let next = lock.withLock {
            var next = manifest
            next.generation = Self.nextGeneration(after: manifest.generation)
            next.pid = getpid()
            next.frameRate = frameRate
            next.rings = listed
            next.displays = displays.map { ScreenSaverLiveManifest.Display(display: $0.display, ring: $0.ring, crop: $0.crop) }
            manifest = next
            rings = made
            return next
        }
        write(next)
        onRings?(framesMessage)
    }

    /// No live frames: the savers go back to their videos, and the surfaces are let go.
    func clear() {
        let next = lock.withLock {
            var next = manifest
            next.generation = Self.nextGeneration(after: manifest.generation)
            next.rings = []
            next.displays = []
            manifest = next
            rings = [:]
            return next
        }
        write(next)
        onRings?(framesMessage)
    }

    /// Where ring `ring`'s next frame goes: the slot after the newest. Nil for an unknown ring.
    func target(ring id: Int) -> (slot: Int, texture: MTLTexture, generation: Int)? {
        lock.withLock {
            guard var ring = rings[id] else { return nil }
            let slot = ring.next
            ring.next = (slot + 1) % ring.textures.count
            rings[id] = ring
            return (slot, ring.textures[slot], manifest.generation)
        }
    }

    /// The frame drawn into `slot` of ring `ring` (for rings of `generation`) is complete: stamps it.
    func drawn(ring id: Int, slot: Int, generation: Int) {
        let posted: (name: String, stamp: ScreenSaverLiveStamp)? = lock.withLock {
            guard generation == manifest.generation, var ring = rings[id] else { return nil }
            ring.frame &+= 1
            if ring.frame == 0 { ring.frame = 1 }
            rings[id] = ring
            return (ring.notifyName, ScreenSaverLiveStamp(generation: ScreenSaverLiveStamp.generation(generation),
                                                          frame: ring.frame, slot: UInt8(slot)))
        }
        guard let posted else { return }
        notifier.post(posted.name, state: posted.stamp.state)
        onStamp?(id, posted.stamp.state)
    }

    /// Wraps within the stamps' 16 bits, skipping 0.
    static func nextGeneration(after generation: Int) -> Int {
        let next = (generation + 1) & 0xFFFF
        return next == 0 ? 1 : next
    }

    private func write(_ manifest: ScreenSaverLiveManifest) {
        guard let manifestURL else { return }
        do {
            try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        } catch {
            OWELog.error(.app, "Live screen saver: can't write \(manifestURL.lastPathComponent): \(error)")
        }
    }
}
