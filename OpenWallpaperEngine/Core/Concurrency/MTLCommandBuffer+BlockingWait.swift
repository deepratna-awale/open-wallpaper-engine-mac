import Metal

extension MTLCommandBuffer {
    /// `waitUntilCompleted()` for an async render loop that must block until the GPU is done (its
    /// next step reads the frame back): Metal marks the wait unavailable from async code, and
    /// `completed()` would suspend instead of blocking.
    func blockUntilCompleted() {
        waitUntilCompleted()
    }
}
