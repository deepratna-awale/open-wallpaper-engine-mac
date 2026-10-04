import CoreGraphics
import Foundation
import ImageIO

/// The main colour of a picture, for a wallpaper without a scheme colour: k-means in OKLab over a
/// small copy of it, the largest cluster's mean. Deterministic; call it off the main thread.
public enum DominantColor {
    /// The side of the square the picture is reduced to: 1 024 samples.
    public static let sampleSide = 32
    public static let clusterCount = 5
    public static let iterations = 8

    /// The main colour of the picture file at `url`; nil when it can't be read.
    public static func of(fileAt url: URL) -> ThemeColor? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceThumbnailMaxPixelSize: 256] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return of(image)
    }

    /// The main colour of `image`; nil when it can't be drawn.
    public static func of(_ image: CGImage) -> ThemeColor? {
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var colors: [ThemeColor] = []
        colors.reserveCapacity(side * side)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            colors.append(ThemeColor(red: Double(pixels[index]) / 255, green: Double(pixels[index + 1]) / 255,
                                     blue: Double(pixels[index + 2]) / 255))
        }
        return dominant(of: colors)
    }

    /// The mean of the largest k-means cluster of `colors`.
    public static func dominant(of colors: [ThemeColor]) -> ThemeColor? {
        guard !colors.isEmpty else { return nil }
        let points = colors.map(OKLab.init)
        var centers = seeds(points)
        var assignment = [Int](repeating: 0, count: points.count)
        for _ in 0..<iterations {
            for (index, point) in points.enumerated() {
                assignment[index] = nearest(point, in: centers)
            }
            centers = centers.indices.map { cluster -> OKLab in
                let members = points.indices.filter { assignment[$0] == cluster }
                guard !members.isEmpty else { return centers[cluster] }
                let count = Double(members.count)
                return OKLab(lightness: members.reduce(0) { $0 + points[$1].lightness } / count,
                             a: members.reduce(0) { $0 + points[$1].a } / count,
                             b: members.reduce(0) { $0 + points[$1].b } / count)
            }
        }
        var sizes = [Int](repeating: 0, count: centers.count)
        for cluster in assignment { sizes[cluster] += 1 }
        guard let largest = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) else { return nil }
        // The cluster's mean in sRGB: the members' average colour, not the OKLab centre's inverse.
        let members = colors.indices.filter { assignment[$0] == largest }
        let count = Double(members.count)
        return ThemeColor(red: members.reduce(0) { $0 + colors[$1].red } / count,
                          green: members.reduce(0) { $0 + colors[$1].green } / count,
                          blue: members.reduce(0) { $0 + colors[$1].blue } / count)
    }

    /// Farthest-point seeds: the first point, then each time the point farthest from every seed.
    private static func seeds(_ points: [OKLab]) -> [OKLab] {
        var centers = [points[0]]
        while centers.count < min(clusterCount, points.count) {
            var best = points[0]
            var bestDistance = -1.0
            for point in points {
                let distance = centers.map { $0.distance(to: point) }.min() ?? 0
                if distance > bestDistance {
                    best = point
                    bestDistance = distance
                }
            }
            guard bestDistance > 0 else { break }
            centers.append(best)
        }
        return centers
    }

    private static func nearest(_ point: OKLab, in centers: [OKLab]) -> Int {
        var best = 0
        var bestDistance = Double.infinity
        for (index, center) in centers.enumerated() {
            let distance = center.distance(to: point)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }
}
