import Foundation

/// Undo for the user properties the Wallpaper Editor shows (the Details panel's own view,
/// `SceneUserPropertiesView`, editing the shared store): each change it announces
/// (`wallpaperUserPropertyChanged`) is registered on the editor's undo manager, beside the
/// layer edits, and undoing writes the earlier value back through the same stores.
@MainActor
final class EditorUserPropertyUndo: ObservableObject {
    /// Moves when an undo or redo changed a value under the view, which then reads the store again.
    @Published private(set) var revision = 0
    private let targets: WallpaperPropertyTargets
    private let wallpaperPath: String
    private let undoManager: UndoManager
    private let coalescingInterval: TimeInterval
    /// The values as last seen, so a change knows what it replaced.
    private var values: [String: String]
    private var lastChange: (key: String, date: Date)?
    /// Set once in init and read again only in deinit, when nothing else can reach it.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(wallpaper: WEWallpaper, undoManager: UndoManager, coalescingInterval: TimeInterval = 1) {
        targets = WallpaperPropertyTargets(wallpaper: wallpaper, scopes: [.shared])
        wallpaperPath = wallpaper.wallpaperDirectory.path
        self.undoManager = undoManager
        self.coalescingInterval = coalescingInterval
        values = targets.storedValues
        observer = NotificationCenter.default.addObserver(forName: .wallpaperUserPropertyChanged, object: nil,
                                                          queue: .main) { [weak self] notification in
            let path = notification.object as? String
            let key = notification.userInfo?["key"] as? String
            let value = notification.userInfo?["value"] as? String
            let stores = notification.userInfo?["stores"] as? [String] ?? []
            MainActor.assumeIsolated {
                guard let self, path == self.wallpaperPath, let key, let value,
                      stores.contains(where: self.targets.runtimeKeys.contains) else { return }
                self.changed(key, to: value)
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// A slider dragged or a field typed in within `coalescingInterval` is one undo step.
    func changed(_ key: String, to value: String, now: Date = Date()) {
        let previous = values[key]
        values[key] = value
        guard previous != value else { return }
        let continues = lastChange.map { $0.key == key && now.timeIntervalSince($0.date) < coalescingInterval } ?? false
        lastChange = (key, now)
        guard !continues else { return }
        register(key, restoring: previous)
    }

    private func register(_ key: String, restoring value: String?) {
        let grouped = !undoManager.isUndoing && !undoManager.isRedoing
        if grouped { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.restore(key, to: value) }
        }
        undoManager.setActionName(String(localized: "Change User Property"))
        if grouped { undoManager.endUndoGrouping() }
    }

    /// Undo or redo: `key` back to `value` (nil: its default, the key dropped) in the store and
    /// the running wallpapers, registering the way back.
    private func restore(_ key: String, to value: String?) {
        var stored = targets.storedValues
        register(key, restoring: stored[key])
        stored[key] = value
        values = stored
        lastChange = nil
        targets.save(stored)
        for runtimeKey in targets.runtimeKeys { WallpaperPropertyTargets.publishReplacing(runtimeKey, stored) }
        revision += 1
    }
}
