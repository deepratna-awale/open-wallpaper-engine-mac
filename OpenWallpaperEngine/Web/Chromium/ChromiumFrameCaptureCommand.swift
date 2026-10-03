#if DEBUG
import CoreImage
import Foundation
import Metal

/// Debug builds only: proves frame sharing end to end without any wallpaper code.
///
///     "Open Wallpaper Engine" --chromium-capture <url> <frame count> <out.png> [<width>x<height>]
///
/// Starts the embedded helper on the installed Chromium engine, waits for `frame count` frames,
/// writes the last one to `out.png` and exits 0, or prints the reason and exits 1.
enum ChromiumFrameCaptureCommand {
    static let argument = "--chromium-capture"
    static let timeout: TimeInterval = 60

    static func run(arguments: [String]) -> Int32? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        let rest = Array(arguments[(index + 1)...])
        guard rest.count >= 3, let url = URL(string: rest[0]), let count = Int(rest[1]), count > 0 else {
            print("usage: \(argument) <url> <frame count> <out.png> [<width>x<height>]")
            return 1
        }
        let output = URL(fileURLWithPath: rest[2])
        let size = rest.count > 3 ? ShaderPrewarmCommand.size(rest[3]) : nil
        do {
            try capture(url: url, frames: count, size: size ?? SIMD2(1280, 720), to: output)
            print("Wrote \(output.path)")
            return 0
        } catch {
            print("Capture failed: \(error.localizedDescription)")
            return 1
        }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Blocks the calling thread; frames arrive on XPC's queue.
    static func capture(url: URL, frames: Int, size: SIMD2<Int>, to output: URL) throws {
        let installer = MainActor.assumeIsolated { ChromiumEngineInstaller() }
        let (install, profile) = MainActor.assumeIsolated { (installer.activeInstall, installer.profileDirectory) }
        guard let install else { throw Failure(errorDescription: "The Chromium engine isn't installed") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw Failure(errorDescription: "No Metal device") }

        let done = DispatchSemaphore(value: 0)
        let progress = CaptureProgress(wanted: frames)
        let session = ChromiumEngineSession.embedded(device: device) { frame in
            if progress.add(frame) { done.signal() }
        }
        defer { session.stop() }
        session.start(url: url, install: install, profile: profile, width: size.x, height: size.y, frameRate: 60) { error in
            guard let error else { return }
            progress.fail(error)
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            throw Failure(errorDescription: "Got \(progress.state.received) of \(frames) frames in \(Int(timeout)) s")
        }
        let state = progress.state
        if let error = state.error { throw Failure(errorDescription: error) }
        guard let frame = state.last else { throw Failure(errorDescription: "No frame") }
        try writePNG(frame.texture, to: output)
    }

    /// Frames so far, shared between XPC's queue and the waiting thread.
    private final class CaptureProgress: @unchecked Sendable {
        struct State {
            var received = 0
            var last: ChromiumFrame?
            var error: String?
        }

        private let lock = NSLock()
        private let wanted: Int
        private var stored = State()

        init(wanted: Int) { self.wanted = wanted }

        var state: State { lock.withLock { stored } }

        /// Whether this was the last frame wanted.
        func add(_ frame: ChromiumFrame) -> Bool {
            lock.withLock {
                stored.received += 1
                stored.last = frame
                return stored.received == wanted
            }
        }

        func fail(_ error: String) { lock.withLock { stored.error = error } }
    }

    static func writePNG(_ texture: MTLTexture, to output: URL) throws {
        guard let image = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]) else {
            throw Failure(errorDescription: "Can't read the frame")
        }
        // Metal's origin is top-left, Core Image's bottom-left.
        let upright = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -image.extent.height))
        try CIContext().writePNGRepresentation(of: upright, to: output, format: .RGBA8,
                                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
}
#endif
