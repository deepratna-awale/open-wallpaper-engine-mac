import XCTest
@testable import OpenWallpaperEngine

/// The filter sidebar draws each filter generically: option `i` is the checkbox for bit `1 << i`,
/// and All/None set the filter's own `all` and `none`. Those have to agree, or All would tick
/// boxes that don't exist or leave some unticked.
final class FilterResultsModelTests: XCTestCase {
    private func assertCheckboxesCoverAll<Option: FilterResultsModel>(_: Option.Type,
                                                                    file: StaticString = #filePath,
                                                                    line: UInt = #line) {
        let checkboxes = Option.allOptions.indices.reduce(into: Option.none) { bits, index in
            bits.insert(Option(rawValue: 1 << index))
        }
        XCTAssertEqual(checkboxes, Option.all, "\(Option.self)", file: file, line: line)
        XCTAssertTrue(Option.none.isEmpty, "\(Option.self)", file: file, line: line)
    }

    func testAllSelectsExactlyTheCheckboxes() {
        assertCheckboxesCoverAll(FRType.self)
        assertCheckboxesCoverAll(FRAgeRating.self)
        assertCheckboxesCoverAll(FRWidescreenResolution.self)
        assertCheckboxesCoverAll(FRUltraWidescreenResolution.self)
        assertCheckboxesCoverAll(FRDualscreenResolution.self)
        assertCheckboxesCoverAll(FRTriplescreenResolution.self)
        assertCheckboxesCoverAll(FRPortraitScreenResolution.self)
        assertCheckboxesCoverAll(FRMiscResolution.self)
        assertCheckboxesCoverAll(FRSource.self)
        assertCheckboxesCoverAll(FRTag.self)
    }
}
