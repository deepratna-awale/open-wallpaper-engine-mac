import XCTest
@testable import OpenWallpaperEngine

/// The cost of a passing thread guard. Per frame the render path runs one `assertRenderThread`
/// and one `renderFrame` per frame entry; neither is per layer, particle or draw.
final class ThreadGuardsCostTests: XCTestCase {
    /// Runs nightly and locally (`OWE_SLOW_TESTS=1`), not on every PR. Prints ns per check.
    func testPassingCheckCost() throws {
        try SlowTests.require()
        let count = 10_000_000
        var report: [String] = []
        ThreadGuards.renderFrame {
            report.append(Self.time("assertRenderThread", count) { ThreadGuards.assertRenderThread("bench") })
        }
        report.append(Self.time("assertNotRenderThread", count) { ThreadGuards.assertNotRenderThread("bench") })
        report.append(Self.time("renderFrame (empty)", count) { ThreadGuards.renderFrame {} })
        XCTAssertEqual(ThreadGuards.store.total, 0)
        print("Thread guard cost per passing check:\n" + report.joined(separator: "\n"))
    }

    private static func time(_ name: String, _ count: Int, _ body: () -> Void) -> String {
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<count { body() }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count))
        }
        return "  \(name): \(String(format: "%.2f", samples.sorted()[2])) ns (median of 5 × \(count))"
    }
}
