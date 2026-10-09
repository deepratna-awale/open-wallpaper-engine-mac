import CoreVideo
import IOSurface
import Metal

/// The IOSurfaces a transition's frames are drawn into for a layer's contents.
enum WallpaperTransitionSurface {
    /// How many a player uses in turn.
    static let count = 3

    /// An IOSurface of `size` can't be made.
    struct Failure: Error, CustomStringConvertible {
        let size: SIMD2<Int>

        var description: String { "can't allocate a \(size.x)×\(size.y) frame" }
    }

    /// A BGRA IOSurface of `size` in sRGB and a render target over it.
    static func make(_ size: SIMD2<Int>, device: MTLDevice) throws -> (surface: IOSurface, texture: MTLTexture) {
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: size.x, .height: size.y, .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ]
        guard let surface = IOSurface(properties: properties) else { throw Failure(size: size) }
        if let space = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, space)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size.x,
                                                                  height: size.y, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
            throw Failure(size: size)
        }
        return (surface, texture)
    }
}
