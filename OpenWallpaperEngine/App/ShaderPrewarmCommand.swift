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

    static func isHelperRun(arguments: [String]) -> Bool {
        arguments.contains(printKeyArgument) || arguments.contains(prewarmArgument)
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
        guard arguments.contains(prewarmArgument) else { return nil }
        defer { AppStorageLocation.current.discardReadOnlyScratch() }
        // Background priority for the CPU work (shader translation); Metal compiles in its own
        // service. No Dock icon or menu bar: an app that is never activated.
        setpriority(PRIO_PROCESS, 0, 10)
        NSApplication.shared.setActivationPolicy(.prohibited)
        OWELog.info(.app, "Shader prewarm started (pid \(ProcessInfo.processInfo.processIdentifier))")
        let report = ShaderPrewarm(defaults: .app).run()
        return report.wallpapers > 0 && report.failed == report.wallpapers ? 1 : 0
    }
}
