import XCTest
@testable import OpenWallpaperEngine

final class CrashReportFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "owe-crash-reports-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory) // Optional: cleanup.
    }

    /// A report in the form macOS writes: a JSON header line, then the JSON body.
    static func report(pid: Int32) -> String {
        """
        {"app_name":"Open Wallpaper Engine","bug_type":"309","name":"Open Wallpaper Engine"}
        {
          "pid" : \(pid),
          "crashReporterKey" : "SECRET",
          "exception" : {"type" : "EXC_BREAKPOINT", "signal" : "SIGTRAP"},
          "termination" : {"indicator" : "Trace/BPT trap: 5"},
          "asi" : {"libswiftCore.dylib" : ["Fatal error: Index out of range"]},
          "faultingThread" : 1,
          "usedImages" : [{"name" : "libswiftCore.dylib"}, {"name" : "OpenWallpaperEngine"}],
          "threads" : [
            {"frames" : [{"imageIndex" : 1, "symbol" : "idle()"}]},
            {"triggered" : true, "queue" : "com.apple.main-thread",
             "frames" : [{"imageIndex" : 0, "symbol" : "_assertionFailure"}, {"imageIndex" : 1, "symbol" : "SceneRenderer.draw()"},
                         {"imageIndex" : 1, "imageOffset" : 255}]}
          ]
        }
        """
    }

    private func write(_ name: String, pid: Int32, modified: Date) throws {
        let url = directory.appending(path: name)
        try Self.report(pid: pid).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func testFindsTheReportOfThatRun() throws {
        let started = Date(timeIntervalSinceNow: -600)
        try write("Open Wallpaper Engine-2026-01-01-000000.ips", pid: 10, modified: started - 60)
        try write("Open Wallpaper Engine-2026-01-01-000100.ips", pid: 11, modified: started + 60)
        try write("Open Wallpaper Engine-2026-01-01-000200.ips", pid: 12, modified: started + 120)
        try write("Wallpaper Editor-2026-01-01-000300.ips", pid: 11, modified: started + 180)

        let found = CrashReportFile.find(processName: "Open Wallpaper Engine", processIdentifier: 11, since: started, in: directory)
        XCTAssertEqual(found?.url.lastPathComponent, "Open Wallpaper Engine-2026-01-01-000100.ips")
        XCTAssertNil(CrashReportFile.find(processName: "Open Wallpaper Engine", processIdentifier: 10, since: started, in: directory),
                     "a report from before the run started")
        XCTAssertEqual(CrashReportFile.find(processName: "Open Wallpaper Engine", processIdentifier: nil, since: started, in: directory)?
            .url.lastPathComponent, "Open Wallpaper Engine-2026-01-01-000200.ips", "the newest without a pid")
    }

    func testPidMatchesWholeNumbersOnly() {
        XCTAssertTrue(CrashReportFile.names(11, in: #""pid" : 11,"#))
        XCTAssertFalse(CrashReportFile.names(11, in: #""pid" : 112,"#))
    }

    func testSummaryNamesTheExceptionAndTheCrashedThread() {
        let summary = CrashReportFile(url: directory, text: Self.report(pid: 1)).summary
        XCTAssertEqual(summary, """
            Exception: EXC_BREAKPOINT · SIGTRAP
            Termination: Trace/BPT trap: 5
            libswiftCore.dylib: Fatal error: Index out of range
            Crashed thread (com.apple.main-thread):
              0  libswiftCore.dylib  _assertionFailure
              1  OpenWallpaperEngine  SceneRenderer.draw()
              2  OpenWallpaperEngine  0xff
            """)
        XCTAssertEqual(CrashReportFile(url: directory, text: "plain text report").summary, "")
    }
}
