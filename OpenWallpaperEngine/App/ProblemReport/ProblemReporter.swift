import AppKit
import SwiftUI

/// Report a Problem: after a run that ended without quitting, the next launch offers a report
/// with the logs from just before it; Help › Report a Problem… and Settings › Diagnostics make
/// one any time.
///
/// - `beginRun()` keeps the last run's log (`RecentLog`) and checks the run record
///   (`AppRunRecord`) the last run should have removed when it quit.
/// - The report (`ProblemReport`) is collected only when the window opens, shown in full, and
///   leaves the Mac only when the person saves it or attaches it to the GitHub issue the window
///   opens. Nothing is sent by the app.
@MainActor
final class ProblemReporter {
    /// The previous run, when it ended without quitting.
    private(set) var uncleanExit: AppRunRecord?
    /// What the previous run was showing when it ended, from safe restart.
    var previousWallpapers: [ProblemReport.Wallpaper] = []
    /// What is showing now.
    var currentWallpapers: () -> [ProblemReport.Wallpaper] = { [] }

    let started = Date()
    private let store: AppRunRecordStore
    private let recentLog: RecentLog
    private var notice: SafeRestartNotice?
    private var window: NSWindow?

    init(store: AppRunRecordStore = AppRunRecordStore(), recentLog: RecentLog = RecentLog(directory: RecentLog.defaultDirectory)) {
        self.store = store
        self.recentLog = recentLog
    }

    // MARK: - Lifecycle hooks

    /// Call first thing at launch.
    func beginRun() {
        recentLog.startRun()
        OWELog.record(to: recentLog)
        uncleanExit = store.load()
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        store.save(AppRunRecord(processIdentifier: processIdentifier, started: started, version: AppVersion.current))
        OWELog.info(.app, "Open Wallpaper Engine \(AppVersion.current) started (pid \(processIdentifier))")
        if let uncleanExit {
            OWELog.info(.app, "The previous run (pid \(uncleanExit.processIdentifier), started \(uncleanExit.started)) ended without quitting")
        }
    }

    /// Call from `applicationWillTerminate`.
    func applicationWillTerminate() {
        OWELog.info(.app, "Quitting")
        store.clear()
    }

    /// Call once the app has finished launching: after an unclean exit, a notice offers a report.
    /// `offeredElsewhere` when safe restart's notice already carries the offer.
    func showPendingNotice(offeredElsewhere: Bool) {
        guard uncleanExit != nil, !offeredElsewhere else { return }
        notice = SafeRestartNotice(message: String(localized: "Open Wallpaper Engine quit unexpectedly last time."),
                                   onRetry: nil,
                                   onReport: { [weak self] in
                                       self?.closeNotice()
                                       self?.showReport(previousRun: true)
                                   },
                                   onDismiss: { [weak self] in self?.closeNotice() })
        notice?.show()
    }

    private func closeNotice() {
        notice?.close()
        notice = nil
    }

    // MARK: - The report window

    /// Opens the report window, on the previous run when it ended without quitting and
    /// `previousRun` asks for it, else on this run.
    func showReport(previousRun: Bool = false) {
        closeNotice()
        let model = ProblemReportModel(uncleanExit: uncleanExit, previousWallpapers: previousWallpapers,
                                       currentWallpapers: currentWallpapers(), started: started,
                                       showsPreviousRun: previousRun && uncleanExit != nil)
        let window = window ?? makeWindow()
        window.contentView = NSHostingView(rootView: ProblemReportView(model: model).appAccentTint())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        model.collect()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = String(localized: "Report a Problem")
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

extension ProblemReport.Wallpaper {
    init(_ wallpaper: WEWallpaper) {
        self.init(title: wallpaper.project.title, type: wallpaper.project.type,
                  folder: wallpaper.wallpaperDirectory.lastPathComponent)
    }
}
