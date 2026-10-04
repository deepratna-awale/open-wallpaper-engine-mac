import Foundation

/// Where the app's control socket is: `<Application Support>/Open Wallpaper Engine/Control/control.sock`,
/// in the app's own support folder (it isn't sandboxed), inside a folder only its user can enter.
///
/// An isolated copy of the app (`OWE_ISOLATED_STATE=<tag>` or `-OWEIsolatedState <tag>`, the app's
/// `AppStorageLocation`) keeps its state in `Open Wallpaper Engine (isolated <tag>)`, so its socket
/// is there too: the `owe-mcp` that copy installed, or one run with the same `OWE_ISOLATED_STATE`,
/// talks to that copy, never to the user's own app.
///
/// A socket's path can't be longer than `maxPathBytes`. When the support folder's is (a long user
/// name, a long isolation tag), the socket goes in the user's own temporary folder instead
/// (`confstr(_CS_DARWIN_USER_TEMP_DIR)`, `0700`, the same for every process of the user), in
/// `owe-<hash of the support folder's path>/control.sock`: the app and `owe-mcp` work it out alike.
public enum ControlSocketLocation {
    public static let isolationEnvironmentKey = "OWE_ISOLATED_STATE"
    public static let folderName = "Control"
    public static let socketName = "control.sock"
    /// `sun_path`'s size less its terminator: a longer path can't be bound or connected.
    public static let maxPathBytes = 103

    /// The socket of the app whose support folder is `supportDirectory`.
    public static func socketURL(supportDirectory: URL, temporaryDirectory: URL? = nil) -> URL {
        let preferred = supportDirectory.appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: socketName, directoryHint: .notDirectory)
        guard preferred.path.utf8.count > maxPathBytes else { return preferred }
        let folder = "owe-" + hash(supportDirectory.standardizedFileURL.path)
        return (temporaryDirectory ?? userTemporaryDirectory).appending(path: folder, directoryHint: .isDirectory)
            .appending(path: socketName, directoryHint: .notDirectory)
    }

    /// The user's own temporary folder, as the system gives it to every process of the user
    /// whatever its environment.
    static var userTemporaryDirectory: URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 {
            return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    /// 64-bit FNV-1a of `text`, as 16 hex digits: stable across processes and launches.
    static func hash(_ text: String) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01b3
        }
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// The app's support folder for `isolationTag` (nil: the user's own app), as the app names it.
    public static func supportDirectory(isolationTag: String?, applicationSupport: URL? = nil) -> URL {
        let base = applicationSupport
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = isolationTag.flatMap(sanitizedTag).map { "Open Wallpaper Engine (isolated \($0))" }
            ?? "Open Wallpaper Engine"
        return base.appending(path: folder, directoryHint: .isDirectory)
    }

    /// An isolation tag as the app cleans it (`AppStorageLocation.sanitized`); nil when empty.
    public static func sanitizedTag(_ tag: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = String(tag.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return cleaned.isEmpty ? nil : cleaned
    }
}
