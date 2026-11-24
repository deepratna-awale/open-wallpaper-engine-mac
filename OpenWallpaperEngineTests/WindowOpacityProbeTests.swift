import XCTest
@testable import OpenWallpaperEngine

/// `WindowOpacityProbe` with an injected capture: it captures in the background, reuses a
/// window's grid until the window is resized or the grid is old, and forgets closed windows.
final class WindowOpacityProbeTests: XCTestCase {
    private final class Captures: @unchecked Sendable {
        private let lock = NSLock()
        private var _batches: [[CGWindowID]] = []
        var batches: [[CGWindowID]] { lock.withLock { _batches } }
        func record(_ windows: [DesktopWindow]) { lock.withLock { _batches.append(windows.map(\.id)) } }
    }

    private let glass = WindowOpacityMask(columns: 1, rows: 1, opaque: [false])

    private func makeProbe(_ captures: Captures) -> WindowOpacityProbe {
        let glass = glass
        return WindowOpacityProbe { windows in
            captures.record(windows)
            return Dictionary(uniqueKeysWithValues: windows.map { ($0.id, glass) })
        }
    }

    private func window(_ id: CGWindowID, width: CGFloat = 800) -> DesktopWindow {
        DesktopWindow(ownerPID: 100, bounds: CGRect(x: 0, y: 0, width: width, height: 600), id: id)
    }

    func testAWindowIsCapturedOnceAndItsGridReused() {
        let captures = Captures()
        let probe = makeProbe(captures)
        XCTAssertEqual(probe.masks(for: [window(7)]), [:], "nothing is known before the first capture")
        XCTAssertTrue(spin(until: { probe.masks(for: [self.window(7)]) == [7: self.glass] }))
        XCTAssertEqual(captures.batches, [[7]])
    }

    func testAResizedOrOldWindowIsCapturedAgain() {
        let captures = Captures()
        let probe = makeProbe(captures)
        _ = probe.masks(for: [window(7)])
        XCTAssertTrue(spin(until: { captures.batches.count == 1 && probe.masks(for: [self.window(7)]) == [7: self.glass] }))
        XCTAssertEqual(probe.masks(for: [window(7, width: 900)]), [:], "a resized window's old grid no longer fits")
        XCTAssertTrue(spin(until: { captures.batches.count == 2 }))
        _ = spin(until: { probe.masks(for: [self.window(7, width: 900)]) == [7: self.glass] })
        let later = Date().addingTimeInterval(WindowOpacityProbe.refreshInterval + 1)
        XCTAssertEqual(probe.masks(for: [window(7, width: 900)], now: later), [7: glass], "an old grid is used until the new one is in")
        XCTAssertTrue(spin(until: { captures.batches.count == 3 }))
    }

    func testWindowsWithoutANumberAreNeverCaptured() {
        let captures = Captures()
        let probe = makeProbe(captures)
        XCTAssertEqual(probe.masks(for: [window(0)]), [:])
        spin(for: 0.2)
        XCTAssertEqual(captures.batches, [])
    }
}
