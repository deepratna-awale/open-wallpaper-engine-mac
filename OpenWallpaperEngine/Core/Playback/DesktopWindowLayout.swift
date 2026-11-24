import CoreGraphics

/// A window as the window server lists it (`CGWindowListCopyWindowInfo`), in its front-to-back
/// order. `bounds` is in global display coordinates: origin at the top left of the main display,
/// y down.
struct DesktopWindow: Equatable {
    var ownerPID: pid_t
    var bounds: CGRect
    /// The window level (`kCGWindowLayer`); 0 is an application's normal window.
    var layer = 0
    var alpha: Double = 1
    /// On screen in the current Space of its display; minimized windows, hidden apps' windows and
    /// windows on other Spaces aren't.
    var isOnScreen = true
    /// Its owner is an application with a Dock icon. Menu bar extras and background agents (window
    /// borders, display utilities) draw overlay windows at the normal level too, but aren't an
    /// application the rules mean.
    var ownerIsApplication = true
    /// The window server's number for it (`kCGWindowNumber`); 0 when unknown.
    var id: CGWindowID = 0
}

/// A display in the same coordinates as `DesktopWindow.bounds`.
struct DesktopDisplay: Equatable {
    /// The display's id (`WallpaperViewModel.screenId(for:)`).
    var id: String
    var frame: CGRect
    /// The frame without the menu bar and the Dock.
    var visibleFrame: CGRect
}

/// What the playback rules that watch windows see on one display.
struct DisplayConditions: Equatable {
    /// The frontmost application's front window is on this display ("Other application focused").
    var focused = false
    /// Another application's window fills the display's visible area, as a zoomed window does
    /// ("Other application maximized").
    var maximized = false
    /// Another application's window covers the whole display, as a native full-screen Space or a
    /// borderless full-screen game does ("Other application fullscreen").
    var fullscreen = false
    /// The bundle identifier of the application whose window is focused here (Application Rules'
    /// "is focused").
    var focusedApplication: String?
    /// The bundle identifiers of the applications with a window covering this whole display
    /// (Application Rules' "is fullscreen").
    var fullscreenApplications: Set<String> = []
    /// The bundle identifiers of the applications with a window filling this display's visible
    /// area but not the whole display (Application Rules' "is maximized").
    var maximizedApplications: Set<String> = []
}

/// Which display each window belongs to, and what that means for the playback rules.
///
/// WE (Windows) asks `MonitorFromWindow` for the display of the foreground window and of the
/// visible windows it enumerates; here a window belongs to the display it overlaps most, ties
/// going to the display listed first (the main display comes first). A window spanning two
/// displays belongs to one of them only, as it does in WE.
///
/// Only applications' normal windows (level 0) count: the menu bar, status items, the Dock,
/// notifications, floating panels and other overlays don't, nor do windows of background agents
/// and menu bar extras, invisible or tiny helper windows, the app's own windows, or windows that
/// aren't on screen (minimized, hidden, or on another Space).
enum DesktopWindowLayout {
    /// Windows narrower or lower than this are helper windows, not an application's window.
    static let minimumSide: CGFloat = 32
    /// How much of the visible area a window has to cover to count as maximized. Leaves room for
    /// the margins macOS puts around tiled windows.
    static let maximizedCoverage: CGFloat = 0.95
    /// Slack when checking that a window covers the whole display, for fractional-point frames.
    static let fullscreenTolerance: CGFloat = 1

    /// The display `bounds` overlaps most; nil when it is on none.
    static func display(of bounds: CGRect, in displays: [DesktopDisplay]) -> DesktopDisplay? {
        var best: (display: DesktopDisplay, area: CGFloat)?
        for display in displays {
            let area = overlap(bounds, display.frame)
            // Strictly larger: on a tie the display listed first keeps it.
            if area > 0, area > (best?.area ?? 0) { best = (display, area) }
        }
        return best?.display
    }

    /// Whether the rules may look at `window`.
    static func counts(_ window: DesktopWindow, ignoring ignoredPIDs: Set<pid_t>) -> Bool {
        window.isOnScreen && window.ownerIsApplication && window.layer == 0 && window.alpha > 0
            && window.bounds.width >= minimumSide && window.bounds.height >= minimumSide
            && !ignoredPIDs.contains(window.ownerPID)
    }

    /// Each display's conditions. `windows` are front to back; `frontmostPID` is the active
    /// application, nil when it is the desktop (Finder) or this app; `ignoredPIDs` are this app's;
    /// `bundleIdentifiers` names the applications the application rules mention, by process.
    /// Every display in `displays` gets an entry.
    static func conditions(windows: [DesktopWindow], displays: [DesktopDisplay], frontmostPID: pid_t?,
                           ignoredPIDs: Set<pid_t>,
                           bundleIdentifiers: [pid_t: String] = [:]) -> [String: DisplayConditions] {
        var result: [String: DisplayConditions] = [:]
        for display in displays { result[display.id] = DisplayConditions() }
        var focusFound = false
        for window in windows where counts(window, ignoring: ignoredPIDs) {
            guard let display = display(of: window.bounds, in: displays) else { continue }
            var conditions = result[display.id] ?? DisplayConditions()
            if !focusFound, let frontmostPID, window.ownerPID == frontmostPID, !ignoredPIDs.contains(frontmostPID) {
                // The frontmost application's front window: the one it has focused.
                focusFound = true
                conditions.focused = true
                conditions.focusedApplication = bundleIdentifiers[window.ownerPID]
            }
            let application = bundleIdentifiers[window.ownerPID]
            if coversFrame(window.bounds, of: display) {
                conditions.fullscreen = true
                if let application { conditions.fullscreenApplications.insert(application) }
            } else if coversVisibleArea(window.bounds, of: display) {
                conditions.maximized = true
                if let application { conditions.maximizedApplications.insert(application) }
            }
            result[display.id] = conditions
        }
        return result
    }

    /// How much of a display's visible area windows have to hide for its wallpaper to count as
    /// covered: what still shows (the gaps between tiled windows) is a sliver.
    static let coveredShare: CGFloat = 0.97

    /// The displays whose visible area (the menu bar and Dock left out) applications' windows,
    /// this app's included, hide all but a sliver of (`coveredShare`), together or alone. Such a
    /// display's wallpaper can't be seen, so it needn't draw new frames. Unlike the window
    /// server's occlusion state, which counts the gaps between windows and the translucent menu
    /// bar as showing the wallpaper, this holds for a display tiled with several windows.
    static func coveredDisplays(windows: [DesktopWindow], displays: [DesktopDisplay]) -> Set<String> {
        let shown = windows.filter { counts($0, ignoring: []) }.map(\.bounds)
        guard !shown.isEmpty else { return [] }
        var covered: Set<String> = []
        for display in displays {
            let visible = display.visibleFrame
            let visibleArea = visible.width * visible.height
            guard visibleArea > 0 else { continue }
            let parts = shown.map { $0.intersection(visible) }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
            if unionArea(parts) >= coveredShare * visibleArea { covered.insert(display.id) }
        }
        return covered
    }

    /// Points sampled along the longer side of a display's visible area when windows' opacity is
    /// known (`coveredDisplays(windows:displays:opacity:)`).
    static let coverageSamples = 128

    /// The windows `coveredDisplays` counts that overlap the visible area of one of `displays`.
    static func coveringWindows(_ windows: [DesktopWindow], on displays: [DesktopDisplay]) -> [DesktopWindow] {
        windows.filter { window in
            counts(window, ignoring: []) && displays.contains { overlap(window.bounds, $0.visibleFrame) > 0 }
        }
    }

    /// `coveredDisplays`, knowing where some windows are see-through (`opacity`, by window
    /// number): the wallpaper shows at a point unless some window is opaque there, so the order
    /// of the windows doesn't matter. A window missing from `opacity` hides all it covers. The
    /// visible area is sampled on a grid of `coverageSamples` points along its longer side.
    static func coveredDisplays(windows: [DesktopWindow], displays: [DesktopDisplay],
                                opacity: [CGWindowID: WindowOpacityMask]) -> Set<String> {
        guard !opacity.isEmpty else { return coveredDisplays(windows: windows, displays: displays) }
        let shown = windows.filter { counts($0, ignoring: []) }
        var covered: Set<String> = []
        for display in displays {
            let visible = display.visibleFrame
            guard visible.width > 0, visible.height > 0 else { continue }
            let onDisplay = shown.filter { overlap($0.bounds, visible) > 0 }
            guard !onDisplay.isEmpty else { continue }
            let scale = CGFloat(coverageSamples) / max(visible.width, visible.height)
            let columns = max(1, Int((visible.width * scale).rounded()))
            let rows = max(1, Int((visible.height * scale).rounded()))
            var hidden = 0
            for row in 0..<rows {
                let y = visible.minY + (CGFloat(row) + 0.5) * visible.height / CGFloat(rows)
                for column in 0..<columns {
                    let point = CGPoint(x: visible.minX + (CGFloat(column) + 0.5) * visible.width / CGFloat(columns), y: y)
                    if onDisplay.contains(where: { hides($0, at: point, opacity: opacity) }) { hidden += 1 }
                }
            }
            if CGFloat(hidden) >= coveredShare * CGFloat(columns * rows) { covered.insert(display.id) }
        }
        return covered
    }

    /// Whether `window` hides the wallpaper at `point`.
    private static func hides(_ window: DesktopWindow, at point: CGPoint,
                              opacity: [CGWindowID: WindowOpacityMask]) -> Bool {
        let bounds = window.bounds
        guard bounds.contains(point) else { return false }
        guard let mask = opacity[window.id] else { return true }
        return mask.isOpaque(atUnit: CGPoint(x: (point.x - bounds.minX) / bounds.width,
                                             y: (point.y - bounds.minY) / bounds.height))
    }

    /// The area `rects` cover together: the sum, over the vertical strips between their edges, of
    /// the merged lengths of the rects crossing each strip.
    static func unionArea(_ rects: [CGRect]) -> CGFloat {
        let edges = Set(rects.flatMap { [$0.minX, $0.maxX] }).sorted()
        var area: CGFloat = 0
        for (left, right) in zip(edges, edges.dropFirst()) {
            let spans = rects.filter { $0.minX <= left && $0.maxX >= right }
                .map { ($0.minY, $0.maxY) }.sorted { $0.0 < $1.0 }
            var length: CGFloat = 0
            var current: (CGFloat, CGFloat)?
            for span in spans {
                if let open = current, span.0 <= open.1 {
                    current = (open.0, max(open.1, span.1))
                } else {
                    if let open = current { length += open.1 - open.0 }
                    current = span
                }
            }
            if let open = current { length += open.1 - open.0 }
            area += length * (right - left)
        }
        return area
    }

    /// `bounds` covers the whole display, menu bar included.
    static func coversFrame(_ bounds: CGRect, of display: DesktopDisplay) -> Bool {
        bounds.insetBy(dx: -fullscreenTolerance, dy: -fullscreenTolerance).contains(display.frame)
    }

    /// `bounds` covers (nearly) all of the display's visible area.
    static func coversVisibleArea(_ bounds: CGRect, of display: DesktopDisplay) -> Bool {
        let visible = display.visibleFrame
        let visibleArea = visible.width * visible.height
        guard visibleArea > 0 else { return false }
        return overlap(bounds, visible) >= maximizedCoverage * visibleArea
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
