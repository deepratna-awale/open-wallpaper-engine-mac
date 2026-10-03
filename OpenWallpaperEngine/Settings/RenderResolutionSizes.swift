//
//  RenderResolutionSizes.swift
//  Open Wallpaper Engine
//

import AppKit
import Combine

/// The sizes the Render Resolution picker shows beside Display and Retina: each display's size in
/// points (what macOS lists under Displays, and what Display renders at) and its backing pixels.
struct RenderResolutionSizes: Equatable {
    struct Screen: Equatable {
        /// `NSScreen.frame.size`.
        var points: CGSize
        /// The screen's backing pixels.
        var pixels: CGSize
    }

    var screens: [Screen]

    /// "2560×1440, 1920×1080": distinct sizes, largest first.
    static func list(_ sizes: [CGSize]) -> String {
        var seen = Set<[Int]>()
        let distinct = sizes
            .map { [Int($0.width.rounded()), Int($0.height.rounded())] }
            .filter { seen.insert($0).inserted }
            .sorted { ($0[0] * $0[1], $0[0]) > ($1[0] * $1[1], $1[0]) }
        return distinct.map { "\($0[0])×\($0[1])" }.joined(separator: ", ")
    }

    var displayList: String { Self.list(screens.map(\.points)) }
    var retinaList: String { Self.list(screens.map(\.pixels)) }

    var displayLabel: String {
        String(format: String(localized: "Display (%@)", comment: "Render resolution: the display's size in points, e.g. 1920×1080"), displayList)
    }

    var retinaLabel: String {
        String(format: String(localized: "Retina (%@)", comment: "Render resolution: the display's native backing pixels, e.g. 3840×2160"), retinaList)
    }

    static var fullLabel: String {
        String(localized: "Full (wallpaper's size)", comment: "Render resolution: the wallpaper's authored size")
    }

    static func screen(_ screen: NSScreen) -> Screen {
        let points = screen.frame.size
        var pixels = CGSize(width: points.width * screen.backingScaleFactor,
                            height: points.height * screen.backingScaleFactor)
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let mode = CGDisplayCopyDisplayMode(CGDirectDisplayID(number.uint32Value)),
           mode.pixelWidth > 0, mode.pixelHeight > 0 {
            pixels = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        }
        return Screen(points: points, pixels: pixels)
    }

    static func current() -> RenderResolutionSizes {
        RenderResolutionSizes(screens: NSScreen.screens.map(screen))
    }
}

/// Keeps `RenderResolutionSizes` current as displays are added, removed or changed.
final class RenderResolutionSizesModel: ObservableObject {
    @Published private(set) var sizes = RenderResolutionSizes.current()
    private var observer: AnyCancellable?

    init() {
        observer = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                let sizes = RenderResolutionSizes.current()
                if self?.sizes != sizes { self?.sizes = sizes }
            }
    }
}
