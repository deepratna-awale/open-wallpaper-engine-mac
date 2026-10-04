import XCTest
@testable import OpenWallpaperEngine

/// The library's title, rating and file size orders compare the sorted value in both directions.
final class SortByOrderTests: XCTestCase {
    func testFileSizesSortByTheirSizeInBothDirections() {
        // Titles in the opposite order to the sizes, so comparing titles would give the wrong order.
        let sizes: [(title: String, size: Int)] = [("A", 30), ("B", 10), ("C", 20)]
        let increasing = sizes.sorted { ContentViewModel.precedes($0.size, $1.size, in: .increase) }
        let decreasing = sizes.sorted { ContentViewModel.precedes($0.size, $1.size, in: .decrease) }
        XCTAssertEqual(increasing.map(\.size), [30, 20, 10])
        XCTAssertEqual(decreasing.map(\.size), [10, 20, 30])
    }

    func testEqualValuesNeverPrecedeEachOther() {
        XCTAssertFalse(ContentViewModel.precedes(5, 5, in: .increase))
        XCTAssertFalse(ContentViewModel.precedes(5, 5, in: .decrease))
    }
}
