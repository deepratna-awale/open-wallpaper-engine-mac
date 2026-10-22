import Foundation

/// Block observers (`NotificationCenter.addObserver(forName:object:queue:using:)`) that a
/// main-actor owner adds and replaces as it goes. They are removed from their centers when the
/// owner, and so this, goes away, whichever thread that happens on, so the owner's nonisolated
/// deinit doesn't have to reach its main-actor state.
final class NotificationObservers: @unchecked Sendable { // `lock` guards `tokens`.
    private let lock = NSLock()
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func add(_ token: NSObjectProtocol, to center: NotificationCenter = .default) {
        lock.withLock { tokens.append((center, token)) }
    }

    /// Removes every observer added so far.
    func removeAll() {
        let removed = lock.withLock { () -> [(center: NotificationCenter, token: NSObjectProtocol)] in
            defer { tokens = [] }
            return tokens
        }
        removed.forEach { $0.center.removeObserver($0.token) }
    }

    deinit { removeAll() }
}
