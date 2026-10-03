import Foundation

/// Where Open Wallpaper Engine's two apps are: the app, and the Wallpaper Editor's own app inside
/// it, `<app>/Contents/Helpers/Wallpaper Editor.app` (`Scripts/build-editor-helper.sh`). The editor's
/// app runs a copy of the same executable under its own bundle id, `<app id>.editor`, so macOS
/// gives it its own Dock tile and LaunchServices identity; it shares the app's defaults, folders
/// and keychain (`AppStorageLocation`) and reads the app's large resources and update key from it.
enum AppBundleLayout {
    /// The editor app's name: its bundle, executable and `CFBundleName`.
    static let editorName = "Wallpaper Editor"
    /// What the editor's bundle id adds to the app's.
    static let editorIdentifierSuffix = ".editor"

    /// The editor's app inside the app at `app`.
    static func editorURL(inApp app: URL) -> URL {
        app.appending(path: "Contents/Helpers/\(editorName).app", directoryHint: .isDirectory)
    }

    /// The app a helper app sits in (`<app>/Contents/Helpers/<helper>.app`); nil when `helper`
    /// isn't inside one.
    static func appURL(containingHelper helper: URL) -> URL? {
        let helpers = helper.standardizedFileURL.deletingLastPathComponent()
        let contents = helpers.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents",
              app.pathExtension == "app" else { return nil }
        return app
    }

    static func isEditor(bundleIdentifier: String?) -> Bool {
        bundleIdentifier?.hasSuffix(editorIdentifierSuffix) ?? false
    }

    /// The app's bundle id, from the app's or the editor's.
    static func appIdentifier(for bundleIdentifier: String) -> String {
        isEditor(bundleIdentifier: bundleIdentifier)
            ? String(bundleIdentifier.dropLast(editorIdentifierSuffix.count)) : bundleIdentifier
    }

    /// The editor's bundle id, from the app's or the editor's.
    static func editorIdentifier(for bundleIdentifier: String) -> String {
        appIdentifier(for: bundleIdentifier) + editorIdentifierSuffix
    }

    /// Open Wallpaper Engine's own bundle: this process's, or, in the editor's app, the app it is
    /// inside. Its resources the editor's app leaves out (the placeholder video) and its
    /// Info.plist (the update key, `AppUpdateConfiguration`) are read here.
    static let appBundle: Bundle = {
        guard isEditor(bundleIdentifier: Bundle.main.bundleIdentifier),
              let app = appURL(containingHelper: Bundle.main.bundleURL), let bundle = Bundle(url: app) else {
            return .main
        }
        return bundle
    }()

    /// The video shown for a missing wallpaper.
    static var wallpaperNotFoundURL: URL {
        // The app always ships it (`Resources/WallpaperNotFound.mp4`).
        appBundle.url(forResource: "WallpaperNotFound", withExtension: "mp4")!
    }
}
