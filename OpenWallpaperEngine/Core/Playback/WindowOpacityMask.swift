import CoreGraphics

/// Which parts of a window are opaque, on a coarse grid over its frame: where it isn't, the
/// wallpaper behind it shows through (a terminal with a see-through background, a translucent
/// sidebar). Made from a tiny snapshot of the window (`WindowOpacityProbe`), of which only the
/// alpha channel is read.
struct WindowOpacityMask: Equatable {
    /// An alpha at or above this (of 255) hides what is behind; anything lower lets it show.
    static let opaqueAlpha: UInt8 = 242
    /// The grid's longer side, in cells.
    static let longSide = 48

    let columns: Int
    let rows: Int
    /// Row by row, top row first.
    let opaque: [Bool]

    init(columns: Int, rows: Int, opaque: [Bool]) {
        precondition(columns > 0 && rows > 0 && opaque.count == columns * rows)
        self.columns = columns
        self.rows = rows
        self.opaque = opaque
    }

    /// The grid for a window of `size`: `longSide` cells along its longer side.
    static func gridSize(for size: CGSize) -> (columns: Int, rows: Int) {
        guard size.width > 0, size.height > 0 else { return (1, 1) }
        let scale = CGFloat(longSide) / max(size.width, size.height)
        return (max(1, Int((size.width * scale).rounded())), max(1, Int((size.height * scale).rounded())))
    }

    /// The mask of `image` at `columns` by `rows`. The image is drawn into an alpha-only buffer,
    /// so none of its colours are kept; nil when that buffer can't be made.
    init?(image: CGImage, columns: Int, rows: Int) {
        guard columns > 0, rows > 0,
              let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8,
                                      bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let data = context.data else { return nil }
        let alpha = data.bindMemory(to: UInt8.self, capacity: columns * rows)
        // A bitmap context's first row is the image's top row.
        let opaque = (0..<(columns * rows)).map { alpha[$0] >= Self.opaqueAlpha }
        self.init(columns: columns, rows: rows, opaque: opaque)
    }

    /// Whether the window is opaque at `point`, given in units of its frame (0…1, top left first).
    func isOpaque(atUnit point: CGPoint) -> Bool {
        let column = min(columns - 1, max(0, Int(point.x * CGFloat(columns))))
        let row = min(rows - 1, max(0, Int(point.y * CGFloat(rows))))
        return opaque[row * columns + column]
    }
}
