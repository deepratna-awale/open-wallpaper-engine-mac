import Foundation
import IOSurface
import notify

/// The `.saver`'s way to the app's live frames. Its host (`legacyScreenSaver`) is sandboxed with
/// no XPC or Mach lookup to the app, but may read any file, look up a global IOSurface by id and
/// use Darwin notifications. So it reads the rings from `live.json` (`ScreenSaverLiveManifest`),
/// looks their surfaces up (`IOSurfaceLookup`), reads each ring's newest stamp from its
/// notification's state as the notification comes, and posts `saverAlive` while a view shows. One per process: hosts keep
/// several views (one per display, stacked instances).
final class GlobalSurfaceFrameSource: LiveFrameSource {
    static let shared = GlobalSurfaceFrameSource(
        manifestURL: ScreenSaverManifest.sharedFolder(home: ScreenSaverManifest.userHome)
            .appending(path: ScreenSaverLiveManifest.fileName, directoryHint: .notDirectory))

    let store = LiveFrameStore()
    private let manifestURL: URL
    private var manifest: ScreenSaverLiveManifest?
    private var modified: Date?
    /// Each ring's notification token (`notify_register_dispatch`).
    private var tokens: [Int: Int32] = [:]
    private var lastManifestCheck: TimeInterval = -.infinity
    private var lastPing: TimeInterval = -.infinity
    private var views: Set<String> = []

    init(manifestURL: URL) {
        self.manifestURL = manifestURL
    }

    func attach(viewID: String, display: String?, isPreview: Bool) {
        SaverLog.transport.notice("attach view=\(viewID, privacy: .public) display=\(display ?? "nil", privacy: .public) preview=\(isPreview) pid=\(getpid())")
        guard !isPreview else { return }
        views.insert(viewID)
        postAlive(force: true)
    }

    func ping(viewID: String) {
        guard views.contains(viewID) else { return }
        postAlive(force: false)
    }

    func detach(viewID: String) {
        views.remove(viewID)
    }

    func refresh() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastManifestCheck > 0.5 {
            lastManifestCheck = now
            reloadIfChanged()
        }
        // A frame posted before the rings were registered isn't delivered: read the states once.
        for (ring, token) in tokens { read(ring: ring, token: token) }
    }

    /// Ring `ring`'s newest stamp, from its notification's state: on each notification (as the
    /// frame is drawn) and on `refresh`.
    private func read(ring: Int, token: Int32) {
        guard let manifest, manifest.isLive else { return }
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == UInt32(NOTIFY_STATUS_OK),
              let stamp = ScreenSaverLiveStamp(state: state) else { return }
        guard stamp.generation == ScreenSaverLiveStamp.generation(manifest.generation) else {
            // Newer rings than the manifest read: read it again on the next refresh.
            lastManifestCheck = -.infinity
            return
        }
        store.show(ring: ring, stamp: stamp)
    }

    /// One alive notification a second for the whole process, however many views show.
    private func postAlive(force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastPing >= 0.9 else { return }
        lastPing = now
        notify_post(ScreenSaverLiveNames.saverAlive)
    }

    private func reloadIfChanged() {
        let path = manifestURL.path(percentEncoded: false)
        // Optional: no file means the app isn't drawing live frames.
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        guard date != modified || manifest == nil && date != nil else { return }
        modified = date
        let read = date == nil ? nil : ScreenSaverLiveManifest.read(manifestURL)
        guard read != manifest else { return }
        use(read ?? ScreenSaverLiveManifest())
    }

    private func use(_ manifest: ScreenSaverLiveManifest) {
        self.manifest = manifest
        for token in tokens.values { notify_cancel(token) }
        tokens = [:]
        var surfaces: [Int: [IOSurface]] = [:]
        var found = 0, listed = 0
        for ring in manifest.rings {
            // `IOSurfaceRef` is toll-free bridged to `IOSurface`.
            let ringSurfaces = ring.surfaces.compactMap { IOSurfaceLookup($0) }.map { unsafeBitCast($0, to: IOSurface.self) }
            listed += ring.surfaces.count
            found += ringSurfaces.count
            // A surface that is gone (the app quit or replaced the rings) leaves the ring unusable.
            guard ringSurfaces.count == ring.surfaces.count else { continue }
            surfaces[ring.id] = ringSurfaces
            var token: Int32 = 0
            let id = ring.id
            // Delivered on the main thread as each frame is drawn: the views draw it then.
            let status = notify_register_dispatch(ring.notifyName, &token, .main) { [weak self] token in
                self?.read(ring: id, token: token)
            }
            if status == UInt32(NOTIFY_STATUS_OK) { tokens[ring.id] = token }
        }
        store.use(manifest, surfaces: surfaces)
        SaverLog.transport.notice("live manifest generation=\(manifest.generation) pid=\(manifest.pid) rings=\(manifest.rings.count) displays=\(manifest.displays.count) surfaces found=\(found)/\(listed) fps=\(manifest.frameRate)")
    }
}
