import Foundation

/// Where this process keeps the user's persistent state: its defaults, its Application Support
/// folder, its caches and the prefix of its keychain services. Chosen once at launch.
///
/// Every copy of the app shares the bundle identifier, so without this a test run (the test host
/// is the app) or a development copy launched by a script would read and overwrite the user's
/// playlists, settings and safe-restart sentinel. Such a copy is **isolated** instead:
///
/// - under XCTest, with the tag `tests`;
/// - with `OWE_ISOLATED_STATE=<tag>` in the environment, or the launch arguments
///   `-OWEIsolatedState <tag>`.
///
/// An isolated copy uses the defaults suite `<bundle id>.isolated.<tag>`, the folders
/// `Open Wallpaper Engine (isolated <tag>)` under Application Support and Caches, and keychain
/// services under `<bundle id>.isolated.<tag>`. A normal launch uses `UserDefaults.standard` and
/// the usual folders, unchanged. Launch arguments (`-Key value`) still override any default in an
/// isolated copy, e.g. `-CustomWallpapersDirectory <path>`.
struct AppStorageLocation: @unchecked Sendable { // UserDefaults is thread-safe; the rest is immutable.
    static let realBundleIdentifier = "com.winddog.wallpaper-engine"
    static let environmentKey = "OWE_ISOLATED_STATE"
    static let argumentKey = "-OWEIsolatedState"
    static let testsTag = "tests"

    /// The store of this process.
    static let current = AppStorageLocation(isolationTag: isolationTag(
        environment: ProcessInfo.processInfo.environment,
        arguments: ProcessInfo.processInfo.arguments,
        isRunningTests: NSClassFromString("XCTestCase") != nil))

    /// `nil` for the user's real state.
    let isolationTag: String?
    let defaults: UserDefaults
    /// The defaults suite, `nil` for `UserDefaults.standard`.
    let suiteName: String?
    /// `<Application Support>/Open Wallpaper Engine`, or its isolated sibling.
    let supportDirectory: URL
    /// The Caches root the app writes under: the user's Caches folder, or a folder inside it.
    let cachesDirectory: URL
    /// Keychain services are `<keychainServicePrefix>.<suffix>`.
    let keychainServicePrefix: String

    var isIsolated: Bool { isolationTag != nil }

    init(isolationTag: String?, bundleIdentifier: String = Bundle.main.bundleIdentifier ?? realBundleIdentifier) {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.isolationTag = isolationTag
        if let isolationTag {
            let suite = "\(bundleIdentifier).isolated.\(isolationTag)"
            let folder = "Open Wallpaper Engine (isolated \(isolationTag))"
            suiteName = suite
            // Only nil for the global domain or the bundle identifier itself, which `suite` never is.
            defaults = UserDefaults(suiteName: suite)!
            supportDirectory = support.appending(path: folder, directoryHint: .isDirectory)
            cachesDirectory = caches.appending(path: folder, directoryHint: .isDirectory)
            keychainServicePrefix = suite
        } else {
            suiteName = nil
            defaults = .standard
            supportDirectory = support.appending(path: "Open Wallpaper Engine", directoryHint: .isDirectory)
            cachesDirectory = caches
            keychainServicePrefix = bundleIdentifier
        }
    }

    /// The tag to isolate this process under, or `nil` for the user's real state.
    static func isolationTag(environment: [String: String], arguments: [String], isRunningTests: Bool) -> String? {
        if let index = arguments.firstIndex(of: argumentKey), arguments.indices.contains(index + 1),
           let tag = sanitized(arguments[index + 1]) {
            return tag
        }
        if let value = environment[environmentKey], let tag = sanitized(value) { return tag }
        let runsTests = isRunningTests || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
        return runsTests ? testsTag : nil
    }

    /// A tag usable in a defaults suite and a folder name; an empty one doesn't count.
    private static func sanitized(_ tag: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = String(tag.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return cleaned.isEmpty ? nil : cleaned
    }
}

extension UserDefaults {
    /// The app's defaults: `.standard` for the user's real launch, an isolated suite for tests and
    /// development copies (see `AppStorageLocation`). Use this instead of `.standard`.
    static var app: UserDefaults { AppStorageLocation.current.defaults }
}
