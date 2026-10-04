import Foundation
import OWEEditor
import OWESceneEditing

/// The app's side of the editor's previews: the cache for the WE assets in use, and the renderer
/// the browsers' provider calls, which runs this app's executable with `--render-editor-previews`
/// in this process's isolated state (`EditorPreviewRenderer` renders there), reports each preview
/// as the helper finishes it, and terminates it when the task is cancelled. The helper exits with
/// the app (`ShaderPrewarmCommand.exitWithParent`).
enum EditorPreviewHelper {
    /// The previews' cache for the WE assets in use; nil without them. Removes the previews of
    /// other builds, in the background.
    static func cache() -> EditorPreviewCache? {
        guard let assets = WallpaperEngineAssets.directory else { return nil }
        let cache = EditorPreviewCache(cachesDirectory: AppStorageLocation.current.cachesDirectory
                                           .appending(path: "Open Wallpaper Engine", directoryHint: .isDirectory),
                                       build: EditorPreviewCache.assetsBuild(of: assets))
        DispatchQueue.global(qos: .utility).async {
            do {
                try cache.prune()
            } catch {
                OWELog.error(.ui, "Editor previews: can't remove other builds' previews in \(cache.root.path): \(error)")
            }
        }
        return cache
    }

    /// The provider of the editor window's previews; nil without WE's assets.
    @MainActor
    static func provider() -> EditorPreviewProvider? {
        cache().map { EditorPreviewProvider(cache: $0, renderer: { items, finished in await render(items, finished: finished) }) }
    }

    /// Renders `items` in one helper run, reporting each as it is done.
    static func render(_ items: [EditorPreviewRenderItem], finished: @escaping @Sendable (EditorPreviewSubject) -> Void) async {
        guard !items.isEmpty, let executable = AppRelauncher.helperExecutable else { return }
        let job = EditorPreviewJob(items: items.map {
            EditorPreviewJob.Item(subject: $0.subject, outputBase: $0.outputBase.path(percentEncoded: false))
        })
        let jobFile = FileManager.default.temporaryDirectory.appending(path: "owe-editor-previews-\(UUID().uuidString).json")
        do {
            try JSONEncoder().encode(job).write(to: jobFile)
        } catch {
            OWELog.error(.ui, "Editor previews: can't write the job file \(jobFile.path): \(error)")
            return
        }
        defer { try? FileManager.default.removeItem(at: jobFile) } // Optional: the job is read at start.

        let process = Process()
        process.executableURL = executable
        process.arguments = [ShaderPrewarmCommand.editorPreviewArgument, jobFile.path(percentEncoded: false)]
        var environment = ProcessInfo.processInfo.environment
        if let tag = AppStorageLocation.current.isolationTag { environment[AppStorageLocation.environmentKey] = tag }
        process.environment = environment
        // The user is looking at the browser, but the editor stays responsive.
        process.qualityOfService = .utility
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let lines = DoneLines { index in
            guard items.indices.contains(index) else { return }
            finished(items[index].subject)
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in lines.append(handle.availableData) }
        let status: Int32? = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
                process.terminationHandler = { finished in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    OWELog.error(.ui, "Editor previews: can't start the render helper: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        if let status, status != 0 {
            OWELog.error(.ui, "Editor previews: the render helper finished with status \(status) for \(items.count) previews")
        }
    }
}

/// Splits the helper's output into lines and reports each `done` line. Reading thread only.
private final class DoneLines: @unchecked Sendable {
    private var buffer = Data()
    private let report: (Int) -> Void

    init(_ report: @escaping (Int) -> Void) { self.report = report }

    func append(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let index = EditorPreviewJob.doneIndex(fromLine: Substring(line)) { report(index) }
        }
    }
}
