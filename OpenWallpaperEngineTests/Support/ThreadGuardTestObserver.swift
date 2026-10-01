import Foundation
import XCTest
@testable import OpenWallpaperEngine

/// Fails the test that caused a thread guard violation, one issue per violation, when the test
/// ends: "TEXParser.decode ran on the main thread (…), thread main" and its top frames. Other
/// tests keep running. A test that expects violations takes them with `ThreadGuards.capture`
/// (or `expectThreadGuardViolations`), so they don't reach here.
///
/// Registered once, by the bundle's principal class (`TestPhaseTimer`).
final class ThreadGuardTestObserver: NSObject, XCTestObservation {
    static let shared = ThreadGuardTestObserver()

    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        ThreadGuards.store.collectPending()
        XCTestObservationCenter.shared.addTestObserver(shared)
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        // Anything left from between tests belongs to none of them.
        for violation in ThreadGuards.store.takePending() {
            print("Thread guard, outside any test: " + violation.message())
        }
        // Teardown blocks run inside the test, so the issues are the test's own.
        testCase.addTeardownBlock { [weak testCase] in
            guard let testCase else { return }
            for violation in ThreadGuards.store.takePending() {
                testCase.record(Self.issue(for: violation))
            }
        }
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
