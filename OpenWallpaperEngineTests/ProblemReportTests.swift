import XCTest
@testable import OpenWallpaperEngine

final class ProblemReportTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "owe-problem-report-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "Crashes"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root) // Optional: cleanup.
    }

    private var sources: ProblemReport.Sources {
        var sources = ProblemReport.Sources()
        sources.processName = "Open Wallpaper Engine"
        sources.recentLogDirectory = root.appending(path: "Logs")
        sources.crashReportDirectory = root.appending(path: "Crashes")
        sources.appVersion = "1.0.0-test"
        sources.systemLog = nil
        let home = root.path
        sources.redactor = { ProblemReportRedactor(homeDirectory: home, names: ["Jane Doe"]) }
        return sources
    }

    /// Collects off the main thread, as the app does.
    private func collect(_ subject: ProblemReport.Subject, wallpapers: [ProblemReport.Wallpaper] = []) async -> ProblemReport {
        let sources = sources
        return await Task.detached { ProblemReport.collect(subject, wallpapers: wallpapers, sources: sources) }.value
    }

    func testAfterACrashTheReportHasTheLastRunsLogAndCrashReport() async throws {
        let log = RecentLog(directory: root.appending(path: "Logs"))
        log.startRun()
        log.append(.info, .app, "Applying wallpaper from \(root.path)/Wallpapers/123")
        log.append(.error, .shader, "Jane Doe's shader failed")
        RecentLog(directory: root.appending(path: "Logs")).startRun() // The launch after the crash.

        let started = Date(timeIntervalSinceNow: -300)
        try CrashReportFileTests.report(pid: 4242)
            .write(to: root.appending(path: "Crashes/Open Wallpaper Engine-2026-01-01-000000.ips"), atomically: true, encoding: .utf8)
        let record = AppRunRecord(processIdentifier: 4242, started: started, version: "1.0.0-beta.15")
        let report = await collect(.uncleanExit(record),
                                   wallpapers: [ProblemReport.Wallpaper(title: "Forest", type: "scene", folder: "2345678901")])

        XCTAssertTrue(report.isUncleanExit)
        XCTAssertTrue(report.text.contains("App: Open Wallpaper Engine 1.0.0-test"))
        XCTAssertTrue(report.text.contains("ended without quitting"))
        XCTAssertTrue(report.text.contains("Forest — scene, folder 2345678901"))
        XCTAssertTrue(report.text.contains("## Crash report (Open Wallpaper Engine-2026-01-01-000000.ips)"))
        XCTAssertTrue(report.text.contains("Exception: EXC_BREAKPOINT · SIGTRAP"))
        XCTAssertTrue(report.text.contains("Applying wallpaper from ~/Wallpapers/123"), "the home folder is removed")
        XCTAssertTrue(report.text.contains("<user>'s shader failed"))
        XCTAssertFalse(report.text.contains("Jane Doe"))
        XCTAssertFalse(report.text.contains("SECRET"), "the crash reporter key is removed")
        XCTAssertTrue(report.summary.hasPrefix("Exception: EXC_BREAKPOINT"))
        XCTAssertTrue(report.summary.contains("<user>'s shader failed"))
    }

    func testWithoutACrashReportTheReportSaysSo() async {
        let record = AppRunRecord(processIdentifier: 99, started: Date(timeIntervalSinceNow: -60), version: "1")
        let report = await collect(.uncleanExit(record))
        XCTAssertTrue(report.text.contains("macOS wrote none for this run"))
        XCTAssertTrue(report.text.contains("Wallpapers showing\n\nNone"))
    }

    func testAReportFromTheRunningAppUsesThisRunsLog() async {
        let log = RecentLog(directory: root.appending(path: "Logs"))
        log.startRun()
        log.append(.info, .app, "this run")
        let report = await collect(.currentRun(started: Date()))
        XCTAssertFalse(report.isUncleanExit)
        XCTAssertTrue(report.text.contains("I App: this run"))
        XCTAssertFalse(report.text.contains("## Crash report"))
    }

    func testSummaryKeepsTheNewestLinesWithinItsLength() {
        let log = (0..<500).map { "line \($0)" }.joined(separator: "\n")
        let summary = ProblemReport.summary(crash: "Exception: X", appLog: log, maxLength: 200)
        XCTAssertLessThanOrEqual(summary.count, 240)
        XCTAssertTrue(summary.hasPrefix("Exception: X"))
        XCTAssertTrue(summary.hasSuffix("line 499"))
    }

    func testIssueURLFillsTheBugReportFormAndFits() throws {
        let long = String(repeating: "frame with a long symbol name\n", count: 2000)
        let report = ProblemReport(text: "", isUncleanExit: true, summary: long, createdAt: Date())
        let url = ProblemReportIssue.url(for: report, macOSVersion: "Version 26.1", appVersion: "1.0.0-beta.15")
        XCTAssertLessThanOrEqual(url.absoluteString.count, ProblemReportIssue.maxURLLength)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.path, "/deepratna-awale/open-wallpaper-engine-mac/issues/new")
        XCTAssertEqual(fields["template"], "bug_report.yml")
        XCTAssertEqual(fields["macos"], "Version 26.1")
        XCTAssertEqual(fields["owe"], "1.0.0-beta.15")
        XCTAssertEqual(fields["type"], "Not wallpaper-specific")
        XCTAssertTrue(fields["logs"]?.hasPrefix("frame with a long symbol name") == true)
        XCTAssertEqual(fields["title"], "Crash: ")
    }

    /// The issue form's field ids and dropdown option the URL fills must stay in the template.
    func testBugReportTemplateHasTheFilledFields() throws {
        let template = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".github/ISSUE_TEMPLATE/bug_report.yml")
        let text = try String(contentsOf: template, encoding: .utf8)
        for id in ["what", "logs", "macos", "owe", "type"] {
            XCTAssertTrue(text.contains("id: \(id)\n"), "bug_report.yml has no field \(id)")
        }
        XCTAssertTrue(text.contains("Not wallpaper-specific"))
    }
}
