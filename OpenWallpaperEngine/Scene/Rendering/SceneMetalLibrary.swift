import Metal

/// The engine's own Metal functions. The `.metal` files build into the OpenWallpaperEngine
/// framework's `default.metallib`, which the app and the Wallpaper Editor's app both load from the
/// framework (`MTLDevice.makeDefaultLibrary()` would look in the running app's bundle).
enum SceneMetalLibrary {
    /// The library, or nil (logged) when it can't be read.
    static func make(device: MTLDevice) -> MTLLibrary? {
        do {
            return try device.makeDefaultLibrary(bundle: AppBundleLayout.framework)
        } catch {
            OWELog.error(.scene, "The engine's Metal library can't be loaded: \(error)")
            return nil
        }
    }
}
