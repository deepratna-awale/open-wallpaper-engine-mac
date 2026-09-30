import XCTest
@testable import OpenWallpaperEngine

final class ThreadGuardsTests: XCTestCase {
    private final class Hits: @unchecked Sendable {
        let lock = NSLock()
        var list: [ThreadGuards.Violation] = []
        func add(_ v: ThreadGuards.Violation) { lock.lock(); list.append(v); lock.unlock() }
        var all: [ThreadGuards.Violation] { lock.lock(); defer { lock.unlock() }; return list }
    }

    func testGuardsFireOnTheMainAndRenderThreads() {
        #if DEBUG
        let hits = Hits()
        let previous = ThreadGuards.setHandler { hits.add($0) }
        defer { ThreadGuards.setHandler(previous) }
        XCTAssertTrue(Thread.isMainThread)
        ThreadGuards.assertNotMainThread("heavy on main")
        ThreadGuards.assertRenderThread("frame work off the render thread")
        ThreadGuards.renderFrame {
            ThreadGuards.assertRenderThread("frame work")        // fine
            ThreadGuards.assertNotRenderThread("heavy in frame")
        }
        let off = expectation(description: "background")
        DispatchQueue.global().async {
            ThreadGuards.assertBackground("heavy in background") // fine
            off.fulfill()
        }
        wait(for: [off], timeout: 5)
        let kinds: [ThreadGuards.Violation.Kind] = hits.all.map(\.kind)
        XCTAssertEqual(kinds, [.onMainThread, .offRenderThread, .onRenderThread])
        #endif
    }

    func testTEXDecodeOnTheMainThreadIsReported() {
        #if DEBUG
        let hits = Hits()
        let previous = ThreadGuards.setHandler { hits.add($0) }
        defer { ThreadGuards.setHandler(previous) }
        _ = TEXParser(data: Data("TEXV0005".utf8)).extractImage()
        let whats: [String] = hits.all.map(\.what)
        XCTAssertEqual(whats, ["TEXParser.extractContainerImage"])
        #endif
    }
}
