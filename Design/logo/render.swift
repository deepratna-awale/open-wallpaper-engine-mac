// Rasterises the logo for the asset catalog. Run through build.sh.
//
//   render.swift svg   <in.svg> <out.png> <pixels>            flat SVG -> square PNG
//   render.swift frame <in.png> <out.png> <pixels>            full-bleed icon -> macOS grid
//
// `frame` places a full-bleed render (ictool's output) on Apple's macOS icon grid:
// an 824/1024 body centred on the canvas with a soft drop shadow, as pre-26
// macOS icons are drawn. Used for the macOS 14/15 AppIcon.appiconset fallback.
import AppKit

func bitmap(_ px: Int, _ draw: (NSRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    draw(NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.retagging(with: .sRGB) ?? rep
}

let args = CommandLine.arguments
guard args.count == 5, let px = Int(args[4]),
      let image = NSImage(contentsOf: URL(fileURLWithPath: args[2])) else {
    FileHandle.standardError.write("usage: render.swift svg|frame <in> <out.png> <pixels>\n".data(using: .utf8)!)
    exit(1)
}
let rep: NSBitmapImageRep
switch args[1] {
case "svg":
    rep = bitmap(px) { image.draw(in: $0) }
case "frame":
    rep = bitmap(px) { canvas in
        let unit = canvas.width / 1024
        let body = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
        shadow.shadowBlurRadius = 20 * unit
        shadow.set()
        image.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
    }
default:
    exit(1)
}
do {
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
} catch {
    FileHandle.standardError.write("\(args[3]): \(error)\n".data(using: .utf8)!)
    exit(1)
}
