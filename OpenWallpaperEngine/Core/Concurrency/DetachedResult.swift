import Foundation

/// Runs `work` on a global queue at `qos` and returns what it made to the caller, which may keep
/// a value that isn't `Sendable` (a loader and the content it built): `work` hands it over and
/// keeps nothing, which `sending` lets the compiler check. A detached task can't, since its result
/// must be `Sendable`.
func detachedResult<T>(qos: DispatchQoS.QoSClass,
                       _ work: @escaping @Sendable () throws -> sending T) async throws -> sending T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: qos).async {
            do {
                continuation.resume(returning: try work())
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
