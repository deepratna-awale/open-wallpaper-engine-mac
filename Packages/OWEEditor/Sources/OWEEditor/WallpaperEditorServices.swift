import CoreGraphics
import SwiftUI
import OWEInspectorKit
import OWESceneEditing

/// What the editor needs from the app: the live scene drawn by the app's own renderer, and the
/// pieces of the Scene Inspector it shows again (the user properties, WE's blend modes and effect
/// help), so the two never disagree.
public struct WallpaperEditorServices {
    /// The live wallpaper, drawn by the app's renderer at the size it is given. Made once.
    public var makeCanvas: () -> AnyView
    /// The wallpaper's user properties, as the Details panel shows them; nil hides the section.
    public var userProperties: (() -> AnyView)?
    /// The Blend Mode picker's title and WE's modes, as the Scene Inspector lists them.
    public var blendModeTitle: String
    public var blendModes: [InspectorOption]
    /// Help for an effect, by its folder name (`waterripple`).
    public var effectHelp: (String) -> String
    /// The title a saved copy gets unless the user changes it.
    public var suggestedLocalTitle: String
    /// Writes a new local wallpaper with the edits baked in and adds it to the library; returns
    /// the title it was saved under.
    public var saveAsLocalWallpaper: (String) throws -> String
    /// The window's timeline (docs/editor-plan.md P4); nil shows none.
    public var timeline: SceneTimelineEditor?

    // MARK: Adding and editing (phases 2–3)

    /// The effects the editor can add: WE's built-in ones and the Workshop effects the wallpaper uses.
    public var effectCatalog: () -> [EffectCatalogEntry] = { [] }
    /// Makes an effect ready to add: WE's editor copies a built-in effect's materials, shaders and
    /// textures into the project (WE only reads them there), which the app does into the edits' files.
    public var prepareEffect: (EffectCatalogEntry) throws -> Void = { _ in }
    /// What an effect (`effects/…/effect.json`) lets the editor change, from its shaders.
    public var effectSchema: (String) -> EffectSchema? = { _ in nil }
    /// Where imported files and painted masks go; nil when the editor can't add files.
    public var assetStore: EditorAssetStore?
    /// The wallpaper's own files the asset browser lists (textures, models, sounds, fonts).
    public var wallpaperAssets: () -> [EditorAsset] = { [] }
    /// A texture's picture (`masks/…`, `editor/…`, a wallpaper's texture), for previews and for
    /// painting over an existing mask; nil when it can't be read.
    public var texture: (String) -> CGImage? = { _ in nil }
    /// Fonts a text layer can use: WE's, the wallpaper's, imported ones.
    public var fonts: () -> [EditorFont] = { [] }
    /// The wallpaper's user properties a value can be bound to (key, title), with their type.
    public var userPropertyChoices: () -> [EditorUserPropertyChoice] = { [] }

    /// The wallpaper's project.json as it ships, whose `general.properties` the user-property
    /// editor starts from; nil hides the editor.
    public var projectJSON: Data?
    /// What the wallpaper's running scripts log and the errors they raise; nil when the app
    /// doesn't report them.
    public var scriptConsole: SceneScriptConsoleFeed?
    /// The wallpaper's files and images the puppet editor reads; nil hides Puppet Warp.
    public var puppetAssets: PuppetEditorAssets?
    /// The particle editor (WE's presets and textures, restarting a system); nil leaves it out.
    public var particles: ParticleEditorServices?
    /// Depth maps for depth parallax (the Depth Map Generation plugin); nil leaves the sections out.
    public var depthMaps: DepthMapEditorServices?

    public init(makeCanvas: @escaping () -> AnyView, userProperties: (() -> AnyView)? = nil,
                blendModeTitle: String, blendModes: [InspectorOption], effectHelp: @escaping (String) -> String,
                suggestedLocalTitle: String, saveAsLocalWallpaper: @escaping (String) throws -> String,
                projectJSON: Data? = nil, scriptConsole: SceneScriptConsoleFeed? = nil) {
        self.makeCanvas = makeCanvas
        self.userProperties = userProperties
        self.blendModeTitle = blendModeTitle
        self.blendModes = blendModes
        self.effectHelp = effectHelp
        self.suggestedLocalTitle = suggestedLocalTitle
        self.saveAsLocalWallpaper = saveAsLocalWallpaper
        self.projectJSON = projectJSON
        self.scriptConsole = scriptConsole
    }
}

/// A file the asset browser lists.
public struct EditorAsset: Hashable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case texture, model, sound, font, other
    }

    /// Its path in the scene (`materials/foo.tex`, `models/foo.json`).
    public var path: String
    public var kind: Kind
    /// Imported in the editor rather than shipped by the wallpaper.
    public var isImported: Bool

    public var id: String { path }

    public init(path: String, kind: Kind, isImported: Bool = false) {
        self.path = path
        self.kind = kind
        self.isImported = isImported
    }

    /// Its kind by its path, as WE lays a wallpaper's folder out.
    public static func kind(of path: String) -> Kind {
        let lowered = path.lowercased()
        let fileExtension = (lowered as NSString).pathExtension
        if ["tex", "png", "jpg", "jpeg", "gif"].contains(fileExtension), lowered.hasPrefix("materials/") { return .texture }
        if fileExtension == "json", lowered.hasPrefix("models/") { return .model }
        if EditorAssetStore.soundTypes.contains(fileExtension) { return .sound }
        if EditorAssetStore.fontTypes.contains(fileExtension) { return .font }
        return .other
    }

    /// The texture name a material or effect slot uses for it (`materials/foo.tex` → `foo`).
    public var textureName: String? {
        guard kind == .texture, path.lowercased().hasPrefix("materials/") else { return nil }
        return ((path as NSString).deletingPathExtension as NSString).substring(from: "materials/".count)
    }

    public var fileName: String { (path as NSString).lastPathComponent }
}

/// A font a text layer can use: its `font` value and a name to show.
public struct EditorFont: Hashable, Identifiable, Sendable {
    public var value: String
    public var title: String
    public var id: String { value }

    public init(value: String, title: String) {
        self.value = value
        self.title = title
    }
}

/// A user property a value can follow.
public struct EditorUserPropertyChoice: Hashable, Identifiable, Sendable {
    public var key: String
    public var title: String
    /// WE's type (`slider`, `color`, `bool`, `combo`, …).
    public var type: String

    public var id: String { key }

    public init(key: String, title: String, type: String) {
        self.key = key
        self.title = title
        self.type = type
    }
}
