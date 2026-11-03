import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One report window's state: which run it covers, the collected report, where it was saved.
@MainActor
final class ProblemReportModel: ObservableObject {
    @Published private(set) var report: ProblemReport?
    @Published private(set) var savedURL: URL?
    /// Whether the report covers the previous run, which ended without quitting.
    @Published var showsPreviousRun: Bool {
        didSet { if showsPreviousRun != oldValue { collect() } }
    }

    let uncleanExit: AppRunRecord?
    private let previousWallpapers: [ProblemReport.Wallpaper]
    private let currentWallpapers: [ProblemReport.Wallpaper]
    private let started: Date
    private var collection: Task<Void, Never>?

    /// Where Report on GitHub… saves: in the app's caches, which macOS doesn't ask permission for.
    static var folder: URL {
        AppStorageLocation.current.appCachesDirectory.appending(path: "Problem Reports", directoryHint: .isDirectory)
    }

    init(uncleanExit: AppRunRecord?, previousWallpapers: [ProblemReport.Wallpaper],
         currentWallpapers: [ProblemReport.Wallpaper], started: Date, showsPreviousRun: Bool) {
        self.uncleanExit = uncleanExit
        self.previousWallpapers = previousWallpapers
        self.currentWallpapers = currentWallpapers
        self.started = started
        self.showsPreviousRun = showsPreviousRun
    }

    func collect() {
        report = nil
        savedURL = nil
        let subject: ProblemReport.Subject
        let wallpapers: [ProblemReport.Wallpaper]
        if showsPreviousRun, let uncleanExit {
            subject = .uncleanExit(uncleanExit)
            wallpapers = previousWallpapers
        } else {
            subject = .currentRun(started: started)
            wallpapers = currentWallpapers
        }
        collection?.cancel()
        collection = Task { [weak self] in
            let report = await Task.detached(priority: .userInitiated) {
                ProblemReport.collect(subject, wallpapers: wallpapers)
            }.value
            guard !Task.isCancelled else { return }
            self?.report = report
        }
    }

    var fileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss" // l10n-ignore: a date format
        let date = formatter.string(from: report?.createdAt ?? Date())
        return "Open Wallpaper Engine problem report \(date).txt" // l10n-ignore: file name, English like the report
    }

    /// Saves the report, shows it in Finder and opens the prefilled GitHub issue to drag it into.
    func reportOnGitHub() {
        guard let report else { return }
        let url = Self.folder.appending(path: fileName, directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try write(report, to: url)
        } catch {
            OWELog.error(.app, "Can't save the problem report to \(url.path): \(error)")
            NSAlert(error: error).runModal()
            return
        }
        savedURL = url
        NSWorkspace.shared.activateFileViewerSelecting([url])
        NSWorkspace.shared.open(ProblemReportIssue.url(for: report))
    }

    func saveAs() {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try write(report, to: url)
        } catch {
            OWELog.error(.app, "Can't save the problem report to \(url.path): \(error)")
            NSAlert(error: error).runModal()
        }
    }

    func copy() {
        guard let report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.text, forType: .string)
    }

    private func write(_ report: ProblemReport, to url: URL) throws {
        try Data(report.text.utf8).write(to: url, options: .atomic)
    }
}

/// The report window: what the report holds, the report itself to read through, and the ways to
/// pass it on.
struct ProblemReportView: View {
    @ObservedObject var model: ProblemReportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The report has the app's recent log, the crash report macOS saved, and your Mac's model and macOS version. Your user name, your Mac's name and your home folder are removed. Nothing is sent: you choose where the report goes.")
                .fixedSize(horizontal: false, vertical: true)
            if model.uncleanExit != nil {
                Picker(selection: $model.showsPreviousRun) {
                    Text("Last Run").tag(true)
                    Text("This Run").tag(false)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Group {
                if let report = model.report {
                    ProblemReportTextView(text: report.text)
                } else {
                    ProgressView("Collecting logs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            if model.savedURL != nil {
                Text("The report is saved and selected in Finder. Drag it into the GitHub issue to attach it.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Copy") { model.copy() }
                Button("Save…") { model.saveAs() }
                Spacer()
                Button("Report on GitHub…") { model.reportOnGitHub() }
                    .buttonStyle(.borderedProminent)
            }
            .disabled(model.report == nil)
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 460)
    }
}

/// The report's text, read-only and selectable: an `NSTextView`, which lays out half a megabyte
/// of log without stalling the way a SwiftUI `Text` does.
private struct ProblemReportTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            textView.textContainerInset = NSSize(width: 6, height: 6)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.scrollToBeginningOfDocument(nil)
    }
}
