import SwiftUI
import AVFoundation
import OWEInspectorKit

private struct SceneInspectorItem: Identifiable {
    let id: String
    let name: String
    let kind: String
    let sourcePath: String
    let materialPath: String?
    let texturePaths: [String]
    let shaderPaths: [String]
    var rawObject: String
    var rawMaterial: String?
    var rawParticle: String?
    let visible: Bool
    let isVersion: Bool
    let versionName: String?
    let versionValue: String?
    let effects: [SceneInspectorEffect]
    /// Video wallpapers have no authored object behind the layer, so it is description-only.
    var isSynthetic = false
}

private struct SceneInspectorEffect: Identifiable {
    let id: String
    let name: String
    let title: String
    let maskPath: String?
    let controls: [SceneInspectorEffectControl]
    var combos: [SceneInspectorEffectCombo] = []
}

/// A `// [COMBO]` switch of the effect's shaders that WE's editor shows.
private struct SceneInspectorEffectCombo: Identifiable {
    let id: String
    let effectID: String
    /// The preprocessor name, which the override is stored under.
    let combo: String
    let title: String
    /// WE's options as (title, value, the editor's group heading); an on/off switch when empty.
    let options: [(title: String, value: Int, group: String?)]
    /// Other combos' values this one is shown for, as WE's `require`.
    var requirements: [String: Int] = [:]
}

private struct SceneInspectorEffectControl: Identifiable {
    let id: String
    let effectID: String
    let key: String
    let component: Int
    let title: String
    let minimum: Double
    let maximum: Double
    let defaultValue: Double
    let displaysDegrees: Bool
    /// From the uniform's annotation (`int`, `"type":"color"`, `linked`).
    var isInteger = false
    var isColor = false
    var isLinked = false
    var componentCount = 1
}

private struct SceneInspectorTexture: Identifiable {
    let id: String
    let path: String
    let image: NSImage
}

/// The Scene Editor (Live)'s modes: the wallpaper's objects, edited on the running wallpaper, or
/// the iPhone & iPad Export mode's lock screen, edited on the mode's own copy
/// (`IsolatedSceneEditSession`). The picker lists them in this order.
enum SceneInspectorMode: CaseIterable {
    case wallpaper, deviceExport

    var title: LocalizedStringResource {
        switch self {
        case .wallpaper: return LocalizedStringResource("Wallpaper", comment: "Scene Editor (Live): the mode that edits the running wallpaper")
        case .deviceExport: return LocalizedStringResource("iPhone & iPad Export", comment: "Scene Editor (Live): the mode that exports a Live Photo")
        }
    }
}

private enum SceneHorizontalSnap {
    case left, center, right
}

private enum SceneVerticalSnap {
    case top, center, bottom
}

/// The inspector's unsaved edits over the store it saves to.
struct SceneInspectorEditBuffer {
    var pending: [String: String]?

    func values(stored: @autoclosure () -> [String: String]) -> [String: String] {
        pending ?? stored()
    }
}

private final class SceneInspectorModel: ObservableObject {
    @Published var items: [SceneInspectorItem] = []
    @Published var errorMessage: String?
    @Published var decodedTextures: [SceneInspectorTexture] = []
    @Published var decodedMasks: [String: SceneInspectorTexture] = [:]
    @Published var effectValues: [String: Double] = [:]
    @Published var effectEnabled: [String: Bool] = [:]
    @Published var comboValues: [String: Int] = [:]
    /// Linked vec2 parameters (by `effectID:key`) currently edited as one value.
    @Published var linkedParameters: Set<String> = []
    @Published var decodedItemID: String?
    @Published var loadingItemID: String?
    private(set) var initiallySelectedID: String?
    private(set) var sceneSize = SIMD2<Double>(1920, 1080)
    /// The size the renderer draws the scene at (`SceneWallpaperViewModel.sceneSize(of:)`): the
    /// iPhone & iPad Export's crop frames the drawn scene, in its preview and its render alike.
    private(set) var renderSceneSize = SIMD2<Double>(1920, 1080)

    private let directory: URL
    private let package: PKGParser?
    /// The stores its edits go to: the selected displays', or the shared one while synced.
    private let targets: WallpaperPropertyTargets
    private var textureLoadGeneration = 0
    private var pendingSave: DispatchWorkItem?
    /// The values handed to the wallpaper but not yet saved (the save is debounced). Reads go
    /// through it, so a control reading the store (Music Amount, Sync to Music) shows its new value
    /// at once, and a second edit inside the debounce doesn't drop the first.
    @Published private var editBuffer = SceneInspectorEditBuffer()
    private var storedValues: [String: String] { editBuffer.values(stored: targets.storedValues) }

    init(wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope]) {
        directory = wallpaper.wallpaperDirectory
        targets = WallpaperPropertyTargets(wallpaper: wallpaper, scopes: scopes)
        let scenePath = wallpaper.project.file
        let packageURL = directory.appending(path: (scenePath as NSString).deletingPathExtension + ".pkg")
        package = try? PKGParser(url: packageURL)

        func data(_ path: String) -> Data? {
            // Optional: the inspector shows an unreadable file as a missing one.
            package?.extractFile(named: path) ?? (try? AssetPathResolver.data(path, in: directory))
        }
        func rawJSON(_ path: String) -> String? {
            guard let data = data(path),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return nil }
            return String(data: formatted, encoding: .utf8)
        }
        guard let sceneData = data(scenePath),
              let scene = try? JSONDecoder().decode(WEScene.self, from: sceneData),
              let sceneJSON = try? JSONSerialization.jsonObject(with: sceneData) as? [String: Any],
              let rawObjects = sceneJSON["objects"] as? [[String: Any]] else {
            if SceneWallpaperViewModel.isVideoType(wallpaper.project.type) {
                buildVideoLayers(for: wallpaper)
            } else {
                errorMessage = String(localized: "Unable to read the scene definition.")
            }
            return
        }
                sceneSize = Self.sceneSize(for: scene)
        renderSceneSize = SIMD2<Double>(SceneWallpaperViewModel.sceneSize(of: scene))

        let storedValues: [String: String] = targets.storedValues
        items = scene.objects.enumerated().map { index, object in
            let objectID = object.id ?? index
            var rawObject = rawObjects.indices.contains(index) ? prettyJSON(rawObjects[index]) : "{}"
            if let origin = storedValues["_owe_scene_object_\(objectID)_origin"] {
                rawObject = Self.rawObject(rawObject, settingOrigin: origin)
            }
            let visible = storedValues[sceneObjectVisibilityKey(objectID: objectID)].map { $0 != "false" }
                ?? object.visible ?? true
            let effects = makeEffects(object.effects ?? [], objectID: objectID, storedValues: storedValues)
            let version = Self.versionName(from: object.name)
            if let imagePath = object.image {
                let model: WEModel? = data(imagePath).flatMap { try? JSONDecoder().decode(WEModel.self, from: $0) }
                let materialPath = model?.material
                let material: WEMaterial? = materialPath.flatMap { data($0) }.flatMap { try? JSONDecoder().decode(WEMaterial.self, from: $0) }
                let passes = material?.passes ?? []
                return SceneInspectorItem(id: String(object.id ?? index), name: object.name ?? String(localized: "Image \(index + 1)", comment: "Scene Editor: an image layer without a name"),
                                          kind: "Image", sourcePath: imagePath, materialPath: materialPath,
                                          texturePaths: passes.flatMap { $0.textures?.compactMap { $0 } ?? [] },
                                          shaderPaths: passes.compactMap(\.shader), rawObject: rawObject,
                                          rawMaterial: materialPath.flatMap(rawJSON), rawParticle: nil,
                                          visible: visible,
                                          isVersion: version != nil, versionName: version,
                                          versionValue: object.visibleCondition, effects: effects)
            }
            if let particlePath = object.particle {
                let particle: WEParticleSystem? = data(particlePath).flatMap { try? JSONDecoder().decode(WEParticleSystem.self, from: $0) }
                let materialPath = particle?.material
                let material: WEMaterial? = materialPath.flatMap { data($0) }.flatMap { try? JSONDecoder().decode(WEMaterial.self, from: $0) }
                let passes = material?.passes ?? []
                return SceneInspectorItem(id: String(object.id ?? index), name: object.name ?? String(localized: "Particle \(index + 1)", comment: "Scene Editor: a particle system without a name"),
                                          kind: "Particle", sourcePath: particlePath, materialPath: materialPath,
                                          texturePaths: passes.flatMap { $0.textures?.compactMap { $0 } ?? [] },
                                          shaderPaths: passes.compactMap(\.shader), rawObject: rawObject,
                                          rawMaterial: materialPath.flatMap(rawJSON), rawParticle: rawJSON(particlePath),
                                          visible: visible,
                                          isVersion: false, versionName: nil, versionValue: nil, effects: effects)
            }
            return SceneInspectorItem(id: String(object.id ?? index), name: object.name ?? String(localized: "Object \(index + 1)", comment: "Scene Editor: a scene object without a name"),
                                      kind: "Other", sourcePath: "", materialPath: nil, texturePaths: [], shaderPaths: [],
                                      rawObject: rawObject, rawMaterial: nil, rawParticle: nil,
                                      visible: visible,
                                      isVersion: false, versionName: nil, versionValue: nil, effects: effects)
        }
                        let selectedVersion = storedValues["version"]
                        initiallySelectedID = items.first { $0.versionValue == selectedVersion }?.id ?? items.first?.id
    }

    private static func versionName(from name: String?) -> String? {
        guard let name, let range = name.range(of: #"_(\d+)$"#, options: .regularExpression) else { return nil }
        let number = name[range].dropFirst()
        return String(localized: "Version \(String(number))", comment: "Scene Editor: one of a layer's alternative versions")
    }

    /// Wallpaper Engine renders a video through its `scenes/videoplayer` scene, and the Metal path
    /// here does the same: one video layer plus the shared effect stack. There is no scene.json to
    /// read, so those layers are described directly instead of leaving the inspector empty.
    private func buildVideoLayers(for wallpaper: WEWallpaper) {
        let file = wallpaper.project.file
        let url = directory.appending(path: file)
        let syncKeys = ["zoom", "pace", "tilt", "saturation"]
        let enabledSync = syncKeys.filter { VideoMusicSyncSettings.bool(wallpaper, "\($0)Enabled") }

        items = [
            SceneInspectorItem(id: "video", name: String(localized: "Video"), kind: "Video", sourcePath: file,
                               materialPath: nil, texturePaths: [], shaderPaths: [],
                               rawObject: prettyJSON(["file": file, "status": String(localized: "Reading media…")]),
                               rawMaterial: nil, rawParticle: nil, visible: true,
                               isVersion: false, versionName: nil, versionValue: nil,
                               effects: [], isSynthetic: true),
            SceneInspectorItem(id: "effects", name: String(localized: "Effects"), kind: "Effect Stack", sourcePath: "",
                               materialPath: nil, texturePaths: [], shaderPaths: [],
                               rawObject: prettyJSON([
                                   "musicSync": enabledSync.isEmpty ? "none" : enabledSync.joined(separator: ", "),
                                   "note": String(localized: "Scene effects are toggled under User Scene Settings.")
                               ]),
                               rawMaterial: nil, rawParticle: nil, visible: true,
                               isVersion: false, versionName: nil, versionValue: nil,
                               effects: [], isSynthetic: true)
        ]
        initiallySelectedID = "video"

        Task { [weak self] in
            let asset = AVURLAsset(url: url)
            let videoTrack = try? await asset.loadTracks(withMediaType: .video).first
            let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
            let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) }
            let size = try? await videoTrack?.load(.naturalSize)
            let frameRate = try? await videoTrack?.load(.nominalFrameRate)

            var summary: [String: Any] = ["file": file]
            if let size { summary["resolution"] = "\(Int(size.width)) x \(Int(size.height))" }
            if let duration, duration.isFinite { summary["duration"] = String(format: "%.2f s", duration) }
            if let frameRate { summary["frameRate"] = String(format: "%.2f fps", frameRate) }
            summary["hasAudio"] = audioTrack != nil

            await MainActor.run { [weak self] in
                guard let self else { return }
                if let index = self.items.firstIndex(where: { $0.id == "video" }) {
                    self.items[index].rawObject = prettyJSON(summary)
                }
                guard audioTrack != nil else { return }
                var audioSummary: [String: Any] = ["file": file, "track": "embedded soundtrack"]
                if let duration, duration.isFinite {
                    audioSummary["duration"] = String(format: "%.2f s", duration)
                }
                let audio = SceneInspectorItem(id: "audio", name: String(localized: "Audio"), kind: "Audio", sourcePath: file,
                                               materialPath: nil, texturePaths: [], shaderPaths: [],
                                               rawObject: prettyJSON(audioSummary),
                                               rawMaterial: nil, rawParticle: nil, visible: true,
                                               isVersion: false, versionName: nil, versionValue: nil,
                                               effects: [], isSynthetic: true)
                self.items.insert(audio, at: 1)
            }
        }
    }

    private func makeEffects(_ effects: [WEObjectEffect], objectID: Int,
                             storedValues: [String: String]) -> [SceneInspectorEffect] {
        let wallpaperDirectory = directory
        let assets = WallpaperEngineAssets.directory
        let labels = WallpaperEngineLabels.load()
        let readFile: (String) -> Data? = { path in
            FileManager.default.contents(atPath: wallpaperDirectory.appending(path: path).path)
                ?? assets.flatMap { FileManager.default.contents(atPath: $0.appending(path: path).path) }
        }
        return effects.enumerated().map { effectIndex, effect in
            let name = ((effect.file as NSString).deletingLastPathComponent as NSString).lastPathComponent.lowercased()
            let effectID = "\(objectID):\(effectIndex)"
            let enabledKey = sceneAuthoredEffectEnabledKey(objectID: objectID, effectIndex: effectIndex)
            effectEnabled[effectID] = storedValues[enabledKey].map { $0.lowercased() != "false" }
                ?? effect.visible.map { $0 != false } ?? true
            // Parameters come from the effect's own shaders, as in WE's editor: its ranges,
            // defaults and labels, nothing widened or renamed.
            let parameters = SceneEffectParameters.parameters(for: effect.file, readFile: readFile)
            let authored = effect.passes?.first?.constants ?? [:]
            var controls: [SceneInspectorEffectControl] = []
            for parameter in parameters {
                let authoredSource = authored.first { $0.key.caseInsensitiveCompare(parameter.materialKey) == .orderedSame }?
                    .value.valueSource
                // WE's editor shows no value control for a parameter bound to a user property: the
                // user property sets it (`SceneEffectPlanBuilder.applyingOverrides`).
                if authoredSource?.boundUserProperty != nil { continue }
                let authoredValue = authoredSource.flatMap { source -> [Double]? in
                    if case .literal(let value) = source { return value.components.map(Double.init) }
                    return nil
                }
                let baseValues = authoredValue ?? parameter.defaultValue
                let overrideKey = sceneAuthoredEffectOverrideKey(objectID: objectID, effectIndex: effectIndex,
                                                                  parameter: parameter.materialKey)
                let overrideValues = storedValues[overrideKey]?
                    .split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
                let values = overrideValues?.isEmpty == false ? overrideValues! : baseValues
                let title = labels.translation(parameter.label) ?? parameter.title
                let count = parameter.defaultValue.count
                if parameter.isLinked, count == 2, values.count >= 2, values[0] == values[1] {
                    linkedParameters.insert("\(effectID):\(parameter.materialKey)")
                }
                for component in parameter.defaultValue.indices {
                    let controlID = "\(effectID):\(parameter.materialKey):\(component)"
                    let value = values.indices.contains(component) ? values[component] : parameter.defaultValue[component]
                    effectValues[controlID] = value
                    // A colour is one picker, titled as WE titles it.
                    let suffix = count > 1 && !parameter.isColor ? " " + ["X", "Y", "Z", "W"][min(component, 3)] : ""
                    controls.append(SceneInspectorEffectControl(
                        id: controlID, effectID: effectID, key: parameter.materialKey, component: component,
                        title: title + suffix,
                        minimum: parameter.minimum, maximum: parameter.maximum,
                        defaultValue: baseValues.indices.contains(component) ? baseValues[component] : 0,
                        displaysDegrees: false, isInteger: parameter.isInteger, isColor: parameter.isColor,
                        isLinked: parameter.isLinked, componentCount: count))
                }
            }
            let authoredCombos = effect.passes?.first?.combos ?? [:]
            var combos: [SceneInspectorEffectCombo] = []
            for combo in SceneEffectParameters.combos(for: effect.file, readFile: readFile) where combo.isEditable {
                let comboID = "\(effectID):combo:\(combo.combo)"
                let key = sceneAuthoredEffectOverrideKey(objectID: objectID, effectIndex: effectIndex, parameter: SceneEffectParameters.comboOverrideKey(combo.combo))
                let authoredValue = authoredCombos.first { $0.key.caseInsensitiveCompare(combo.combo) == .orderedSame }?.value
                comboValues[comboID] = storedValues[key].flatMap { Int($0) } ?? authoredValue ?? combo.defaultValue
                combos.append(SceneInspectorEffectCombo(
                    id: comboID, effectID: effectID, combo: combo.combo,
                    title: labels.translation(combo.label) ?? SceneEffectParameters.title(combo.label),
                    options: combo.options.map { option in
                        (labels.translation(option.label) ?? option.english ?? SceneEffectParameters.title(option.label),
                         option.value, option.group.map { labels.translation($0) ?? Self.groupTitle($0) })
                    },
                    requirements: combo.requirements))
            }
            let maskPath = effect.passes?.first?.textures?.compactMap { $0 }.first
            return SceneInspectorEffect(id: effectID, name: name,
                                        title: name.replacingOccurrences(of: "_", with: " ").capitalized,
                                        maskPath: maskPath, controls: controls, combos: combos)
        }
    }

    /// A blend-mode group heading without WE's translation table: its English text.
    private static func groupTitle(_ key: String) -> String {
        SceneBlendModeOptions.groupTitle(key)
    }

    func setEffectValue(_ value: Double, control: SceneInspectorEffectControl) {
        effectValues[control.id] = value
        // A linked vec2 moves both components together, as WE's linked slider does.
        if control.isLinked, linkedParameters.contains("\(control.effectID):\(control.key)") {
            for component in 0..<control.componentCount {
                effectValues["\(control.effectID):\(control.key):\(component)"] = value
            }
        }
        let prefix = "\(control.effectID):\(control.key):"
        let components = effectValues.keys.filter { $0.hasPrefix(prefix) }
            .sorted { (Int($0.split(separator: ":").last!) ?? 0) < (Int($1.split(separator: ":").last!) ?? 0) }
            .compactMap { effectValues[$0] }
        let parts = control.effectID.split(separator: ":")
        guard parts.count == 2, let objectID = Int(parts[0]), let effectIndex = Int(parts[1]) else { return }
        let key = sceneAuthoredEffectOverrideKey(objectID: objectID, effectIndex: effectIndex,
                                                 parameter: control.key)
        var values = storedValues
        values[key] = components.map { String($0) }.joined(separator: " ")
        persist(values)
    }

    func isLinked(_ control: SceneInspectorEffectControl) -> Bool {
        linkedParameters.contains("\(control.effectID):\(control.key)")
    }

    /// WE's link toggle: linking copies X into Y.
    func setLinked(_ linked: Bool, control: SceneInspectorEffectControl) {
        let id = "\(control.effectID):\(control.key)"
        if linked {
            linkedParameters.insert(id)
            setEffectValue(effectValues["\(id):0"] ?? control.defaultValue, control: control)
        } else {
            linkedParameters.remove(id)
        }
    }

    /// WE shows a combo only while the combos it `require`s have those values.
    func requirementsHold(_ combo: SceneInspectorEffectCombo, in effect: SceneInspectorEffect) -> Bool {
        combo.requirements.allSatisfy { name, value in
            effect.combos.first { $0.combo == name }.map { comboValue($0) == value } ?? true
        }
    }

    func comboValue(_ combo: SceneInspectorEffectCombo) -> Int {
        comboValues[combo.id] ?? 0
    }

    func setComboValue(_ value: Int, combo: SceneInspectorEffectCombo) {
        comboValues[combo.id] = value
        let parts = combo.effectID.split(separator: ":")
        guard parts.count == 2, let objectID = Int(parts[0]), let effectIndex = Int(parts[1]) else { return }
        let key = sceneAuthoredEffectOverrideKey(objectID: objectID, effectIndex: effectIndex, parameter: SceneEffectParameters.comboOverrideKey(combo.combo))
        var values = storedValues
        values[key] = String(value)
        persist(values)
    }

    func displayedEffectValue(for control: SceneInspectorEffectControl) -> Double {
        let value = effectValues[control.id] ?? control.defaultValue
        return control.displaysDegrees ? value * 180 / .pi : value
    }

    func effectColor(for control: SceneInspectorEffectControl) -> Color {
        let prefix = "\(control.effectID):\(control.key):"
        let values = effectValues.keys.filter { $0.hasPrefix(prefix) }.sorted().compactMap { effectValues[$0] }
        // WE's colour uniforms are normalised 0...1.
        return Color(red: values.indices.contains(0) ? values[0] : 1,
                     green: values.indices.contains(1) ? values[1] : 1,
                     blue: values.indices.contains(2) ? values[2] : 1)
    }

    func setEffectColor(_ color: Color, control: SceneInspectorEffectControl) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        let rgb = [nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent]
        let prefix = "\(control.effectID):\(control.key):"
        for (index, id) in effectValues.keys.filter({ $0.hasPrefix(prefix) }).sorted().enumerated() where index < 3 {
            effectValues[id] = rgb[index]
        }
        let parts = control.effectID.split(separator: ":")
        guard parts.count == 2, let objectID = Int(parts[0]), let effectIndex = Int(parts[1]) else { return }
        let key = sceneAuthoredEffectOverrideKey(objectID: objectID, effectIndex: effectIndex, parameter: control.key)
        var values = storedValues
        values[key] = rgb.map(String.init).joined(separator: " ")
        persist(values)
    }

    func setDisplayedEffectValue(_ value: Double, control: SceneInspectorEffectControl) {
        setEffectValue(control.displaysDegrees ? value * .pi / 180 : value, control: control)
    }

    func musicSyncEnabled(for control: SceneInspectorEffectControl) -> Bool {
        let key = musicSyncKey(for: control)
        let values = storedValues
        return (values[key] ?? "false").lowercased() == "true"
    }

    func setMusicSyncEnabled(_ enabled: Bool, for control: SceneInspectorEffectControl) {
        var values = storedValues
        values[musicSyncKey(for: control)] = enabled ? "true" : "false"
        if values[musicAmountKey(for: control)] == nil {
            values[musicAmountKey(for: control)] = "0"
        }
        persist(values)
    }

    func musicAmount(for control: SceneInspectorEffectControl) -> Double {
        let values = storedValues
        let raw = Double(values[musicAmountKey(for: control)] ?? "0") ?? 0
        return control.displaysDegrees ? raw * 180 / .pi : raw
    }

    func setMusicAmount(_ amount: Double, for control: SceneInspectorEffectControl) {
        var values = storedValues
        values[musicAmountKey(for: control)] = String(control.displaysDegrees ? amount * .pi / 180 : amount)
        persist(values)
    }

    private func overrideKey(for control: SceneInspectorEffectControl) -> String? {
        let parts = control.effectID.split(separator: ":")
        guard parts.count == 2, let objectID = Int(parts[0]), let effectIndex = Int(parts[1]) else { return nil }
        let key = sceneAuthoredEffectOverrideKey(objectID: objectID, effectIndex: effectIndex, parameter: control.key)
        let prefix = "\(control.effectID):\(control.key):"
        let componentCount = effectValues.keys.filter { $0.hasPrefix(prefix) }.count
        return componentCount > 1 ? "\(key)_\(control.component)" : key
    }

    private func musicSyncKey(for control: SceneInspectorEffectControl) -> String {
        "\(overrideKey(for: control) ?? control.id)_musicSync"
    }

    private func musicAmountKey(for control: SceneInspectorEffectControl) -> String {
        "\(overrideKey(for: control) ?? control.id)_musicAmount"
    }

    func setEffectEnabled(_ enabled: Bool, effect: SceneInspectorEffect) {
        effectEnabled[effect.id] = enabled
        let parts = effect.id.split(separator: ":")
        guard parts.count == 2, let objectID = Int(parts[0]), let effectIndex = Int(parts[1]) else { return }
        let key = sceneAuthoredEffectEnabledKey(objectID: objectID, effectIndex: effectIndex)
        var values = storedValues
        values[key] = enabled ? "true" : "false"
        persist(values)
    }

    func setObjectVisible(_ visible: Bool, item: SceneInspectorItem) {
        let objectID = Int(item.id) ?? 0
        var values = storedValues
        values[sceneObjectVisibilityKey(objectID: objectID)] = visible ? "true" : "false"
        persist(values)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = SceneInspectorItem(id: item.id, name: item.name, kind: item.kind,
                                              sourcePath: item.sourcePath, materialPath: item.materialPath,
                                              texturePaths: item.texturePaths, shaderPaths: item.shaderPaths,
                                              rawObject: item.rawObject, rawMaterial: item.rawMaterial,
                                              rawParticle: item.rawParticle, visible: visible,
                                              isVersion: item.isVersion, versionName: item.versionName,
                                              versionValue: item.versionValue, effects: item.effects)
        }
    }

    func origin(for item: SceneInspectorItem) -> SIMD3<Double> {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let data = items[index].rawObject.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SIMD3<Double>(0, 0, 0)
        }
        return Self.parseOrigin(object["origin"]) ?? SIMD3<Double>(0, 0, 0)
    }

    func moveObject(_ item: SceneInspectorItem, deltaX: Double, deltaY: Double) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let data = items[index].rawObject.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let current = Self.parseOrigin(object["origin"]) ?? SIMD3<Double>(0, 0, 0)
        let updated = SIMD3<Double>(current.x + deltaX, current.y + deltaY, current.z)
        setObjectOrigin(item, index: index, object: &object, origin: updated)
    }

    func alignObject(_ item: SceneInspectorItem, horizontal: SceneHorizontalSnap) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let data = items[index].rawObject.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let current = Self.parseOrigin(object["origin"]) ?? SIMD3<Double>(0, 0, 0)
        let size = Self.parseSize(object["size"]) ?? SIMD2<Double>(300, 120)
        let x: Double
        switch horizontal {
        case .left:
            x = size.x / 2
        case .center:
            x = sceneSize.x / 2
        case .right:
            x = sceneSize.x - size.x / 2
        }
        setObjectOrigin(item, index: index, object: &object, origin: SIMD3<Double>(x, current.y, current.z))
    }

    func alignObject(_ item: SceneInspectorItem, vertical: SceneVerticalSnap) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let data = items[index].rawObject.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let current = Self.parseOrigin(object["origin"]) ?? SIMD3<Double>(0, 0, 0)
        let size = Self.parseSize(object["size"]) ?? SIMD2<Double>(300, 120)
        let y: Double
        switch vertical {
        case .top:
            y = sceneSize.y - size.y / 2
        case .center:
            y = sceneSize.y / 2
        case .bottom:
            y = size.y / 2
        }
        setObjectOrigin(item, index: index, object: &object, origin: SIMD3<Double>(current.x, y, current.z))
    }

    private func setObjectOrigin(_ item: SceneInspectorItem, index: Int, object: inout [String: Any], origin updated: SIMD3<Double>) {
        let origin = Self.originString(updated)
        object["origin"] = origin
        items[index].rawObject = prettyJSON(object)
        var values = storedValues
        values["_owe_scene_object_\(item.id)_origin"] = origin
        persist(values)
    }

    func scale(for item: SceneInspectorItem) -> Double {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let data = items[index].rawObject.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parsed = Self.parseOrigin(object["scale"]) else {
            return 1
        }
        return parsed.x == 0 ? 1 : parsed.x
    }

    func setObjectScale(_ item: SceneInspectorItem, scale value: Double) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let data = items[index].rawObject.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let current = Self.parseOrigin(object["scale"]) ?? SIMD3<Double>(1, 1, 1)
        // Scaling uniformly keeps the object's aspect, and the renderer scales each effect's mask
        // with the layer it belongs to, so masks follow along.
        let updated = SIMD3<Double>(value, value, current.z == 0 ? 1 : current.z)
        let scale = Self.originString(updated)
        object["scale"] = scale
        items[index].rawObject = prettyJSON(object)
        var values = storedValues
        values["_owe_scene_object_\(item.id)_scale"] = scale
        persist(values)
    }

    private static func sceneSize(for scene: WEScene) -> SIMD2<Double> {
        if case .orthographic(let width, let height) = scene.general.projection {
            return SIMD2<Double>(Double(width), Double(height))
        }
        let bounds = scene.objects.compactMap { object -> SIMD2<Double>? in
            guard let origin = object.origin?.parseVector3(), let size = object.size?.parseVector2() else { return nil }
            return SIMD2<Double>(origin.0 + size.0 / 2, origin.1 + size.1 / 2)
        }
        guard let width = bounds.map(\.x).max(), let height = bounds.map(\.y).max(), width > 0, height > 0 else {
            return SIMD2<Double>(1920, 1080)
        }
        return SIMD2<Double>(width, height)
    }

    private static func rawObject(_ rawObject: String, settingOrigin origin: String) -> String {
        guard let data = rawObject.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return rawObject }
        object["origin"] = origin
          guard let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return rawObject }
          return String(data: formatted, encoding: .utf8) ?? rawObject
    }

    private static func parseOrigin(_ value: Any?) -> SIMD3<Double>? {
        if let string = value as? String {
            let parts = string.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            guard parts.count >= 2 else { return nil }
            return SIMD3<Double>(parts[0], parts[1], parts.indices.contains(2) ? parts[2] : 0)
        }
        if let array = value as? [Any] {
            let parts = array.compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) }
            guard parts.count >= 2 else { return nil }
            return SIMD3<Double>(parts[0], parts[1], parts.indices.contains(2) ? parts[2] : 0)
        }
        if let dict = value as? [String: Any] {
            let x = (dict["x"] as? NSNumber)?.doubleValue ?? dict["x"] as? Double
            let y = (dict["y"] as? NSNumber)?.doubleValue ?? dict["y"] as? Double
            let z = (dict["z"] as? NSNumber)?.doubleValue ?? dict["z"] as? Double ?? 0
            if let x, let y { return SIMD3<Double>(x, y, z) }
        }
        return nil
    }

    private static func parseSize(_ value: Any?) -> SIMD2<Double>? {
        if let string = value as? String {
            let parts = string.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            guard parts.count >= 2 else { return nil }
            return SIMD2<Double>(parts[0], parts[1])
        }
        if let array = value as? [Any] {
            let parts = array.compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) }
            guard parts.count >= 2 else { return nil }
            return SIMD2<Double>(parts[0], parts[1])
        }
        if let dict = value as? [String: Any] {
            let x = (dict["x"] as? NSNumber)?.doubleValue ?? dict["x"] as? Double
            let y = (dict["y"] as? NSNumber)?.doubleValue ?? dict["y"] as? Double
            if let x, let y { return SIMD2<Double>(x, y) }
        }
        return nil
    }

    private static func originString(_ origin: SIMD3<Double>) -> String {
        let components: [Double] = [origin.x, origin.y, origin.z]
        let parts: [String] = components.map { value -> String in
            value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        }
        return parts.joined(separator: " ")
    }

    /// An image layer's `alpha` (WE's default 1); nil while something else sets it (a user
    /// property, a script or an animation), which WE's editor shows no value for either.
    func alpha(for item: SceneInspectorItem) -> Double? {
        guard let data = item.rawObject.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 1 } // not an object: WE's default
        switch object["alpha"] {
        case nil: return 1
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// Sets an image layer's `alpha`, saved with the object's edited JSON.
    func setAlpha(_ value: Double, for item: SceneInspectorItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let data = items[index].rawObject.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        object["alpha"] = min(max(value, 0), 1)
        saveObjectJSON(prettyJSON(object), item: items[index])
    }

    /// An image layer's `color` (WE's default white); nil while something else sets it.
    func color(for item: SceneInspectorItem) -> SIMD3<Double>? {
        guard let data = item.rawObject.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return SIMD3(1, 1, 1) } // WE's default
        guard let value = object["color"] else { return SIMD3(1, 1, 1) }
        guard !(value is [String: Any]), let parsed = Self.parseOrigin(value) else { return nil }
        return parsed
    }

    /// Sets an image layer's `color`, saved with the object's edited JSON.
    func setColor(_ color: Color, for item: SceneInspectorItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let data = items[index].rawObject.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let rgb = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        let components: [Double] = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Double($0) }
        object["color"] = components.map { String(format: "%.5g", $0) }.joined(separator: " ")
        saveObjectJSON(prettyJSON(object), item: items[index])
    }

    /// An image layer's `colorBlendMode` (WE's default 0, Normal).
    func blendMode(for item: SceneInspectorItem) -> Int {
        guard let data = item.rawObject.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 } // not an object: Normal
        return (object["colorBlendMode"] as? NSNumber)?.intValue ?? 0
    }

    /// Sets an image layer's `colorBlendMode`, saved with the object's edited JSON.
    func setBlendMode(_ value: Int, for item: SceneInspectorItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let data = items[index].rawObject.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        object["colorBlendMode"] = value
        saveObjectJSON(prettyJSON(object), item: items[index])
    }

    /// The material blendings a layer offers: its kind's (`WEMaterialBlending`); none for a layer
    /// without a material of its own.
    static func blendingOptions(for item: SceneInspectorItem) -> [WEMaterialBlending] {
        guard !item.isSynthetic, item.materialPath != nil, Int(item.id) != nil else { return [] }
        switch item.kind {
        case "Image": return WEMaterialBlending.imageLayer
        case "Particle": return WEMaterialBlending.particleSystem
        default: return []
        }
    }

    /// The blending of the layer's material as the scene loads it: its first pass's, with the
    /// material's own edit (`saveAssetJSON`) when it has one.
    func authoredBlending(for item: SceneInspectorItem) -> WEMaterialBlending {
        let particle = item.kind == "Particle"
        let raw = item.materialPath.flatMap { storedValues["_owe_scene_asset_\($0)_json"] } ?? item.rawMaterial
        guard let data = raw?.data(using: .utf8),
              let material = try? JSONSerialization.jsonObject(with: data) as? [String: Any], // no material: its default
              let pass = (material["passes"] as? [[String: Any]])?.first else {
            return WEMaterialBlending.authored(nil, particle: particle)
        }
        return WEMaterialBlending.authored(pass["blending"] as? String, particle: particle)
    }

    /// The blending the layer draws with: the one set here, else its material's.
    func materialBlending(for item: SceneInspectorItem) -> WEMaterialBlending {
        guard let objectID = Int(item.id),
              let value = storedValues[sceneObjectBlendingKey(objectID: objectID)],
              let blending = WEMaterialBlending(authored: value),
              Self.blendingOptions(for: item).contains(blending) else { return authoredBlending(for: item) }
        return blending
    }

    /// Draws the layer's material with `blending`, applied live (the content is rebuilt, the
    /// scene isn't reloaded) and saved with the other edits.
    func setMaterialBlending(_ blending: WEMaterialBlending, for item: SceneInspectorItem) {
        guard let objectID = Int(item.id), Self.blendingOptions(for: item).contains(blending) else { return }
        var values = storedValues
        values[sceneObjectBlendingKey(objectID: objectID)] = blending.rawValue
        persist(values)
    }

    /// Back to the material's own blending: the edit is removed, so the layer no longer counts as
    /// edited, and the running wallpaper's store is replaced so it drops the key too.
    func resetMaterialBlending(for item: SceneInspectorItem) {
        guard let objectID = Int(item.id) else { return }
        var values = storedValues
        guard values.removeValue(forKey: sceneObjectBlendingKey(objectID: objectID)) != nil else { return }
        objectWillChange.send()
        persist(values, replacing: true)
    }

    /// WE's blend modes as its editor lists them (`WEImageBlendModes`), with WE's labels.
    lazy var blendModeCombo: SceneInspectorEffectCombo = {
        // Shared with the Wallpaper Editor (`SceneBlendModeOptions`).
        let labels = WallpaperEngineLabels.load()
        return SceneInspectorEffectCombo(
            id: "colorBlendMode", effectID: "", combo: "BLENDMODE",
            title: SceneBlendModeOptions.title(labels: labels),
            options: SceneBlendModeOptions.options(labels: labels).map { (title: $0.title, value: $0.value, group: $0.group) })
    }()

    func saveObjectJSON(_ text: String, item: SceneInspectorItem) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              JSONSerialization.isValidJSONObject(object) else { return }
        let formatted = prettyJSON(object)
        var values = storedValues
        values["_owe_scene_object_\(item.id)_json"] = formatted
        persist(values)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].rawObject = formatted
        }
    }

    func saveAssetJSON(_ text: String, path: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              JSONSerialization.isValidJSONObject(object) else { return }
        var values = storedValues
        values["_owe_scene_asset_\(path)_json"] = prettyJSON(object)
        persist(values)
    }

    func useVersion(_ item: SceneInspectorItem) {
        guard let value = item.versionValue else { return }
        var values = storedValues
        values["version"] = value
        persist(values)
    }

    func loadTextures(for item: SceneInspectorItem) {
        textureLoadGeneration &+= 1
        let generation = textureLoadGeneration
        decodedTextures = []
        decodedMasks = [:]
        decodedItemID = nil
        guard !item.texturePaths.isEmpty else {
            loadingItemID = nil
            decodedItemID = item.id
            return
        }
        loadingItemID = item.id

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let textures = self.decodeTextures(for: item)
            let masks = Dictionary(uniqueKeysWithValues: item.effects.compactMap { effect -> (String, SceneInspectorTexture)? in
                guard let path = effect.maskPath, let texture = self.decodeTexture(path, itemID: effect.id,
                                                                                   materialPath: "materials") else { return nil }
                return (effect.id, texture)
            })
            DispatchQueue.main.async { [weak self] in
                guard let self, self.textureLoadGeneration == generation else { return }
                self.decodedTextures = textures
                self.decodedMasks = masks
                self.decodedItemID = item.id
                self.loadingItemID = nil
            }
        }
    }

    private func decodeTextures(for item: SceneInspectorItem) -> [SceneInspectorTexture] {
        item.texturePaths.compactMap { decodeTexture($0, itemID: item.id, materialPath: item.materialPath) }
    }

    private func decodeTexture(_ textureName: String, itemID: String, materialPath: String?) -> SceneInspectorTexture? {
        let materialDirectory = ((materialPath ?? "") as NSString).deletingLastPathComponent
        let fileName = (textureName as NSString).pathExtension.isEmpty ? "\(textureName).tex" : textureName
        let candidates = ["\(materialDirectory)/\(fileName)", "materials/\(fileName)", fileName]
            .filter { !$0.hasPrefix("/") }
        var visited = Set<String>()
        for path in candidates where visited.insert(path).inserted {
            guard let bytes = data(path) else { continue }
            let parser = TEXParser(data: bytes)
            let image = parser.extractAnimatedImages()?.images.first ?? parser.extractImage() ?? NSImage(data: bytes)
            if let image { return SceneInspectorTexture(id: "\(itemID):\(path)", path: path, image: image) }
        }
        return nil
    }

    private func data(_ path: String) -> Data? {
        // Optional: the inspector shows an unreadable file as a missing one.
        package?.extractFile(named: path) ?? (try? AssetPathResolver.data(path, in: directory))
    }

    private func prettyJSON(_ json: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Drops every edit made here to the wallpaper, in every store it edits (its Reset Edits);
    /// the wallpaper's properties stay.
    func removeEdits() {
        pendingSave?.cancel()
        pendingSave = nil
        editBuffer = SceneInspectorEditBuffer()
        targets.removeSceneInspectorEdits()
    }

    /// `replacing`: the running stores take `values` whole, so a removed key is dropped there too.
    private func persist(_ values: [String: String], replacing: Bool = false) {
        editBuffer.pending = values
        if replacing {
            for key in targets.runtimeKeys { WallpaperPropertyTargets.publishReplacing(key, values) }
        } else {
            targets.publish(values)
        }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self, targets] in
            targets.save(values)
            self?.editBuffer.pending = nil
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
}

extension AppDelegate {
    /// `scopes`: whose properties its edits change (`WallpaperViewModel.editedPropertyScopes`).
    func showSceneInspector(for wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope] = [.shared]) {
        if let sceneInspectorWindow {
            sceneInspectorWindow.contentView = Self.sceneInspectorContent(wallpaper, scopes)
            // A closed inspector (kept, not released) edits again.
            if !sceneInspectorWindow.isVisible { WallpaperServices.shared.propertyEditing.begin() }
            sceneInspectorWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Scene Editor (Live)")
        window.isReleasedWhenClosed = false
        window.contentView = Self.sceneInspectorContent(wallpaper, scopes)
        window.center()
        // The inspector edits properties while it is open (`ScenePropertyEditing`). The window is
        // kept for the app's life, and so is this observer.
        WallpaperServices.shared.propertyEditing.begin()
        _ = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                   queue: .main) { [weak window] _ in
            MainActor.assumeIsolated {
                WallpaperServices.shared.propertyEditing.end()
                // The editor goes with the window, so an isolated mode's private instance and
                // store stop now. Showing the editor again gives the window new content.
                window?.contentView = NSView()
            }
        }
        window.makeKeyAndOrderFront(nil)
        sceneInspectorWindow = window
    }

    /// The window can't shrink below the view's minimum size: a smaller window laid the columns
    /// out at their minimum and centred them, pushing their tops under the toolbar.
    private static func sceneInspectorContent(_ wallpaper: WEWallpaper, _ scopes: [WallpaperPropertyScope]) -> NSView {
        let view = NSHostingView(rootView: SceneInspectorView(wallpaper: wallpaper, scopes: scopes))
        view.sizingOptions = [.minSize]
        return view
    }
}

/// The Scene Editor (Live): its mode, and the editor for it. The Wallpaper mode edits the stores
/// the running wallpaper reads; the iPhone & iPad Export mode edits an isolated copy of them made
/// when it opens (`IsolatedSceneEditSession`), shown by the mode's private instance and exported,
/// and dropped when it closes.
struct SceneInspectorView: View {
    private let wallpaper: WEWallpaper
    private let scopes: [WallpaperPropertyScope]
    @State private var exportModel: LivePhotoExportModel?

    init(wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope] = [.shared]) {
        self.wallpaper = wallpaper
        self.scopes = scopes
    }

    var body: some View {
        if let exportModel {
            SceneInspectorContent(wallpaper: wallpaper, scopes: [exportModel.session.scope], isolated: exportModel.session,
                                  exportModel: exportModel, onModeChange: setMode)
                .id(SceneInspectorMode.deviceExport)
        } else {
            SceneInspectorContent(wallpaper: wallpaper, scopes: scopes, isolated: nil, exportModel: nil,
                                  onModeChange: setMode)
                .id(SceneInspectorMode.wallpaper)
        }
    }

    /// Opening the export mode copies the edited store's values into its isolated store; leaving
    /// it drops them, once its preview (and with it the private instance) is gone.
    private func setMode(_ mode: SceneInspectorMode, sceneSize: SIMD2<Double>) {
        switch mode {
        case .deviceExport:
            guard exportModel == nil else { return }
            let session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: LivePhotoExportModel.purpose,
                                                   seededFrom: scopes)
            exportModel = LivePhotoExportModel(session: session, sceneSize: sceneSize)
        case .wallpaper:
            guard let model = exportModel else { return }
            exportModel = nil
            model.cancel()
            DispatchQueue.main.async { model.session.end() }
        }
    }
}

private struct SceneInspectorContent: View {
    @StateObject private var model: SceneInspectorModel
    /// Depth maps and depth parallax, kept in the wallpaper's editor overlay.
    @StateObject private var depthMaps: SceneEditorDepthMapHost
    @State private var selectedID: String?
    @State private var searchText = ""
    @State private var didCopyPath = false
    @State private var isMovementPresented = true
    @State private var isConfirmingReset = false
    /// Moves when the Export Settings sheet closes, so the panel reads the properties it changed.
    @State private var exportPanelRevision = 0
    @FocusState private var isSearchFocused: Bool
    private let wallpaperDirectory: URL
    private let wallpaper: WEWallpaper
    /// The stores the editor edits: the running wallpaper's, or the isolated session's.
    private let scopes: [WallpaperPropertyScope]
    /// An isolated mode's session; nil in the Wallpaper mode.
    private let isolated: IsolatedSceneEditSession?
    private let exportModel: LivePhotoExportModel?
    private let onModeChange: (SceneInspectorMode, SIMD2<Double>) -> Void

    private var mode: SceneInspectorMode { exportModel == nil ? .wallpaper : .deviceExport }

    init(wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope], isolated: IsolatedSceneEditSession?,
         exportModel: LivePhotoExportModel?, onModeChange: @escaping (SceneInspectorMode, SIMD2<Double>) -> Void) {
        wallpaperDirectory = wallpaper.wallpaperDirectory
        self.wallpaper = wallpaper
        self.scopes = scopes
        self.isolated = isolated
        self.exportModel = exportModel
        self.onModeChange = onModeChange
        _model = StateObject(wrappedValue: SceneInspectorModel(wallpaper: wallpaper, scopes: scopes))
        _depthMaps = StateObject(wrappedValue: SceneEditorDepthMapHost(wallpaper: wallpaper))
    }

    private func matches(_ item: SceneInspectorItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        if item.name.localizedCaseInsensitiveContains(searchText)
            || item.kind.localizedCaseInsensitiveContains(searchText)
            || item.sourcePath.localizedCaseInsensitiveContains(searchText)
            || (item.materialPath?.localizedCaseInsensitiveContains(searchText) ?? false)
            || (item.versionName?.localizedCaseInsensitiveContains(searchText) ?? false) {
            return true
        }
        if item.texturePaths.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            || item.shaderPaths.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) {
            return true
        }
        return item.effects.contains { effect in
            effect.name.localizedCaseInsensitiveContains(searchText)
                || effect.title.localizedCaseInsensitiveContains(searchText)
                || (effect.maskPath?.localizedCaseInsensitiveContains(searchText) ?? false)
                || effect.controls.contains { $0.title.localizedCaseInsensitiveContains(searchText) || $0.key.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        inspectorSplitView
            .frame(minWidth: 1120, minHeight: 560)
            .frostedWindowBackground()
            .onAppear {
                selectedID = model.initiallySelectedID
                loadSelectedTextures()
            }
            .onChange(of: selectedID) { _, _ in loadSelectedTextures() }
            .onDisappear { isolated?.end() }
    }

    /// Both side columns (the object list and the movement controls) start at one width.
    private static let sidebarWidth: CGFloat = 300

    /// The name shown for an item's kind; `kind` itself stays English, as the code matches on it.
    private static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "Image": return String(localized: "Image", comment: "Scene Editor: the kind of a scene object")
        case "Particle": return String(localized: "Particle System", comment: "Scene Editor: the kind of a scene object")
        case "Video": return String(localized: "Video")
        case "Audio": return String(localized: "Audio")
        case "Effect Stack": return String(localized: "Effect Stack", comment: "Scene Editor: the effects applied to a video")
        default: return String(localized: "Other", comment: "Scene Editor: the kind of a scene object that is neither an image nor particles")
        }
    }

    private var inspectorSplitView: some View {
        NavigationSplitView {
            sidebarColumn
                .navigationSplitViewColumnWidth(min: 240, ideal: Self.sidebarWidth, max: 440)
        } detail: {
            modeDetail
                .inspector(isPresented: $isMovementPresented) {
                    Group {
                        if let exportModel {
                            LivePhotoExportSettingsView(model: exportModel) {
                                layerAdjustments(for: model.items.first(where: { $0.id == selectedID }))
                            }
                            .id(exportPanelRevision)
                        } else {
                            movementColumn(for: model.items.first(where: { $0.id == selectedID }))
                        }
                    }
                    .inspectorColumnWidth(min: 260, ideal: Self.sidebarWidth, max: 400)
                }
                .modifier(LivePhotoExportSheetHost(model: exportModel, onClose: { exportPanelRevision += 1 }) {
                    layerAdjustments(for: model.items.first(where: { $0.id == selectedID }))
                })
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        modePicker
                    }
                    // Two separate items at the trailing end: on macOS 26 a fixed spacer keeps them
                    // from sharing one glass capsule.
                    if #available(macOS 26, *) {
                        ToolbarSpacer(.flexible)
                    }
                    ToolbarItem(placement: .automatic) {
                        pathControl
                    }
                    if #available(macOS 26, *) {
                        ToolbarSpacer(.fixed)
                    }
                    ToolbarItem(placement: .automatic) {
                        panelToggle
                    }
                    if #available(macOS 26, *) {
                        ToolbarSpacer(.fixed)
                    }
                    ToolbarItem(placement: .automatic) {
                        modeAction
                    }
                }
                .alert("Reset Scene Editor (Live) Edits", isPresented: $isConfirmingReset) {
                    Button("Reset", role: .destructive) {
                        model.removeEdits()
                        // Rebuilt from the stored values, now without the edits, once this view's
                        // alert has closed.
                        let wallpaper = wallpaper, scopes = scopes
                        DispatchQueue.main.async { AppDelegate.shared.showSceneInspector(for: wallpaper, scopes: scopes) }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Do you want to undo every Scene Editor (Live) edit of “\(wallpaper.project.displayTitle)”? Its properties are kept.")
                }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .modifier(SearchFieldFocus(isFocused: $isSearchFocused))
        .background {
            Button("") { focusSearch() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
    }

    /// The detail column: the selected object, or the device's lock screen.
    @ViewBuilder
    private var modeDetail: some View {
        if let exportModel {
            LockScreenPreview(model: exportModel)
                .navigationTitle(Text(SceneInspectorMode.deviceExport.title))
        } else {
            detailColumn
        }
    }

    /// Shows or hides the right-hand panel: Move & Align, or the Export Settings.
    private var panelToggle: some View {
        Button {
            withAnimation { isMovementPresented.toggle() }
        } label: {
            if exportModel == nil {
                Label("Move & Align", systemImage: "sidebar.right")
            } else {
                Label("Export Settings Panel", systemImage: "sidebar.right")
            }
        }
        .help(exportModel == nil ? Text("Show or hide the move, size and align controls")
                                 : Text("Show or hide the Export Settings panel"))
    }

    /// The Wallpaper mode's Reset Edits, or the export mode's Export Settings.
    @ViewBuilder
    private var modeAction: some View {
        if let exportModel {
            Button {
                exportModel.showSettings()
            } label: {
                Label("Export Settings", systemImage: "slider.horizontal.3")
            }
            .help("Open the export settings: device, crop, clip, quality, layers and properties")
        } else {
            Button {
                isConfirmingReset = true
            } label: {
                Label("Reset Edits", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Undo every change made to this wallpaper in the Scene Editor (Live)")
        }
    }

    /// The modes; only a scene wallpaper can leave the Wallpaper mode (a Live Photo is rendered
    /// from a scene).
    private var modePicker: some View {
        let eligible = LivePhotoExportModel.isEligible(wallpaper)
        return Picker("Mode", selection: Binding(get: { mode }, set: { newValue in
            guard newValue != mode else { return }
            onModeChange(newValue, model.renderSceneSize)
        })) {
            ForEach(SceneInspectorMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!eligible)
        .help(eligible ? Text("Edit the running wallpaper, or preview it as an iPhone or iPad lock screen and export a Live Photo without changing your desktop")
                       : Text("Only scene wallpapers can be exported to iPhone or iPad for now"))
    }

    /// ⌘K. macOS 15 focuses a search field through `searchFocused`; macOS 14 has no API for it,
    /// so the window's search field is made first responder directly.
    private func focusSearch() {
        if #available(macOS 15, *) {
            isSearchFocused = true
        } else {
            guard let window = NSApp.keyWindow,
                  let field = Self.searchField(in: window.contentView?.superview ?? window.contentView) else { return }
            window.makeFirstResponder(field)
        }
    }

    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let field = searchField(in: subview) { return field }
        }
        return nil
    }

    private var sidebarColumn: some View {
        List(selection: $selectedID) {
            let versions = model.items.filter(\.isVersion).filter(matches)
            if !versions.isEmpty {
                Section("Versions") {
                    ForEach(versions) { item in
                        Label(item.versionName ?? item.name, systemImage: "square.stack.3d.up")
                            .tag(item.id)
                    }
                }
            }
            Section("Scene Objects") {
                ForEach(model.items.filter { !$0.isVersion }.filter(matches)) { item in
                    HStack(spacing: 8) {
                        Label(item.name, systemImage: item.kind == "Particle" ? "sparkles" : "photo")
                        Spacer(minLength: 4)
                        Toggle("Visible", isOn: Binding(
                            get: { item.visible },
                            set: { model.setObjectVisible($0, item: item) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .help(item.visible ? "Hide object" : "Show object")
                    }
                    .contentShape(Rectangle())
                    .tag(item.id)
                }
            }
        }
        .navigationTitle(exportModel == nil ? Text("Scene Editor (Live)") : Text(SceneInspectorMode.deviceExport.title))
    }

    private var detailColumn: some View {
        let selectedItem = model.items.first(where: { $0.id == selectedID })
        return Group {
            if let item = selectedItem {
                selectedItemDetail(item)
            } else if let error = model.errorMessage {
                ContentUnavailableView("Scene Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ContentUnavailableView("Select a Scene Object", systemImage: "square.stack.3d.up")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(ArrowKeyMove { direction in
            if let selectedItem { move(selectedItem, direction: direction) }
        })
    }

    /// Shows where the wallpaper lives and copies that path, so its files can be opened elsewhere.
    private var pathControl: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(wallpaperDirectory.path, forType: .string)
            didCopyPath = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopyPath = false }
        } label: {
            Label(didCopyPath ? "Copied" : "Copy Path", systemImage: didCopyPath ? "checkmark" : "doc.on.doc")
                .labelStyle(.titleAndIcon)
        }
        .help(didCopyPath ? "Copied" : "Copy wallpaper folder path\n\(wallpaperDirectory.path)")
    }

    private func selectedItemDetail(_ item: SceneInspectorItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Type", value: Self.kindLabel(item.kind))
                if item.isVersion {
                    Button {
                        model.useVersion(item)
                    } label: {
                        Label("Use This Version", systemImage: "checkmark.circle")
                    }
                }
                if !item.sourcePath.isEmpty { LabeledContent("Source", value: item.sourcePath) }
                if let material = item.materialPath { LabeledContent("Material", value: material) }
                detailList("Textures", values: item.texturePaths)
                decodedTextureList(for: item)
                detailList("Shaders", values: item.shaderPaths)
                effectList(for: item)
                if !item.isSynthetic, let objectID = Int(item.id) {
                    SceneEditorDepthMapSection(host: depthMaps, objectID: objectID)
                }
                editableObjectBlock(for: item)
                if let particle = item.rawParticle {
                    editableAssetBlock(title: "Particle System", isParticle: true, text: particle, path: item.sourcePath)
                }
                if let material = item.rawMaterial, let materialPath = item.materialPath {
                    editableAssetBlock(title: "Material Properties", isParticle: false, text: material, path: materialPath)
                }
            }
            .padding()
        }
        .navigationTitle(item.name)
    }

    @ViewBuilder private func effectList(for item: SceneInspectorItem) -> some View {
        if !item.effects.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Effects").font(.title3.bold())
                ForEach(item.effects) { effect in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            if let maskPath = effect.maskPath {
                                HStack(spacing: 5) {
                                    Text("Mask").font(.headline)
                                    InfoTip(String(localized: "Limits this effect to the white areas of the mask. Black areas are left untouched."))
                                }
                                Text(maskPath).font(.caption.monospaced()).foregroundStyle(.secondary)
                                if let mask = model.decodedMasks[effect.id] {
                                    Image(nsImage: mask.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity, maxHeight: 300)
                                        .background(Color.black)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else if model.loadingItemID == item.id {
                                    ProgressView()
                                }
                            } else {
                                Text("No mask").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(effect.combos.filter { model.requirementsHold($0, in: effect) }) { combo in
                                effectComboControl(combo, effect: effect)
                            }
                            ForEach(effect.controls) { control in
                                if control.isColor {
                                    if control.component == 0 {
                                        ColorPicker(selection: Binding(
                                            get: { model.effectColor(for: control) },
                                            set: { model.setEffectColor($0, control: control) }
                                        ), supportsOpacity: false) {
                                            parameterLabel(control.title, help: parameterHelp(control, effect: effect.name))
                                        }
                                        .anchorsColorPanel()
                                    }
                                } else {
                                    effectSlider(control, effect: effect)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Toggle("Enabled", isOn: Binding(
                                get: { model.effectEnabled[effect.id] ?? true },
                                set: { model.setEffectEnabled($0, effect: effect) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            Label(effect.title, systemImage: "slider.horizontal.3")
                            InfoTip(SceneHelp.effect(effect.name))
                        }
                    }
                }
            }
        }
    }

    /// WE's material slider: the annotation's range, step 0.01 (1 for `int`), and a number field
    /// that accepts values past the range.
    @ViewBuilder private func effectSlider(_ control: SceneInspectorEffectControl, effect: SceneInspectorEffect) -> some View {
        let value = Binding<Double>(
            get: { model.displayedEffectValue(for: control) },
            set: { model.setDisplayedEffectValue($0, control: control) }
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                parameterLabel(control.title, help: parameterHelp(control, effect: effect.name))
                if control.isLinked, control.component == 0 {
                    Toggle(isOn: Binding(get: { model.isLinked(control) },
                                         set: { model.setLinked($0, control: control) })) {
                        Image(systemName: "link")
                    }
                    .toggleStyle(.button)
                    .help("Edit X and Y together")
                }
            }
            NumericSliderInput(value: value,
                               range: control.minimum...max(control.maximum, control.minimum + 0.001),
                               defaultValue: control.defaultValue,
                               step: control.isInteger ? 1 : 0.01,
                               fractionDigits: control.isInteger ? 0 : 2, fieldWidth: 76,
                               clampsTypedValue: false)
            inspectorMusicSyncControls(for: control)
        }
    }

    @ViewBuilder private func effectComboControl(_ combo: SceneInspectorEffectCombo, effect: SceneInspectorEffect) -> some View {
        let selection = Binding<Int>(get: { model.comboValue(combo) }, set: { model.setComboValue($0, combo: combo) })
        if combo.options.isEmpty {
            Toggle(combo.title, isOn: Binding(get: { selection.wrappedValue != 0 },
                                              set: { selection.wrappedValue = $0 ? 1 : 0 }))
                .toggleStyle(.checkbox)
        } else {
            Picker(combo.title, selection: selection) {
                ForEach(Self.optionGroups(combo), id: \.offset) { group in
                    if let heading = group.heading {
                        Section(heading) {
                            ForEach(group.options, id: \.value) { option in Text(option.title).tag(option.value) }
                        }
                    } else {
                        ForEach(group.options, id: \.value) { option in Text(option.title).tag(option.value) }
                    }
                }
            }
        }
    }

    /// The combo's options in runs of one editor group (WE's "Native (fast)" / "Emulated (slow)"
    /// blend modes), in order; one run without a heading for authored options.
    private static func optionGroups(_ combo: SceneInspectorEffectCombo)
        -> [(offset: Int, heading: String?, options: [(title: String, value: Int)])] {
        // Shared with the Wallpaper Editor (`InspectorOptionGroups`).
        InspectorOptionGroups.groups(combo.options.map { InspectorOption(title: $0.title, value: $0.value, group: $0.group) })
            .map { group -> (offset: Int, heading: String?, options: [(title: String, value: Int)]) in
                (group.id, group.heading, group.options.map { (title: $0.title, value: $0.value) })
            }
    }

    @ViewBuilder private func inspectorMusicSyncControls(for control: SceneInspectorEffectControl) -> some View {
        let isEnabled = Binding<Bool>(
            get: { model.musicSyncEnabled(for: control) },
            set: { model.setMusicSyncEnabled($0, for: control) }
        )
        Toggle("Sync to Music", isOn: isEnabled)
            .toggleStyle(.checkbox)
            .font(.caption)
            .help(SceneHelp.musicSyncSource)
        if isEnabled.wrappedValue {
            let span = max(control.maximum - control.minimum, 0.001)
            let amount = Binding<Double>(
                get: { model.musicAmount(for: control) },
                set: { model.setMusicAmount($0, for: control) }
            )
            HStack {
                Text("Music Amount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NumericSliderInput(value: amount, range: -span...span,
                                   defaultValue: 0, fractionDigits: 3,
                                   sliderWidth: 100, fieldWidth: 64)
            }
        }
    }

    @ViewBuilder private func movementControls(for item: SceneInspectorItem?) -> some View {
        let origin = item.map(model.origin(for:))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Move Element", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.title3.bold())
                Spacer()
                if let origin {
                    Text("X \(Int(origin.x))  Y \(Int(origin.y))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Color.clear.frame(width: 48, height: 40)
                    moveButton(systemImage: "arrow.up", title: "Move Up",
                               help: "Move up. Shift = 50 px, Control = 1 px, default = 10 px") {
                        guard let item else { return }
                        model.moveObject(item, deltaX: 0, deltaY: movementStep())
                    }
                    Color.clear.frame(width: 48, height: 40)
                }
                GridRow {
                    moveButton(systemImage: "arrow.left", title: "Move Left",
                               help: "Move left. Shift = 50 px, Control = 1 px, default = 10 px") {
                        guard let item else { return }
                        model.moveObject(item, deltaX: -movementStep(), deltaY: 0)
                    }
                    Text("Move")
                        .font(.callout.weight(.semibold))
                        .frame(width: 58, height: 40)
                    moveButton(systemImage: "arrow.right", title: "Move Right",
                               help: "Move right. Shift = 50 px, Control = 1 px, default = 10 px") {
                        guard let item else { return }
                        model.moveObject(item, deltaX: movementStep(), deltaY: 0)
                    }
                }
                GridRow {
                    Color.clear.frame(width: 48, height: 40)
                    moveButton(systemImage: "arrow.down", title: "Move Down",
                               help: "Move down. Shift = 50 px, Control = 1 px, default = 10 px") {
                        guard let item else { return }
                        model.moveObject(item, deltaX: 0, deltaY: -movementStep())
                    }
                    Color.clear.frame(width: 48, height: 40)
                }
            }
            // The arrows point at screen directions, so the pad doesn't mirror in right-to-left languages.
            .environment(\.layoutDirection, .leftToRight)
            .disabled(item == nil)
            .opacity(item == nil ? 0.4 : 1)
            Text(item == nil ? "Select an object to move it." : "Arrow keys work when this panel is focused. Shift moves faster, Control moves slower.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GroupBoxed())
    }

    private func moveButton(systemImage: String, title: LocalizedStringKey, help: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 40)
        }
        .glassButtonStyle(.prominent)
        .help(help)
    }

    @ViewBuilder private func scaleControls(for item: SceneInspectorItem?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Size", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.headline)
                Spacer()
                if let item {
                    Text(verbatim: model.scale(for: item).formatted(.number.precision(.fractionLength(2))) + "×")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let item {
                let binding = Binding(
                    get: { model.scale(for: item) },
                    set: { model.setObjectScale(item, scale: $0) })
                NumericSliderInput(value: binding, range: 0.05...5,
                                   defaultValue: 1, step: 0.05, suffix: "x",
                                   fractionDigits: 2, sliderWidth: 120, fieldWidth: 52)
                Button("Reset to 1x") { model.setObjectScale(item, scale: 1) }
                    .buttonStyle(.link)
                    .font(.caption)
                if item.kind == "Image" {
                    appearanceControls(for: item)
                    blendModePicker(for: item)
                }
                if !SceneInspectorModel.blendingOptions(for: item).isEmpty {
                    materialBlendingPicker(for: item)
                }
            } else {
                Text("Select an object to resize it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The image layer's opacity and colour (its `alpha` and `color`), when nothing else sets them.
    @ViewBuilder private func appearanceControls(for item: SceneInspectorItem) -> some View {
        if let alpha = model.alpha(for: item) {
            SceneLayerOpacitySlider(value: alpha) { model.setAlpha($0, for: item) }
        }
        if let color = model.color(for: item) {
            ColorPicker(selection: Binding(get: { Color(red: color.x, green: color.y, blue: color.z) },
                                           set: { model.setColor($0, for: item) }),
                        supportsOpacity: false) {
                Text("Color")
            }
            .anchorsColorPanel()
        }
    }

    /// The selected layer's adjustments in an isolated mode's panel: the Wallpaper mode's own
    /// controls (visibility, move, size, opacity and colour, blending, alignment, effects), on the
    /// isolated store.
    @ViewBuilder private func layerAdjustments(for item: SceneInspectorItem?) -> some View {
        if let item, !item.isSynthetic {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { item.visible }, set: { model.setObjectVisible($0, item: item) })) {
                    Text(verbatim: item.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                .toggleStyle(.switch)
                .help(item.visible ? "Hide object" : "Show object")
                movementControls(for: item)
                scaleControls(for: item)
                alignmentControls(for: item)
                effectList(for: item)
            }
            .modifier(ArrowKeyMove { direction in move(item, direction: direction) })
        } else {
            Text("Select a layer in the list to adjust it here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The image layer's blend mode, WE's 33 in its editor's order and groups.
    private func blendModePicker(for item: SceneInspectorItem) -> some View {
        let combo = model.blendModeCombo
        return Picker(combo.title, selection: Binding(get: { model.blendMode(for: item) },
                                                      set: { model.setBlendMode($0, for: item) })) {
            ForEach(Self.optionGroups(combo), id: \.offset) { group in
                Section(group.heading ?? "") {
                    ForEach(group.options, id: \.value) { option in Text(option.title).tag(option.value) }
                }
            }
        }
    }

    /// The blending the layer's material draws with, of those its kind of layer draws
    /// (`WEMaterialBlending`), and a reset to its material's own.
    private func materialBlendingPicker(for item: SceneInspectorItem) -> some View {
        HStack {
            Picker("Blending", selection: Binding(get: { model.materialBlending(for: item) },
                                                  set: { model.setMaterialBlending($0, for: item) })) {
                ForEach(SceneInspectorModel.blendingOptions(for: item), id: \.self) { blending in
                    Self.title(of: blending).tag(blending)
                }
            }
            Button("Reset") { model.resetMaterialBlending(for: item) }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(model.materialBlending(for: item) == model.authoredBlending(for: item))
        }
    }

    private static func title(of blending: WEMaterialBlending) -> Text {
        switch blending {
        case .normal: Text("Normal")
        case .translucent: Text("Translucent")
        case .additive: Text("Additive")
        case .alphaToCoverage: Text("Alpha to Coverage")
        }
    }

    private func movementColumn(for item: SceneInspectorItem?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                movementControls(for: item)
                Divider()
                scaleControls(for: item)
                Divider()
                alignmentControls(for: item)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step")
                        .font(.headline)
                    Text("Default 10 px")
                    Text("Shift 50 px")
                    Text("Control 1 px")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .modifier(ArrowKeyMove { direction in
            if let item { move(item, direction: direction) }
        })
    }

    private func alignmentControls(for item: SceneInspectorItem?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Align Element", systemImage: "align.horizontal.center")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    alignmentButton("Left", help: "Align Left", systemImage: "align.horizontal.left") {
                        guard let item else { return }
                        model.alignObject(item, horizontal: .left)
                    }
                    alignmentButton("Center", help: "Align Center", systemImage: "align.horizontal.center") {
                        guard let item else { return }
                        model.alignObject(item, horizontal: .center)
                    }
                    alignmentButton("Right", help: "Align Right", systemImage: "align.horizontal.right") {
                        guard let item else { return }
                        model.alignObject(item, horizontal: .right)
                    }
                }
                // Left, centre, right on screen, in every language.
                .environment(\.layoutDirection, .leftToRight)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Vertical")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    alignmentButton("Top", help: "Align Top", systemImage: "align.vertical.top") {
                        guard let item else { return }
                        model.alignObject(item, vertical: .top)
                    }
                    alignmentButton("Middle", help: "Align Middle", systemImage: "align.vertical.center") {
                        guard let item else { return }
                        model.alignObject(item, vertical: .center)
                    }
                    alignmentButton("Bottom", help: "Align Bottom", systemImage: "align.vertical.bottom") {
                        guard let item else { return }
                        model.alignObject(item, vertical: .bottom)
                    }
                }
            }
        }
        .disabled(item == nil)
        .opacity(item == nil ? 0.4 : 1)
    }

    private func alignmentButton(_ title: LocalizedStringKey, help: LocalizedStringKey, systemImage: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                Text(title)
                    .font(.caption2)
            }
            .frame(width: 68, height: 46)
        }
        .glassButtonStyle()
        .help(help)
    }

    private func move(_ item: SceneInspectorItem, direction: MoveCommandDirection) {
        let step = movementStep()
        switch direction {
        case .up:
            model.moveObject(item, deltaX: 0, deltaY: step)
        case .down:
            model.moveObject(item, deltaX: 0, deltaY: -step)
        case .left:
            model.moveObject(item, deltaX: -step, deltaY: 0)
        case .right:
            model.moveObject(item, deltaX: step, deltaY: 0)
        @unknown default:
            break
        }
    }

    private func movementStep() -> Double {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { return 50 }
        if flags.contains(.control) { return 1 }
        return 10
    }

    private func parameterLabel(_ title: String, help: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
            InfoTip(help)
        }
    }

    private func parameterHelp(_ control: SceneInspectorEffectControl, effect: String? = nil) -> String {
        SceneHelp.parameter(effect: effect, key: control.key, title: control.title,
                            displaysDegrees: control.displaysDegrees)
    }


    @ViewBuilder private func decodedTextureList(for item: SceneInspectorItem) -> some View {
        if model.loadingItemID == item.id {
            ProgressView("Decoding textures...")
        } else if model.decodedItemID == item.id {
            ForEach(model.decodedTextures) { texture in
                VStack(alignment: .leading, spacing: 6) {
                    Text(texture.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Image(nsImage: texture.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 420)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            if !item.texturePaths.isEmpty && model.decodedTextures.isEmpty {
                ContentUnavailableView("Texture Unavailable", systemImage: "photo.badge.exclamationmark")
            }
        }
    }

    private func loadSelectedTextures() {
        guard let item = model.items.first(where: { $0.id == selectedID }) else { return }
        model.loadTextures(for: item)
    }

    @ViewBuilder private func detailList(_ title: LocalizedStringKey, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                ForEach(values, id: \.self) { Text($0).font(.caption.monospaced()) }
            }
        }
    }

    @ViewBuilder private func editableAssetBlock(title: LocalizedStringKey, isParticle: Bool, text: String,
                                                path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Save") {
                    model.saveAssetJSON(text, path: path)
                }
                .buttonStyle(.borderedProminent)
            }
            TextEditor(text: Binding(
                get: { text },
                set: { value in
                    if let itemIndex = model.items.firstIndex(where: { $0.id == selectedID }) {
                        if isParticle {
                            model.items[itemIndex].rawParticle = value
                        } else {
                            model.items[itemIndex].rawMaterial = value
                        }
                    }
                }
            ))
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 220)
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder private func editableObjectBlock(for item: SceneInspectorItem) -> some View {
        if item.isSynthetic {
            VStack(alignment: .leading, spacing: 6) {
                Text("Layer Details").font(.headline)
                Text(model.items.first(where: { $0.id == item.id })?.rawObject ?? item.rawObject)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Object Properties").font(.headline)
                    Spacer()
                    Button("Save") {
                        let current = model.items.first(where: { $0.id == item.id })?.rawObject ?? item.rawObject
                        model.saveObjectJSON(current, item: item)
                    }
                    .buttonStyle(.borderedProminent)
                }
                TextEditor(text: Binding(
                    get: { model.items.first(where: { $0.id == item.id })?.rawObject ?? item.rawObject },
                    set: { value in
                        guard let index = model.items.firstIndex(where: { $0.id == item.id }) else { return }
                        model.items[index].rawObject = value
                    }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 220)
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// A layer's opacity: the slider shows the value as it moves and saves it when the drag ends (an
/// object JSON edit reloads the scene).
private struct SceneLayerOpacitySlider: View {
    let value: Double
    let onCommit: (Double) -> Void
    @State private var draft: Double?

    var body: some View {
        let shown = draft ?? value
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Opacity")
                Spacer()
                Text(shown, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { draft ?? value }, set: { draft = $0 }), in: 0...1, onEditingChanged: { editing in
                guard !editing, let draft else { return }
                onCommit(draft)
                self.draft = nil
            })
        }
    }
}

/// Arrow keys nudge the selected object while this panel has keyboard focus.
private struct ArrowKeyMove: ViewModifier {
    let onMove: (MoveCommandDirection) -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand(perform: onMove)
    }
}

/// A native group box around a block of controls.
private struct GroupBoxed: ViewModifier {
    func body(content: Content) -> some View {
        GroupBox { content }
    }
}

/// Ties a `FocusState` to the window's search field, where the OS can (`searchFocused`, macOS 15).
private struct SearchFieldFocus: ViewModifier {
    let isFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.searchFocused(isFocused)
        } else {
            content
        }
    }
}
