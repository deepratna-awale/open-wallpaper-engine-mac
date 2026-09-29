import CoreGraphics
import Metal

extension SceneMetalRenderer {
    /// Copies the latest shared frame (`renderShared`), as a display of `pixelSize` shows it, into
    /// CPU memory and hands `completion` the picture once the GPU is done, on a Metal thread (nil
    /// if the GPU failed). The copy is one blit into a shared buffer that the image then wraps,
    /// so nothing waits on the GPU. False (and no completion) when there is no frame to copy or
    /// the drawables' format isn't 8-bit BGRA. Render thread.
    func captureSharedFrame(pixelSize: SIMD2<Int>, pixelsPerPoint: Float,
                            completion: @escaping @Sendable (CGImage?) -> Void) -> Bool {
        guard pixelSize.x > 0, pixelSize.y > 0, pixelFormat == .bgra8Unorm || pixelFormat == .bgra8Unorm_srgb else { return false }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: pixelSize.x,
                                                                  height: pixelSize.y, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let bytesPerRow = (pixelSize.x * 4 + 255) / 256 * 256
        let length = bytesPerRow * pixelSize.y
        guard let target = device.makeTexture(descriptor: descriptor),
              let buffer = device.makeBuffer(length: length, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            OWELog.error(.scene, "Loading snapshot: can't allocate a \(pixelSize.x)×\(pixelSize.y) capture")
            return false
        }
        commandBuffer.label = "Loading snapshot"
        guard encodeSharedFrame(into: target, pixelsPerPoint: pixelsPerPoint, commandBuffer: commandBuffer),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: pixelSize.x, height: pixelSize.y, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: length)
        blit.endEncoding()
        commandBuffer.addCompletedHandler { finished in
            guard finished.status == .completed else {
                OWELog.error(.scene, "Loading snapshot: the capture failed on the GPU: \(finished.error.map { "\($0)" } ?? "unknown")")
                completion(nil)
                return
            }
            completion(Self.image(wrapping: buffer, size: pixelSize, bytesPerRow: bytesPerRow))
        }
        commandBuffer.commit()
        return true
    }

    /// An sRGB image over `buffer`'s BGRA pixels (alpha ignored); the image keeps the buffer alive.
    private static func image(wrapping buffer: MTLBuffer, size: SIMD2<Int>, bytesPerRow: Int) -> CGImage? {
        let retained = Unmanaged.passRetained(buffer as AnyObject)
        guard let provider = CGDataProvider(dataInfo: retained.toOpaque(), data: buffer.contents(), size: buffer.length,
                                            releaseData: { info, _, _ in
                                                if let info { Unmanaged<AnyObject>.fromOpaque(info).release() }
                                            }) else {
            retained.release()
            return nil
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
        return CGImage(width: size.x, height: size.y, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}
