import XCTest
@testable import OpenWallpaperEngine

final class InstalledPageWindowTests: XCTestCase {
    func testNoPages() {
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 1, total: 0), [])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 5, total: 0), [])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 0, total: 0), [])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 1, total: -3), [])
    }

    func testOnePage() {
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 1, total: 1), [1])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 9, total: 1), [1])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: -2, total: 1), [1])
    }

    func testTwoPages() {
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 1, total: 2), [1, 2])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 2, total: 2), [1, 2])
    }

    func testCurrentBeyondTotal() {
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 10, total: 3), [1, 2, 3])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 50, total: 7), [5, 6, 7])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: .max, total: 7), [5, 6, 7])
    }

    func testCurrentBelowOne() {
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 0, total: 5), [1, 2, 3])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: -4, total: 5), [1, 2, 3])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: .min, total: 5), [1, 2, 3])
    }

    func testLargeTotals() {
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 500, total: 10_000), [498, 499, 500, 501, 502])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 1, total: 10_000), [1, 2, 3])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: 10_000, total: 10_000), [9_998, 9_999, 10_000])
        XCTAssertEqual(InstalledPageWindow.pageNumbers(current: .max, total: .max), [.max - 2, .max - 1, .max])
    }

    func testClamp() {
        XCTAssertEqual(InstalledPageWindow.clamp(0, total: 0), 1)
        XCTAssertEqual(InstalledPageWindow.clamp(4, total: 0), 1)
        XCTAssertEqual(InstalledPageWindow.clamp(4, total: 3), 3)
        XCTAssertEqual(InstalledPageWindow.clamp(-1, total: 3), 1)
        XCTAssertEqual(InstalledPageWindow.clamp(2, total: 3), 2)
    }
}
