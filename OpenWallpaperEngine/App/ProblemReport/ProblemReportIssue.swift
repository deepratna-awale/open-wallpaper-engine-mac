import Foundation

/// The GitHub issue a problem report opens: the repository's bug report form
/// (`.github/ISSUE_TEMPLATE/bug_report.yml`) with its fields filled in through the URL. The full
/// report is too long for a URL, so the Logs field gets the report's summary, and the description
/// asks for the saved file: the Logs field renders as code and takes no attachments.
enum ProblemReportIssue {
    /// GitHub refuses longer URLs (414); the encoded summary is shortened until the URL fits.
    static let maxURLLength = 7500

    static func url(for report: ProblemReport, macOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
                    appVersion: String = AppVersion.current) -> URL {
        var summary = report.summary
        while true {
            let candidate = Self.url(fields: [
                ("template", "bug_report.yml"),
                ("title", report.isUncleanExit ? "Crash: " : ""),
                ("type", "Not wallpaper-specific"),
                ("what", "What I was doing:\n\n\nProblem report: (drag the saved .txt file here)\n"),
                ("logs", summary),
                ("macos", macOSVersion),
                ("owe", appVersion),
            ])
            if candidate.absoluteString.count <= maxURLLength || summary.isEmpty { return candidate }
            // Drop from the end: the crash summary comes first and matters most.
            summary = String(summary.prefix(summary.count * 3 / 4))
        }
    }

    private static func url(fields: [(String, String)]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(ProblemReport.issueRepository)/issues/new"
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        // `+` would read as a space in a query.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        // Always valid: fixed scheme, host and path.
        return components.url!
    }
}
