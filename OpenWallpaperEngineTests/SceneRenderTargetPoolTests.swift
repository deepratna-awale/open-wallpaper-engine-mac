import XCTest
import Metal
@testable import OpenWallpaperEngine

final class SceneRenderTargetPoolTests: XCTestCase {
    private var device: MTLDevice!
    /// The pool's clock, advanced by the tests.
    private var seconds: TimeInterval = 0

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func makePool(byteBudget: Int = 256 << 20, maxIdleSeconds: TimeInterval = 10) -> SceneRenderTargetPool {
        SceneRenderTargetPool(device: device, byteBudget: byteBudget, maxIdleSeconds: maxIdleSeconds, now: { [unowned self] in seconds })
    }

    private func size(_ width: Int, _ height: Int) -> Int {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        // The pool's targets come from its heap (`SceneHeap`).
        return SceneHeap(device: device).makeTexture(descriptor)?.allocatedSize ?? 0
    }

    func testTwoRequestsInOneFrameGetDistinctTextures() throws {
        let pool = makePool()
        let a = try XCTUnwrap(pool.texture(width: 32, height: 32, pixelFormat: .rgba8Unorm))
        let b = try XCTUnwrap(pool.texture(width: 32, height: 32, pixelFormat: .rgba8Unorm))
        XCTAssertFalse(a === b)
        pool.endFrame()
        let c = try XCTUnwrap(pool.texture(width: 32, height: 32, pixelFormat: .rgba8Unorm))
        XCTAssertTrue(c === a || c === b, "the next frame reuses a returned texture")
    }

    func testAvoidsEveryGivenTexture() throws {
        let pool = makePool()
        let a = try XCTUnwrap(pool.texture(width: 16, height: 16, pixelFormat: .rgba8Unorm))
        let b = try XCTUnwrap(pool.texture(width: 16, height: 16, pixelFormat: .rgba8Unorm))
        pool.endFrame()
        let c = try XCTUnwrap(pool.texture(width: 16, height: 16, pixelFormat: .rgba8Unorm, avoiding: [a, b]))
        XCTAssertFalse(c === a || c === b)
    }

    func testFreeTexturesIdleOutByTimeNotFrames() throws {
        let pool = makePool(maxIdleSeconds: 10)
        _ = pool.texture(width: 16, height: 16, pixelFormat: .rgba8Unorm)
        // Many frames within the idle time (a 240 Hz display) keep it.
        for _ in 0..<2000 {
            seconds += 1.0 / 240
            pool.endFrame()
        }
        XCTAssertEqual(pool.textureCount, 1)
        seconds += 2
        pool.endFrame()
        XCTAssertEqual(pool.textureCount, 0, "unused for over 10 s")
    }

    func testPersistentTargetsAreNeverEvictedOrShared() throws {
        let pool = makePool(byteBudget: 1, maxIdleSeconds: 1)
        let feedback = try XCTUnwrap(pool.persistentTexture(width: 64, height: 64, pixelFormat: .rgba8Unorm))
        seconds += 3600
        pool.endFrame()
        XCTAssertEqual(pool.textureCount, 1, "not idle-evicted")
        let other = try XCTUnwrap(pool.texture(width: 64, height: 64, pixelFormat: .rgba8Unorm))
        XCTAssertFalse(other === feedback, "not handed to another caller")
        XCTAssertEqual(pool.textureCount, 2, "leased textures stay even over budget")
        pool.removeAll()
        XCTAssertEqual(pool.textureCount, 2, "removeAll keeps leased textures")
        pool.endFrame()
        pool.release(feedback)
        pool.removeAll()
        XCTAssertEqual(pool.textureCount, 0)
    }

    func testEvictsLeastRecentlyUsedFreeTexturesOverBudget() throws {
        let pool = makePool(byteBudget: size(64, 64) + size(64, 32))
        let a = try XCTUnwrap(pool.texture(width: 64, height: 64, pixelFormat: .rgba8Unorm))
        let b = try XCTUnwrap(pool.texture(width: 64, height: 32, pixelFormat: .rgba8Unorm))
        pool.endFrame()
        XCTAssertTrue(pool.texture(width: 64, height: 64, pixelFormat: .rgba8Unorm) === a, "a free texture is reused")
        pool.endFrame()
        _ = try XCTUnwrap(pool.texture(width: 32, height: 64, pixelFormat: .rgba8Unorm))
        XCTAssertLessThanOrEqual(pool.residentBytes, pool.byteBudget)
        pool.endFrame()
        XCTAssertTrue(pool.texture(width: 64, height: 64, pixelFormat: .rgba8Unorm) === a, "recently used texture survives")
        XCTAssertFalse(pool.texture(width: 64, height: 32, pixelFormat: .rgba8Unorm) === b, "least recently used was evicted")
    }
}

final class SceneHeapTests: XCTestCase {
    private func descriptor(_ side: Int) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        return descriptor
    }

    func testTargetsShareAChunkAndAnEmptyChunkIsReleased() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let heap = SceneHeap(device: device, chunkBytes: 8 << 20)
        var a: MTLTexture? = try XCTUnwrap(heap.makeTexture(descriptor(256)))
        var b: MTLTexture? = try XCTUnwrap(heap.makeTexture(descriptor(256)))
        XCTAssertEqual(heap.chunkCount, 1)
        XCTAssertTrue(a?.heap === b?.heap)
        heap.recycle(a!)
        heap.recycle(b!)
        a = nil
        b = nil
        heap.trim()
        XCTAssertEqual(heap.chunkCount, 0)
    }

    func testARecycledTargetsMemoryIsTakenByTheNextOfAnotherSize() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let heap = SceneHeap(device: device, chunkBytes: 4 << 20)
        let big = try XCTUnwrap(heap.makeTexture(descriptor(900)))  // ~3.2 MB of the 4 MB chunk
        heap.recycle(big)
        _ = try XCTUnwrap(heap.makeTexture(descriptor(700)))
        XCTAssertEqual(heap.chunkCount, 1, "the aliased memory is reused instead of a new chunk")
    }

    func testThePoolDrawsFromTheHeapAndReleasesIdleChunks() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        var seconds: TimeInterval = 0
        let pool = SceneRenderTargetPool(device: device, maxIdleSeconds: 1, now: { seconds })
        let texture = try XCTUnwrap(pool.texture(width: 64, height: 64, pixelFormat: .rgba8Unorm))
        XCTAssertNotNil(texture.heap)
        pool.endFrame()
        seconds = 5
        pool.endFrame()
        XCTAssertEqual(pool.textureCount, 0)
        XCTAssertEqual(pool.heap?.chunkCount, 0)
    }
}
