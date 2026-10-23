import CryptoKit
import Foundation

/// Which `SceneScriptStorage` store (and script id prefix) a wallpaper gets.
///
/// The key comes from where the wallpaper is installed, never from what its `project.json` says:
/// the Steam folder id (the wallpaper folder's name when it is all ASCII digits, as Steam names
/// Workshop items), or else `local-<hash of the standardized folder path>`. A `workshopid` in
/// `project.json` is chosen by the author, so keying on it would let one wallpaper read another's
/// store.
enum SceneScriptStorageKey {
    static let localPrefix = "local-"

    /// The key of the wallpaper in `directory`.
    static func key(forWallpaperDirectory directory: URL) -> String {
        steamFolderID(of: directory) ?? localKey(forWallpaperDirectory: directory)
    }

    /// The folder's name when it is a Steam item id (ASCII digits only), else nil.
    static func steamFolderID(of directory: URL) -> String? {
        let folder = directory.standardizedFileURL.lastPathComponent
        return !folder.isEmpty && folder.allSatisfy({ $0.isASCII && $0.isNumber }) ? folder : nil
    }

    /// `local-` and the first 8 bytes of the SHA-256 of the standardized folder path, in hex.
    static func localKey(forWallpaperDirectory directory: URL) -> String {
        let digest = SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8))
        return localPrefix + Digest.hex(digest.prefix(8))
    }
}
