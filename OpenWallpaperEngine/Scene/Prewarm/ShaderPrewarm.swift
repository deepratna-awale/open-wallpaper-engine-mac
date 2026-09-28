import Metal
import simd

/// Compiles the shader variants and effect pipelines of some scene wallpapers into the shader
/// caches, the way showing them would: each scene is loaded by the real loader
/// (`SceneWallpaperViewModel`) and drawn offscreen by the real renderer (`SceneMetalRenderer`)
/// until its pipelines have compiled, so the caches get exactly the entries a launch creates.
///
/// Run by `ShaderPrewarmCommand` in a new build before it replaces the running one. It writes
/// nothing but the caches: it reads the user's settings and wallpapers from `defaults` and never
/// sets them (the scene loader's own writes go to `UserDefaults.app`, which a helper run makes a
/// read-only view, `AppStorageLocation`).
@MainActor
struct ShaderPrewarm {
    struct Report: Equatable {
        var wallpapers: Int
        var failed: Int
        /// Variant files in the cache generation before and after.
        var variantsBefore: Int
        var variantsAfter: Int
        var seconds: Double
    }

    /// Read only.
    var defaults: UserDefaults
    var variantCacheDirectory: URL?
    var pipelineArchiveDirectory: URL?
    var recentLimit = 5
    /// Frames drawn per wallpaper before it counts as compiled once no pipeline is pending.
    var minimumFrames = 6
    var timeoutPerWallpaper: TimeInterval = 90

    init(defaults: UserDefaults,
         variantCacheDirectory: URL? = ShaderVariantTranslator.defaultCacheDirectory,
         pipelineArchiveDirectory: URL? = EffectPipelineArchive.defaultDirectory) {
        self.defaults = defaults
        self.variantCacheDirectory = variantCacheDirectory
        self.pipelineArchiveDirectory = pipelineArchiveDirectory
    }

    /// Prewarms the shown and recent scenes on the connected displays.
    func run() -> Report {
        let (displays, main) = ShaderPrewarmTargets.connectedDisplays()
        return run(ShaderPrewarmTargets.read(from: defaults, displays: displays, mainDisplay: main,
                                             recentLimit: recentLimit))
    }

    func run(_ targets: [ShaderPrewarmTargets.Target]) -> Report {
        let started = Date()
        let translator = ShaderVariantTranslator(
            compiler: ShaderCompilerFactory.makeDefault(stateDirectory: variantCacheDirectory?.deletingLastPathComponent()
                .appending(path: "shader-compiler", directoryHint: .isDirectory)),
            cacheDirectory: variantCacheDirectory)
        let variantsBefore: Int = Self.fileCount(in: translator.generationDirectory)
        // Held for the whole run, so every scene's pipelines go into one write.
        let archive: EffectPipelineArchive? = pipelineArchiveDirectory.flatMap { directory in
            MTLCreateSystemDefaultDevice().map { EffectPipelineArchive.shared(device: $0, directory: directory) }
        }
        let settings: GlobalSettings = Self.globalSettings(from: defaults)
        var failed = 0
        for target in targets where !prewarm(target, translator: translator, settings: settings) {
            failed += 1
        }
        archive?.flush()
        let report = Report(wallpapers: targets.count, failed: failed, variantsBefore: variantsBefore,
                            variantsAfter: Self.fileCount(in: translator.generationDirectory),
                            seconds: Date().timeIntervalSince(started))
        OWELog.info(.shader, "Shader prewarm: \(report.wallpapers) wallpapers (\(report.failed) failed) in "
                    + String(format: "%.1f s", report.seconds)
                    + ", \(report.variantsAfter - report.variantsBefore) new variants (\(report.variantsAfter) cached)")
        return report
    }

    /// Loads and draws one scene until its pipelines have compiled; false when it couldn't.
    private func prewarm(_ target: ShaderPrewarmTargets.Target, translator: ShaderVariantTranslator,
                         settings: GlobalSettings) -> Bool {
        let name: String = target.wallpaper.wallpaperDirectory.lastPathComponent
        let model = SceneWallpaperViewModel(wallpaper: target.wallpaper, effectTranslator: translator)
        let renderSettings = SceneRenderSettings(settings, outputPixels: target.display.drawableSize,
                                                 sceneSize: model.textureReductionSceneSize)
        model.setRenderSettings(renderSettings)
        guard let content = model.metalContent() else {
            OWELog.error(.shader, "Shader prewarm: \(name) has no scene content")
            return false
        }
        guard let renderer = SceneMetalRenderer(pixelFormat: .bgra8Unorm, scriptServices: nil,
                                                screenID: "prewarm-\(name)",
                                                pipelineArchiveDirectory: pipelineArchiveDirectory) else {
            OWELog.error(.shader, "Shader prewarm: no Metal renderer for \(name)")
            return false
        }
        defer { renderer.releaseContent() }
        renderer.renderSettings = renderSettings
        renderer.sounds.setTargetGain(0)
        renderer.setContent(content)
        let deadline = Date().addingTimeInterval(timeoutPerWallpaper)
        while !renderer.hasContent, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        guard renderer.hasContent else {
            OWELog.error(.shader, "Shader prewarm: \(name) never got its content")
            return false
        }
        let viewport = SceneViewport(drawableSize: target.display.drawableSize, pointSize: target.display.pointSize,
                                     cursor: nil, frameRateLimit: 30)
        var frames = 0
        var settledFrames = 0
        // New passes can start compiling on any frame (effects that turn on later), so a scene is
        // done once a few frames in a row had nothing compiling.
        while settledFrames < 3 || frames < minimumFrames {
            guard Date() < deadline else {
                OWELog.error(.shader, "Shader prewarm: \(name) was still compiling after \(Int(timeoutPerWallpaper)) s")
                return false
            }
            renderer.renderShared([viewport])
            renderer.lastCommandBuffer?.waitUntilCompleted()
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            frames += 1
            settledFrames = renderer.hasPendingEffectPipelines ? 0 : settledFrames + 1
        }
        OWELog.debug(.shader, "Shader prewarm: \(name) compiled in \(frames) frames")
        return true
    }

    private static func globalSettings(from defaults: UserDefaults) -> GlobalSettings {
        guard let data = defaults.data(forKey: "GlobalSettings") else { return GlobalSettings() }
        do {
            return try JSONDecoder().decode(GlobalSettings.self, from: data)
        } catch {
            OWELog.error(.shader, "Shader prewarm: can't read the settings, using the defaults: \(error)")
            return GlobalSettings()
        }
    }

    static func fileCount(in directory: URL?) -> Int {
        guard let directory,
              let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            // Optional: a file removed while counting doesn't count.
            count += 1
        }
        return count
    }
}
