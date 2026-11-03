import Foundation
import OWESceneEditing
import QuartzCore
import os

/// Severity-gated logging plus near-zero-cost signposts and per-frame counters.
/// Signposts are always emitted: `os_signpost` compiles to a no-op unless Instruments is recording.
enum OWELog {
    enum Severity: Int, Comparable {
        case debug = 0, info = 1, error = 2, silent = 3
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Category: String {
        case scene = "SceneVM"
        case script = "SceneScript"
        case audio = "AudioCapture"
        case shader = "ShaderTranslator"
        case importer = "Import"
        case workshop = "Workshop"
        case texture = "TEXParser"
        case perf = "Perf"
        case app = "App"
        case library = "Library"
        case web = "Web"
        case settings = "Settings"
        case ui = "UI"
    }

    private static let loggers: [Category: Logger] = Dictionary(uniqueKeysWithValues: [
        Category.scene, .script, .audio, .shader, .importer, .workshop, .texture, .perf,
        .app, .library, .web, .settings, .ui
    ].map { ($0, Logger(subsystem: "app.openwallpaperengine", category: $0.rawValue)) })

    /// Before the Log Level is applied, debug builds log lifecycle diagnostics (`.info`) too.
    nonisolated(unsafe) static var minimumSeverity: Severity = {
        #if DEBUG
        return .info
        #else
        return .error
        #endif
    }()

    /// The lowest severity a log level lets through: None logs nothing, Errors Only only errors,
    /// Verbose everything. The system's own faults still reach the unified log.
    static func threshold(for logLevel: GSLogLevel) -> Severity {
        switch logLevel {
        case .none: return .silent
        case .error: return .error
        case .verbose: return .debug
        }
    }

    /// Whether a message of `severity` is logged at `logLevel`.
    static func logs(_ severity: Severity, at logLevel: GSLogLevel) -> Bool {
        severity != .silent && severity >= threshold(for: logLevel)
    }

    /// Applies the user's Log Level. Until it is applied (early launch), debug builds log from
    /// `.info` and release builds errors.
    static func apply(logLevel: GSLogLevel) {
        minimumSeverity = threshold(for: logLevel)
        EditorLog.isEnabled = logs(.error, at: logLevel)
        OWEFrameMetrics.isReportingEnabled = (logLevel == .verbose) || OWEFrameMetrics.defaultsEnabled
    }

    static func debug(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.debug, category, message)
    }

    static func info(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.info, category, message)
    }

    static func error(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.error, category, message)
    }

    /// The app's on-disk record of its recent messages, for problem reports (`RecentLog`). Only the
    /// app's own process has one; helper runs and test hosts don't.
    private static let recentLogSink = OSAllocatedUnfairLock<RecentLog?>(initialState: nil)

    /// Starts or stops copying messages to `log`. Call once at launch.
    static func record(to log: RecentLog?) {
        recentLogSink.withLock { $0 = log }
    }

    private static func emit(_ severity: Severity,
                             _ category: Category,
                             _ message: () -> String) {
        guard severity != .silent, let logger = loggers[category] else { return }
        let logsToSystem = severity >= minimumSeverity
        // Info and errors while the Log Level isn't None, whatever it lets into the unified log.
        let recent = severity >= .info && minimumSeverity != .silent ? recentLogSink.withLock { $0 } : nil
        guard logsToSystem || recent != nil else { return }
        // Public: these messages carry paths and effect names, which the unified log would
        // otherwise redact to <private> and make useless for diagnosing a wallpaper.
        let text = message()
        if logsToSystem {
            switch severity {
            case .debug: logger.debug("\(text, privacy: .public)")
            case .info: logger.info("\(text, privacy: .public)")
            case .error: logger.error("\(text, privacy: .public)")
            case .silent: break
            }
        }
        recent?.append(severity, category, text)
    }
}
