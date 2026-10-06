import XCTest
@testable import OpenWallpaperEngine

/// The library's title, rating and file size orders compare the sorted value in both directions.
final class SortByOrderTests: XCTestCase {
    func testFileSizesSortByTheirSizeInBothDirections() {
        // Titles in the opposite order to the sizes, so comparing titles would give the wrong order.
        let sizes: [(title: String, size: Int)] = [("A", 30), ("B", 10), ("C", 20)]
        let increasing = sizes.sorted { InstalledLibraryModel.precedes($0.size, $1.size, in: .increase) }
        let decreasing = sizes.sorted { InstalledLibraryModel.precedes($0.size, $1.size, in: .decrease) }
        XCTAssertEqual(increasing.map(\.size), [30, 20, 10])
        XCTAssertEqual(decreasing.map(\.size), [10, 20, 30])
    }

    func testEqualValuesNeverPrecedeEachOther() {
        XCTAssertFalse(InstalledLibraryModel.precedes(5, 5, in: .increase))
        XCTAssertFalse(InstalledLibraryModel.precedes(5, 5, in: .decrease))
    }

    func testRatingsSortEveryoneQuestionableMature() {
        let ratings: [String?] = ["Mature", nil, "Questionable", "Everyone"]
        let decreasing = ratings.sorted {
            InstalledLibraryModel.precedes(InstalledLibraryModel.ratingRank($0), InstalledLibraryModel.ratingRank($1), in: .decrease)
        }
        XCTAssertEqual(decreasing, [nil, "Everyone", "Questionable", "Mature"])
        XCTAssertEqual(InstalledLibraryModel.ratingRank(" mature"), InstalledLibraryModel.ratingRank("Mature"))
    }
}
