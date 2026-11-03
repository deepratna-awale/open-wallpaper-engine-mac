import XCTest
@testable import OpenWallpaperEngine

final class AppRunRecordStoreTests: XCTestCase {
    func testARunThatQuitLeavesNoRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "owe-run-record-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) } // Optional: cleanup.
        let store = AppRunRecordStore(directory: directory)
        XCTAssertNil(store.load())

        let record = AppRunRecord(processIdentifier: 42, started: Date(timeIntervalSince1970: 1_800_000_000), version: "1.0.0-beta.15")
        store.save(record)
        XCTAssertEqual(store.load(), record, "a run that never quit leaves its record for the next launch")

        store.clear()
        XCTAssertNil(store.load())
    }
}
