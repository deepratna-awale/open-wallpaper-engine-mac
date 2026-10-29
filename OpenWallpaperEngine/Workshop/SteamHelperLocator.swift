import Foundation

/// Which `owe-steam-helper` the app runs: `OWE_STEAM_HELPER` when set (a development build, which
/// may lack the bundled one), otherwise the app's own for this architecture.
enum SteamHelperLocator {
    static let environmentKey = "OWE_STEAM_HELPER"

    /// This process's architecture, as the helper's file name has it.
    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    /// The helper, or nil when there is none to run.
    static func executable(environment: [String: String] = ProcessInfo.processInfo.environment,
                           app: URL = AppBundleLayout.appBundle.bundleURL,
                           fileManager: FileManager = .default) -> URL? {
        let candidate = environment[environmentKey].map { URL(filePath: $0) }
            ?? AppBundleLayout.steamHelperURL(inApp: app, architecture: architecture)
        guard fileManager.isExecutableFile(atPath: candidate.path) else {
            OWELog.error(.workshop, "No Steam helper at \(candidate.path)")
            return nil
        }
        return candidate
    }
}
