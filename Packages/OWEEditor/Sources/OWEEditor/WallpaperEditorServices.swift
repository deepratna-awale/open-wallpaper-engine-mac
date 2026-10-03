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

    public init(makeCanvas: @escaping () -> AnyView, userProperties: (() -> AnyView)? = nil,
                blendModeTitle: String, blendModes: [InspectorOption], effectHelp: @escaping (String) -> String,
                suggestedLocalTitle: String, saveAsLocalWallpaper: @escaping (String) throws -> String) {
        self.makeCanvas = makeCanvas
        self.userProperties = userProperties
        self.blendModeTitle = blendModeTitle
        self.blendModes = blendModes
        self.effectHelp = effectHelp
        self.suggestedLocalTitle = suggestedLocalTitle
        self.saveAsLocalWallpaper = saveAsLocalWallpaper
    }
}
