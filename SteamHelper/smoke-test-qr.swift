// usage: swift smoke-test-qr.swift <text> <out.png>; renders a QR code with Core Image (smoke-test.py).
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let filter = CIFilter.qrCodeGenerator()
filter.message = Data(args[1].utf8)
filter.correctionLevel = "M"
let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
let context = CIContext()
let cg = context.createCGImage(image, from: image.extent)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, nil)
CGImageDestinationFinalize(dest)
