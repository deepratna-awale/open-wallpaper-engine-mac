import AppKit
import Darwin

/// The app's helper runs, handled in `main.swift` before any app lifecycle starts:
/// - `--print-shader-cache-key` prints this build's `ShaderCacheKey` as one line of JSON;
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

    static func isHelperRun(arguments: [String]) -> Bool {
        arguments.contains(printKeyArgument) || arguments.contains(prewarmArgument)
            || arguments.contains(prepareArgument)
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
            report = ShaderPrewarm(defaults: .app).run(targets)
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
