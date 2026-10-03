import XCTest
@testable import OpenWallpaperEngine

final class CrashRelaunchPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testCrashRelaunchesAndIsRecorded() {
        XCTAssertEqual(CrashRelaunchPolicy.decide(.vanished, isIsolated: false, history: [], now: now),
                       .relaunch(history: [now]))
    }

    func testCleanEndingsNeverRelaunch() {
        for ending in [CrashRelaunchPolicy.Ending.quit, .stopWatching, .watcherTerminated] {
            XCTAssertEqual(CrashRelaunchPolicy.decide(ending, isIsolated: false, history: [], now: now), .stay, "\(ending)")
        }
    }

    func testAtMostThreeRelaunchesInFiveMinutes() {
        let three = [now - 240, now - 120, now - 10]
        XCTAssertEqual(CrashRelaunchPolicy.decide(.vanished, isIsolated: false, history: three, now: now), .rateLimited)
        let two = [now - 120, now - 10]
        XCTAssertEqual(CrashRelaunchPolicy.decide(.vanished, isIsolated: false, history: two, now: now),
                       .relaunch(history: two + [now]))
    }

    func testOldRelaunchesFallOutOfTheWindow() {
        let history = [now - 400, now - 301, now - 10]
        XCTAssertEqual(CrashRelaunchPolicy.decide(.vanished, isIsolated: false, history: history, now: now),
                       .relaunch(history: [now - 10, now]))
    }

    func testIsolatedCopyNeverWatchesOrRelaunches() {
        XCTAssertFalse(CrashRelaunchPolicy.shouldWatch(enabled: true, isIsolated: true))
        XCTAssertFalse(CrashRelaunchPolicy.shouldWatch(enabled: false, isIsolated: false))
        XCTAssertTrue(CrashRelaunchPolicy.shouldWatch(enabled: true, isIsolated: false))
        XCTAssertEqual(CrashRelaunchPolicy.decide(.vanished, isIsolated: true, history: [], now: now), .stay)
    }

    @MainActor
    func testIsolatedAppNeverStartsTheWatcher() {
        let watcher = CrashWatcher(isIsolated: true)
        watcher.update(enabled: true)
        XCTAssertFalse(watcher.isRunning)
    }

    func testWatcherReadsTheAppsEnding() {
        XCTAssertEqual(CrashWatcher.ending(for: Data("quit\n".utf8)), .quit)
        XCTAssertEqual(CrashWatcher.ending(for: Data("stop\n".utf8)), .stopWatching)
        XCTAssertEqual(CrashWatcher.ending(for: Data()), .vanished, "the pipe closed with no word: a crash")
        XCTAssertEqual(CrashWatcher.ending(for: Data("qu".utf8)), .vanished)
    }

    func testWatcherSeesEOFAsACrashAndQuitAsClean() throws {
        let crashed = Pipe()
        try crashed.fileHandleForWriting.close()
        XCTAssertEqual(CrashWatcher.readEnding(from: crashed.fileHandleForReading), .vanished)

        let quit = Pipe()
        quit.fileHandleForWriting.write(Data("quit\n".utf8))
        XCTAssertEqual(CrashWatcher.readEnding(from: quit.fileHandleForReading), .quit)
    }

    func testHistoryRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = CrashRelaunchHistory(directory: directory)
        XCTAssertEqual(history.load(), [])
        history.save([now])
        XCTAssertEqual(history.load(), [now])
    }
}
