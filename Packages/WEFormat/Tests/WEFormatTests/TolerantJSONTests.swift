import XCTest
@testable import WEFormat

/// The one byte order mark skip (`TolerantJSON`) and the tolerant decoder on top of it.
final class TolerantJSONTests: XCTestCase {
    private struct Value: Decodable, Equatable { let a: Int }

    func testByteOrderMarkIsSkippedOnce() {
        let json = Data("{\"a\": 1}".utf8)
        let marked = Data(TolerantJSON.byteOrderMark) + json
        XCTAssertTrue(TolerantJSON.hasBOM(marked))
        XCTAssertFalse(TolerantJSON.hasBOM(json))
        XCTAssertEqual(TolerantJSON.withoutBOM(marked), json)
        XCTAssertEqual(TolerantJSON.withoutBOM(json), json)
        XCTAssertEqual(TolerantJSON.withoutBOM(Data(TolerantJSON.byteOrderMark + TolerantJSON.byteOrderMark)),
                       Data(TolerantJSON.byteOrderMark))
        XCTAssertEqual(TolerantJSON.withoutBOM(Data()), Data())
    }

    func testSliceWithMarkReadsFromItsOwnStart() throws {
        let whole = Data("xx".utf8) + Data(TolerantJSON.byteOrderMark) + Data("{\"a\": 2,}".utf8)
        let slice = whole.dropFirst(2)
        XCTAssertTrue(TolerantJSON.hasBOM(slice))
        XCTAssertEqual(try decodeTolerant(Value.self, from: slice), Value(a: 2))
    }

    func testDecodeTolerantTakesMarkCommentsAndTrailingCommas() throws {
        let data = Data(TolerantJSON.byteOrderMark) + Data("{ // note\n\"a\": 3, }".utf8)
        XCTAssertEqual(try decodeTolerant(Value.self, from: data), Value(a: 3))
    }
}
