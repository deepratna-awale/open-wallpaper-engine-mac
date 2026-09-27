import Foundation

/// The user-property stores an edit in the sidebar or the inspector goes to: the selected
/// displays' (`WallpaperViewModel.editedPropertyScopes`), or the shared store while properties
/// are synced. The first scope is the one shown.
struct WallpaperPropertyTargets {
    let directory: URL
    let identity: WallpaperSettingsIdentity
    let scopes: [WallpaperPropertyScope]

    init(wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope]) {
        directory = wallpaper.wallpaperDirectory
        identity = WallpaperSettingsIdentity.resolve(wallpaper)
        self.scopes = scopes.isEmpty ? [.shared] : scopes
    }

    /// The shown scope's saved values (the shared ones for a display that has none yet).
    var storedValues: [String: String] {
        identity.stored(.userProperties, scope: scopes[0]) as? [String: String] ?? [:]
    }

    /// The keys of the running stores (`SceneUserPropertyService`) the scopes are read from.
    var runtimeKeys: [String] { scopes.map { $0.runtimeKey(directory: directory) } }

    /// Hands `values` to the running wallpapers at once.
    func publish(_ values: [String: String]) {
        for key in runtimeKeys { WallpaperServices.shared.setUserProperties(values, wallpaper: key, replacing: false) }
    }

    /// Saves `values` as every scope's, marked as set by the user, and lets the displays regroup
    /// by their properties (`Notification.Name.wallpaperPropertiesDidSave`).
    func save(_ values: [String: String], defaults: UserDefaults = .app) {
        for scope in scopes {
            defaults.set(values, forKey: identity.key(.userProperties, scope: scope))
            defaults.set(true, forKey: identity.key(.explicitUserProperties, scope: scope))
        }
        NotificationCenter.default.post(name: .wallpaperPropertiesDidSave, object: directory.path)
    }

    /// WE's Reset (`WallpaperPropertyReset`): each scope's properties go back to `defaultValues`,
    /// keeping that scope's Scene Inspector edits. Returns the shown scope's new values.
    @discardableResult
    func reset(to defaultValues: [String: String], defaults: UserDefaults = .app,
               publish: (String, [String: String]) -> Void = Self.publishReplacing) -> [String: String] {
        rewrite(defaults: defaults, publish: publish) { WallpaperPropertyReset.values(resetting: $0, to: defaultValues) }
    }

    /// The Scene Inspector's Reset: each scope's inspector edits are dropped, its other
    /// properties kept. Returns the shown scope's new values.
    @discardableResult
    func removeSceneInspectorEdits(defaults: UserDefaults = .app,
                                   publish: (String, [String: String]) -> Void = Self.publishReplacing) -> [String: String] {
        rewrite(defaults: defaults, publish: publish, WallpaperPropertyReset.values(removingSceneInspectorEditsFrom:))
    }

    /// Hands a store's whole set of values to its running wallpaper: keys missing from them are
    /// dropped there too, and the wallpaper applies the change live or rebuilds what it needs
    /// (`SceneWallpaperViewModel.impact(of:)`).
    static func publishReplacing(_ runtimeKey: String, _ values: [String: String]) {
        WallpaperServices.shared.setUserProperties(values, wallpaper: runtimeKey, replacing: true)
    }

    /// Replaces every scope's saved values with `transform` of them (a display without its own
    /// yet starts from the shared ones), saves them as set by the user, so a load doesn't
    /// re-derive what the transform kept, and publishes them.
    private func rewrite(defaults: UserDefaults, publish: (String, [String: String]) -> Void,
                         _ transform: ([String: String]) -> [String: String]) -> [String: String] {
        var shown: [String: String]?
        for scope in scopes {
            let values = transform(identity.stored(.userProperties, scope: scope, defaults: defaults) as? [String: String] ?? [:])
            defaults.set(values, forKey: identity.key(.userProperties, scope: scope))
            defaults.set(true, forKey: identity.key(.explicitUserProperties, scope: scope))
            publish(scope.runtimeKey(directory: directory), values)
            if shown == nil { shown = values }
        }
        NotificationCenter.default.post(name: .wallpaperPropertiesDidSave, object: directory.path)
        return shown ?? [:]
    }
}
