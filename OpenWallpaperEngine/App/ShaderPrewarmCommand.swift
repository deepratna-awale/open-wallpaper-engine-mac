import AppKit
import Darwin

/// The app's helper runs, handled in `main.swift` before any app lifecycle starts:
/// - `--print-shader-cache-key` prints this build's `ShaderCacheKey` as one line of JSON;
/// - `--prepare-wallpapers <folders>` prepares arrived scenes the same way, and writes their
///   loading snapshots (`SceneLoadingSnapshotStore`);
/// - `--prewarm-shaders` compiles the shown and recent wallpapers into the shader caches
///   (`ShaderPrewarm`) with no UI, no Dock icon, no wallpaper windows, status item, audio capture
///   or asset installs, at background priority.
///
/// Both run in the isolated state the caller passes (`OWE_ISOLATED_STATE`), with read-only
/// defaults (`AppStorageLocation`), and exit when done.
enum ShaderPrewarmCommand {
    static let printKeyArgument = "--print-shader-cache-key"
    static let prewarmArgument = "--prewarm-shaders"
    static let prepareArgument = "--prepare-wallpapers"

    /// `--render-screensaver-loop <folder> <width>x<height> <points width>x<points height> <output>`
    /// renders a scene's loop video for the screen saver (`ScreenSaverLoopRenderer`).
    static let screenSaverArgument = "--render-screensaver-loop"

    static func isHelperRun(arguments: [String]) -> Bool {
        arguments.contains(printKeyArgument) || arguments.contains(prewarmArgument)
            || arguments.contains(prepareArgument) || arguments.contains(screenSaverArgument)
    }

    /// `<width>x<height>` as numbers, nil otherwise.
    static func size(_ text: String) -> SIMD2<Int>? {
        let parts = text.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return SIMD2(parts[0], parts[1])
    }

    @MainActor
    private static func renderScreenSaverLoop(_ arguments: ArraySlice<String>) -> Int32 {
        let values = Array(arguments)
        guard values.count >= 4, let pixels = size(values[1]), let points = size(values[2]),
              let wallpaper = InstalledLibrary.wallpaper(at: URL(filePath: values[0], directoryHint: .isDirectory), hiding: []),
              wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame else {
            OWELog.error(.app, "Screen saver: bad loop arguments \(values)")
            return 2
        }
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "owe-screensaver-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) } // Optional: a scratch folder.
        let renderer = ScreenSaverLoopRenderer(wallpaper: wallpaper, pixelSize: pixels,
                                               pointSize: SIMD2(Float(points.x), Float(points.y)),
                                               output: URL(filePath: values[3], directoryHint: .notDirectory),
                                               defaults: .app, scratchDirectory: scratch)
        return renderer.run() ? 0 : 1
    }

    /// Runs the helper `arguments` ask for and returns its exit status, or nil for a normal launch.
    @MainActor
    static func run(arguments: [String]) -> Int32? {
        if arguments.contains(printKeyArgument) {
            defer { AppStorageLocation.current.discardReadOnlyScratch() }
            do {
                FileHandle.standardOutput.write(try ShaderCacheKey.current.encoded() + Data("\n".utf8))
                return 0
            } catch {
                OWELog.error(.app, "Can't encode the shader cache key: \(error)")
                return 1
            }
        }
        if let index = arguments.firstIndex(of: screenSaverArgument) {
            defer { AppStorageLocation.current.discardReadOnlyScratch() }
            setpriority(PRIO_PROCESS, 0, 10)
            NSApplication.shared.setActivationPolicy(.prohibited)
            return renderScreenSaverLoop(arguments[(index + 1)...])
        }
        let prepareIndex = arguments.firstIndex(of: prepareArgument)
        guard arguments.contains(prewarmArgument) || prepareIndex != nil else { return nil }
        defer { AppStorageLocation.current.discardReadOnlyScratch() }
        // Background priority for the CPU work (shader translation); Metal compiles in its own
        // service. No Dock icon or menu bar: an app that is never activated.
        setpriority(PRIO_PROCESS, 0, 10)
        NSApplication.shared.setActivationPolicy(.prohibited)
        OWELog.info(.app, "Shader prewarm started (pid \(ProcessInfo.processInfo.processIdentifier))")
        let report: ShaderPrewarm.Report
        if let prepareIndex {
            let (displays, main) = ShaderPrewarmTargets.connectedDisplays()
            let display = main.flatMap { displays[$0] } ?? displays.values.first
                ?? ShaderPrewarmTargets.Display(drawableSize: SIMD2(1920, 1080), pointSize: SIMD2(1920, 1080))
            let targets = arguments[(prepareIndex + 1)...]
                .compactMap { InstalledLibrary.wallpaper(at: URL(filePath: $0, directoryHint: .isDirectory), hiding: []) }
                .filter { $0.project.type.caseInsensitiveCompare("scene") == .orderedSame }
                .map { ShaderPrewarmTargets.Target(wallpaper: $0, display: display) }
            var prepare = ShaderPrewarm(defaults: .app)
            // The picture shown while the wallpaper loads, at each display's size.
            prepare.loadingSnapshots = .current
            prepare.snapshotDisplays = displays.values.sorted { $0.drawableSize.x * $0.drawableSize.y > $1.drawableSize.x * $1.drawableSize.y }
            report = prepare.run(targets)
            // The texture blobs the loads scheduled.
            var idle = false
            PreparationPool.shared.whenIdle { idle = true }
            while !idle { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        } else {
            report = ShaderPrewarm(defaults: .app).run()
        }
        return report.wallpapers > 0 && report.failed == report.wallpapers ? 1 : 0
    }
}
