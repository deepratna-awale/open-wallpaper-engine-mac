import AppKit

/// What a copy of the app shows on its Dock icon, so it's never mistaken for the user's own copy:
/// a red "TEST" badge on a test or development copy running with isolated state, a blue "Dev"
/// badge on a local build (one without the release update key), nothing on a release.
enum DockBadge: Equatable {
    case none
    case test
    case dev

    static func kind(isIsolated: Bool, isReleaseBuild: Bool) -> DockBadge {
        if isIsolated { return .test }
        return isReleaseBuild ? .none : .dev
    }

    static var current: DockBadge {
        kind(isIsolated: AppStorageLocation.current.isIsolated, isReleaseBuild: AppUpdateConfiguration.main.isConfigured)
    }

    @MainActor
    func apply(to tile: NSDockTile = NSApp.dockTile) {
        switch self {
        case .none:
            tile.badgeLabel = nil
            tile.contentView = nil
        case .test:
            tile.contentView = nil
            tile.badgeLabel = "TEST"
        case .dev:
            // The system badge is always red; a blue one is drawn over the icon instead.
            tile.badgeLabel = nil
            tile.contentView = DevBadgeTileView(icon: NSApp.applicationIconImage)
        }
        tile.display()
    }
}

/// The app icon with a blue "Dev" capsule in its top-right corner.
private final class DevBadgeTileView: NSView {
    private let icon: NSImage?

    init(icon: NSImage?) {
        self.icon = icon
        super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        icon?.draw(in: bounds)
        let label: NSString = "Dev"
        let font: NSFont = .systemFont(ofSize: bounds.height * 0.2, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize: NSSize = label.size(withAttributes: attributes)
        let height: CGFloat = textSize.height * 1.15
        let width: CGFloat = max(height, textSize.width + height * 0.7)
        let capsule = NSRect(x: bounds.maxX - width - bounds.width * 0.02,
                             y: bounds.maxY - height - bounds.height * 0.02, width: width, height: height)
        let path = NSBezierPath(roundedRect: capsule, xRadius: height / 2, yRadius: height / 2)
        NSColor.systemBlue.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = bounds.width * 0.012
        path.stroke()
        label.draw(at: NSPoint(x: capsule.midX - textSize.width / 2, y: capsule.midY - textSize.height / 2),
                   withAttributes: attributes)
    }
}
