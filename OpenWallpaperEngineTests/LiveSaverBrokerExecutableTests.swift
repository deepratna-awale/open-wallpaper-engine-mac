import XCTest
@testable import OpenWallpaperEngine

/// The broker exits once an update replaced its binary, so launchd runs the new one.
final class LiveSaverBrokerExecutableTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "LiveSaverBrokerExecutableTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeBinary(_ name: String, _ contents: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testTheSameBinaryIsUpToDate() throws {
        let binary = try writeBinary("owe-saver-broker", "old")
        let executable = LiveSaverBrokerExecutable(path: binary.path)
        XCTAssertNotNil(executable.started)
        XCTAssertFalse(executable.isOutOfDate)
    }

    func testABinaryReplacedByAnUpdateIsOutOfDate() throws {
        let binary = try writeBinary("owe-saver-broker", "old")
        let executable = LiveSaverBrokerExecutable(path: binary.path)
        // Sparkle swaps the whole bundle: a new file at the same path.
        let staged = try writeBinary("staged", "new")
        _ = try FileManager.default.replaceItemAt(binary, withItemAt: staged)
        XCTAssertTrue(executable.isOutOfDate)
    }

    func testABinaryWithNothingAtItsPathIsOutOfDate() throws {
        let binary = try writeBinary("owe-saver-broker", "old")
        let executable = LiveSaverBrokerExecutable(path: binary.path)
        try FileManager.default.removeItem(at: binary)
        XCTAssertTrue(executable.isOutOfDate)
    }

    func testAnUnreadableStartNeverCountsAsOutOfDate() {
        let executable = LiveSaverBrokerExecutable(path: directory.appending(path: "missing").path)
        XCTAssertNil(executable.started)
        XCTAssertFalse(executable.isOutOfDate)
        XCTAssertFalse(executable.isOutOfDate(current: .init(device: 1, inode: 2)))
    }
}
