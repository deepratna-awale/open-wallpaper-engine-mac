//
//  GifImage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import Cocoa
import SwiftUI
import ImageIO

struct GifImage: NSViewRepresentable {
    private static let imageCache = NSCache<NSString, NSImage>()

    var gifName: String?
    var gifUrl: URL?

    var isResizable: Bool = false
    var contentMode: ContentMode = .fill

    var animates: Bool

    final class Coordinator {
        var loadedKey: String?
        var loadingKey: String?
    }

    init(_ gifName: String, animates: Bool = true) {
        self.gifName = gifName
        self.animates = animates
    }

    init(contentsOf url: URL, animates: Bool = true) {
        self.gifUrl = url
        self.animates = animates
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PreviewImageView {
        let nsView = PreviewImageView()
        nsView.fills = contentMode == .fill
        nsView.wantsAnimation = animates

        loadImage(into: nsView, coordinator: context.coordinator)

        return nsView
    }

    func updateNSView(_ nsView: PreviewImageView, context: Context) {
        nsView.fills = contentMode == .fill
        nsView.wantsAnimation = animates
        loadImage(into: nsView, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PreviewImageView, context: Context) -> CGSize? {
        if !self.isResizable {
            return nsView.imageView.sizeThatFits(nsView.frame.size)
        } else {
            guard let width = proposal.width, let height = proposal.height else { return nil }
            return CGSize(width: width, height: height)
        }
    }

    /// Loads a downsampled still, or every frame once the image is to play. A paused image keeps
    /// its frames; a still is replaced when the image starts playing.
    private func loadImage(into nsView: PreviewImageView, coordinator: Coordinator) {
        let url = gifUrl ?? gifName.flatMap { Bundle.main.url(forResource: $0, withExtension: "gif") }
        guard let url else { return }
        let animatedKey = url.path + "#animated"
        if !animates, coordinator.loadedKey == animatedKey { return }
        let crops = contentMode == .fill
        let key = animates ? animatedKey : url.path + (crops ? "#still-fill" : "#still-fit")
        guard coordinator.loadedKey != key else { return }
        if let cached = Self.imageCache.object(forKey: key as NSString) {
            nsView.image = cached
            coordinator.loadedKey = key
            coordinator.loadingKey = nil
            return
        }
        guard coordinator.loadingKey != key else { return }
        coordinator.loadingKey = key
        let animated = animates
        DispatchQueue.global(qos: .userInitiated).async {
            let image: NSImage?
            if animated {
                // Uncropped: drawing a crop keeps only the first frame. The view fills instead.
                image = NSImage(contentsOf: url)
            } else {
                image = Self.downsampledImage(at: url, maxPixelSize: 512)
                    .map { crops ? Self.centeredSquareCrop($0) : $0 }
            }
            guard let image else { return }
            Self.imageCache.setObject(image, forKey: key as NSString)
            DispatchQueue.main.async {
                guard coordinator.loadingKey == key else { return }
                nsView.image = image
                coordinator.loadedKey = key
                coordinator.loadingKey = nil
            }
        }
    }

    private static func downsampledImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func centeredSquareCrop(_ image: NSImage) -> NSImage {
        let width = image.size.width
        let height = image.size.height
        guard width > height, height > 0 else { return image }
        let cropRect = NSRect(x: (width - height) / 2, y: 0, width: height, height: height)
        let cropped = NSImage(size: NSSize(width: height, height: height))
        cropped.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: cropped.size),
                   from: cropRect, operation: .copy, fraction: 1)
        cropped.unlockFocus()
        return cropped
    }

    func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: Image.ResizingMode = .stretch) -> Self {
        var view = self
        view.isResizable = true
        return view
    }

    func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> Self {
        var view = self
        view.contentMode = contentMode
        return view
    }
}

/// The image view `GifImage` shows, in a clipping container that scales it to fill (cropping the
/// overflow) or to fit. It plays only while asked to and while its window is on screen
/// (`ThumbnailAnimation.windowShows`), so the previews of a hidden or minimized window stand still.
final class PreviewImageView: NSView {
    let imageView = NSImageView()
    private var windowObservers: [NSObjectProtocol] = []

    var image: NSImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            needsLayout = true
            updateAnimation()
        }
    }

    /// Scale to fill the bounds (cropping) rather than fit inside them.
    var fills = true {
        didSet { if fills != oldValue { needsLayout = true } }
    }

    /// Whether the image is to play while its window shows.
    var wantsAnimation = false {
        didSet { if wantsAnimation != oldValue { updateAnimation() } }
    }

    /// Whether the image is playing now.
    var isAnimating: Bool { imageView.animates }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        imageView.canDrawSubviewsIntoLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = false
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func layout() {
        super.layout()
        imageView.frame = Self.imageFrame(for: imageView.image?.size, in: bounds, fills: fills)
    }

    /// The image's frame: the bounds when fitting, else the aspect-filled rect centred on them.
    static func imageFrame(for imageSize: CGSize?, in bounds: CGRect, fills: Bool) -> CGRect {
        guard fills, let size = imageSize, size.width > 0, size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers = []
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main) { [weak self] _ in self?.updateAnimation() })
            }
        }
        updateAnimation()
    }

    private func updateAnimation() {
        let plays = wantsAnimation && ThumbnailAnimation.windowShows(window)
        if imageView.animates != plays { imageView.animates = plays }
    }
}
