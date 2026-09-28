import AppKit

/// Quits and opens the app again, e.g. so a new language applies (macOS reads an app's language
/// at launch). The new copy gets the same launch arguments and isolated-state tag, so a
/// development copy stays isolated.
@MainActor
enum AppRelauncher {
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = Array(CommandLine.arguments.dropFirst())
        let environmentKey = AppStorageLocation.environmentKey
        if let tag = ProcessInfo.processInfo.environment[environmentKey] {
            configuration.environment = [environmentKey: tag]
        }
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    OWELog.error(.settings, "Can't relaunch Open Wallpaper Engine: \(error)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
