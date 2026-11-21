import Foundation

/// The parts of the user's Wallpaper Engine copy the app downloads through the Steam login into
/// the Wallpaper Storage folder (`<storage>/.owe-assets`), kept as the install lays them out and
/// read in place (`SteamHelperDownload.assetsFileList`), and what is recorded about the download.
enum WallpaperEngineAssetsCache {
    /// What the download was, stored beside it.
    struct Info: Codable, Equatable {
        var installedAt: Date
        /// Steam's build id of the Wallpaper Engine copy, when it came from Steam.
        var steamBuildID: String?
        /// The default wallpapers brought into the storage folder with the assets, by folder name,
        /// so removing the assets can offer to remove them too.
        var defaultProjects: [String]?
    }

    enum Failure: LocalizedError {
        case notAnInstall(URL)

        var errorDescription: String? {
            switch self {
            case .notAnInstall(let url):
                return String(localized: "\(url.path) isn't a Wallpaper Engine folder or its assets folder.",
                              comment: "Assets error; %@ is a folder path")
            }
        }
    }

    static let infoFileName = ".owe-assets-info.json"
    /// WE's project templates, relative to the install.
    static let installTemplatesPath = "projects/templates"
    /// Where WE's editor keeps its script and shader snippets, relative to the install.
    static let installSnippetsPath = "ui/dist/monaco/snippets"

    static func infoURL(cache: URL) -> URL { cache.appending(path: infoFileName) }

    static func readInfo(cache: URL) -> Info? {
        let url = infoURL(cache: cache)
        // An absent file is a cache without history (or no cache): no info to show.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Info.self, from: Data(contentsOf: url))
        } catch {
            OWELog.error(.library, "Can't read the assets cache's info at \(url.path): \(error)")
            return nil
        }
    }

    static func writeInfo(_ info: Info, cache: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: infoURL(cache: cache), options: .atomic)
    }

    /// Deletes a folder the app created itself.
    static func removeIfPresent(_ url: URL, fileManager: FileManager = .default) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            OWELog.error(.library, "Can't remove \(url.path): \(error)")
        }
    }

    /// The bytes `directory` takes on disk.
    static func size(of directory: URL, fileManager: FileManager = .default) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            do {
                let values = try file.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? 0)
            } catch {
                OWELog.error(.library, "Can't size \(file.path): \(error)")
            }
        }
        return total
    }
}
