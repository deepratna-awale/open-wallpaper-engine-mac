import CoreImage
import CoreImage.CIFilterBuiltins

/// The QR code of the page's address (CoreImage's `CIQRCodeGenerator`), black on white with its
/// quiet zone, scaled up without smoothing so each module stays sharp.
enum AndroidWiFiQRCode {
    /// `text`'s QR code, `scale` pixels per module; nil when it doesn't fit a QR code.
    static func image(for text: String, scale: CGFloat = 8) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }
}
