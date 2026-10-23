import Foundation
import XCTest
@testable import OpenWallpaperEngine

/// Fails the test that caused a thread guard violation, one issue per violation, when the test
/// ends: "TEXParser.decode ran on the main thread (…), thread main" and its top frames. Other
/// tests keep running. A test that expects violations takes them with `ThreadGuards.capture`
/// (or `expectThreadGuardViolations`), so they don't reach here.
///
/// Registered once, by the bundle's principal class (`TestPhaseTimer`).
// `@unchecked Sendable`: it keeps no state of its own; XCTest calls it on the main thread.
final class ThreadGuardTestObserver: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared = ThreadGuardTestObserver()

    /// Runs once, however often `register` is called (a static's initializer runs exactly once).
    private static let registration: Void = {
        ThreadGuards.store.collectPending()
        XCTestObservationCenter.shared.addTestObserver(shared)
    }()

    static func register() {
        _ = registration
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        // Anything left from between tests belongs to none of them.
        for violation in ThreadGuards.store.takePending() {
            print("Thread guard, outside any test: " + violation.message())
        }
        // Teardown blocks run inside the test, so the issues are the test's own. XCTest calls this
        // and runs the block on the main thread, so the unguarded reference is never shared.
        final class WeakTestCase: @unchecked Sendable { weak var value: XCTestCase?; init(_ value: XCTestCase) { self.value = value } }
        let observed = WeakTestCase(testCase)
        testCase.addTeardownBlock {
            guard let testCase = observed.value else { return }
            for violation in ThreadGuards.store.takePending() {
                guard Self.fails(violation) else {
                    print("Thread guard, from the test's own main-thread setup: " + violation.message(frames: 2))
                    continue
                }
                testCase.record(Self.issue(for: violation))
            }
        }
    }

    /// Test bodies run on the main thread and load fixtures there synchronously (`metalContent()`,
    /// texture and shader preparation), work the app does off it; so a main-thread violation fails
    /// a test only with `OWE_STRICT_THREAD_GUARDS=1`. Render-thread violations always fail it.
    static let strictMainThread = ProcessInfo.processInfo.environment["OWE_STRICT_THREAD_GUARDS"] == "1"

    static func fails(_ violation: ThreadGuards.Violation) -> Bool {
        violation.kind != .onMainThread || strictMainThread
    }

    static func issue(for violation: ThreadGuards.Violation) -> XCTIssue {
        XCTIssue(type: .assertionFailure, compactDescription: "Thread guard: \(violation.summary)",
                 detailedDescription: violation.message())
    }
}

/// Runs `body` and returns the thread guard violations it caused on any thread; they don't fail
/// the test.
func expectThreadGuardViolations(_ body: () throws -> Void) rethrows -> [ThreadGuards.Violation] {
    try ThreadGuards.capture(body).1
}
