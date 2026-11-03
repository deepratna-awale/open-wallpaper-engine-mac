import XCTest
@testable import OpenWallpaperEngine

final class RecentLogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "owe-recent-log-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory) // Optional: a test may not have created it.
    }

    func testANewRunKeepsTheLastRunAsPrevious() {
        let first = RecentLog(directory: directory)
        first.startRun()
        first.append(.info, .app, "first run")
        let second = RecentLog(directory: directory)
        second.startRun()
        second.append(.error, .shader, "second run")

        XCTAssertTrue(RecentLog.tail(of: .previous, in: directory).contains("I App: first run"))
        let current = RecentLog.tail(of: .current, in: directory)
        XCTAssertTrue(current.contains("E ShaderTranslator: second run"))
        XCTAssertFalse(current.contains("first run"))
    }

    func testARunKeepsAtMostTwoChunks() {
        let log = RecentLog(directory: directory, maxFileSize: 200)
        log.startRun()
        for index in 0..<40 { log.append(.info, .app, "message \(index)") }
        let tail = RecentLog.tail(of: .current, in: directory)
        XCTAssertTrue(tail.contains("message 39"))
        XCTAssertFalse(tail.contains("message 0\n"), "the oldest chunk is gone")
        XCTAssertLessThanOrEqual(tail.utf8.count, 400)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecentLog.fileURL(.current, chunk: 2, in: directory).path))
    }

    func testTailCutsAtALineStart() {
        let log = RecentLog(directory: directory)
        log.startRun()
        for index in 0..<100 { log.append(.info, .app, "line \(index)") }
        let tail = RecentLog.tail(of: .current, in: directory, maxBytes: 300)
        XCTAssertLessThanOrEqual(tail.utf8.count, 300)
        XCTAssertTrue(tail.hasSuffix("line 99\n"))
        XCTAssertTrue(tail.first?.isNumber == true, "starts with a whole line's timestamp: \(tail.prefix(30))")
    }

    func testNoRunNoLog() {
        XCTAssertEqual(RecentLog.tail(of: .previous, in: directory), "")
        XCTAssertNil(RecentLog.lastWrite(of: .previous, in: directory))
        // Appending before `startRun` writes nothing.
        RecentLog(directory: directory).append(.error, .app, "lost")
        XCTAssertEqual(RecentLog.tail(of: .current, in: directory), "")
    }
}
