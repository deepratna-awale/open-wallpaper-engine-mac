import Metal

/// One scene's GPU memory for scratch render targets (efficiency plan N6): sub-allocated from
/// heaps instead of one allocation per texture, so making a target costs no driver allocation
/// and a dropped target's memory is taken by the next one of any size (`makeAliasable`).
///
/// Heaps are tracked (`hazardTrackingMode = .tracked`): Metal orders work on aliased memory
/// itself, so a target made aliasable while a command buffer still reads it is not overwritten
/// before that buffer completes. Chunks grow as needed and a chunk left empty is released at
/// `trim()`, so an idle scene keeps no more than its live targets.
///
/// Not thread-safe: owned by `SceneRenderTargetPool` on the render thread.
final class SceneHeap {
    private let device: MTLDevice
    /// Size of a new chunk (a bigger texture gets a chunk of its own size).
    let chunkBytes: Int
    private var heaps: [MTLHeap] = []

    init(device: MTLDevice, chunkBytes: Int = 32 << 20) {
        self.device = device
        self.chunkBytes = chunkBytes
    }

    /// Bytes reserved by the heaps, and bytes their live textures use.
    var reservedBytes: Int { heaps.reduce(0) { $0 + $1.size } }
    var usedBytes: Int { heaps.reduce(0) { $0 + $1.usedSize } }
    var chunkCount: Int { heaps.count }

    /// A private texture from the heaps, growing them when none has room; nil when Metal can't.
    func makeTexture(_ descriptor: MTLTextureDescriptor) -> MTLTexture? {
        descriptor.storageMode = .private
        let sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: descriptor)
        for heap in heaps where heap.maxAvailableSize(alignment: sizeAndAlign.align) >= sizeAndAlign.size {
            if let texture = heap.makeTexture(descriptor: descriptor) { return texture }
        }
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.storageMode = .private
        heapDescriptor.hazardTrackingMode = .tracked
        heapDescriptor.type = .automatic
        heapDescriptor.size = max(chunkBytes, sizeAndAlign.size)
        guard let heap = device.makeHeap(descriptor: heapDescriptor) else { return nil }
        heap.label = "owe.scene-heap"
        heaps.append(heap)
        return heap.makeTexture(descriptor: descriptor)
    }

    /// Returns a texture's memory to its heap for the next allocation. The caller drops every
    /// reference to it; GPU work already encoded on it still completes first (tracked heap).
    func recycle(_ texture: MTLTexture) {
        guard texture.heap != nil else { return }
        texture.makeAliasable()
    }

    /// Releases chunks no live texture uses.
    func trim() {
        heaps.removeAll { $0.usedSize == 0 }
    }

    func removeAll() { heaps.removeAll() }
}
