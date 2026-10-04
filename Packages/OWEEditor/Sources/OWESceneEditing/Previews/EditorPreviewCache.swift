import Foundation

/// The editor's previews of effects and particle systems on disk:
/// `<Caches>/EditorPreviews/<assets build>-r<revision>/<subject>.heic` for a still preview, `.mov`
/// (HEVC) for a moving one. A preview shows WE's files, so the folder is keyed by the build of WE's
/// assets it was rendered from: another build gets a folder of its own, and opening it removes
/// the others (`prune`). `revision` is bumped whenever the rendering changes.
public struct EditorPreviewCache: Sendable {
    /// Bump when what a preview shows changes (its scene, size, length or encoding).
    public static let revision = 1
    /// A preview's file types: a still, a loop.
    public static let stillExtension = "heic"
    public static let movieExtension = "mov"

    /// `EditorPreviews`, the folder holding every build's previews.
    public let root: URL
    /// The assets build (`assetsBuild(of:)`).
    public let build: String

    public init(root: URL, build: String) {
        self.root = root
        self.build = build
    }

    /// `<root>/EditorPreviews`.
    public init(cachesDirectory: URL, build: String) {
        self.init(root: cachesDirectory.appending(path: "EditorPreviews", directoryHint: .isDirectory), build: build)
    }

    /// This build's folder.
    public var directory: URL {
        root.appending(path: "\(EditorPreviewSubject.fileSafe(build))-r\(Self.revision)", directoryHint: .isDirectory)
    }

    /// Where the subject's preview goes, without its extension (the renderer picks it).
    public func outputBase(for subject: EditorPreviewSubject) -> URL {
        directory.appending(path: subject.cacheName, directoryHint: .notDirectory)
    }

    /// The subject's preview when it was rendered for this build: its still, else its loop.
    public func cachedPreview(for subject: EditorPreviewSubject, fileManager: FileManager = .default) -> URL? {
        let base = outputBase(for: subject)
        for fileExtension in [Self.stillExtension, Self.movieExtension] {
            let url = base.appendingPathExtension(fileExtension)
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        }
        return nil
    }

    /// Removes the previews of every other build and revision.
    public func prune(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: root.path(percentEncoded: false)) else { return }
        let keep = directory.standardizedFileURL.lastPathComponent
        for folder in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        where folder.lastPathComponent != keep {
            try fileManager.removeItem(at: folder)
        }
    }

    // MARK: The assets build

    /// The build of the WE assets in `assets` (an `assets` folder, or a copy of one), most exact
    /// first: Steam's build id from the app's copy (`.owe-assets-info.json`), the CI copy
    /// (`.build`) or a Steam install's app manifest; else WE's version (`version.json` of an
    /// install); else the modification dates of the folders previews read.
    public static func assetsBuild(of assets: URL, fileManager: FileManager = .default) -> String {
        let parent = assets.deletingLastPathComponent()
        for folder in [assets, parent] {
            if let id = infoBuildID(in: folder) { return "steam-\(id)" }
            // Optional: a copy without a `.build` file is looked up the next way.
            if let text = try? String(contentsOf: folder.appending(path: ".build"), encoding: .utf8) {
                let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty { return "steam-\(id)" }
            }
        }
        // `steamapps/common/wallpaper_engine/assets` → `steamapps/appmanifest_431960.acf`.
        let manifest = parent.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "appmanifest_431960.acf")
        if let id = manifestBuildID(manifest) { return "steam-\(id)" }
        // Optional: an install without version.json falls through to the folder dates.
        if let data = try? Data(contentsOf: parent.appending(path: "version.json")),
           let root = try? WETolerantJSON.object(from: data) as? [String: Any],
           let version = root["version"] as? String, !version.isEmpty {
            return "we-\(version)"
        }
        var stamps: [String] = []
        for name in ["effects", "particles", "presets", "shaders", "materials"] {
            let url = assets.appending(path: name, directoryHint: .isDirectory)
            // Optional: a folder the copy doesn't have is no part of the stamp.
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate else { continue }
            stamps.append("\(name)=\(Int(date.timeIntervalSince1970))")
        }
        return "files-" + EditorPreviewSubject.fileSafe(String(stamps.joined(separator: ",").hashValueStable, radix: 16))
    }

    /// `steamBuildID` of the app's own copy's info file.
    private static func infoBuildID(in folder: URL) -> String? {
        // Optional: only the app's and the CI's copies have the file.
        guard let data = try? Data(contentsOf: folder.appending(path: ".owe-assets-info.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = root["steamBuildID"] as? String, !id.isEmpty else { return nil }
        return id
    }

    /// `"buildid" "23967692"` of a Steam app manifest.
    static func manifestBuildID(_ url: URL) -> String? {
        // Optional: only a Steam install has the manifest.
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #""buildid"\s+"(\d+)""#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

private extension String {
    /// FNV-1a over the UTF-8 bytes: the same in every run (Swift's `hashValue` isn't).
    var hashValueStable: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}
