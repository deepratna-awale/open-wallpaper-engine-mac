import Foundation

/// The crash report macOS wrote for a run of the app (`~/Library/Logs/DiagnosticReports/<process
/// name>-<date>.ips`), and the few lines of it that say what crashed.
///
/// A hang the user force-quit, a `kill -9` and a power loss leave no report.
struct CrashReportFile: Sendable {
    let url: URL
    let text: String

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
    }

    /// The newest report of `processName` written at or after `since`; with `processIdentifier`,
    /// only one that names that process.
    static func find(processName: String, processIdentifier: Int32?, since: Date,
                     in directory: URL = defaultDirectory) -> CrashReportFile? {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        } catch {
            OWELog.error(.app, "Can't list the crash reports in \(directory.path): \(error)")
            return nil
        }
        let candidates = contents
            .filter { $0.pathExtension == "ips" && $0.lastPathComponent.hasPrefix(processName + "-") }
            .compactMap { url -> (URL, Date)? in
                // A report whose date can't be read is skipped like an older one.
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      date >= since else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
        for (url, _) in candidates {
            guard let text = OWELog.attempt(.app, "Crash report \(url.lastPathComponent)", {
                try String(contentsOf: url, encoding: .utf8)
            }) else { continue }
            if let processIdentifier, !names(processIdentifier, in: text) { continue }
            return CrashReportFile(url: url, text: text)
        }
        return nil
    }

    /// Whether the report's body says `"pid" : <processIdentifier>`.
    static func names(_ processIdentifier: Int32, in text: String) -> Bool {
        text.range(of: #""pid"\s*:\s*\#(processIdentifier)\b"#, options: .regularExpression) != nil
    }

    /// The exception, the app-specific message (a Swift fatal error's text) and the top frames of
    /// the thread that crashed; empty when the report isn't the JSON form macOS writes.
    var summary: String {
        // The first line is a JSON header; the body after it is one JSON object.
        guard let newline = text.firstIndex(of: "\n"),
              let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any]
        else { return "" } // Optional: an older plain-text report has no summary.
        var lines: [String] = []
        if let exception = body["exception"] as? [String: Any] {
            let parts = ["type", "signal", "subtype"].compactMap { exception[$0] as? String }
            if !parts.isEmpty { lines.append("Exception: " + parts.joined(separator: " · ")) }
        }
        if let termination = body["termination"] as? [String: Any], let indicator = termination["indicator"] as? String {
            lines.append("Termination: \(indicator)")
        }
        if let asi = body["asi"] as? [String: [String]] {
            for (image, messages) in asi.sorted(by: { $0.key < $1.key }) {
                for message in messages { lines.append("\(image): \(message)") }
            }
        }
        let images = (body["usedImages"] as? [[String: Any]])?.map { $0["name"] as? String ?? "?" } ?? []
        if let threads = body["threads"] as? [[String: Any]] {
            let index = body["faultingThread"] as? Int
            let thread = index.flatMap { threads.indices.contains($0) ? threads[$0] : nil }
                ?? threads.first { $0["triggered"] as? Bool == true }
            if let thread, let frames = thread["frames"] as? [[String: Any]] {
                let queue = thread["queue"] as? String ?? thread["name"] as? String
                lines.append("Crashed thread" + (queue.map { " (\($0))" } ?? "") + ":")
                for (number, frame) in frames.prefix(16).enumerated() {
                    let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0] : nil } ?? "?"
                    let symbol = frame["symbol"] as? String ?? "0x" + String(frame["imageOffset"] as? Int ?? 0, radix: 16)
                    lines.append("  \(number)  \(image)  \(symbol)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
