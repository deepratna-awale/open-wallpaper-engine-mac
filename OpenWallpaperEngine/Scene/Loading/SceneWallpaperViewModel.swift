//
//  SceneWallpaperViewModel.swift
//  Open Wallpaper Engine
//
//  Loads Wallpaper Engine scene wallpapers and builds the content the Metal renderer draws.
//  Follows the same ViewModel pattern as VideoWallpaperViewModel.
//

import SwiftUI
import CoreText
import CryptoKit

class SceneWallpaperViewModel: ObservableObject {
    static func log(_ msg: String) {
        OWELog.info(.scene, msg)
    }

    /// High-volume per-asset/per-texture diagnostics; only surfaces at verbose log level.
    static func logDetail(_ msg: String) {
        OWELog.debug(.scene, msg)
    }

    @Published var currentWallpaper: WEWallpaper {
        willSet {
            if loadsInBackground { startLoad(from: newValue) } else { loadScene(from: newValue) }
        }
    }

    /// Loads run on the preparation pool (`startLoad`) instead of the calling thread. The app's
    /// instances load this way, so setting a wallpaper never blocks the main thread; tools and
    /// tests that want the scene at once load synchronously.
    let loadsInBackground: Bool

    /// Guards the small state the main thread reads and writes (the revision, the settings, what
    /// the loaded scene declares), so the main thread never waits on a load or a content build
    /// holding `sceneLock`.
    private let stateLock = NSLock()
    private var _metalRevision = 0
    var metalRevision: Int { stateLock.withLock { _metalRevision } }
    /// The settings `setRenderSettings` last gave; the next content build takes them.
    private var pendingRenderSettings = SceneRenderSettings()
    private var loadedTextureReductionSize: SIMD2<Float>?
    private var loadedBindingTable = UserPropertyBindingTable()
    /// The newest load; an older one that finishes later is dropped.
    private var loadGeneration = 0
    private var loadJob: PreparationPool.Job?
    /// Guards `settings` (the resolved settings identity), which loads resolve off the main thread.
    private let identityLock = NSLock()

    /// Every content invalidation must both bump the revision and tell SwiftUI, or `updateNSView`
    /// never runs and the renderer keeps drawing the previous wallpaper until some unrelated
    /// re-render happens to come along.
    private func bumpRevision() {
        stateLock.withLock { _metalRevision &+= 1 }
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
        }
    }

    /// Guards the parsed scene and its asset caches. `metalContent()` runs on a background queue,
    /// so it must not race a `loadScene` triggered from the main thread.
    private let sceneLock = NSRecursiveLock()
    private let contentQueue = DispatchQueue(label: "com.winddog.wallpaper-engine.scene-content", qos: .userInitiated)
    private var cachedContent: SceneMetalContent?
    private var cachedContentRevision = -1
    /// The user's quality settings the content is built for: `pendingRenderSettings` as the
    /// build in progress took them (under the scene lock).
    private var renderSettings = SceneRenderSettings()
    /// The engine combos of the content being built, for every material plan built with it.
    private var sceneEngineCombos = SceneEngineCombos()
    /// The content's model plans by `.mdl` and skin (`buildModels`), for script clones.
    private var modelPlans: [String: SceneModelPlan] = [:]
    /// The factor the particle budget put on the scene's systems (`ParticleBudget`); systems
    /// scripts create later are thinned by it too.
    private var particleBudgetScale: Float = 1
    /// The particles each object's systems hold as authored (`ParticleBudget.capacity`), by object
    /// id, as the last content build made them: an object rebuilt alone is thinned by the scene's
    /// factor while that stays the same.
    private var particleCapacities: [Int: Int] = [:]
    /// Time spent planning particle materials (`buildParticleMaterial`) since the content build
    /// began, and the plans made, for its load log line.
    private var particleMaterialPlanTime: (nanoseconds: UInt64, plans: Int) = (0, 0)
    /// The budget scaling last logged, so a rebuild of the same scene doesn't log it again.
    private var loggedParticleBudget: (directory: URL, report: ParticleBudget.Report)?
    /// Retained for video wallpapers rendered through the scene pipeline.
    private var videoStream: VideoTextureStream?
    /// Scene images' video textures, which follow the wallpaper's playback (`setEmbeddedVideoRate`).
    private let embeddedVideoStreams = NSHashTable<VideoTextureStream>.weakObjects()
    private var embeddedVideoRate: Float = 1
    private let embeddedVideoLock = NSLock()
    private var builtVideoFrameSize: SIMD2<Float>?

    /// Builds the render content off the main thread and delivers it on the main queue. While a
    /// load is in flight it delivers the previous content (nil at first); the load's commit bumps
    /// the revision, and the content is built again.
    func contentAsync(completion: @escaping (SceneMetalContent?) -> Void) {
        contentQueue.async { [weak self] in
            let content = self?.metalContent()
            DispatchQueue.main.async { completion(content) }
        }
    }

    private var pkgParser: PKGParser?
    /// The `.pkg` `pkgParser` reads, which keys the sound cache's copies.
    private var pkgURL: URL?
    private var loadedScene: WEScene?
    /// The loaded scene.json and its parse signature (`ParsedScene`), which the scripts run from.
    private var loadedDocument: (document: SceneJSON, signature: String)?
    /// The loaded wallpaper's project.json, which declares its user properties.
    private var loadedProject: SceneJSON?
    /// Every user-property binding of the loaded scene and the documents its build read; every
    /// bound value the build decodes is resolved through it.
    var bindingTable: UserPropertyBindingTable { stateLock.withLock { loadedBindingTable } }
    /// Copies of a particle definition share its built parts within one build
    /// (`ParticleDefinitionCache`); false builds every copy in full (tests compare the two).
    var sharesParticleDefinitions = true
    /// The loaded scene has SceneScripts.
    private var hasScriptSites = false
    private var loadedWallpaperDirectory: URL?
    private var assetDataCache: [String: Data] = [:]
    /// Where the loaded wallpaper's settings are stored, and the directory it was resolved for.
    private var settings: (directory: URL, identity: WallpaperSettingsIdentity)?
    /// Whose user properties this instance runs with: every display's, or one display's
    /// (`WallpaperPropertyScope`, `WallpaperPropertyGroups`).
    let propertyScope: WallpaperPropertyScope
    /// Other Workshop items' assets (`…/workshop/<id>/…`), loose or inside the item's `.pkg`.
    private var workshopAssets = WorkshopAssetResolver(roots: WorkshopAssetResolver.defaultRoots())
    /// WE's fixed copies of broken Workshop shaders (`assets/zcompat`).
    private var shaderCompat: SceneShaderCompat?
    /// The loaded wallpaper's Workshop id, which bounds the zcompat fixes.
    private var loadedProjectId: String?

    /// The textures decoded by the build in progress, so every layer, clone and effect that names
    /// the same file shares one image (and the renderer one upload). Emptied when the build ends:
    /// once the renderer uploaded them, the only copy of the pixels is on the GPU, and the next
    /// build loads the files again. Guarded by `sceneLock`, which every build holds.
    private var buildTextures: [String: SceneMetalTextureSource] = [:]

    /// Every screen showing the same wallpaper parses the identical PKG index and scene.json.
    /// PKGParser is immutable after init and WEScene is a value type, so both are safe to share.
    private struct ParsedScene {
        let parser: PKGParser?
        let scene: WEScene
        let signature: String
        /// scene.json as `scene` was decoded from (the user's object edits applied), for scripts.
        let document: SceneJSON?
    }

    private static let parseCacheLock = NSLock()
    nonisolated(unsafe) private static var parseCache: [String: ParsedScene] = [:]

    private static func cachedParse(for directory: URL, signature: String) -> ParsedScene? {
        parseCacheLock.lock()
        defer { parseCacheLock.unlock() }
        guard let entry = parseCache[directory.path], entry.signature == signature else { return nil }
        return entry
    }

    /// Forgets the shared parses, so the next load reads the scene cache or the source (tests).
    static func dropSharedParses() {
        parseCacheLock.lock()
        defer { parseCacheLock.unlock() }
        parseCache.removeAll()
    }

    private static func storeParse(_ entry: ParsedScene, for directory: URL) {
        parseCacheLock.lock()
        defer { parseCacheLock.unlock() }
        // Deliberately tiny: every display showing one wallpaper shares a single entry, so this
        // only needs the current wallpaper plus one for switching back. A larger cap would pin
        // mapped PKG data across playlist rotation for no benefit.
        if parseCache.count >= 2, parseCache[directory.path] == nil {
            parseCache.removeAll(keepingCapacity: true)
        }
        parseCache[directory.path] = entry
    }

    private func cachedTexture(_ key: String) -> SceneMetalTextureSource? {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        return buildTextures[key]
    }

    private func cacheTexture(_ source: SceneMetalTextureSource, for key: String) -> SceneMetalTextureSource {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        buildTextures[key] = source
        return source
    }

    /// Ends a build: the content now holds the only CPU copies, which the renderer drops once uploaded.
    private func endBuildTextures() {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        buildTextures.removeAll()
    }
    private var registeredFontNames: [String: String] = [:]

    /// `effectTranslator` translates and caches every shader variant the scene needs; the app's
    /// shared one (`defaultEffectTranslator`) unless a caller keeps its own cache (shader prewarm, tests).
    /// `loadsInBackground` starts the load on the preparation pool and returns at once
    /// (`startLoad`); otherwise the scene is loaded when init returns.
    init(wallpaper: WEWallpaper, propertyScope: WallpaperPropertyScope = .shared,
         effectTranslator: ShaderVariantTranslator? = SceneWallpaperViewModel.defaultEffectTranslator,
         loadsInBackground: Bool = false) {
        self.currentWallpaper = wallpaper
        self.propertyScope = propertyScope
        self.effectTranslator = effectTranslator
        self.loadsInBackground = loadsInBackground
        Self.log("init: wallpaper=\(wallpaper.project.title) dir=\(wallpaper.wallpaperDirectory.path)")
        if loadsInBackground { startLoad(from: wallpaper) } else { loadScene(from: wallpaper) }
    }

    deinit {
        loadJob?.cancel()
        // The built layer hands a strong reference to the renderer, so releasing this view model
        // is not enough on its own to silence the soundtrack.
        videoStream?.stop()
    }

    /// Both local and remote videos render through the one-layer video scene.
    static func isVideoType(_ type: String) -> Bool {
        let value = type.lowercased()
        return value == "video" || value == "remote-video"
    }

    /// Reloads the scene: in the background when this model loads there (`startLoad`), whose
    /// commit then bumps the revision.
    func reloadCurrentScene() {
        if loadsInBackground {
            startLoad(from: currentWallpaper, prepareDefaults: false)
        } else {
            loadScene(from: currentWallpaper, prepareDefaults: false)
        }
    }

    /// Drops the memoised scene content so the next build re-reads user properties that are
    /// consumed at build time, such as an authored effect's enabled flag.
    func invalidateContent() {
        bumpRevision()
    }

    /// The user's quality settings; a change rebuilds the content, whose engine combos follow them.
    /// The next build takes them, so this never waits on a build in progress.
    func setRenderSettings(_ settings: SceneRenderSettings) {
        let rebuild: Bool? = stateLock.withLock {
            guard settings != pendingRenderSettings else { return nil }
            let rebuild = settings.contentKey != pendingRenderSettings.contentKey
            pendingRenderSettings = settings
            return rebuild
        }
        // Settings applied per frame (reflection, the bloom gate, …) keep the content.
        if rebuild == true { bumpRevision() }
    }

    /// The loaded scene's size as WE's automatic texture resolution weighs it
    /// (`TextureReduction.orthographicSize(of:)`); nil for a perspective scene or none.
    var textureReductionSceneSize: SIMD2<Float>? {
        stateLock.withLock { loadedTextureReductionSize }
    }

    // MARK: - Scene Loading

    /// What reading a wallpaper's scene yields, before it becomes the loaded scene (`commit`).
    private struct SceneRead {
        let wallpaper: WEWallpaper
        /// The parse's identity: the scene cache key's name (the files, edits, properties,
        /// displays and settings it was read for).
        let signature: String
        let hasPackage: Bool
        var parser: PKGParser?
        var scene: WEScene?
        var document: SceneJSON?
        var project: SceneJSON?
        var source = "parsed"
        var bindingTable = UserPropertyBindingTable()
        var hasScriptSites = false
    }

    /// Loads `wallpaper` on the calling thread; the scene is loaded when it returns. The app loads
    /// through `startLoad` instead, off the main thread.
    func loadScene(from wallpaper: WEWallpaper, prepareDefaults: Bool = true) {
        let generation = supersedeLoads()
        guard let read = readScene(wallpaper, isCurrent: { true }) else { return }
        commit(read, generation: generation, prepareDefaults: prepareDefaults)
    }

    /// Starts loading `wallpaper` on the preparation pool and returns at once: the key, the cache
    /// read or the parse, and the commit all run there, and the main thread only sees the new
    /// revision (`objectWillChange`). A newer load (a quick switch, a reload) cancels this one.
    func startLoad(from wallpaper: WEWallpaper, prepareDefaults: Bool = true) {
        let generation = supersedeLoads()
        let job = Self.loadPool.submit(priority: .settingWallpaper, estimatedBytes: 64 << 20) { [weak self] job in
            guard let self else { return }
            defer { self.stateLock.withLock { if self.loadGeneration == generation { self.loadJob = nil } } }
            let isCurrent = { !job.isCancelled && self.isCurrentLoad(generation) }
            guard isCurrent(), let read = self.readScene(wallpaper, isCurrent: isCurrent) else { return }
            self.commit(read, generation: generation, prepareDefaults: prepareDefaults)
        }
        stateLock.withLock { if loadGeneration == generation, !job.isCancelled { loadJob = job } }
    }

    /// The pool background loads run on (tests swap it).
    nonisolated(unsafe) static var loadPool = PreparationPool.shared

    /// A load started by `startLoad` has not committed yet.
    var isLoading: Bool { stateLock.withLock { loadJob != nil } }

    /// Starts a new load generation, cancelling the load in flight; returns the new generation.
    private func supersedeLoads() -> Int {
        stateLock.withLock {
            loadGeneration &+= 1
            loadJob?.cancel()
            loadJob = nil
            return loadGeneration
        }
    }

    private func isCurrentLoad(_ generation: Int) -> Bool {
        stateLock.withLock { loadGeneration == generation }
    }

    /// Reads `wallpaper`'s scene: the in-memory parse, else the scene file itself. Touches no loaded state, so
    /// it runs without the scene lock; nil when `isCurrent` says a newer load took over.
    private func readScene(_ wallpaper: WEWallpaper, isCurrent: () -> Bool) -> SceneRead? {
        OWEPhaseTiming.measure(.sceneLoad) { readSceneUntimed(wallpaper, isCurrent: isCurrent) }
    }

    private func readSceneUntimed(_ wallpaper: WEWallpaper, isCurrent: () -> Bool) -> SceneRead? {
        let signpost = OWESignpost.begin(OWESignpost.scene, "loadScene")
        defer { signpost.end() }
        OWEFrameMetrics.countSceneReload()
        // Symlink in any already-installed cross-workshop-item asset dependencies before parsing,
        // so paths like "effects/workshop/<id>/name/effect.json" resolve as ordinary loose files.
        WorkshopDependencyResolver.linkInstalledDependencies(for: wallpaper)
        let dir = wallpaper.wallpaperDirectory
        let sceneFile = wallpaper.project.file  // e.g. "scene.json" or "gifscene.json"
        let settingsKey = settingsIdentity(for: dir).key(.userProperties, scope: propertyScope)

        // Derive PKG name from scene file: "scene.json" → "scene.pkg", "gifscene.json" → "gifscene.pkg"
        let pkgURL = dir.appending(path: (sceneFile as NSString).deletingPathExtension + ".pkg")
        let looseSceneURL = dir.appending(path: sceneFile)
        let hasPackage = FileManager.default.fileExists(atPath: pkgURL.path(percentEncoded: false))

        // The in-memory parse's key: it covers every file of the wallpaper, the scene file the
        // project names, the edits baked into the parse, and what it is built for.
        let request = preparationRequest(for: wallpaper, settingsKey: settingsKey)
        let key = request.key
        guard isCurrent() else { return nil }
        var read = SceneRead(wallpaper: wallpaper, signature: key.name + "|" + sceneFile, hasPackage: hasPackage)
        if let cached = Self.cachedParse(for: dir, signature: read.signature) {
            read.parser = cached.parser
            read.scene = cached.scene
            read.document = cached.document
            read.source = "shared parse"
        } else if hasPackage {
            do {
                let parser = try PKGParser(url: pkgURL)
                read.parser = parser
                if let data = parser.extractFile(named: sceneFile) {
                    (read.scene, read.document) = try decodeScene(data, edits: request.edits)
                }
            } catch {
                Self.log("Failed to parse PKG: \(error)")
            }
        } else if FileManager.default.fileExists(atPath: looseSceneURL.path(percentEncoded: false)) {
            // Loose files (no .pkg)
            do {
                if let data = try AssetPathResolver.data(sceneFile, in: dir) {
                    (read.scene, read.document) = try decodeScene(data, edits: request.edits)
                } else {
                    Self.log("Loose \(sceneFile) is not a usable file inside the wallpaper folder")
                }
            } catch {
                Self.log("Failed to parse loose \(sceneFile): \(error)")
            }
        }
        guard isCurrent() else { return nil }
        if let scene = read.scene {
            Self.storeParse(ParsedScene(parser: read.parser, scene: scene, signature: read.signature,
                                        document: read.document), for: dir)
        }
        if let document = read.document {
            read.bindingTable.record(.scene, json: document)
            read.hasScriptSites = !SceneScriptSiteBuilder(wallpaperID: "").sites(in: document).isEmpty
        }
        read.project = Self.project(in: dir)
        return read
    }

    /// Makes `read` the loaded scene, unless a newer load superseded it; short, under the scene lock.
    private func commit(_ read: SceneRead, generation: Int, prepareDefaults: Bool) {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        guard isCurrentLoad(generation) else { return }
        let wallpaper = read.wallpaper
        let dir = wallpaper.wallpaperDirectory

        // Re-parsing the same wallpaper (a settings change) must keep decoded textures and fonts;
        // only a different wallpaper invalidates them. Textures are shared process-wide and keyed
        // per wallpaper, so they survive switches and are reclaimed by NSCache under pressure.
        if loadedWallpaperDirectory != dir {
            assetDataCache.removeAll(keepingCapacity: true)
            registeredFontNames.removeAll(keepingCapacity: true)
            // Otherwise a stale stream either keeps playing the previous video's audio after
            // switching to a non-video wallpaper, or gets reused verbatim for a different video.
            videoStream?.stop()
            videoStream = nil
            builtVideoFrameSize = nil
            workshopAssets = WorkshopAssetResolver(roots: WorkshopAssetResolver.defaultRoots())
            shaderCompat = SceneShaderCompat(assetsDirectory: WallpaperEngineAssets.directory)
            loadedProjectId = Self.workshopId(of: wallpaper)
        }
        pkgParser = read.parser
        pkgURL = dir.appending(path: (wallpaper.project.file as NSString).deletingPathExtension + ".pkg")

        guard let scene = read.scene else {
            // A video or web wallpaper legitimately has no scene; only a scene wallpaper missing
            // one is a real failure, and treating both as errors buries the genuine case.
            let type = wallpaper.project.type.lowercased()
            if type.isEmpty || type == "scene" {
                OWELog.error(.scene, "No scene data found")
            } else {
                Self.logDetail("No scene data for \(type) wallpaper; handled by its own renderer")
                // Otherwise metalContent()'s memoization still sees the old revision and keeps
                // serving the previous wallpaper's content until something else bumps it.
                loadedWallpaperDirectory = dir
                bumpRevision()
            }
            return
        }
        if prepareDefaults {
            prepareSceneUserPropertyDefaults(for: wallpaper, scene: scene)
        }
        Self.log("Scene loaded: \(scene.objects.count) objects from \(wallpaper.project.file) [\(read.source)]")
        if !read.hasPackage {
            WallpaperPackageConverter.markVerified(wallpaperDirectory: dir, objectCount: scene.objects.count)
        }
        loadedScene = scene
        loadedDocument = read.document.map { ($0, "\(dir.path)|\(read.signature)") }
        loadedProject = read.project
        hasScriptSites = read.hasScriptSites
        loadedWallpaperDirectory = dir
        stateLock.withLock {
            loadedBindingTable = read.bindingTable
            loadedTextureReductionSize = TextureReduction.orthographicSize(of: scene)
        }
        bumpRevision()
    }

    /// What preparing `wallpaper` reads, as the scene cache key covers it.
    private func preparationRequest(for wallpaper: WEWallpaper, settingsKey: String) -> ScenePreparation.Request {
        let stored = UserDefaults.app.dictionary(forKey: settingsKey) as? [String: String] ?? [:]
        let split = ScenePreparation.split(storedValues: stored)
        let dir = wallpaper.wallpaperDirectory
        let settings = stateLock.withLock { pendingRenderSettings }
        return ScenePreparation.Request(directory: dir, sceneFile: wallpaper.project.file,
                                        edits: split.edits, userProperties: split.properties,
                                        settings: String(describing: settings.contentKey),
                                        displays: SceneCacheKey.Display.connected())
    }

    /// The scene and the document it was decoded from (for the scripts; nil when it isn't JSON the
    /// tolerant reader takes).
    private func decodeScene(_ data: Data, edits: [String: String]) throws -> (WEScene, SceneJSON?) {
        let resolved = try ScenePreparation.resolvedScene(data, edits: edits)
        return (try JSONDecoder().decode(WEScene.self, from: resolved), Self.document(resolved))
    }

    private static func document(_ data: Data) -> SceneJSON? {
        do {
            return try SceneScriptSiteBuilder.document(from: data)
        } catch {
            OWELog.error(.script, "scene.json can't be read for its scripts: \(error)")
            return nil
        }
    }

    /// project.json as JSON; nil (logged) when it can't be read.
    private static func project(in directory: URL) -> SceneJSON? {
        let url = directory.appending(path: "project.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try decodeTolerant(SceneJSON.self, from: Data(contentsOf: url))
        } catch {
            OWELog.error(.scene, "Can't read \(url.path): \(error)")
            return nil
        }
    }

    /// What changing user properties `keys` needs (`SceneBindingUpdate`), from the bindings the
    /// loaded scene and the documents its build read declare.
    func bindingUpdate(for keys: [String]) -> SceneBindingUpdate {
        SceneBindingUpdate(keys: keys, table: bindingTable)
    }

    /// How much of the whole scene a change of `keys` invalidates: only the app's own keys and
    /// scene-wide structural bindings rebuild it (`bindingUpdate(for:)`).
    func impact(of keys: [String]) -> SceneChangeImpact {
        bindingUpdate(for: keys).impact
    }

    /// The settings identity of the wallpaper in `directory`, resolved (and old path keys moved)
    /// once per load.
    private func settingsIdentity(for directory: URL) -> WallpaperSettingsIdentity {
        identityLock.lock()
        defer { identityLock.unlock() }
        if let settings, settings.directory == directory { return settings.identity }
        let identity = WallpaperSettingsIdentity.resolve(directory: directory)
        identity.seed(propertyScope)
        settings = (directory, identity)
        return identity
    }

    private func prepareSceneUserPropertyDefaults(for wallpaper: WEWallpaper, scene: WEScene) {
        guard wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame else { return }
        let identity = settingsIdentity(for: wallpaper.wallpaperDirectory)
        let key = identity.key(.userProperties, scope: propertyScope)
        let explicitKey = identity.key(.explicitUserProperties, scope: propertyScope)
        let defaults = UserDefaults.app
        let stored = defaults.bool(forKey: explicitKey)
            ? defaults.dictionary(forKey: key) as? [String: String] ?? [:]
            : [:]
        let values = Self.userPropertyValues(stored: stored,
                                             declared: Self.declaredUserProperties(in: wallpaper.wallpaperDirectory),
                                             scene: scene)
        // A display's own store keeps what the user saved, so displays whose properties are equal
        // stay equal (`WallpaperPropertyGroups` compares the stores) whichever of them loaded.
        if propertyScope == .shared { defaults.set(values, forKey: key) }
        WallpaperServices.shared.setUserProperties(values, wallpaper: propertyScope.runtimeKey(directory: wallpaper.wallpaperDirectory),
                                                           replacing: true)
    }

    /// The wallpaper's property values: what the user stored, else project.json's defaults (the
    /// first option for a combo without one). Nothing else is invented: WE shows exactly what the
    /// properties say, even when that selects no variant of a conditional layer.
    static func userPropertyValues(stored: [String: String], declared: [String: [String: Any]],
                                   scene: WEScene) -> [String: String] {
        var values = stored
        for (name, property) in declared where values[name] == nil {
            if let value = property["value"] {
                values[name] = sceneUserPropertyString(value)
            } else if property["type"] as? String == "combo",
                      let option = (property["options"] as? [[String: Any]])?.first?["value"] {
                values[name] = sceneUserPropertyString(option)
            }
        }
        for object in SceneObjectIdentity.assigningFallbackIDs(scene.objects) where object.textValue != nil {
            let prefix = "_owe_text_\(object.id ?? -1)_"
            if values[prefix + "font"] == nil, let font = object.font {
                values[prefix + "font"] = font
            }
            // A user-bound point size follows its property; a seeded override would pin it.
            if values[prefix + "size"] == nil, object.values[.pointsize]?.userPropertyName == nil,
               let pointSize = object.pointsize {
                values[prefix + "size"] = String(pointSize)
            }
        }
        return values
    }

    /// `general.properties` of project.json; empty when the wallpaper declares none.
    private static func declaredUserProperties(in directory: URL) -> [String: [String: Any]] {
        let url = directory.appending(path: "project.json")
        do {
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let general = root?["general"] as? [String: Any]
            return general?["properties"] as? [String: [String: Any]] ?? [:]
        } catch {
            OWELog.error(.scene, "Can't read user properties from \(url.path): \(error)")
            return [:]
        }
    }

    private func loadPreviewImage(wallpaperDir: URL) -> NSImage? {
        for name in ["preview.jpg", "preview.png", "preview.gif"] {
            let url = wallpaperDir.appending(path: name)
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }

    func metalContent() -> SceneMetalContent? {
        OWEPhaseTiming.measure(.sceneLoad) { metalContentUntimed() }
    }

    private func metalContentUntimed() -> SceneMetalContent? {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        let revision = metalRevision
        renderSettings = stateLock.withLock { pendingRenderSettings }
        // Rebuilding walks every object and re-resolves textures; the result only changes when
        // the scene or its user properties do.
        if cachedContentRevision == revision, let cachedContent {
            return cachedContent
        }
        if SceneWallpaperViewModel.isVideoType(currentWallpaper.project.type) {
            let content = videoContent()
            cachedContent = content
            cachedContentRevision = revision
            return content
        }
        let signpost = OWESignpost.begin(OWESignpost.scene, "metalContent")
        defer { signpost.end() }
        defer { endBuildTextures() }
        guard let authoredScene = loadedScene, let wallpaperDir = loadedWallpaperDirectory else { return nil }
        // Content is built from what the user properties say (`bindingTable`).
        let valueContext = userValueContext
        var scene = resolvedScene(authoredScene)
        scene.objects = SceneObjectIdentity.assigningFallbackIDs(scene.objects)
        let sceneSize = metalSceneSize(for: scene)
        if scene.general.projection == .orthographicAuto { Self.centreFirstImage(of: &scene, sceneSize: sceneSize) }
        let bloom = bloomSettings(for: scene.general)
        let lighting = SceneLightingSettings(scene.general, in: valueContext)
        modelPlans.removeAll()
        sceneEngineCombos = SceneEngineCombos(bloom: bloom, lighting: lighting,
                                              orthographic: !scene.general.projection.isPerspective,
                                              settings: renderSettings)
        // Hidden objects are built too: a script can show them (docs/scenescript-plan.md §4.3).
        let visibility = Dictionary(scene.objects.map { (String($0.id ?? -1), isObjectVisible($0)) },
                                    uniquingKeysWith: { first, _ in first })
        let authoredTransforms = SceneTransformHierarchy(objects: scene.objects, sceneSize: sceneSize)
        // WE draws objects in scene.json order; both lists carry that index so the renderer can interleave them.
        let layers: [SceneMetalLayer] = scene.objects.enumerated().compactMap { index, object in
            var layer = bindingTable.building(.object(object.id ?? index)) {
                buildLayer(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize, context: valueContext)
            }
            layer?.order = index
            return layer
        }
        var particleSystems: [SceneMetalParticleSystem] = []
        particleMaterialPlanTime = (0, 0)
        let memoBefore = effectTranslator?.sources.counts
        let particleCache = ParticleDefinitionCache(sharesParts: sharesParticleDefinitions)
        for (index, object) in scene.objects.enumerated() {
            let base = particleSystems.count
            let family = bindingTable.building(.object(object.id ?? index)) {
                buildParticleFamily(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize,
                                    pixelUnits: Self.particlesUsePixelUnits(scene), transforms: authoredTransforms,
                                    cache: particleCache)
            }
            for var system in family {
                system.order = index
                system.link?.parentIndex += base
                particleSystems.append(system)
            }
        }
        logParticleMaterialPlanTime(wallpaperDir: wallpaperDir, memoBefore: memoBefore)
        logParticleBuildTiming(particleCache.timing, wallpaperDir: wallpaperDir)
        particleCapacities = Dictionary(particleSystems.map { system in
            (system.order < scene.objects.count ? scene.objects[system.order].id ?? system.order : system.order,
             ParticleBudget.capacity(of: system))
        }, uniquingKeysWith: +)
        applyParticleBudget(to: &particleSystems, wallpaperDir: wallpaperDir)
        // A scene of scripts alone (groups whose scripts create layers) runs too, and so does one
        // of models alone (the default project arsenal).
        if !layers.isEmpty || !particleSystems.isEmpty || hasScriptSites || scene.objects.contains(where: { $0.model != nil }) {
            var transforms = authoredTransforms
            for layer in layers where layer.fillsScene {
                transforms.makeRoot(layer.id, local: SceneLocalTransform(origin: layer.position, scale: layer.scale, angle: layer.rotation))
            }
            var content = SceneMetalContent(size: sceneSize, layers: layers, particleSystems: particleSystems,
                                            bloom: bloom,
                                            transforms: transforms,
                                            camera: SceneCameraEffects(scene.general, in: valueContext),
                                            clearColor: scene.general.clearColor(in: valueContext),
                                            wallpaperKey: propertyStoreKey)
            content.general = scene.general
            content.motions = objectMotions(scene.objects, besides: layers, sceneSize: sceneSize, context: valueContext)
            content.visibility = visibility
            content.userVisibility = SceneUserVisibility(objects: scene.objects)
            content.objectIDs = scene.objects.map { $0.id ?? -1 }
            content.spatial = SceneSpatialContentBuilder(
                readFile: { self.assetData(named: $0, wallpaperDir: wallpaperDir) },
                wallpaperName: wallpaperDir.lastPathComponent).build(scene, context: valueContext, sceneSize: sceneSize)
            content.spatial.models = buildModels(content.spatial.models, wallpaperDir: wallpaperDir)
            SceneAttachmentCheck.logUnresolved(in: scene.objects, models: content.spatial.models, layers: layers,
                                               wallpaperName: wallpaperDir.lastPathComponent)
            content.scripts = scriptContent(wallpaperDir: wallpaperDir, sceneSize: sceneSize)
            content.timelines = loadedDocument.map {
                SceneTimelineSource(wallpaperID: loadedProjectId ?? Self.localWallpaperID(wallpaperDir),
                                    document: $0.document, signature: $0.signature)
            }
            content.sounds = soundBuilder(wallpaperDir: wallpaperDir).sounds(in: scene.objects, context: valueContext)
            content.lighting = SceneLightingContent(settings: lighting, lights: Self.lights(in: scene.objects, context: valueContext))
            content.lighting.cookies = SceneLightCookie.load(content.lighting.lights) { name, materialPath in
                loadMetalTexture(named: name, materialDir: materialPath, wallpaperDir: wallpaperDir)
            }
            content.volumetrics = volumetricsPlan(content.lighting.lights, wallpaperDir: wallpaperDir)
            content.engineCombos = sceneEngineCombos
            // An HDR content blooms through the HDR chain only (its `combine_srgb` when bloom is off).
            if sceneEngineCombos.hdr {
                content.hdrChain = engineChain("WE's HDR bloom", wallpaperDir: wallpaperDir, SceneHDRChain.build)
            } else {
                content.bloomChain = engineChain("WE's bloom", wallpaperDir: wallpaperDir, SceneBloomChain.build)
            }
            content.colorCorrection = engineChain("WE's colour correction", wallpaperDir: wallpaperDir,
                                                  SceneColorCorrection.build)
            // WE makes the fade only for a scene with camera paths (0x140181bae).
            if !content.spatial.cameraPaths.isEmpty {
                content.cameraFade = engineChain("WE's camera fade", wallpaperDir: wallpaperDir, SceneCameraFade.build)
            }
            // Not kept: it holds every decoded image, which the renderer drops once uploaded. The
            // instance asks again only after the revision changed, which rebuilds it anyway.
            cachedContent = nil
            return content
        }
        guard let preview = loadPreviewImage(wallpaperDir: wallpaperDir) else { return nil }
        return SceneMetalContent(size: sceneSize, layers: [SceneMetalLayer(id: "preview", name: "preview", source: .image(preview),
            position: sceneSize / 2, size: sceneSize, scale: SIMD2<Float>(repeating: 1),
            opacity: 1,
            brightness: 1, color: SIMD4<Float>(repeating: 1), text: nil,
            parallaxDepth: .zero, perspective: false,
            rotation: 0,
                effects: .identity,
            )], particleSystems: [],
            bloom: SceneBloomSettings(enabled: false, strength: 0, threshold: 0.7, tint: SIMD3<Float>(repeating: 1)))
    }

    // MARK: - Objects rebuilt alone

    /// Rebuilds objects `ids` off the render and main threads, on the content queue, and delivers
    /// them on the main queue (`rebuildObjects`); nil when they can't be rebuilt alone.
    func rebuildObjectsAsync(_ ids: Set<Int>, completion: @escaping (SceneObjectReplacement?) -> Void) {
        contentQueue.async { [weak self] in
            let replacement = self?.rebuildObjects(ids)
            DispatchQueue.main.async { completion(replacement) }
        }
    }

    /// Objects `ids` built again with the current user properties, for the renderer to swap in
    /// (`SceneObjectReplacement`): the layers and particle systems of image, text, shape and
    /// particle objects. Nil, for a whole-content rebuild instead, when one is anything else (a
    /// light, sound, model or camera, which the scene's own stages hold), isn't in the scene,
    /// builds nothing, emits from another layer's image, or changes the scene's particle budget
    /// factor. Takes the scene lock.
    func rebuildObjects(_ ids: Set<Int>) -> SceneObjectReplacement? {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        defer { endBuildTextures() }
        guard !ids.isEmpty, let authoredScene = loadedScene, let wallpaperDir = loadedWallpaperDirectory,
              !Self.isVideoType(currentWallpaper.project.type) else { return nil }
        let valueContext = userValueContext
        var scene = resolvedScene(authoredScene)
        scene.objects = SceneObjectIdentity.assigningFallbackIDs(scene.objects)
        let sceneSize = metalSceneSize(for: scene)
        if scene.general.projection == .orthographicAuto { Self.centreFirstImage(of: &scene, sceneSize: sceneSize) }
        let authoredTransforms = SceneTransformHierarchy(objects: scene.objects, sceneSize: sceneSize)
        var layers: [SceneMetalLayer] = []
        var particleSystems: [SceneMetalParticleSystem] = []
        var capacities = particleCapacities
        let particleCache = ParticleDefinitionCache(sharesParts: sharesParticleDefinitions)
        defer { logParticleBuildTiming(particleCache.timing, wallpaperDir: wallpaperDir) }
        for id in ids.sorted() {
            guard let index = scene.objects.firstIndex(where: { $0.id == id }) else { return nil }
            let object = scene.objects[index]
            guard object.light == nil, object.sound == nil, object.model == nil, object.cameraLayer == nil else { return nil }
            var layer = bindingTable.building(.object(id)) {
                buildLayer(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize, context: valueContext)
            }
            layer?.order = index
            let family = bindingTable.building(.object(id)) {
                buildParticleFamily(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize,
                                    pixelUnits: Self.particlesUsePixelUnits(scene), transforms: authoredTransforms,
                                    cache: particleCache)
            }
            guard layer != nil || !family.isEmpty, !family.contains(where: { !$0.emitterImages.isEmpty }) else { return nil }
            if let layer { layers.append(layer) }
            let base = particleSystems.count
            for var system in family {
                system.order = index
                system.link?.parentIndex += base
                particleSystems.append(system)
            }
            capacities[id] = family.isEmpty ? nil : family.reduce(0) { $0 + ParticleBudget.capacity(of: $1) }
        }
        let limit = renderSettings.particleBudget.limit
        let scale = ParticleBudget.scale(authored: ParticleBudget.total(Array(capacities.values)), budget: limit)
        guard particleSystems.isEmpty || scale == particleBudgetScale else { return nil }
        particleCapacities = capacities
        for index in particleSystems.indices { particleSystems[index].budgetScale = particleBudgetScale }
        var transforms = authoredTransforms
        for layer in layers where layer.fillsScene {
            transforms.makeRoot(layer.id, local: SceneLocalTransform(origin: layer.position, scale: layer.scale, angle: layer.rotation))
        }
        let rebuilt = scene.objects.filter { $0.id.map(ids.contains) ?? false }
        var content = SceneMetalContent(size: sceneSize, layers: layers, particleSystems: particleSystems,
                                        bloom: bloomSettings(for: scene.general), transforms: transforms,
                                        camera: SceneCameraEffects(scene.general, in: valueContext),
                                        clearColor: scene.general.clearColor(in: valueContext), wallpaperKey: propertyStoreKey)
        content.motions = objectMotions(rebuilt, besides: layers, sceneSize: sceneSize, context: valueContext)
        content.engineCombos = sceneEngineCombos
        return SceneObjectReplacement(objectIDs: Set(ids.map(String.init)), content: content)
    }

    // MARK: - Video as a scene

    /// Wraps a video wallpaper in a one-layer scene so the effect stack applies to it, the way
    /// Wallpaper Engine's own `scenes/videoplayer` does.
    private func videoContent() -> SceneMetalContent? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        // Runs on the content queue: a video AVFoundation refuses as it is plays from its repaired
        // copy, made here on first play when the import didn't make it.
        let url = videoStream == nil ? RepairedVideoCache.current.playableURL(for: currentWallpaper.mediaURL) : currentWallpaper.mediaURL
        let stream = videoStream ?? VideoTextureStream(url: url, device: device)
        guard let stream else {
            OWELog.error(.scene, "Could not open video \(url.lastPathComponent) for Metal playback")
            return nil
        }
        videoStream = stream

        // The display size is unknown here, so the scene is the video's own size and the renderer's
        // placement handles fitting. `keepaspect` then costs nothing: the layer fills its scene.
        let sceneSize = stream.frameSize
        builtVideoFrameSize = sceneSize
        let wallpaper = currentWallpaper
        let musicSync = VideoMusicSyncVisuals(
            zoomAmount: VideoMusicSyncSettings.bool(wallpaper, "zoomEnabled")
                ? Float(VideoMusicSyncSettings.double(wallpaper, "zoomAmount", default: 0.08)) : 0,
            tiltAmount: VideoMusicSyncSettings.bool(wallpaper, "tiltEnabled")
                ? Float(VideoMusicSyncSettings.double(wallpaper, "tiltAmount", default: 3)) : 0,
            saturationAmount: VideoMusicSyncSettings.bool(wallpaper, "saturationEnabled")
                ? Float(VideoMusicSyncSettings.double(wallpaper, "saturationAmount", default: 0.6)) : 0,
            levelSource: { [weak stream] in
                stream?.musicSyncLevel ?? WallpaperServices.shared.audioLevel
            })

        var layer = SceneMetalLayer(
            id: "video", name: "video", source: .video(stream),
            position: sceneSize / 2, size: sceneSize,
            scale: SIMD2<Float>(repeating: 1),
            opacity: 1,
            brightness: 1, color: SIMD4<Float>(repeating: 1), text: nil, parallaxDepth: .zero, perspective: false,
            rotation: 0,
            effects: .identity)
        layer.musicSync = musicSync
        return SceneMetalContent(size: sceneSize, layers: [layer], particleSystems: [],
                                 bloom: SceneBloomSettings(enabled: false, strength: 0, threshold: 0.7,
                                                           tint: SIMD3<Float>(repeating: 1)))
    }

    /// Plays or pauses every scene image's video texture with the wallpaper: 0 while it is
    /// paused, covered or frozen, so their decoders stop as a video wallpaper's does.
    func setEmbeddedVideoRate(_ rate: Float) {
        embeddedVideoLock.withLock {
            embeddedVideoRate = rate
            for stream in embeddedVideoStreams.allObjects { stream.setHostRate(rate) }
        }
    }

    /// Drives playback for the Metal video path; the AVKit path owns its own players.
    func updateVideoPlayback(playRate: Float, audioRate: Float, audioLevel: Double,
                             audioEnabled: Bool, volume: Float) {
        guard let stream = videoStream else { return }
        stream.setAudio(enabled: audioEnabled, volume: volume)
        let pace = VideoMusicSyncSettings.bool(currentWallpaper, "paceEnabled")
            ? VideoMusicSyncSettings.double(currentWallpaper, "paceAmount", default: 0.25)
            : 0
        stream.update(playRate: playRate, audioRate: audioRate,
                      audioLevel: stream.musicSyncLevel, paceAmount: pace)

        // The first frame decodes seconds after the layer is built, so the scene starts at the
        // placeholder size and would keep the wrong aspect ratio without a rebuild.
        if let built = builtVideoFrameSize, built != stream.frameSize {
            builtVideoFrameSize = stream.frameSize
            bumpRevision()
        }
    }

    /// An object's layer: an image, text or shape layer, with its user bindings; nil for objects
    /// that draw nothing of their own (groups, particle systems, sounds).
    private func buildLayer(_ object: WESceneObject, wallpaperDir: URL, sceneSize: SIMD2<Float>,
                            context: SceneValueContext) -> SceneMetalLayer? {
        var layer = buildMetalLayer(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize)
            ?? buildMetalTextLayer(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize)
            ?? buildShapeLayer(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize)
        layer?.bindings = SceneLayerBindings(object: object, builtWith: context)
        if layer?.fillsScene == false { layer?.tilt = SceneLocalTransform(object: object, sceneSize: sceneSize).tilt }
        return layer
    }

    // MARK: - Scripts

    /// What the renderer runs the scene's scripts from; nil without a scene document.
    private func scriptContent(wallpaperDir: URL, sceneSize: SIMD2<Float>) -> SceneScriptSceneContent? {
        guard let loadedDocument else { return nil }
        let storeKey = propertyStoreKey
        let modelData = SceneScriptModelDataStore()
        // Keyed on the install folder, not project.json (SceneScriptStorageKey); the key used before.
        let previousKey = loadedProjectId ?? Self.localWallpaperID(wallpaperDir)
        return SceneScriptSceneContent(
            wallpaperID: SceneScriptStorageKey.key(forWallpaperDirectory: wallpaperDir),
            document: loadedDocument.document, documentSignature: loadedDocument.signature,
            project: loadedProject,
            userValues: { WallpaperServices.shared.userProperties(wallpaper: storeKey) },
            file: { [weak self] path in self?.scriptFile(path, wallpaperDir: wallpaperDir) },
            modelData: modelData,
            legacyStorageID: SceneScriptStorageKey.legacyKeyToAdopt(previousKey: previousKey,
                                                                    wallpaperDirectory: wallpaperDir),
            makeLayer: { [weak self] json in
                self?.buildScriptLayer(json, wallpaperDir: wallpaperDir, sceneSize: sceneSize, modelData: modelData)
            })
    }

    /// A stable id for a wallpaper without a Workshop id: its directory's hash (timelines are keyed
    /// on it; `localStorage` uses `SceneScriptStorageKey`).
    static func localWallpaperID(_ directory: URL) -> String {
        SceneScriptStorageKey.localKey(forWallpaperDirectory: directory)
    }

    /// A file for the scripts (`createLayer` assets, texture animations). Called on a script
    /// thread, so it takes the scene lock like every other asset read.
    private func scriptFile(_ path: String, wallpaperDir: URL) -> Data? {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        return assetData(named: path, wallpaperDir: wallpaperDir)
    }

    /// An object a script created (`thisScene.createLayer`), built like the scene's own: a layer,
    /// a particle system or a sound. Off the main thread, under the scene lock.
    private func buildScriptLayer(_ json: [String: SceneJSON], wallpaperDir: URL, sceneSize: SIMD2<Float>,
                                  modelData: SceneScriptModelDataStore) -> SceneScriptCreatedObject? {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        defer { endBuildTextures() }
        let context = userValueContext
        let resolved: WESceneObject
        do {
            resolved = try UserPropertyBindingTable.decode(
                WESceneObject.self, from: UserPropertyBindingTable.resolving(.object(json), properties: userProperty))
        } catch {
            OWELog.error(.script, "createLayer: the object can't be decoded: \(error)")
            return nil
        }
        if resolved.particle != nil {
            var systems = buildParticleFamily(resolved, wallpaperDir: wallpaperDir, sceneSize: sceneSize,
                                              pixelUnits: loadedScene.map(Self.particlesUsePixelUnits) ?? true,
                                              transforms: SceneTransformHierarchy(objects: [resolved], sceneSize: sceneSize),
                                              cache: ParticleDefinitionCache(sharesParts: sharesParticleDefinitions))
            guard !systems.isEmpty else { return nil }
            // The scene's factor, or the family's own if it alone exceeds the budget.
            let own = ParticleBudget.scale(authored: systems.reduce(0) { $0 + ParticleBudget.capacity(of: $1) },
                                           budget: renderSettings.particleBudget.limit)
            for index in systems.indices { systems[index].budgetScale = min(particleBudgetScale, own) }
            let motion = SceneObjectMotion(object: resolved, sceneSize: sceneSize,
                                           bindings: SceneLayerBindings(object: resolved, builtWith: context))
            return .particles(systems, motion: motion)
        }
        if resolved.sound != nil {
            return soundBuilder(wallpaperDir: wallpaperDir).sounds(in: [resolved], context: context).first.map { .sound($0) }
        }
        if let model = resolved.model {
            // The renderer keys it by the id the script gave it.
            let object = SceneModelObject(id: "", name: resolved.name ?? "", order: Int.max, authored: model,
                                          animationLayers: resolved.animationLayers, renderValues: resolved.renderValues)
            let made: SceneModelObject?
            if case .loadedID(let token) = model.source {
                made = buildScriptModel(object, token: token, modelData: modelData, wallpaperDir: wallpaperDir)
            } else {
                made = buildModels([object], wallpaperDir: wallpaperDir).first
            }
            guard let built = made, built.plan != nil,
                  let node = SceneTransformHierarchy3D(objects: [resolved]).nodes.values.first else { return nil }
            let motion = SceneObjectMotion(object: resolved, sceneSize: sceneSize,
                                           bindings: SceneLayerBindings(object: resolved, builtWith: context))
            return .model(built, node: node, motion: motion)
        }
        return buildLayer(resolved, wallpaperDir: wallpaperDir, sceneSize: sceneSize, context: context).map { .layer($0) }
    }

    /// Finds the scene's sound files in the package, the folder, Workshop items and WE's assets.
    private func soundBuilder(wallpaperDir: URL) -> SceneSoundContentBuilder {
        let parser = pkgParser
        let workshop = workshopAssets
        return SceneSoundContentBuilder(wallpaperDirectory: wallpaperDir,
                                        packagedData: { parser?.extractFile(named: $0) },
                                        workshopURL: { workshop.url(for: $0) },
                                        workshopData: { path in workshop.located(path).map { ($0.data, $0.source) } },
                                        packageURL: parser == nil ? nil : pkgURL)
    }

    private func bloomSettings(for general: WESceneGeneral) -> SceneBloomSettings {
        SceneBloomSettings(general, in: userValueContext)
    }

    /// The scene's light objects, in scene order. They draw nothing; their transforms are in the
    /// content's hierarchy and motions like any other object's.
    static func lights(in objects: [WESceneObject], context: SceneValueContext) -> [SceneLightObject] {
        objects.compactMap { object in
            guard let light = object.light, let id = object.id else { return nil }
            let animated: [SceneLightValueField] = [.intensity, .radius, .exponent, .innercone, .outercone, .controlpoint]
            let hasTimelines = animated.contains { field in
                if case .object(let bound)? = light.values[field] { return bound.animation != nil }
                return false
            }
            return SceneLightObject(id: String(id), authored: light, light: SceneLight(light, in: context),
                                    depth: SceneLightDepth(object: object), hasTimelines: hasTimelines)
        }
    }

    /// Resolves user-bound values against this wallpaper's properties.
    /// The loaded scene with its user bindings resolved (`UserPropertyBindingTable.resolvedScene`);
    /// the authored scene, logged, when the resolved document can't be decoded.
    private func resolvedScene(_ authored: WEScene) -> WEScene {
        guard let document = loadedDocument?.document else { return authored }
        do {
            return try bindingTable.resolvedScene(authored, document: document, properties: userProperty)
        } catch {
            OWELog.error(.scene, "\(currentWallpaper.project.title): scene.json can't be decoded with its user properties: \(error)")
            return authored
        }
    }

    private var userValueContext: LiveSceneValueContext {
        LiveSceneValueContext(wallpaper: propertyStoreKey)
    }

    /// The scene's size in scene units (`general.orthogonalprojection` as WE reads it,
    /// docs/models-plan.md §2.1): an orthographic scene's width and height; `{"auto": true}`'s
    /// first image's size (0x14018b2c0); a perspective scene, whose objects are in world units,
    /// WE's default canvas.
    private func metalSceneSize(for scene: WEScene) -> SIMD2<Float> {
        switch scene.general.projection {
        case .orthographic(let width, let height):
            return SIMD2<Float>(Float(width), Float(height))
        case .orthographicAuto:
            if let size = Self.firstImage(of: scene)?.size?.parseVector2(), size.0 != 0, size.1 != 0 {
                return SIMD2<Float>(Float(size.0), Float(size.1))
            }
            OWELog.error(.scene, "\(loadedWallpaperDirectory?.lastPathComponent ?? "?"): orthogonalprojection auto "
                         + "needs an image with a size; the scene is 1920×1080")
            return SIMD2<Float>(1920, 1080)
        case .perspective:
            return SIMD2<Float>(1920, 1080)
        }
    }

    /// `{"auto": true}` sizes the scene from its first image object, which WE puts at the
    /// scene's centre (0x14018b2c0; it does so every frame, over what a script set [I]).
    private static func firstImage(of scene: WEScene) -> WESceneObject? {
        scene.objects.first { $0.image != nil }
    }

    private static func centreFirstImage(of scene: inout WEScene, sceneSize: SIMD2<Float>) {
        guard let index = scene.objects.firstIndex(where: { $0.image != nil }) else { return }
        scene.objects[index].origin = "\(sceneSize.x / 2) \(sceneSize.y / 2) 0"
    }

    /// An object's own `origin`, relative to its parent.
    private func localOrigin(for object: WESceneObject, sceneSize: SIMD2<Float>) -> SIMD2<Float> {
        SceneLocalTransform(object: object, sceneSize: sceneSize).origin
    }

    private func buildMetalLayer(_ object: WESceneObject, wallpaperDir: URL, sceneSize: SIMD2<Float>) -> SceneMetalLayer? {
        var layer = buildImageLayer(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize)
        layer?.systemImage = systemImage(of: object, wallpaperDir: wallpaperDir)
        return layer
    }

    /// The system texture an image object binds to its image's slot (0): its `instance`'s
    /// `usertextures`, else its material's first pass's (2963872291's album-art placeholder);
    /// nil (logged when it names one this app doesn't supply) for none.
    private func systemImage(of object: WESceneObject, wallpaperDir: URL) -> SceneSystemTexture? {
        var userTextures: [SceneJSON?] = [object.instance?.usertextures]
        if let imagePath = object.image,
           let model: WEModel = loadJSON(path: imagePath, wallpaperDir: wallpaperDir),
           let materialPath = model.material,
           let material: WEMaterial = loadJSON(path: materialPath, wallpaperDir: wallpaperDir) {
            userTextures.append(material.passes?.first?.usertextures)
        }
        return SceneSystemTexture.bindings(in: userTextures, owner: "Layer \(object.id ?? -1)")[0]
    }

    private func buildImageLayer(_ object: WESceneObject, wallpaperDir: URL, sceneSize: SIMD2<Float>) -> SceneMetalLayer? {
        guard let imagePath = object.image,
              let model: WEModel = loadJSON(path: imagePath, wallpaperDir: wallpaperDir),
              let materialPath = model.material,
              let material: WEMaterial = loadJSON(path: materialPath, wallpaperDir: wallpaperDir) else {
            return nil
        }
        if model.solidlayer == true {
            var layer = buildSolidLayer(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize)
            // `flat` has no `BLENDMODE`: a blend mode composites the fill through WE's material for it.
            if let mode = object.colorBlendMode, mode != 0 {
                layer.imageMaterial = buildBlendComposite(mode, object: object, wallpaperDir: wallpaperDir)
            } else {
                layer.imageMaterial = buildImageMaterial(materialPath, object: object, wallpaperDir: wallpaperDir)
            }
            return layer
        }
        guard let textureName = material.passes?.first?.textures?.first ?? nil,
              let source = loadMetalTexture(named: textureName, materialDir: materialPath, wallpaperDir: wallpaperDir,
                                            colour: true) else {
            return nil
        }
        let sceneInput = textureName == "_rt_FullFrameBuffer" || textureName == "_rt_MipMappedFrameBuffer"
        let size: SIMD2<Float>
        if model.fullscreen == true {
            size = sceneSize
        } else if let sizeString = object.size {
            let value = sizeString.parseVector2()
            size = SIMD2<Float>(Float(value.0), Float(value.1))
        } else if let declared = model.declaredSize {
            // The model's own size (WE's templates), not its first texture's.
            size = declared
        } else {
            // In pixels, and for a .tex the image's own size, not the padded allocation around it;
            // for a sprite sheet one frame's.
            if case let .animated(animation) = source, animation.images.isEmpty { return nil }
            size = source.unsizedLayerSize * textureReductionApplied(named: textureName, materialDir: materialPath,
                                                                     wallpaperDir: wallpaperDir)
        }
        let position: SIMD2<Float> = model.fullscreen == true
            ? sceneSize / 2
            : localOrigin(for: object, sceneSize: sceneSize)
        let rotation = Float(object.angles?.parseVector3().2 ?? 0)
        let staticScale = object.scale?.parseVector3() ?? (1, 1, 1)
        let objectColor = object.color?.parseVector3() ?? (1, 1, 1)
        let effectPlans = buildEffectPlans(object.effects ?? [], objectID: object.id ?? -1, wallpaperDir: wallpaperDir)
        var layer = SceneMetalLayer(id: String(object.id ?? -1), name: object.name ?? String(object.id ?? -1), source: source, position: position, size: size,
                       scale: SIMD2<Float>(Float(staticScale.0), Float(staticScale.1)),
                       opacity: Float(object.alpha ?? 1),
                       brightness: Float(object.brightness ?? 1), color: SIMD4<Float>(Float(objectColor.0), Float(objectColor.1), Float(objectColor.2), 1), text: nil,
                       parallaxDepth: Self.parallaxDepth(of: object),
                       perspective: object.perspective ?? false,
                               rotation: rotation, effects: .identity)
        layer.weEffects = effectPlans.plans
        layer.sceneInput = sceneInput
        if case .animated = source { layer.textureKey = textureName }
        layer.alignment = model.fullscreen == true ? nil : object.alignment
        layer.fillsScene = model.fullscreen == true
        // A layer whose image is the scene only exists to run effects on it; WE skips it without any.
        if sceneInput, effectPlans.plans.isEmpty { return nil }
        if !sceneInput {
            // A puppet is lit like any image: its mesh draws the image (`layer.puppet`) that its
            // effects, prelighting and own draw read.
            layer.imageMaterial = buildImageMaterial(materialPath, object: object, wallpaperDir: wallpaperDir,
                                                     prelit: !effectPlans.plans.isEmpty)
        }
        if let rig = model.puppet, !sceneInput {
            let imageSize = source.pixelSize * textureReductionApplied(named: textureName, materialDir: materialPath,
                                                                       wallpaperDir: wallpaperDir)
            layer.puppet = buildPuppet(rig, materialPath: materialPath, object: object, source: source,
                                       imageSize: imageSize, wallpaperDir: wallpaperDir)
        }
        return layer
    }

    /// A Puppet Warp image's mesh (`ScenePuppetPlan`); nil (logged) draws the image unwarped.
    private func buildPuppet(_ rig: String, materialPath: String, object: WESceneObject, source: SceneMetalTextureSource,
                             imageSize: SIMD2<Float>, wallpaperDir: URL) -> ScenePuppetPlan? {
        guard let translator = effectTranslator else { return nil }
        let builder = ImageMaterialPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { [weak self] name, path in self?.loadMetalTexture(named: name, materialDir: path, wallpaperDir: wallpaperDir) },
            sceneEngineCombos: sceneEngineCombos)
        do {
            let model = try MDLModel.load(path: rig, package: pkgParser, directory: wallpaperDir)
            return try ScenePuppetPlan.make(model: model, rigPath: rig, materialPath: materialPath, source: source,
                                            imageSize: imageSize, animationLayers: object.animationLayers,
                                            builder: builder)
        } catch {
            OWELog.error(.scene, "Puppet layer \(object.id ?? -1) draws its image unwarped, rig \(rig): \(error)")
            return nil
        }
    }

    /// The model objects' `.mdl`s and materials (`SceneModelBuilder`); without a translator none draws.
    /// Plans are kept by `.mdl` and skin for the content's life, so a script's clones share their
    /// original's (and its GPU buffers).
    private func buildModels(_ models: [SceneModelObject], wallpaperDir: URL) -> [SceneModelObject] {
        OWEPhaseTiming.measure(.particlesModels) { buildModelsUntimed(models, wallpaperDir: wallpaperDir) }
    }

    private func buildModelsUntimed(_ models: [SceneModelObject], wallpaperDir: URL) -> [SceneModelObject] {
        guard !models.isEmpty, let translator = effectTranslator else { return models }
        let known = models.map { object -> SceneModelObject in
            var object = object
            object.plan = object.authored.path.flatMap { modelPlans["\($0)|\(object.authored.skin)"] }
            return object
        }
        if known.allSatisfy({ $0.plan != nil }) { return known }
        let materials = ModelMaterialPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { [weak self] name, path in self?.loadMetalTexture(named: name, materialDir: path, wallpaperDir: wallpaperDir) },
            sceneEngineCombos: sceneEngineCombos)
        let package = pkgParser
        let built = SceneModelBuilder(materials: materials,
                                      loadModel: { try MDLModel.load(path: $0, package: package, directory: wallpaperDir) },
                                      wallpaperName: wallpaperDir.lastPathComponent).build(models)
        for object in built {
            guard let plan = object.plan, let path = object.authored.path else { continue }
            modelPlans["\(path)|\(object.authored.skin)"] = plan
        }
        return built
    }

    /// A model layer showing a script's model data (`thisScene.createModelData`, its token as the
    /// object's `model`); nil (logged) when the token names no data or no shape can draw.
    private func buildScriptModel(_ object: SceneModelObject, token: Int, modelData: SceneScriptModelDataStore,
                                  wallpaperDir: URL) -> SceneModelObject? {
        guard let translator = effectTranslator else { return nil }
        guard let data = modelData.snapshot(token)?.data else {
            OWELog.error(.script, "createLayer: model data \(token) of \(object.name) doesn't exist")
            return nil
        }
        let materials = ModelMaterialPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { [weak self] name, path in self?.loadMetalTexture(named: name, materialDir: path, wallpaperDir: wallpaperDir) },
            sceneEngineCombos: sceneEngineCombos)
        var built = object
        let planner = SceneScriptModelPlanBuilder(materials: materials, wallpaperName: wallpaperDir.lastPathComponent)
        let geometry = SceneScriptModelGeometry(store: modelData, token: token)
        // `replaceData` re-creates the model from its new shapes, on the script's thread
        // (`SceneScriptModelGeometry.dataReplaced`). The planner reads this model's assets and
        // caches, which the scene lock owns, so it plans under it as `createLayer` does.
        geometry.replan = { [weak self, weak geometry] data in
            guard let self, let geometry else { return nil }
            self.sceneLock.lock()
            defer { self.sceneLock.unlock() }
            return planner.plan(data, geometry: geometry, objectName: object.name)
        }
        built.plan = planner.plan(data, geometry: geometry, objectName: object.name)
        return built
    }

    /// The image's own material through WE's shader; nil (logged when it's a failure) keeps the native draw.
    /// `prelit`: the layer has effects, so WE lights it before them (`ImageMaterialPlan.prelighting`).
    private func buildImageMaterial(_ materialPath: String, object: WESceneObject, wallpaperDir: URL,
                                    prelit: Bool = false) -> ImageMaterialPlan? {
        guard let translator = effectTranslator else { return nil }
        let builder = ImageMaterialPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { [weak self] name, path in self?.loadMetalTexture(named: name, materialDir: path, wallpaperDir: wallpaperDir) },
            sceneEngineCombos: sceneEngineCombos, blending: blendingOverride(for: object))
        do {
            return try builder.build(materialPath: materialPath, colorBlendMode: object.colorBlendMode,
                                     clampUVs: object.clampuvs, prelit: prelit)
        } catch {
            OWELog.error(.scene, "Image layer \(object.id ?? -1) draws natively, material \(materialPath): \(error)")
            return nil
        }
    }

    /// A layer's own image composited with its `colorBlendMode` through WE's composite material
    /// (`ImageMaterialPlanBuilder.buildBlendComposite`); nil (logged) keeps the native draw.
    private func buildBlendComposite(_ mode: Int, object: WESceneObject, wallpaperDir: URL) -> ImageMaterialPlan? {
        guard let translator = effectTranslator else { return nil }
        let builder = ImageMaterialPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { [weak self] name, path in self?.loadMetalTexture(named: name, materialDir: path, wallpaperDir: wallpaperDir) },
            sceneEngineCombos: sceneEngineCombos, blending: blendingOverride(for: object))
        do {
            return try builder.buildBlendComposite(colorBlendMode: mode)
        } catch {
            OWELog.error(.scene, "Layer \(object.id ?? -1) draws without its blend mode \(mode): \(error)")
            return nil
        }
    }

    /// `models/util/solidlayer*.json`: WE's `flat` shader fills the quad with the object's `color`.
    /// The colour is baked into a generated texture so authored effects see the coloured image, as
    /// they do in WE; `alpha` stays on the layer and is applied when the quad is drawn.
    private func buildSolidLayer(_ object: WESceneObject, wallpaperDir: URL,
                                 sceneSize: SIMD2<Float>) -> SceneMetalLayer {
        let authoredSize = object.size.map { value -> SIMD2<Float> in
            let parsed = value.parseVector2()
            return SIMD2<Float>(Float(parsed.0), Float(parsed.1))
        }
        // An authored size is the quad's even when it is zero: WE draws nothing of an empty quad
        // (2963872291's 'Player Options', a 0×0 host for the music player's scripts). Only a
        // layer without a size takes the scene's.
        let size = authoredSize ?? sceneSize
        let color = object.color?.parseVector3() ?? (1, 1, 1)
        let staticScale = object.scale?.parseVector3() ?? (1, 1, 1)
        var layer = SceneMetalLayer(id: String(object.id ?? -1), name: object.name ?? String(object.id ?? -1),
                       source: .image(Self.solidImage(red: color.0, green: color.1, blue: color.2)),
                       position: localOrigin(for: object, sceneSize: sceneSize),
                       size: size,
                       scale: SIMD2<Float>(Float(staticScale.0), Float(staticScale.1)),
                       opacity: Float(object.alpha ?? 1),
                       brightness: Float(object.brightness ?? 1), color: SIMD4<Float>(repeating: 1), text: nil,
                       parallaxDepth: Self.parallaxDepth(of: object),
                       perspective: object.perspective ?? false,
                       rotation: Float(object.angles?.parseVector3().2 ?? 0), effects: .identity)
        layer.weEffects = buildEffectPlans(object.effects ?? [], objectID: object.id ?? -1, wallpaperDir: wallpaperDir).plans
        layer.alignment = object.alignment
        layer.solidFill = SIMD4(Float(color.0), Float(color.1), Float(color.2), 1)
        // The colour is the image: a bound colour rebuilds the layer.
        bindingTable.baked(.objectField(.color), of: .object(object.id ?? -1))
        return layer
    }

    /// A 1x1 opaque image of one colour; the quad stretches it to the layer's size. Its texel is
    /// the colour's value as authored, like WE's `util/white` tinted by `g_Color4`. Drawing it with
    /// AppKit would convert it to the display's colour space (e.g. Display P3) and shift it.
    static func solidImage(red: Double, green: Double, blue: Double) -> NSImage {
        pixelImage([red, green, blue, 1])
    }

    /// A 1x1 image holding `rgba` (0...1 each) as straight-alpha bytes, without colour management.
    static func pixelImage(_ rgba: [Double]) -> NSImage {
        let bytes = rgba.map { UInt8((min(max($0.isFinite ? $0 : 0, 0), 1) * 255).rounded()) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder32Big),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            preconditionFailure("a 1x1 RGBA8 image is always representable")
        }
        return NSImage(cgImage: image, size: NSSize(width: 1, height: 1))
    }

    /// Text is laid out and rasterised by the renderer every frame (its string can change); the
    /// layer's source is only a placeholder. `size` is the block before auto-sizing.
    private func buildMetalTextLayer(_ object: WESceneObject, wallpaperDir: URL, sceneSize: SIMD2<Float>) -> SceneMetalLayer? {
        guard let text = object.textValue else { return nil }
        let sizeValue = object.size?.parseVector2() ?? (0, 0)
        let textScale = object.scale?.parseVector3() ?? (1, 1, 1)
        let color = object.color?.parseVector3() ?? (1, 1, 1)
        // Padding is authored as "32" or "32 32"; a scalar applies to both axes. Absent, WE's 32.
        let paddingParts = (object.padding ?? "").split(separator: " ").compactMap { Float($0) }
        let firstPadding = paddingParts.first ?? WETextDefaults.padding
        let padding = SIMD2<Float>(firstPadding, paddingParts.count > 1 ? paddingParts[1] : firstPadding)
        let textConfig = SceneMetalText(value: text, font: registerFont(object.font),
                                         pointSize: CGFloat(object.pointsize ?? WETextDefaults.pointSize),
                                         horizontalAlignment: object.horizontalalign,
                                         verticalAlignment: object.verticalalign,
                                         padding: padding,
                                         maxWidth: object.limitwidth == true
                                            ? Float(object.maxwidth ?? WETextDefaults.maxWidth) : nil,
                                         maxRows: object.limitrows == true ? object.maxrows ?? WETextDefaults.maxRows : nil,
                                         useEllipsis: object.limituseellipsis ?? false,
                                         anchor: object.anchor, blockAlign: object.blockalign ?? false,
                                         effects: object.textEffects.effects)
        var layer = SceneMetalLayer(id: String(object.id ?? -1), name: object.name ?? String(object.id ?? -1),
                               source: .image(transparentPlaceholderImage),
                               position: localOrigin(for: object, sceneSize: sceneSize),
                               size: SIMD2<Float>(Float(sizeValue.0), Float(sizeValue.1)),
                               scale: SIMD2<Float>(Float(textScale.0), Float(textScale.1)),
                               opacity: Float(object.alpha ?? 1),
                               brightness: Float(object.brightness ?? 1), color: SIMD4<Float>(Float(color.0), Float(color.1), Float(color.2), 1), text: textConfig, parallaxDepth: Self.parallaxDepth(of: object),
                               perspective: object.perspective ?? false,
                               rotation: Float(object.angles?.parseVector3().2 ?? 0),
                               effects: .identity)
        // No alignment: the lines sit around the origin by `horizontalalign` and `verticalalign` as
        // WE places them (`SceneTextLayout.baselineOrigins`), in a block centred on them (`boxCenter`).
        // WE runs a text object's effects on its rasterised text; the renderer rasterises before effects run.
        layer.weEffects = buildEffectPlans(object.effects ?? [], objectID: object.id ?? -1, wallpaperDir: wallpaperDir).plans
        // Drawn through WE's `font` material, which reads its texture as coverage: effects' output
        // isn't that, and `font` has no blend-mode combo, so those layers keep the native draw.
        // Text with font effects draws its coloured raster (`SceneTextEffects`), not coverage.
        if layer.weEffects.isEmpty, (object.colorBlendMode ?? 0) == 0, textConfig.effects == nil {
            layer.imageMaterial = buildTextMaterial(object, wallpaperDir: wallpaperDir)
        }
        return layer
    }

    /// A text object's `font` material (`materials/fonts/basefont.json`), whose `g_Texture0` is the
    /// renderer's rasterised text. WE's MSDF atlas (`msdf`, outline, drop shadow) isn't generated:
    /// CoreText's coverage stands in for it, as for plain fonts. nil (logged) keeps the native draw.
    private func buildTextMaterial(_ object: WESceneObject, wallpaperDir: URL) -> ImageMaterialPlan? {
        guard let translator = effectTranslator else { return nil }
        let builder = ImageMaterialPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { _, _ in nil },
            sceneEngineCombos: sceneEngineCombos)
        let materialPath = "materials/fonts/basefont.json"
        do {
            return try builder.buildText(materialPath: materialPath)
        } catch {
            OWELog.error(.scene, "Text layer \(object.id ?? -1) draws natively, material \(materialPath): \(error)")
            return nil
        }
    }

    /// A `shape` object (the light-shaft presets' `"shape": "quad"`): an image object without an
    /// image that only hosts its effects. WE builds it as an image subclass (0x1401907af) whose load
    /// (0x14025fac0) sizes it as a square the scene's orthographic height on each side, and which
    /// writes `DIRECTDRAW` 1 into the combos of every pass of its effects before they load
    /// (0x14025ff50, called per pass at 0x1401e7ad2), so an effect draws on nothing, not on an image.
    private func buildShapeLayer(_ object: WESceneObject, wallpaperDir: URL, sceneSize: SIMD2<Float>) -> SceneMetalLayer? {
        guard object.shape != nil, let effects = object.effects, !effects.isEmpty else { return nil }
        let plans = buildEffectPlans(effects, objectID: object.id ?? -1, wallpaperDir: wallpaperDir,
                                     objectCombos: Self.shapeEffectCombos).plans
        guard !plans.isEmpty else { return nil }
        let position = localOrigin(for: object, sceneSize: sceneSize)
        let size: SIMD2<Float>
        if let sizeString = object.size {
            let value = sizeString.parseVector2()
            size = SIMD2<Float>(Float(value.0), Float(value.1))
        } else {
            size = Self.shapeSize(sceneSize: sceneSize)
        }
        // Its transform is any object's (the base class 0x1401e6980 reads `scale` as for an image).
        let staticScale = object.scale?.parseVector3() ?? (1, 1, 1)
        var layer = SceneMetalLayer(id: String(object.id ?? -1), name: object.name ?? String(object.id ?? -1),
                       source: .image(transparentPlaceholderImage), position: position, size: size,
                       scale: SIMD2<Float>(Float(staticScale.0), Float(staticScale.1)),
                       opacity: Float(object.alpha ?? 1),
                       brightness: 1, color: SIMD4<Float>(repeating: 1), text: nil, parallaxDepth: Self.parallaxDepth(of: object), perspective: object.perspective ?? false,
                       rotation: Float(object.angles?.parseVector3().2 ?? 0),
                       effects: .identity)
        layer.weEffects = plans
        layer.alignment = object.alignment
        layer.solidFill = SIMD4(1, 1, 1, 0)
        // Its last pass adds to the scene (the shape class's blend state, 0x140260790).
        layer.additive = true
        return layer
    }

    /// The combos a shape object writes into each pass of its effects (0x14025ff50).
    static let shapeEffectCombos = ["DIRECTDRAW": 1]

    /// A shape object's size: the scene's orthographic height on both sides (0x14025fac0 reads
    /// the height the scene stored from `orthogonalprojection` at 0x1401875fb).
    static func shapeSize(sceneSize: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2<Float>(repeating: sceneSize.y)
    }

    /// A fully transparent 1x1 placeholder texture for procedural shape layers (e.g. light shafts) that
    /// have no authored image of their own; only the effect's computed alpha should ever become visible.
    private var transparentPlaceholderImage: NSImage {
        Self.pixelImage([1, 1, 1, 0])
    }

    private func registerFont(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if let registered = registeredFontNames[path] { return registered }
        let resolver = SceneFontResolver(
            wallpaperData: { self.loadFontData(named: $0) },
            assetDirectories: WallpaperEngineAssets.searchDirectories,
            workshop: WorkshopAssetResolver(roots: WorkshopAssetResolver.defaultRoots()))
        let data: Data
        switch resolver.resolve(path) {
        case .system(let family)?:
            registeredFontNames[path] = family
            // The per-layer font setting is seeded with the scene's name (`systemfont_*`).
            if let installed = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12) {
                SceneFontRegistry.register(postScriptName: installed.fontName, names: [path])
            }
            return family
        case .data(let bytes, _)?:
            data = bytes
        case nil:
            OWELog.error(.scene, "Font \"\(path)\" not found in the wallpaper, WE assets or workshop items; using the system font")
            return path
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let descriptor = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else {
            return path
        }

        // Fonts inside a PKG have no filesystem URL, so register their in-memory
        // CGFont before NSFont(name:) is used by either text rendering path.
        if let provider = CGDataProvider(data: data as CFData),
           let font = CGFont(provider) {
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterGraphicsFont(font, &error)
            let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
            SceneFontRegistry.register(font, names: [path, name, family ?? ""])
        }
        registeredFontNames[path] = name
        return name
    }

    /// The wallpaper's own package or folder; `SceneFontResolver` handles the other sources.
    private func loadFontData(named path: String) -> Data? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let keys = [path, normalized, (normalized as NSString).lastPathComponent]
        for key in keys {
            if let cached = assetDataCache[key] { return cached }
            if let data = pkgParser?.extractFile(named: key) {
                assetDataCache[key] = data
                return data
            }
        }
        if let entry = pkgParser?.fileList.first(where: {
            let candidate = $0.replacingOccurrences(of: "\\", with: "/")
            return candidate.caseInsensitiveCompare(normalized) == .orderedSame
                || (candidate as NSString).lastPathComponent.caseInsensitiveCompare((normalized as NSString).lastPathComponent) == .orderedSame
        }), let data = pkgParser?.extractFile(named: entry) {
            assetDataCache[path] = data
            return data
        }
        if let directory = loadedWallpaperDirectory {
            for candidate in [normalized, (normalized as NSString).lastPathComponent] {
                let data: Data?
                do {
                    data = try AssetPathResolver.data(candidate, in: directory)
                } catch {
                    OWELog.error(.scene, "Failed to read font \(candidate): \(error)")
                    continue
                }
                if let data {
                    assetDataCache[path] = data
                    return data
                }
            }
        }
        return nil
    }


    /// Shared by every scene: translated variants are cached in memory and on disk.
    /// Optional only for its callers' `guard let`s; it always exists.
    static let defaultEffectTranslator: ShaderVariantTranslator? =
        ShaderVariantTranslator(compiler: ShaderCompilerFactory.makeDefault())
    /// This scene's translator (`init`).
    private let effectTranslator: ShaderVariantTranslator?

    /// One of WE's post-processing chains (`SceneBloomChain`, `SceneHDRChain`) planned by `build`;
    /// nil, logged, when it can't be planned.
    private func engineChain<Chain>(_ name: String, wallpaperDir: URL,
                                    _ build: (SceneEffectPlanBuilder) throws -> Chain) -> Chain? {
        guard let translator = effectTranslator else { return nil }
        let builder = SceneEffectPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { [weak self] name, materialPath in
                self?.loadMetalTexture(named: name, materialDir: materialPath, wallpaperDir: wallpaperDir)
            },
            sceneEngineCombos: sceneEngineCombos)
        do {
            return try build(builder)
        } catch {
            OWELog.error(.scene, "\(name) can't be planned; the scene draws without it: \(error)")
            return nil
        }
    }

    /// WE's volumetric lights (`SceneVolumetricsPlan`); nil, logged, when they can't be planned.
    private func volumetricsPlan(_ lights: [SceneLightObject], wallpaperDir: URL) -> SceneVolumetricsPlan? {
        guard lights.contains(where: \.light.castVolumetrics), let translator = effectTranslator else { return nil }
        let builder = SceneEffectPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { [weak self] name, materialPath in
                self?.loadMetalTexture(named: name, materialDir: materialPath, wallpaperDir: wallpaperDir)
            },
            sceneEngineCombos: sceneEngineCombos)
        do {
            return try SceneVolumetricsPlan.build(lights: lights, settings: renderSettings, builder: builder)
        } catch {
            OWELog.error(.scene, "WE's volumetrics can't be planned; the scene draws without them: \(error)")
            return nil
        }
    }

    /// Plans each visible effect for Wallpaper Engine's own shaders. An effect that can't be
    /// planned (no toolchain, sources missing) is left out, with the reason logged.
    private func buildEffectPlans(_ effects: [WEObjectEffect], objectID: Int, wallpaperDir: URL,
                                  objectCombos: [String: Int] = [:]) -> (plans: [SceneEffectPlan], handled: Set<Int>) {
        guard !effects.isEmpty, let translator = effectTranslator else { return ([], []) }
        var builder = SceneEffectPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { [weak self] name, materialPath in
                self?.loadMetalTexture(named: name, materialDir: materialPath, wallpaperDir: wallpaperDir)
            },
            sceneEngineCombos: sceneEngineCombos,
            readWallpaperFile: { [weak self] path in
                guard let self, let data = self.wallpaperData(named: path, wallpaperDir: wallpaperDir) else { return nil }
                return self.bindingTable.resolvedData(data, path: path, properties: self.userProperty)
            })
        builder.objectCombos = objectCombos
        var plans: [SceneEffectPlan] = []
        var handled = Set<Int>()
        let storeKey = propertyStoreKey
        for (index, effect) in effects.enumerated() {
            // The app's own switch removes an effect; WE's `visible` only hides it, so a script or a
            // user property can show it again.
            let enabled = userProperty(
                sceneAuthoredEffectEnabledKey(objectID: objectID, effectIndex: index)) != "false"
            guard enabled else {
                handled.insert(index)
                continue
            }
            do {
                var plan = try builder.build(effect, owner: (objectID, index), overrides: { key in
                    SceneEffectOverride.stored(
                        property: sceneAuthoredEffectOverrideKey(objectID: objectID, effectIndex: index, parameter: key),
                        lookup: { WallpaperServices.shared.userPropertyString($0, wallpaper: storeKey) })
                })
                plan.effectIndex = index
                plan.visible = isEffectVisible(effect)
                plans.append(plan)
                handled.insert(index)
            } catch {
                OWELog.error(.scene, "Effect \(effect.file) on object \(objectID) can't use WE shaders: \(error)")
            }
        }
        return (plans, handled)
    }






    /// Key of this wallpaper instance's user properties in the script engine's store.
    var propertyStoreKey: String {
        propertyScope.runtimeKey(directory: loadedWallpaperDirectory ?? currentWallpaper.wallpaperDirectory)
    }

    /// This wallpaper's current value of a user property.
    func userProperty(_ name: String) -> String? {
        WallpaperServices.shared.userPropertyString(name, wallpaper: propertyStoreKey)
    }

    /// The Scene Inspector's blending for the object's material (`sceneObjectBlendingKey`); nil
    /// when it has none, or one its kind of layer doesn't draw with, which keeps the material's.
    private func blendingOverride(for object: WESceneObject) -> WEMaterialBlending? {
        guard let objectID = object.id, let value = userProperty(sceneObjectBlendingKey(objectID: objectID)) else { return nil }
        let supported = object.particle != nil ? WEMaterialBlending.particleSystem : WEMaterialBlending.imageLayer
        guard let blending = WEMaterialBlending(authored: value), supported.contains(blending) else {
            OWELog.error(.scene, "Object \(objectID) keeps its material's blending: \"\(value)\" isn't one it draws with")
            return nil
        }
        return blending
    }

    private func isObjectVisible(_ object: WESceneObject) -> Bool {
        SceneUserVisibility.Site(object).isShown(userProperty)
    }

    private func isEffectVisible(_ effect: WEObjectEffect) -> Bool {
        Self.isEffectVisible(effect, userProperty: userProperty)
    }

    /// An effect bound to a user property follows it; with the property missing it keeps its
    /// authored `visible` (default true), as objects do.
    static func isEffectVisible(_ effect: WEObjectEffect, userProperty: (String) -> String?) -> Bool {
        SceneUserVisibility.Gate(visible: effect.visible, condition: effect.visibleCondition,
                                 property: effect.visibleUserProperty).isShown(userProperty)
    }

    /// An object's `parallaxDepth` (WE's 1 1 when absent), as the layer carries it.
    static func parallaxDepth(of object: WESceneObject) -> SIMD3<Float> {
        let value = object.parallaxDepthValue
        return SIMD3<Float>(Float(value.0), Float(value.1), Float(value.2))
    }

    /// `colour`: the texture is a layer's or particle's own image, which "Optimise textures" may
    /// load as a prepared BC7 texture (`TexturePreparation`). Every other texture (masks, flow and
    /// normal maps, anything a material reads as data) loads as stored.
    private func loadMetalTexture(named name: String, materialDir: String, wallpaperDir: URL,
                                  colour: Bool = false) -> SceneMetalTextureSource? {
        OWEPhaseTiming.measure(.texture) {
            loadMetalTextureUntimed(named: name, materialDir: materialDir, wallpaperDir: wallpaperDir, colour: colour)
        }
    }

    private func loadMetalTextureUntimed(named name: String, materialDir: String, wallpaperDir: URL,
                                         colour: Bool) -> SceneMetalTextureSource? {
        // WE's texture reduction loads a smaller mipmap (`TextureReduction`), cached apart.
        let reduction = renderSettings.textureReduction
        let optimise = colour && renderSettings.optimiseTextures && TexturePreparation.deviceSupportsBC7
        let cacheKey = "\(materialDir)|\(name)" + (reduction > 1 ? "|reduced\(reduction)" : "") + (optimise ? "|bc7" : "")
        if let cached = cachedTexture(cacheKey) { return cached }
        OWEFrameMetrics.countTextureDecode()
        let signpost = OWESignpost.begin(OWESignpost.scene, "decodeTexture")
        defer { signpost.end() }

        if name.hasPrefix("_rt") || name.hasPrefix("rt/") {
            return cacheTexture(.image(transparentPlaceholderImage), for: cacheKey)
        }

        for path in Self.texturePaths(named: name, materialDir: materialDir) {
            let data = assetData(named: path, wallpaperDir: wallpaperDir)
            guard let data else { continue }
            let parser = TEXParser(data: data)
            if let animation = parser.extractAnimatedImages(reduction: reduction) {
                return cacheTexture(.animated(animation), for: cacheKey)
            }
            if let texture = parser.extractCompressedTexture(reduction: reduction) {
                return cacheTexture(.dxt(texture), for: cacheKey)
            }
            // A video texture plays (`IVideoTexture`); its poster frame stays the fallback.
            if let video = parser.extractVideoData(), let device = MTLCreateSystemDefaultDevice(),
               let stream = VideoTextureStream.embedded(mp4: video, device: device) {
                embeddedVideoLock.withLock {
                    embeddedVideoStreams.add(stream)
                    stream.setHostRate(embeddedVideoRate)
                }
                return cacheTexture(.video(stream), for: cacheKey)
            }
            // A padded raw image keeps its allocation (`TEXRawImageRep.makeAllocationTexture`); a
            // prepared texture holds only the image.
            let prepares = optimise && !parser.isPaddedRawImage()
            let mipmaps = prepares ? parser.firstImageMipmapCount() ?? 1 : 1
            let level = TextureReduction.loadedMipmap(reduction: reduction, mipmapCount: mipmaps)
            let preparedKey = prepares ? TexturePreparation.key(texData: data, level: level) : nil
            if let preparedKey, let prepared = TexturePreparation.cachedTexture(key: preparedKey) {
                return cacheTexture(.dxt(prepared), for: cacheKey)
            }
            if let image = parser.extractImage(reduction: reduction) {
                if let preparedKey { TexturePreparation.schedule(image, key: preparedKey, mipmaps: mipmaps - level) }
                return cacheTexture(.image(image), for: cacheKey)
            }
        }
        guard let image = loadTexture(named: name, materialDir: materialDir, wallpaperDir: wallpaperDir) else { return nil }
        return cacheTexture(.image(image), for: cacheKey)
    }

    /// Where a material's texture `name` may be, in the order they are tried.
    private static func texturePaths(named name: String, materialDir: String) -> [String] {
        let materialDirPath = (materialDir as NSString).deletingLastPathComponent
        let root = materialDirPath.split(separator: "/").first.map(String.init) ?? "materials"
        return Array(Set(["\(materialDirPath)/\(name).tex", "\(root)/\(name).tex",
                          "materials/\(name).tex", "\(name).tex"]))
    }

    /// How much smaller than its header's image texture `name` loaded under WE's texture reduction:
    /// 2 when it skipped the first of several mipmaps, else 1. A layer sized by its image keeps the
    /// header's size, as WE's texture keeps it (`TextureReduction`).
    private func textureReductionApplied(named name: String, materialDir: String, wallpaperDir: URL) -> Float {
        let reduction = renderSettings.textureReduction
        guard reduction > 1 else { return 1 }
        for path in Self.texturePaths(named: name, materialDir: materialDir) {
            guard let data = assetData(named: path, wallpaperDir: wallpaperDir) else { continue }
            let mipmaps = TEXParser(data: data).firstImageMipmapCount() ?? 1
            return Float(1 << TextureReduction.loadedMipmap(reduction: reduction, mipmapCount: mipmaps))
        }
        return 1
    }

    /// How every object that isn't a drawn layer (groups, particle systems) moves, so its
    /// children and its own particles follow it live.
    private func objectMotions(_ objects: [WESceneObject], besides layers: [SceneMetalLayer], sceneSize: SIMD2<Float>,
                               context: SceneValueContext) -> [String: SceneObjectMotion] {
        let layerIDs = Set(layers.map(\.id))
        var motions: [String: SceneObjectMotion] = [:]
        for object in objects {
            guard let id = object.id.map(String.init), !layerIDs.contains(id) else { continue }
            motions[id] = SceneObjectMotion(object: object, sceneSize: sceneSize,
                                            bindings: SceneLayerBindings(object: object, builtWith: context))
        }
        return motions
    }

    /// Thins the scene's particle systems to the user's budget (`ParticleBudget`), logging it once
    /// per scene and budget.
    private func applyParticleBudget(to systems: inout [SceneMetalParticleSystem], wallpaperDir: URL) {
        let report = ParticleBudget.apply(renderSettings.particleBudget.limit, to: &systems)
        particleBudgetScale = report?.scale ?? 1
        guard let report, loggedParticleBudget?.directory != wallpaperDir || loggedParticleBudget?.report != report else { return }
        loggedParticleBudget = (wallpaperDir, report)
        OWELog.info(.scene, String(format: "%@: %d particles authored over the budget of %d; every system's maximum and rate × %.3f",
                                   wallpaperDir.lastPathComponent, report.authored, report.budget, report.scale))
    }

    /// A particle object's system followed by its children (`ParticleFamilyBuilder`).
    /// WE's particle defaults are in pixels in an orthographic scene (its parser's flag,
    /// `wallpaper64.exe` 0x14018768a, set with the scene's ortho bit), in world units otherwise.
    static func particlesUsePixelUnits(_ scene: WEScene) -> Bool {
        !scene.general.projection.isPerspective
    }

    private func buildParticleFamily(_ object: WESceneObject, wallpaperDir: URL, sceneSize: SIMD2<Float>, pixelUnits: Bool,
                                     transforms: SceneTransformHierarchy,
                                     cache: ParticleDefinitionCache) -> [SceneMetalParticleSystem] {
        OWEPhaseTiming.measure(.particlesModels) {
            buildParticleFamilyUntimed(object, wallpaperDir: wallpaperDir, sceneSize: sceneSize, pixelUnits: pixelUnits,
                                       transforms: transforms, cache: cache)
        }
    }

    private func buildParticleFamilyUntimed(_ object: WESceneObject, wallpaperDir: URL, sceneSize: SIMD2<Float>,
                                            pixelUnits: Bool, transforms: SceneTransformHierarchy,
                                            cache: ParticleDefinitionCache) -> [SceneMetalParticleSystem] {
        guard let particlePath = object.particle else { return [] }
        // The emitter's full world transform: its own and its parents' origin, scale and angle.
        let world = object.id.map { transforms.world(of: String($0)) }
            ?? SceneAffineTransform(SceneLocalTransform(object: object, sceneSize: sceneSize))
        let builder = ParticleFamilyBuilder(
            load: { [weak self] path in self?.loadJSON(path: path, wallpaperDir: wallpaperDir) },
            build: { [weak self] path, system, world, overrides in
                self?.buildMetalParticleSystem(path, particleSystem: system, object: object, world: world,
                                               overrides: overrides, sceneSize: sceneSize, pixelUnits: pixelUnits,
                                               wallpaperDir: wallpaperDir, cache: cache)
            },
            report: { message in OWELog.error(.scene, "Particle object \(object.id ?? -1): \(message)") })
        var family = builder.family(particlePath, world: world,
                                    overrides: SceneParticleOverrides(object.instanceoverride, in: userValueContext))
        // Only the root is the object; its children follow it through their links.
        for index in family.indices.dropFirst() { family[index].objectID = nil }
        if !family.isEmpty {
            family[0].emitterImages = ParticleEmitterImage.bound(object.dependencies ?? [])
            family[0].collisionModels = ParticleCollision.linkedModels(object.dependencies ?? [])
        }
        return family
    }

    /// Logs where a build's particle systems spent their time (`ParticleBuildTiming`).
    private func logParticleBuildTiming(_ timing: ParticleBuildTiming, wallpaperDir: URL) {
        guard let summary = timing.summary else { return }
        Self.logDetail("\(wallpaperDir.lastPathComponent): \(summary)")
    }

    private func buildMetalParticleSystem(_ particlePath: String, particleSystem: WEParticleSystem, object: WESceneObject,
                                          world: SceneAffineTransform, overrides: SceneParticleOverrides,
                                          sceneSize: SIMD2<Float>, pixelUnits: Bool, wallpaperDir: URL,
                                          cache: ParticleDefinitionCache) -> SceneMetalParticleSystem? {
        guard let materialPath = particleSystem.material else { return nil }
        // The object's blending is its own system's; the children it spawns keep their materials'.
        let blending = particlePath == object.particle ? blendingOverride(for: object) : nil
        // Every copy of a definition shares what its definition, material and blending decide;
        // the rest is the copy's own.
        let key = ParticleDefinitionCache.Key(particlePath: particlePath, materialPath: materialPath,
                                              blending: blending?.rawValue)
        let table = bindingTable
        guard let parts = cache.parts(for: key, noteReads: { table.noteReads($0) }, build: {
            table.capturingReads {
                buildSharedParticleParts(particlePath, materialPath: materialPath, particleSystem: particleSystem,
                                         blending: blending, object: object, wallpaperDir: wallpaperDir,
                                         timing: cache.timing)
            }
        }) else { return nil }
        return makeParticleSystem(particlePath, parts: parts, particleSystem: particleSystem, object: object, world: world,
                                  overrides: overrides, sceneSize: sceneSize, pixelUnits: pixelUnits,
                                  timing: cache.timing)
    }

    /// What every copy of a particle definition with the same material and blending draws with:
    /// the material, texture 0, its sprite sheet, each renderer's material plan and the built-in
    /// draw's texture. Nil when the system can't draw (no material or texture).
    private func buildSharedParticleParts(_ particlePath: String, materialPath: String, particleSystem: WEParticleSystem,
                                          blending: WEMaterialBlending?, object: WESceneObject, wallpaperDir: URL,
                                          timing: ParticleBuildTiming) -> ParticleSharedParts? {
        guard var material: WEMaterial = timing.measure(.materialDocument, {
                  loadJSON(path: materialPath, wallpaperDir: wallpaperDir)
              }),
              let textureName = material.passes?.first?.textures?.first ?? nil else { return nil }
        if let blending { material.passes?[0].blending = blending.rawValue }
        guard let source = timing.measure(.texture, {
            loadMetalTexture(named: textureName, materialDir: materialPath, wallpaperDir: wallpaperDir, colour: true)
        }) else {
            OWELog.error(.scene, "\(wallpaperDir.lastPathComponent): particle \(particlePath) (object \(object.id ?? -1)): "
                         + "texture \(textureName) of \(materialPath) not found")
            return nil
        }
        let spriteSheet = timing.measure(.spriteSheet) {
            loadSpriteSheet(named: textureName, materialDir: materialPath, wallpaperDir: wallpaperDir, source: source)
        }
        let renderers = particleSystem.renderer ?? []
        let materialPlan = timing.measure(.materialPlan) {
            buildParticleMaterial(materialPath, particleSystem: particleSystem, renderer: renderers.first, source: source,
                                  spriteSheet: spriteSheet, blending: blending, object: object, wallpaperDir: wallpaperDir)
        }
        let fallbackSource = timing.measure(.fallbackTexture) { () -> SceneMetalTextureSource? in
            let albedo = ParticleMaterialPlanBuilder.textureHeader(named: textureName, materialPath: materialPath) {
                assetData(named: $0, wallpaperDir: wallpaperDir)
            }
            return ParticleFallbackTexture.converted(source, format: albedo.flatMap(TEXImageFormat.init(texData:)))
        }
        // WE draws every renderer of the system from its one simulation, each through the material
        // with that renderer's combos.
        let rendererMaterials = timing.measure(.extraRenderers) {
            renderers.dropFirst().map { renderer in
                buildParticleMaterial(materialPath, particleSystem: particleSystem, renderer: renderer, source: source,
                                      spriteSheet: spriteSheet, blending: blending, object: object,
                                      wallpaperDir: wallpaperDir)
            }
        }
        return ParticleSharedParts(material: material, source: source, spriteSheet: spriteSheet, materialPlan: materialPlan,
                                   fallbackSource: fallbackSource, rendererMaterials: rendererMaterials)
    }

    /// One copy's system: its own transform, overrides and object over the shared `parts`.
    private func makeParticleSystem(_ particlePath: String, parts: ParticleSharedParts, particleSystem: WEParticleSystem,
                                    object: WESceneObject, world: SceneAffineTransform, overrides: SceneParticleOverrides,
                                    sceneSize: SIMD2<Float>, pixelUnits: Bool,
                                    timing: ParticleBuildTiming) -> SceneMetalParticleSystem {
        var system = timing.measure(.system) {
            ParticleSystemBuilder.build(particlePath, particleSystem: particleSystem, object: object, world: world,
                                        overrides: overrides, sceneSize: sceneSize, source: parts.source,
                                        spriteSheet: parts.spriteSheet, material: parts.material,
                                        materialPlan: parts.materialPlan, pixelUnits: pixelUnits)
        }
        system.material = parts.materialPlan
        system.fallbackSource = parts.fallbackSource
        var rendererMaterials = parts.rendererMaterials.makeIterator()
        ParticleSystemBuilder.addRenderers(to: &system, particleSystem: particleSystem) { _ in
            rendererMaterials.next() ?? nil
        }
        return system
    }

    /// The system's material through WE's particle shaders; nil (logged when it's a failure)
    /// keeps the built-in particle draw.
    private func buildParticleMaterial(_ materialPath: String, particleSystem: WEParticleSystem,
                                       renderer: WEParticleRenderer?, source: SceneMetalTextureSource,
                                       spriteSheet: SpriteSheet?, blending: WEMaterialBlending?, object: WESceneObject,
                                       wallpaperDir: URL) -> ParticleMaterialPlan? {
        guard let translator = effectTranslator else { return nil }
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            particleMaterialPlanTime.nanoseconds += DispatchTime.now().uptimeNanoseconds - start
            particleMaterialPlanTime.plans += 1
        }
        let builder = ParticleMaterialPlanBuilder(
            translator: translator,
            readFile: { [weak self] path in self?.assetData(named: path, wallpaperDir: wallpaperDir) },
            loadTexture: { [weak self] name, path in self?.loadMetalTexture(named: name, materialDir: path, wallpaperDir: wallpaperDir) },
            sceneEngineCombos: sceneEngineCombos, blending: blending)
        do {
            return try builder.build(materialPath: materialPath, renderer: renderer, flags: particleSystem.flags ?? 0,
                                     baseTexture: source, spriteSheet: spriteSheet)
        } catch {
            OWELog.error(.scene, "Particle system \(object.id ?? -1) uses the built-in draw, material \(materialPath): \(error)")
            return nil
        }
    }

    /// One line: the content build's particle material plans and their time, and how many
    /// shader parses and geometry folds came from the translator's memo (`ShaderSourceMemo`).
    private func logParticleMaterialPlanTime(wallpaperDir: URL, memoBefore: (hits: Int, misses: Int)?) {
        guard particleMaterialPlanTime.plans > 0 else { return }
        let memo = effectTranslator.map { translator -> String in
            let now = translator.sources.counts
            return ", shader memo \(now.hits - (memoBefore?.hits ?? 0)) hits, \(now.misses - (memoBefore?.misses ?? 0)) misses"
        } ?? ""
        Self.logDetail(String(format: "%@: particle material plans: %d in %.1f ms", wallpaperDir.lastPathComponent,
                              particleMaterialPlanTime.plans, Double(particleMaterialPlanTime.nanoseconds) / 1e6) + memo)
    }

    private func loadSpriteSheet(named name: String, materialDir: String, wallpaperDir: URL,
                                 source: SceneMetalTextureSource) -> SpriteSheet? {
        struct TextureMetadata: Decodable {
            struct Sequence: Decodable { let frames: Int; let width: Double; let height: Double; let duration: Double }
            let spritesheetsequences: [Sequence]?
        }
        let materialDirectory = (materialDir as NSString).deletingLastPathComponent
        let root = materialDirectory.split(separator: "/").first.map(String.init) ?? "materials"
        let candidates = ["\(materialDirectory)/\(name).tex-json", "\(root)/\(name).tex-json", "\(name).tex-json"]
        for candidate in candidates {
            let data = assetData(named: candidate, wallpaperDir: wallpaperDir)
            guard let data, let metadata = try? JSONDecoder().decode(TextureMetadata.self, from: data),
                  let sequence = metadata.spritesheetsequences?.first, sequence.frames > 0,
                  sequence.width > 0, sequence.height > 0 else { continue }
            guard let textureSize = source.sheetPixelSize else { continue }
            return SpriteSheet(frames: sequence.frames, frameSize: SIMD2(sequence.width, sequence.height),
                               duration: Float(sequence.duration), textureSize: textureSize)
        }
        // No `.tex-json` (every compiled Workshop texture): the `.tex`'s own `TEXS` frames.
        if case let .animated(animation) = source, let textureSize = source.sheetPixelSize {
            return SpriteSheet(texFrames: animation.frames, textureSize: textureSize)
        }
        return nil
    }

    // MARK: - Asset Loading

    private func loadJSON<T: Decodable>(path: String, wallpaperDir: URL) -> T? {
        guard let original = assetData(named: path, wallpaperDir: wallpaperDir) else { return nil }
        let storageKey = settingsIdentity(for: wallpaperDir).key(.userProperties, scope: propertyScope)
        let overrideKey = "_owe_scene_asset_\(path)_json"
        let data: Data
        if let values = UserDefaults.app.dictionary(forKey: storageKey) as? [String: String],
           let override = values[overrideKey], let overrideData = override.data(using: .utf8) {
            data = bindingTable.resolvedData(overrideData, path: path, properties: userProperty)
        } else {
            data = original
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// The file at `path` as the build reads it: a JSON document with its user bindings resolved
    /// and recorded (`bindingTable`), any other file as it is.
    private func assetData(named path: String, wallpaperDir: URL) -> Data? {
        rawAssetData(named: path, wallpaperDir: wallpaperDir).map {
            bindingTable.resolvedData($0, path: path, properties: userProperty)
        }
    }

    private func rawAssetData(named path: String, wallpaperDir: URL) -> Data? {
        if let cached = assetDataCache[path] { return cached }
        // WE's fixed copy of a broken Workshop shader replaces the one the wallpaper ships.
        if let fixed = shaderCompat?.replacement(forShaderPath: path, projectId: loadedProjectId) {
            Self.log("Using WE's compatibility copy of \(path)")
            assetDataCache[path] = fixed
            return fixed
        }
        let data = wallpaperData(named: path, wallpaperDir: wallpaperDir) ?? sharedAssetData(named: path)
        if let data { assetDataCache[path] = data }
        return data
    }

    /// A file of the wallpaper itself: its package, its folder, or a Workshop item it references.
    private func wallpaperData(named path: String, wallpaperDir: URL) -> Data? {
        if let data = pkgParser?.extractFile(named: path) { return data }
        // A missing loose file is an ordinary miss: the next source is tried.
        do {
            if let data = try AssetPathResolver.data(path, in: wallpaperDir) { return data }
        } catch {
            OWELog.error(.scene, "Failed to read \(path) in \(wallpaperDir.path): \(error)")
        }
        return workshopAssets.data(for: path)
    }

    /// The project's Workshop id: `workshopid` in project.json, else a numeric folder name
    /// (Steam names downloaded items by id). Nil for a local project.
    static func workshopId(of wallpaper: WEWallpaper) -> String? {
        if let id = wallpaper.project.workshopid?.rawValue, !id.isEmpty, id.allSatisfy(\.isNumber) { return id }
        let folder = wallpaper.wallpaperDirectory.lastPathComponent
        return !folder.isEmpty && folder.allSatisfy({ $0.isASCII && $0.isNumber }) ? folder : nil
    }

    private func sharedAssetData(named path: String) -> Data? {
        let assetsDirectories = WallpaperEngineAssets.searchDirectories
        guard !assetsDirectories.isEmpty else {
            Self.logDetail("Shared asset lookup skipped: no Wallpaper Engine assets available")
            return nil
        }
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var relativePaths = [normalizedPath]
        if URL(fileURLWithPath: normalizedPath).pathExtension.isEmpty {
            relativePaths.append("\(normalizedPath).tex")
        }
        if normalizedPath.hasPrefix("materials/presets/") {
            relativePaths.append("materials/\(normalizedPath.dropFirst("materials/presets/".count))")
        } else if !normalizedPath.hasPrefix("materials/") {
            relativePaths.append("materials/\(normalizedPath)")
        }
        guard let candidate = WallpaperEngineAssets.locate(relativePaths, in: assetsDirectories) else { return nil }
        do {
            let data = try AssetPathResolver.readRegularFile(at: candidate)
            Self.logDetail("Using shared asset '\(candidate.path)'")
            return data
        } catch {
            OWELog.error(.scene, "Could not read shared asset \(candidate.path): \(error)")
            return nil
        }
    }

    private func loadTexture(named name: String, materialDir: String, wallpaperDir: URL) -> NSImage? {
        // Build candidate .tex paths: relative to material dir, then relative to materials/ root
        let materialDirPath = (materialDir as NSString).deletingLastPathComponent
        var texPaths = [String]()
        if !materialDirPath.isEmpty {
            texPaths.append("\(materialDirPath)/\(name).tex")
        }
        // Also try materials/{name}.tex for textures with embedded paths (e.g. "workshop/xxx/foo")
        let materialsRoot = materialDirPath.split(separator: "/").first.map(String.init) ?? "materials"
        let rootPath = "\(materialsRoot)/\(name).tex"
        if !texPaths.contains(rootPath) {
            texPaths.append(rootPath)
        }
        texPaths.append("\(name).tex")

        for texPath in texPaths {
            // Try .tex from PKG
            if let texData = assetData(named: texPath, wallpaperDir: wallpaperDir) {
                Self.logDetail("  TEX from PKG '\(texPath)' size=\(texData.count)")
                let texParser = TEXParser(data: Data(texData))  // Copy to reset indices
                if let image = texParser.extractImage() {
                    return image
                }
                Self.log("  TEXParser.extractImage() returned nil for '\(texPath)'")
            }
        }

        // Try common image formats directly, where the .tex was looked for (WE ships some effect
        // textures as a PNG with a .tex-json, e.g. `materials/effects/refractnormal.png`).
        for ext in ["png", "jpg", "jpeg", "gif"] {
            for texPath in texPaths {
                let imgPath = (texPath as NSString).deletingPathExtension + ".\(ext)"
                if let imgData = assetData(named: imgPath, wallpaperDir: wallpaperDir), let image = NSImage(data: imgData) {
                    return image
                }
            }
        }

        Self.log("  No texture found for '\(name)'")
        return nil
    }
}
