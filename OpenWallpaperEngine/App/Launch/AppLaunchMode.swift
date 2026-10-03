import Foundation

/// What this launch of the app's executable is, read from its arguments before any app lifecycle
/// starts (`main.swift`). The helper runs (`ShaderPrewarmCommand`, `CrashWatcher`) exit before
/// this is asked.
enum AppLaunchMode: Equatable {
    /// Open Wallpaper Engine: the desktop wallpapers, the menu bar item, the library.
    case main
    /// The Wallpaper Editor alone, in a process of its own (`--wallpaper-editor [<folder>]`):
    /// quitting either app leaves the other running. `folder` is the wallpaper to open first.
    case wallpaperEditor(URL?)

    static let wallpaperEditorArgument = "--wallpaper-editor"

    /// The mode `arguments` (the process's, executable first) ask for.
    static func parse(_ arguments: [String]) -> AppLaunchMode {
        guard let index = arguments.firstIndex(of: wallpaperEditorArgument) else { return .main }
        let next = index + 1
        // A folder follows unless the next argument is another option (`-OWEIsolatedState …`).
        guard arguments.indices.contains(next), !arguments[next].isEmpty, !arguments[next].hasPrefix("-") else {
            return .wallpaperEditor(nil)
        }
        return .wallpaperEditor(URL(filePath: arguments[next], directoryHint: .isDirectory).standardizedFileURL)
    }

    /// The arguments that launch the editor on `folder`, keeping this process's isolation
    /// (`AppStorageLocation`): an isolated app opens an isolated editor.
    static func wallpaperEditorArguments(folder: URL?, isolationTag: String?) -> [String] {
        var arguments = [wallpaperEditorArgument]
        if let folder { arguments.append(folder.standardizedFileURL.path) }
        if let isolationTag { arguments += [AppStorageLocation.argumentKey, isolationTag] }
        return arguments
    }

    var isWallpaperEditor: Bool {
        if case .wallpaperEditor = self { return true }
        return false
    }
}
