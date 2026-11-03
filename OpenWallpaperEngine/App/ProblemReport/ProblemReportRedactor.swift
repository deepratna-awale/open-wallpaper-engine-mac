import Foundation

/// Takes what identifies the person out of a problem report before anyone sees it: the home
/// folder (paths become `~/…`), the account's short and full name, the Mac's name, email
/// addresses, and the per-Mac identifiers macOS writes into crash reports.
///
/// Wallpaper titles, Workshop ids and paths inside the library stay: they are what a report is for.
struct ProblemReportRedactor: Sendable {
    var homeDirectory: String
    /// Replaced wherever they appear as a word; names shorter than 3 characters are left alone,
    /// since they would match inside ordinary words.
    var names: [String]

    static let userPlaceholder = "<user>"
    static let removedPlaceholder = "<removed>"

    /// The keys of crash-report fields that identify the Mac or its owner, not the crash.
    static let identifyingKeys = ["crashReporterKey", "sleepWakeUUID", "bootSessionUUID", "deviceIdentifierForVendor",
                                  "deviceIdentifierForAdvertising", "userID", "rolloutId", "experimentId"]

    /// This Mac's user and names. Reads the computer name, so call it off the main thread.
    static func current() -> ProblemReportRedactor {
        var names = [NSUserName(), NSFullUserName()]
        if let computer = Host.current().localizedName { names.append(computer) }
        let host = ProcessInfo.processInfo.hostName
        names.append(host)
        if let short = host.split(separator: ".").first { names.append(String(short)) }
        return ProblemReportRedactor(homeDirectory: NSHomeDirectory(), names: names)
    }

    func redact(_ text: String) -> String {
        var text = text
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        if home.count > 1 {
            // Not inside a longer name: /Users/dee must leave /Users/deep alone.
            text = Self.replace(NSRegularExpression.escapedPattern(for: home) + #"(?![\p{L}\p{N}_-])"#, in: text, with: "~")
        }
        // Longest first, so a full name goes before a short name inside it.
        for name in Set(names).filter({ $0.count >= 3 }).sorted(by: { $0.count > $1.count }) {
            let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\p{L}\p{N}_])"#
            text = Self.replace(pattern, in: text, with: NSRegularExpression.escapedTemplate(for: Self.userPlaceholder),
                                options: .caseInsensitive)
        }
        text = Self.replace(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: text, with: "<email>")
        let keys = Self.identifyingKeys.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        text = Self.replace(#"("(?:"# + keys + #")"\s*:\s*)"[^"]*""#, in: text, with: "$1\"\(Self.removedPlaceholder)\"")
        return text
    }

    private static func replace(_ pattern: String, in text: String, with template: String,
                                options: NSRegularExpression.Options = []) -> String {
        // The patterns are built from escaped literals, so they always compile.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
