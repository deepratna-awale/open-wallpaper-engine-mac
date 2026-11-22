import os
import XCTest
@testable import OpenWallpaperEngine

/// Running a Steam helper download to its end: the exit is always noticed, with the whole output.
final class SteamHelperProcessRunnerTests: XCTestCase {
    private func run(_ script: String, input: String = "", timeout: TimeInterval? = nil,
                     cancellation: ProcessCancellation = ProcessCancellation(),
                     onOutput: @escaping @Sendable (String) -> Void = { _ in }) -> ProcessRun {
        ProcessRunner.runProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script],
                                 standardInput: Data(input.utf8), timeout: timeout, cancellation: cancellation,
                                 onOutput: onOutput)
    }

    /// `Process.waitUntilExit` off the launching thread missed the exit once in a while, which left
    /// every later Workshop download queued. Many short programs at once, from background queues as
    /// the downloads are.
    func testEveryExitIsNoticed() {
        let lanes = 8, runsPerLane = 40
        let finished = expectation(description: "every run returned")
        finished.expectedFulfillmentCount = lanes
        let failures = OSAllocatedUnfairLock(initialState: [String]())
        for lane in 0..<lanes {
            DispatchQueue(label: "owe.tests.run.\(lane)").async(qos: .utility) {
                for _ in 0..<runsPerLane {
                    let result = ProcessRunner.runProcess(
                        executable: URL(filePath: "/bin/sh"), arguments: ["-c", "cat >/dev/null; echo a; sleep 0.02; echo b"],
                        standardInput: Data("login\n".utf8), timeout: nil, cancellation: ProcessCancellation(), onOutput: { _ in })
                    if result.exitCode != 0 || result.output != "a\nb\n" {
                        failures.withLock { $0.append("\(result.exitCode): \(result.output)") }
                    }
                }
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 120)
        XCTAssertEqual(failures.withLock { $0 }, [])
    }

    func testTheOutputIsWholeAndTheInputArrives() {
        let streamed = OSAllocatedUnfairLock(initialState: "")
        let result = run("cat; seq 1 20000; echo error >&2; exit 3", input: "login\n") { chunk in
            streamed.withLock { $0 += chunk }
        }
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertTrue(result.output.hasPrefix("login\n1\n"))
        XCTAssertTrue(result.output.hasSuffix("20000\nerror\n"))
        XCTAssertEqual(streamed.withLock { $0 }, result.output)
    }

    /// A program that left a child of its own holding the output doesn't hold up the download.
    func testAnOutputLeftOpenDoesNotHoldUpTheRun() {
        let started = Date()
        let result = run("echo done; sleep 20 &")
        XCTAssertEqual(result.output, "done\n")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testATimeoutAndACancellationStopTheProgram() {
        let started = Date()
        XCTAssertEqual(run("exec sleep 30", timeout: 0.2).exitCode, -1)
        let cancellation = ProcessCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { cancellation.cancel() }
        XCTAssertNotEqual(run("exec sleep 30", cancellation: cancellation).exitCode, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
    }
}
