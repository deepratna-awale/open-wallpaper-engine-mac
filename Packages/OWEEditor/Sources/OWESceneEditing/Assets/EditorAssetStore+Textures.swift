import CoreGraphics
import Foundation
import ImageIO

/// Image imports with WE's importer options (`TextureImportOptions`): a still image kept as a
/// PNG or JPEG where WE's defaults give the renderer the same texture, else written as a `.tex`
/// in the chosen format; an animated GIF or an image sequence as a sprite sheet; an MP4 as a
/// video texture (WE 2.2's video image layers); a normal map beside the image.
extension EditorAssetStore {
    /// Video files an image layer can draw (WE imports MP4 only).
    public static let videoTypes: Set<String> = ["mp4"]

    /// Imports an image (or a GIF, or an MP4) for a new image layer with the importer's options.
    public func importImage(from url: URL, options: TextureImportOptions) throws -> ImportedImage {
        let title = url.deletingPathExtension().lastPathComponent
        if Self.videoTypes.contains(url.pathExtension.lowercased()) { return try importVideo(from: url) }
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ImportError.unsupported(name)
        }
        if CGImageSourceGetCount(source) > 1 {
            return try importFrames(Self.frames(of: source, name: name), title: title, options: options)
        }
        guard var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImportError.unsupported(name) }
        let normal = try options.normalMap.map { try normalMapTexture(from: $0) }
        let cropped = options.cropTransparency ? Self.croppedToContent(image, padding: options.cropPadding) : nil
        if let cropped { image = cropped }
        let size = SIMD2(Double(image.width), Double(image.height))
        if options.keepsPicture {
            // A PNG or JPEG the importer doesn't change is the texture as it is.
            let data: Data, fileExtension: String
            if cropped == nil {
                let kept = try Self.textureData(from: url)
                data = kept.0
                fileExtension = kept.1
            } else {
                guard let png = Self.pngData(image) else { throw ImportError.unreadable(name) }
                data = png
                fileExtension = "png"
            }
            let assetName = Self.assetName(title, data: data)
            try write(data, to: "materials/editor/\(assetName).\(fileExtension)")
            return try writeImageMaterial(name: assetName, texture: "editor/\(assetName)", normalMap: try normal?(assetName),
                                          size: size, title: title)
        }
        guard let encoder else { throw ImportError.needsEncoder(name) }
        let data = try encoder.texture(image, options: options)
        let assetName = Self.assetName(title, data: data)
        try write(data, to: "materials/editor/\(assetName).tex")
        return try writeImageMaterial(name: assetName, texture: "editor/\(assetName)", normalMap: try normal?(assetName),
                                      size: size, title: title)
    }

    /// Imports images as one animated texture, in their names' order (Finder's), each shown for
    /// `options.frameDuration` (WE's Import image sequence).
    public func importImageSequence(from urls: [URL], options: TextureImportOptions) throws -> ImportedImage {
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let first = sorted.first else { throw ImportError.unsupported("") }
        var frames: [TextureImportFrame] = []
        for url in sorted {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImportError.unsupported(url.lastPathComponent) }
            frames.append(TextureImportFrame(image: image, duration: max(options.frameDuration, 0.001)))
        }
        return try importFrames(frames, title: first.deletingPathExtension().lastPathComponent, options: options)
    }

    /// Imports an MP4 as a video texture an image layer draws at the video's size.
    public func importVideo(from url: URL) throws -> ImportedImage {
        guard let encoder else { throw ImportError.needsEncoder(url.lastPathComponent) }
        let title = url.deletingPathExtension().lastPathComponent
        let (data, size) = try encoder.video(url)
        let assetName = Self.assetName(title, data: data)
        try write(data, to: "materials/editor/\(assetName).tex")
        return try writeImageMaterial(name: assetName, texture: "editor/\(assetName)", normalMap: nil, size: size, title: title)
    }

    // MARK: Pieces

    private func importFrames(_ frames: [TextureImportFrame], title: String, options: TextureImportOptions) throws -> ImportedImage {
        guard let encoder else { throw ImportError.needsEncoder(title) }
        guard let first = frames.first else { throw ImportError.unsupported(title) }
        let (data, _) = try encoder.spriteSheet(frames, options: options)
        let assetName = Self.assetName(title, data: data)
        try write(data, to: "materials/editor/\(assetName).tex")
        let normal = try options.normalMap.map { try normalMapTexture(from: $0) }
        // The layer shows one frame: its size is a frame's.
        return try writeImageMaterial(name: assetName, texture: "editor/\(assetName)", normalMap: try normal?(assetName),
                                      size: SIMD2(Double(first.image.width), Double(first.image.height)), title: title)
    }

    /// Writes the normal map once its image's name is known: `materials/editor/<name>_normal.tex`,
    /// as WE names one (`<texture>_normal`); returns a function from that name to the texture.
    private func normalMapTexture(from url: URL) throws -> (String) throws -> String {
        guard let encoder else { throw ImportError.needsEncoder(url.lastPathComponent) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImportError.unsupported(url.lastPathComponent) }
        let data = try encoder.normalMap(image)
        return { name in
            try write(data, to: "materials/editor/\(name)_normal.tex")
            return "editor/\(name)_normal"
        }
    }

    /// An animated image's frames with their delays (a GIF's unclamped delay, else its delay;
    /// WE's GIF importer reads FreeImage's frame time, and browsers show a 0 s frame for 0.1 s).
    static func frames(of source: CGImageSource, name: String) throws -> [TextureImportFrame] {
        var frames: [TextureImportFrame] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw ImportError.unreadable(name) }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double) ?? (png?[kCGImagePropertyAPNGDelayTime] as? Double)
            frames.append(TextureImportFrame(image: image, duration: delay.flatMap { $0 > 0 ? $0 : nil } ?? 0.1))
        }
        return frames
    }

    /// The image cut to the rectangle of its pixels with any alpha, grown by `padding` (within the
    /// image); nil when nothing would be cut, or when it is fully transparent.
    public static func croppedToContent(_ image: CGImage, padding: Int) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The context's rows run top to bottom in memory, as the image's do.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] != 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let pad = max(padding, 0)
        let rect = CGRect(x: max(minX - pad, 0), y: max(minY - pad, 0),
                          width: min(maxX + pad, width - 1) - max(minX - pad, 0) + 1,
                          height: min(maxY + pad, height - 1) - max(minY - pad, 0) + 1)
        guard rect.width < CGFloat(width) || rect.height < CGFloat(height) else { return nil }
        return image.cropping(to: rect)
    }
}
