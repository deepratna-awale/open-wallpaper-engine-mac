import Foundation
import IOSurface

// Compiled into both the app and owe-chromium-helper: the XPC contract between them. Class and
// protocol names are fixed with @objc(...) so both modules archive and look up the same names.

enum ChromiumHelperIPC {
    /// The bundle identifier of the XPC service in `Contents/XPCServices`.
    static let serviceName = "com.winddog.wallpaper-engine.chromium-helper"
    /// The largest frame side either end accepts, in pixels.
    static let maxDimension = 16_384
    /// The only pixel format frames come in: 8-bit BGRA, what CEF paints on macOS.
    static let pixelFormat: OSType = 0x4247_5241 // 'BGRA'
}

/// What the app asks the helper to do.
@objc(OWEChromiumHelperProtocol)
protocol ChromiumHelperProtocol {
    /// Loads CEF from `frameworkDirectory` (the installed version's folder), keeps its profile in
    /// `cacheDirectory` and opens `url` windowless at `width`×`height` pixels, painting at most
    /// `frameRate` frames a second. Replies nil once the browser exists, else the reason.
    func start(url: String, frameworkDirectory: String, cacheDirectory: String, width: Int, height: Int,
               frameRate: Int, reply: @escaping (String?) -> Void)
    /// Closes the browser; the helper exits when the connection goes away.
    func stop()
}

/// What the helper sends back.
@objc(OWEChromiumHostProtocol)
protocol ChromiumHostProtocol {
    func didPaint(_ frame: ChromiumFrameMessage)
}

/// One painted frame: an IOSurface (sent as a Mach port by XPC, never copied) and its number.
@objc(OWEChromiumFrameMessage)
final class ChromiumFrameMessage: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let surface: IOSurface
    /// Counts up from 1 per browser.
    let frameNumber: Int64

    init(surface: IOSurface, frameNumber: Int64) {
        self.surface = surface
        self.frameNumber = frameNumber
    }

    func encode(with coder: NSCoder) {
        coder.encode(surface, forKey: "surface")
        coder.encode(frameNumber, forKey: "frameNumber")
    }

    init?(coder: NSCoder) {
        guard let surface = coder.decodeObject(of: IOSurface.self, forKey: "surface") else { return nil }
        self.surface = surface
        frameNumber = coder.decodeInt64(forKey: "frameNumber")
    }

    /// Whether the frame is one the app can show: BGRA, inside the size limit, a positive number.
    var isValid: Bool {
        surface.pixelFormat == ChromiumHelperIPC.pixelFormat
            && (1...ChromiumHelperIPC.maxDimension).contains(surface.width)
            && (1...ChromiumHelperIPC.maxDimension).contains(surface.height)
            && frameNumber > 0
    }
}

extension NSXPCInterface {
    static var chromiumHelper: NSXPCInterface { NSXPCInterface(with: ChromiumHelperProtocol.self) }

    /// `didPaint`'s argument class comes from its signature; the message decodes its IOSurface itself.
    static var chromiumHost: NSXPCInterface { NSXPCInterface(with: ChromiumHostProtocol.self) }
}
