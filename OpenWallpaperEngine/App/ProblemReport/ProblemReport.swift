import Foundation
import Metal

/// One problem report: a plain-text file a person checks, saves and attaches to a GitHub issue.
/// Nothing is sent anywhere by the app.
///
/// It holds details of the Mac and the app, what happened, the wallpapers that were showing, the
/// crash report macOS wrote, the app's recent log (`RecentLog`) and the errors and faults the
/// system logged for the process. All of it goes through `ProblemReportRedactor` first. The text
/// is English on purpose: it is read by the maintainers, not shown as the app's UI.
struct ProblemReport: Sendable {
    /// What the report is about.
    enum Subject: Sendable {
        /// The previous run ended without quitting.
        case uncleanExit(AppRunRecord)
        /// The running app made it unresponsive, or the user just wants to report something.
        case currentRun(started: Date)
    }

    /// A wallpaper that was showing, as the report names it.
    struct Wallpaper: Sendable {
        var title: String
        var type: String
        /// The wallpaper's folder name: the Workshop id for a Workshop wallpaper.
        var folder: String
    }

    let text: String
    /// Whether the previous run ended without quitting, rather than a report from the running app.
    let isUncleanExit: Bool
    /// A short form for the GitHub issue's Logs field, which has to fit in a URL.
    let summary: String
    let createdAt: Date

    static let issueRepository = "deepratna-awale/open-wallpaper-engine-mac"

    // MARK: - Collecting

    struct Sources: Sendable {
        var processName = ProcessInfo.processInfo.processName
        var recentLogDirectory = RecentLog.defaultDirectory
        var crashReportDirectory = CrashReportFile.defaultDirectory
        var appVersion = AppVersion.current
        /// Reads the unified log; nil skips it (tests).
        var systemLog: (@Sendable (_ processIdentifier: Int32, _ start: Date, _ end: Date) -> String)? = {
            ProblemReport.systemLog(processIdentifier: $0, start: $1, end: $2)
        }
        var redactor: @Sendable () -> ProblemReportRedactor = { ProblemReportRedactor.current() }
    }

    /// Gathers everything for `subject`. Reads files and runs `log show`, so call it off the main thread.
    static func collect(_ subject: Subject, wallpapers: [Wallpaper], sources: Sources = Sources(), now: Date = Date()) -> ProblemReport {
        ThreadGuards.assertBackground("ProblemReport.collect")
        var sections: [(String, String)] = []
        sections.append(("About this Mac", about(appVersion: sources.appVersion)))

        let run: RecentLog.Run
        let processIdentifier: Int32
        let start: Date
        var end = now
        var crash: CrashReportFile?
        switch subject {
        case .uncleanExit(let record):
            run = .previous
            processIdentifier = record.processIdentifier
            start = record.started
            crash = CrashReportFile.find(processName: sources.processName, processIdentifier: record.processIdentifier,
                                         since: record.started, in: sources.crashReportDirectory)
            // About when it ended: the crash report's time, else the last thing it logged.
            let crashDate = crash.flatMap { try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            end = crashDate ?? RecentLog.lastWrite(of: .previous, in: sources.recentLogDirectory) ?? now
            sections.append(("What happened", """
                The previous run (version \(record.version), started \(record.started.formatted(.iso8601))) \
                ended without quitting: it crashed, hung and was force-quit, or the Mac restarted or lost power.
                It ended around \(end.formatted(.iso8601)).
                """))
        case .currentRun(let started):
            run = .current
            processIdentifier = ProcessInfo.processInfo.processIdentifier
            start = started
            sections.append(("What happened", "Report made from the running app (started \(started.formatted(.iso8601)))."))
        }

        let shown = wallpapers.map { "\($0.title) — \($0.type), folder \($0.folder)" }
        sections.append(("Wallpapers showing", shown.isEmpty ? "None" : shown.joined(separator: "\n")))

        let crashSummary = crash?.summary ?? ""
        if let crash {
            sections.append(("Crash report (\(crash.url.lastPathComponent))",
                             (crashSummary.isEmpty ? "" : crashSummary + "\n\n") + crash.text))
        } else if case .uncleanExit = subject {
            sections.append(("Crash report", "macOS wrote none for this run. A hang that was force-quit, a kill or a power loss leaves none."))
        }

        let appLog = RecentLog.tail(of: run, in: sources.recentLogDirectory)
        sections.append(("App log", appLog.isEmpty ? "Empty. Settings › Diagnostics › Log Level may be None." : appLog))

        if let systemLog = sources.systemLog {
            // The last minutes of the run: `log show` over a whole day of a long run is slow.
            let from = max(start, end.addingTimeInterval(-15 * 60))
            sections.append(("System log (errors and faults, \(from.formatted(.iso8601)) to \(end.formatted(.iso8601)))",
                             systemLog(processIdentifier, from, end.addingTimeInterval(60))))
        }

        let redactor = sources.redactor()
        var text = "Open Wallpaper Engine problem report\nCreated \(now.formatted(.iso8601))\n"
        for (title, body) in sections {
            text += "\n## \(title)\n\n\(body.trimmingCharacters(in: .newlines))\n"
        }
        let summary = Self.summary(crash: crashSummary, appLog: appLog)
        var isUncleanExit = false
        if case .uncleanExit = subject { isUncleanExit = true }
        return ProblemReport(text: redactor.redact(text), isUncleanExit: isUncleanExit, summary: redactor.redact(summary),
                             createdAt: now)
    }

    /// The crash's summary and the last lines of the app log, within `maxLength` characters.
    static func summary(crash: String, appLog: String, maxLength: Int = 3000) -> String {
        var parts: [String] = []
        if !crash.isEmpty { parts.append(String(crash.prefix(maxLength / 2))) }
        let room = maxLength - parts.joined().count
        var lines: [Substring] = []
        var length = 0
        for line in appLog.split(separator: "\n").reversed() {
            let clipped = line.prefix(300)
            guard length + clipped.count + 1 <= room else { break }
            lines.insert(clipped, at: 0)
            length += clipped.count + 1
        }
        if !lines.isEmpty { parts.append("Last log lines:\n" + lines.joined(separator: "\n")) }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Sources

    private static func about(appVersion: String) -> String {
        let processInfo = ProcessInfo.processInfo
        var lines = ["App: Open Wallpaper Engine \(appVersion)",
                     "macOS: \(processInfo.operatingSystemVersionString)",
                     "Mac: \(sysctlString("hw.model") ?? "unknown") (\(architecture))",
                     "Memory: \(ByteCountFormatter.string(fromByteCount: Int64(processInfo.physicalMemory), countStyle: .memory))"]
        if let device = MTLCreateSystemDefaultDevice() { lines.append("GPU: \(device.name)") }
        return lines.joined(separator: "\n")
    }

    private static var architecture: String {
        #if arch(arm64)
        return "Apple silicon"
        #else
        return "Intel"
        #endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The errors and faults the unified log kept for the process between `start` and `end`.
    static func systemLog(processIdentifier: Int32, start: Date, end: Date) -> String {
        // `log show`'s date form, in local time.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let arguments = ["show", "--style", "compact", "--start", formatter.string(from: start), "--end", formatter.string(from: end),
                         "--predicate", "processIdentifier == \(processIdentifier) AND (messageType == error OR messageType == fault)"]
        let run = ProcessRunner.runProcess(executable: URL(filePath: "/usr/bin/log"), arguments: arguments, standardInput: Data(),
                                           timeout: 60, cancellation: ProcessCancellation(), onOutput: { _ in })
        guard run.exitCode == 0 else {
            OWELog.error(.app, "Problem report: log show failed (\(run.exitCode)): \(run.output.prefix(300))")
            return "Unavailable (log show ended with \(run.exitCode)): \(run.output.prefix(300))"
        }
        // Keep the last 256 KB; the start of a noisy run matters least.
        let output = run.output
        return output.count > 256 * 1024 ? String(output.suffix(256 * 1024)) : output
    }
}
