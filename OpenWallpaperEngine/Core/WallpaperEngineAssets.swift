import Foundation

/// Resolves the Wallpaper Engine asset tree used for effects, shared materials and the SceneScript
/// runtime: the translated copy bundled inside the app, which is what makes effects work without
/// Wallpaper Engine installed.
enum WallpaperEngineAssets {
    /// The translated assets shipped inside the app, if present.
    static var bundled: URL? {
        guard let url = Bundle.main.url(forResource: "we-assets", withExtension: nil),
              FileManager.default.fileExists(atPath: url.appending(path: "effects").path) else { return nil }
        return url
    }

    /// Under XCTest only: the Wallpaper Engine install (or its `assets` folder) named by
    /// `OWE_WE_ASSETS`, for tests that need files the bundled copy leaves out (the particle
    /// gallery's presets). Always nil in the app.
    static var testInstall: URL? {
        guard NSClassFromString("XCTestCase") != nil,
              let path = ProcessInfo.processInfo.environment["OWE_WE_ASSETS"], !path.isEmpty else { return nil }
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let assets = root.lastPathComponent.caseInsensitiveCompare("assets") == .orderedSame
            ? root
            : root.appending(path: "assets", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: assets.path) ? assets : nil
    }

    static var directory: URL? {
        testInstall ?? bundled
    }

    /// Where shared assets are looked up, in order.
    static var searchDirectories: [URL] {
        var directories: [URL] = []
        for directory in [testInstall, bundled].compactMap({ $0 }) where !directories.contains(directory) {
            directories.append(directory)
        }
        return directories
    }

    /// The first of `relativePaths` that exists, trying every path in each directory before the next.
    static func locate(_ relativePaths: [String], in directories: [URL]) -> URL? {
        for directory in directories {
            for path in relativePaths {
                let candidate = directory.appending(path: path).standardizedFileURL
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }
}
