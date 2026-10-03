import Foundation
import IOSurface
import Metal

/// Accepts the app's connection. Only the app that embeds this service can reach it. One
/// connection per process: CEF starts once and the helper exits when the app lets go.
final class ChromiumHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private var service: ChromiumHelperService?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard service == nil else { return false }
        let service = ChromiumHelperService(connection: connection)
        self.service = service
        connection.exportedInterface = .chromiumHelper
        connection.exportedObject = service
        connection.remoteObjectInterface = .chromiumHost
        // CEF's subprocesses watch this process and exit with it.
        connection.invalidationHandler = { exit(0) }
        connection.interruptionHandler = { exit(0) }
        connection.resume()
        return true
    }
}

/// Starts CEF on the main thread and forwards each painted frame to the app as a copy in one of
/// a few IOSurfaces it owns, because CEF takes its own surface back when the paint returns.
final class ChromiumHelperService: NSObject, ChromiumHelperProtocol {
    private weak var connection: NSXPCConnection?
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var queue = device?.makeCommandQueue()
    /// The surfaces frames are copied into, used in turn. Main thread only, like everything below.
    private var ring: [IOSurface] = []
    private var ringIndex = 0
    private var frameNumber: Int64 = 0

    /// Copies in flight that the app may still be reading: three frames at 60 Hz is 50 ms.
    static let ringSize = 3

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func start(url: String, frameworkDirectory: String, cacheDirectory: String, width: Int, height: Int,
               frameRate: Int, reply: @escaping (String?) -> Void) {
        guard (1...ChromiumHelperIPC.maxDimension).contains(width), (1...ChromiumHelperIPC.maxDimension).contains(height) else {
            reply("Frame size \(width)×\(height) is out of range")
            return
        }
        guard device != nil else {
            reply("No Metal device")
            return
        }
        DispatchQueue.main.async {
            var error = [CChar](repeating: 0, count: 512)
            let context = Unmanaged.passUnretained(self).toOpaque()
            let status = owe_cef_start(frameworkDirectory, cacheDirectory, url, Int32(width), Int32(height),
                                       Int32(max(1, min(frameRate, 240))), { context, surface in
                guard let context, let surface else { return }
                Unmanaged<ChromiumHelperService>.fromOpaque(context).takeUnretainedValue().forward(surface)
            }, context, &error, error.count)
            reply(status == 0 ? nil : String(cString: error))
        }
    }

    func stop() {
        DispatchQueue.main.async { owe_cef_stop() }
    }

    /// Copies CEF's surface into the next ring surface on the GPU and sends that one.
    private func forward(_ source: IOSurface) {
        guard let device, let queue, source.pixelFormat == ChromiumHelperIPC.pixelFormat,
              let host = connection?.remoteObjectProxy as? ChromiumHostProtocol else { return }
        if ring.first.map({ $0.width != source.width || $0.height != source.height }) ?? true {
            ring = (0..<Self.ringSize).compactMap { _ in Self.makeSurface(width: source.width, height: source.height) }
            ringIndex = 0
        }
        guard ring.count == Self.ringSize else { return }
        let target = ring[ringIndex]
        ringIndex = (ringIndex + 1) % ring.count
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: source.width,
                                                                  height: source.height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard let from = device.makeTexture(descriptor: descriptor, iosurface: source, plane: 0),
              let to = device.makeTexture(descriptor: descriptor, iosurface: target, plane: 0),
              let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() else { return }
        blit.copy(from: from, to: to)
        blit.endEncoding()
        commands.commit()
        // The copy must finish before CEF reuses its surface, which happens when this returns.
        commands.waitUntilCompleted()
        frameNumber += 1
        host.didPaint(ChromiumFrameMessage(surface: target, frameNumber: frameNumber))
    }

    static func makeSurface(width: Int, height: Int) -> IOSurface? {
        IOSurface(properties: [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .pixelFormat: ChromiumHelperIPC.pixelFormat,
        ])
    }
}
