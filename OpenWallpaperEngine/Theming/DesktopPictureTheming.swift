import AppKit
import OWETheming

/// The one hook theming has in the desktop pictures OWE sets (`DesktopSnapshotCache`,
/// `LockScreenPicture`): the menu bar strip, filled with the scheme colour, drawn into each
/// display's picture after it is written and before it is shown. The menu bar is translucent over
/// the desktop picture, so the strip tints it (docs/theming.md).
enum DesktopPictureTheming {
    /// The strips for the screens about to get a picture; set by Open Wallpaper Engine's delegate
    /// at launch (`ThemingController.strips`). Nil in the Wallpaper Editor's process and in tests,
    /// where pictures stay as they are. A registration, not state: the controller owns the strips.
    @MainActor static var provider: (() -> DesktopPictureStrips?)?

    /// The strips to draw, captured on the main thread before the pictures are written.
    @MainActor
    static func strips() -> DesktopPictureStrips? { provider?() }

    /// Draws `display`'s strip into the picture at `url`, if there is one. Off the main thread.
    static func draw(_ strips: DesktopPictureStrips?, into url: URL, display: CGDirectDisplayID) {
        guard let strips else { return }
        do { try strips.apply(toFileAt: url, display: display) } catch {
            OWELog.error(.app, "Theming: drawing the menu bar strip into \(url.lastPathComponent) failed: \(error)")
        }
    }
}
