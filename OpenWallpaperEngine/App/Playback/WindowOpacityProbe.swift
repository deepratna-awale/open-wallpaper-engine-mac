import CoreGraphics
import Foundation
import ScreenCaptureKit

/// "Check for see-through windows": where the windows covering a display let the wallpaper show
/// through (a terminal with a see-through background), so that display keeps drawing. The window
/// list can't tell: such a window reports an alpha of 1, and only its pixels say otherwise.
///
/// Each window is captured on its own (ScreenCaptureKit's single-window screenshot, without
/// shadow or cursor) at `WindowOpacityMask.longSide` pixels along its longer side, drawn into an
/// alpha-only buffer and dropped: only the coarse opacity grid is kept, in memory, never written
/// or logged, and nothing outside this object can reach it. It runs only while a display is
/// covered and Screen Recording is already allowed (it never asks), one window batch at a time,
/// and a window's grid is reused until it is resized or `refreshInterval` passes.
final class WindowOpacityProbe: @unchecked Sendable {
    /// How long a window's grid is trusted before it is captured again.
    static let refreshInterval: TimeInterval = 5

    private struct Entry {
        var size: CGSize
        var mask: WindowOpacityMask?
        var captured: Date
    }

    // `lock` guards `entries` and `capturing`.
    private let lock = NSLock()
    private var entries: [CGWindowID: Entry] = [:]
    private var capturing = false
    private let capture: @Sendable ([DesktopWindow]) async -> [CGWindowID: WindowOpacityMask]

    /// `capture` takes the snapshots; tests pass their own.
    init(capture: @escaping @Sendable ([DesktopWindow]) async -> [CGWindowID: WindowOpacityMask] = { await WindowOpacityProbe.captureMasks(of: $0) }) {
        self.capture = capture
    }

    /// The grids known for `windows`; windows not seen before, resized, or captured too long ago
    /// are captured in the background, and the next call sees the result. Windows no longer
    /// asked about are forgotten. Any thread.
    func masks(for windows: [DesktopWindow], now: Date = Date()) -> [CGWindowID: WindowOpacityMask] {
        let windows = windows.filter { $0.id != 0 }
        let asked = Set(windows.map(\.id))
        var masks: [CGWindowID: WindowOpacityMask] = [:]
        var stale: [DesktopWindow] = []
        let starts: Bool = lock.withLock {
            entries = entries.filter { asked.contains($0.key) }
            for window in windows {
                if let entry = entries[window.id], entry.size == window.bounds.size {
                    if let mask = entry.mask { masks[window.id] = mask }
                    if now.timeIntervalSince(entry.captured) >= Self.refreshInterval { stale.append(window) }
                } else {
                    stale.append(window)
                }
            }
            guard !stale.isEmpty, !capturing else { return false }
            capturing = true
            return true
        }
        if starts { start(stale) }
        return masks
    }

    private func start(_ windows: [DesktopWindow]) {
        let capture = capture
        Task.detached(priority: .utility) { [self] in
            let masks = await capture(windows)
            let now = Date()
            lock.withLock {
                for window in windows {
                    entries[window.id] = Entry(size: window.bounds.size, mask: masks[window.id], captured: now)
                }
                capturing = false
            }
        }
    }

    /// Captures each of `windows` and reduces it to its grid. Empty without Screen Recording.
    static func captureMasks(of windows: [DesktopWindow]) async -> [CGWindowID: WindowOpacityMask] {
        guard CGPreflightScreenCaptureAccess() else { return [:] }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            OWELog.error(.app, "See-through window check: the windows can't be listed: \(error)")
            return [:]
        }
        let shareable = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var masks: [CGWindowID: WindowOpacityMask] = [:]
        for window in windows {
            // Optional: the window may have closed since the window list was read.
            guard let target = shareable[window.id] else { continue }
            let grid = WindowOpacityMask.gridSize(for: window.bounds.size)
            let configuration = SCStreamConfiguration()
            configuration.width = grid.columns
            configuration.height = grid.rows
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.backgroundColor = .clear
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.capturesAudio = false
            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
                masks[window.id] = WindowOpacityMask(image: image, columns: grid.columns, rows: grid.rows)
            } catch {
                OWELog.debug(.app, "See-through window check: window \(window.id) can't be captured: \(error)")
            }
        }
        return masks
    }
}
