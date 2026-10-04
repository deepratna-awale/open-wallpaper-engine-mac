import Foundation

/// Records a scene's loop for the Screen Saver mode and installs it: the screen saver's own loop
/// render (`ScreenSaverPlugin.runHelper`, `--render-screensaver-loop` with
/// `ShaderPrewarmCommand.screenSaverRecordingArgument`) into a staging folder, then
/// `ScreenSaverVideoInstalling.install`, which switches the saver to it at once. A failed or
/// cancelled render leaves the installed video as it was.
struct ScreenSaverRecorder: Sendable {
    /// Where renders are written before they are installed: outside the saver's folder, which the
    /// plugin prunes (`ScreenSaverVideoStore.retain`).
    let stagingDirectory: URL
    let runner: ScreenSaverPlugin.Runner
    let installer: any ScreenSaverVideoInstalling

    static var current: ScreenSaverRecorder {
        ScreenSaverRecorder(
            stagingDirectory: AppStorageLocation.current.cachesDirectory
                .appending(path: "ScreenSaverRecordings", directoryHint: .isDirectory),
            runner: { ScreenSaverPlugin.runHelper($0, $1, $2) },
            installer: ScreenSaverVideoStore.current)
    }

    /// Renders `target` of the wallpaper in `wallpaper` and installs it as `target.fileName`; true
    /// when the saver now plays it. Blocks for the whole render: call it off the main thread.
    func record(wallpaper: URL, target: ScreenSaverPlugin.Target) -> Bool {
        let name = wallpaper.lastPathComponent
        let staged = stagingDirectory.appending(path: target.fileName, directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: staged.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: staged)
            }
        } catch {
            OWELog.error(.app, "Screen saver: can't prepare the recording of \(name): \(error)")
            return false
        }
        defer { removeLeftover(staged) }
        guard runner(wallpaper, target, staged) == .rendered,
              FileManager.default.fileExists(atPath: staged.path(percentEncoded: false)) else {
            OWELog.error(.app, "Screen saver: recording \(name) failed; the installed video is unchanged")
            return false
        }
        do {
            try installer.install(staged, as: target.fileName, pixelSize: target.pixelSize)
        } catch {
            OWELog.error(.app, "Screen saver: can't install the recording of \(name): \(error)")
            return false
        }
        OWELog.info(.app, "Screen saver: recorded \(name) as \(target.fileName)")
        return true
    }

    private func removeLeftover(_ staged: URL) {
        guard FileManager.default.fileExists(atPath: staged.path(percentEncoded: false)) else { return }
        do { try FileManager.default.removeItem(at: staged) } catch {
            OWELog.error(.app, "Screen saver: can't remove \(staged.lastPathComponent): \(error)")
        }
    }
}
