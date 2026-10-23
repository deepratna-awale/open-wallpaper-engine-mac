import Foundation

/// The running instances of wallpapers, one per wallpaper however many displays show it
/// (docs/architecture.md "Wallpaper instances").
///
/// Each display holds the instance it shows (`WallpaperInstanceLease`); the instance lives while
/// any display holds it. The last release doesn't tear it down at once but on the next turn of
/// the main queue: a display that is rebuilt (screens changed, a window recreated) takes hold of
/// it again first, so the wallpaper keeps running instead of loading again.
@MainActor
final class WallpaperInstanceRegistry<Key: Hashable & Sendable, Instance: AnyObject> {
    private struct Entry {
        let instance: Instance
        var holders: Set<ObjectIdentifier>
    }

    /// The instances and how they stop, in a main-actor box (so `Sendable`) that the nonisolated
    /// `deinit` can hand to the main actor.
    @MainActor
    private final class State {
        var entries: [Key: Entry] = [:]
        let teardown: (Instance) -> Void

        init(teardown: @escaping (Instance) -> Void) {
            self.teardown = teardown
        }

        func tearDownAll() {
            let instances = entries.values.map(\.instance)
            for instance in instances { teardown(instance) }
        }
    }

    private let state: State
    private let deferTeardown: (@escaping @MainActor @Sendable () -> Void) -> Void

    /// `teardown` stops an instance nothing holds any more; `deferTeardown` runs the check for
    /// that later (the next main-queue turn; tests pass one that runs it at once).
    init(teardown: @escaping (Instance) -> Void,
         deferTeardown: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void = { work in
             DispatchQueue.main.async { MainActor.assumeIsolated(work) }
         }) {
        state = State(teardown: teardown)
        self.deferTeardown = deferTeardown
    }

    /// Instances still here when the registry goes (its owner went before a deferred teardown
    /// ran) stop now: nothing could release them any more, and a running instance keeps its
    /// render thread, display links and sound.
    deinit {
        let state = state
        if Thread.isMainThread {
            MainActor.assumeIsolated { state.tearDownAll() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { state.tearDownAll() } }
        }
    }

    /// The instance for `key`, made by `make` when none runs, now held by `holder` too.
    func acquire(_ key: Key, holder: AnyObject, make: () -> Instance) -> Instance {
        let id = ObjectIdentifier(holder)
        if var entry = state.entries[key] {
            entry.holders.insert(id)
            state.entries[key] = entry
            return entry.instance
        }
        let instance = make()
        state.entries[key] = Entry(instance: instance, holders: [id])
        return instance
    }

    /// `holder` no longer shows `key`'s instance; it stops once nothing holds it.
    func release(_ key: Key, holder: AnyObject) {
        let id = ObjectIdentifier(holder)
        guard var entry = state.entries[key], entry.holders.remove(id) != nil else { return }
        state.entries[key] = entry
        guard entry.holders.isEmpty else { return }
        deferTeardown { [weak self] in self?.tearDownIfUnheld(key) }
    }

    private func tearDownIfUnheld(_ key: Key) {
        guard let entry = state.entries[key], entry.holders.isEmpty else { return }
        state.entries[key] = nil
        state.teardown(entry.instance)
    }

    /// The running instance for `key`, if any.
    func instance(for key: Key) -> Instance? { state.entries[key]?.instance }

    /// How many displays hold `key`'s instance.
    func holderCount(for key: Key) -> Int { state.entries[key]?.holders.count ?? 0 }

    /// The running instances (held or waiting for their teardown).
    var instances: [Instance] { state.entries.values.map(\.instance) }
}
