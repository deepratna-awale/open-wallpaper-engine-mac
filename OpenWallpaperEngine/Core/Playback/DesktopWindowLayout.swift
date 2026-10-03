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
    /// The bundle identifiers of the applications with a window filling this display, full screen
    /// or maximized (Application Rules' "is fullscreen").
    var fillingApplications: Set<String> = []
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
            var fills = true
            if coversFrame(window.bounds, of: display) {
                conditions.fullscreen = true
            } else if coversVisibleArea(window.bounds, of: display) {
                conditions.maximized = true
            } else {
                fills = false
            }
            if fills, let application = bundleIdentifiers[window.ownerPID] {
                conditions.fillingApplications.insert(application)
            }
            result[display.id] = conditions
        }
        return result
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
