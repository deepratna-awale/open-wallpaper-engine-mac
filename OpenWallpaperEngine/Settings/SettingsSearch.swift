import Foundation

/// The anchors of the settings sections a search result can open (`settingsAnchor`).
enum SettingsAnchor {
    static let startup = "startup"
    static let language = "language"
    static let appearance = "appearance"
    static let macOS = "macos"
    static let setup = "setup"
    static let shortcuts = "shortcuts"
    static let playback = "playback"
    static let quality = "quality"
    static let converted = "converted"
    static let displays = "displays"
    static let video = "video"
    static let audio = "audio"
    static let rendering = "rendering"
    static let assets = "assets"
    static let steamCmd = "steamcmd"
    static let storage = "storage"
    static let libraryFolders = "libraryfolders"
    static let apiKey = "apikey"
    static let updates = "updates"
    static let privacy = "privacy"
    static let legal = "legal"
    static let security = "security"
    static let permissions = "permissions"
    static let diagnostics = "diagnostics"
    static let threadGuards = "threadguards"
    static let developer = "developer"
    static let reset = "reset"
    static let plugins = "plugins"
    static let chromium = "chromium"
    static let depthMaps = "depthmaps"
    static let mcpServer = "mcpserver"
}

/// Search in Settings: the settings people look for, where they are, and the matches for a query.
struct SettingsSearch {
    struct Entry: Identifiable, Equatable {
        let title: LocalizedStringResource
        let tab: SettingsTab
        let anchor: String?

        var id: String { "\(tab.rawValue).\(anchor ?? "").\(title.key)" }

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
    }

    static let entries: [Entry] = {
        func entry(_ title: LocalizedStringResource, _ tab: SettingsTab, _ anchor: String?) -> Entry {
            Entry(title: title, tab: tab, anchor: anchor)
        }
        let tabs = SettingsTab.allCases.map { entry($0.title, $0, nil) }
        return tabs + [
            entry("Automatic Startup", .general, SettingsAnchor.startup),
            entry("Start with macOS", .general, SettingsAnchor.startup),
            entry("Language", .general, SettingsAnchor.language),
            entry("Appearance", .general, SettingsAnchor.appearance),
            entry("Theme", .general, SettingsAnchor.appearance),
            entry("Adjust Menu Bar Color", .general, SettingsAnchor.macOS),
            entry("Show Wallpaper on Lock Screen", .general, SettingsAnchor.macOS),
            entry("Run Setup Again…", .general, SettingsAnchor.setup),
            entry("Keyboard Shortcuts", .general, SettingsAnchor.shortcuts),

            entry("Playback", .performance, SettingsAnchor.playback),
            entry("Laptop on battery", .performance, SettingsAnchor.playback),
            entry("Display asleep", .performance, SettingsAnchor.playback),
            entry("Quality", .performance, SettingsAnchor.quality),
            entry("Anti-aliasing", .performance, SettingsAnchor.quality),
            entry("Post-Processing", .performance, SettingsAnchor.quality),
            entry("Texture Resolution", .performance, SettingsAnchor.quality),
            entry("Scene Detail", .performance, SettingsAnchor.quality),
            entry("Render Resolution", .performance, SettingsAnchor.quality),
            entry("Shadows", .performance, SettingsAnchor.quality),
            entry("Volumetrics", .performance, SettingsAnchor.quality),
            entry("FPS", .performance, SettingsAnchor.quality),
            entry("Quality ↔ Efficiency", .performance, SettingsAnchor.quality),
            entry("Particle Budget", .performance, SettingsAnchor.quality),
            entry("Reflections", .performance, SettingsAnchor.quality),

            entry("Converted Wallpapers", .optimizations, SettingsAnchor.converted),
            entry("Remove original packages after conversion", .optimizations, SettingsAnchor.converted),
            entry("Displays", .optimizations, SettingsAnchor.displays),
            entry("Sync properties across displays", .optimizations, SettingsAnchor.displays),
            entry("Video Framework", .optimizations, SettingsAnchor.video),
            entry("Audio", .optimizations, SettingsAnchor.audio),
            entry("Audio Output", .optimizations, SettingsAnchor.audio),
            entry("Media integration support", .optimizations, SettingsAnchor.audio),
            entry("Rendering", .optimizations, SettingsAnchor.rendering),
            entry("Process Priority", .optimizations, SettingsAnchor.rendering),
            entry("Restart after crashing", .optimizations, SettingsAnchor.rendering),
            entry("Optimise textures", .optimizations, SettingsAnchor.rendering),
            entry("Cheaper shadows", .optimizations, SettingsAnchor.rendering),
            entry("Render web wallpapers at standard resolution", .optimizations, SettingsAnchor.rendering),
            entry("Draw large glowing particles at half resolution", .optimizations, SettingsAnchor.rendering),

            entry("Wallpaper Engine Assets", .assets, SettingsAnchor.assets),
            entry("SteamCMD", .assets, SettingsAnchor.steamCmd),
            entry("Wallpaper Storage", .assets, SettingsAnchor.storage),
            entry("Library Folders", .assets, SettingsAnchor.libraryFolders),
            entry("Steam Web API Key", .assets, SettingsAnchor.apiKey),

            entry("Update automatically", .updates, SettingsAnchor.updates),
            entry("Receive beta updates", .updates, SettingsAnchor.updates),
            entry("Don't show release notes", .updates, SettingsAnchor.updates),

            entry("Terms of Use", .privacy, SettingsAnchor.legal),
            entry("Privacy Policy", .privacy, SettingsAnchor.legal),
            entry("Report a Security Issue", .privacy, SettingsAnchor.security),

            entry("Screen & System Audio Recording", .permissions, SettingsAnchor.permissions),
            entry("System Audio Recording", .permissions, SettingsAnchor.permissions),
            entry("Audio Visualizers", .permissions, SettingsAnchor.permissions),

            entry("Shader Cache", .diagnostics, SettingsAnchor.diagnostics),
            entry("Shader Compiler", .diagnostics, SettingsAnchor.diagnostics),
            entry("Log Level", .diagnostics, SettingsAnchor.developer),
            entry("Reset Config", .diagnostics, SettingsAnchor.reset),

            entry("Screen Saver", .plugins, SettingsAnchor.plugins),
            entry("Depth Map Generation", .plugins, SettingsAnchor.depthMaps),
            entry("Chromium web engine", .plugins, SettingsAnchor.chromium),
            entry("MCP Server", .plugins, SettingsAnchor.mcpServer),

            entry("Credits", .about, nil),
        ] + AppShortcut.all.map { entry($0.title, .general, SettingsAnchor.shortcuts) }
    }()

    /// The entries whose title (in the app's language, or in English) contains every word of
    /// `query`, ignoring case and accents; exact tab names first.
    static func results(for query: String, locale: Locale = .current) -> [Entry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        func matches(_ text: String) -> Bool {
            words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil }
        }
        var seen = Set<String>()
        return entries.filter { entry in
            var english = entry.title
            english.locale = Locale(identifier: "en")
            guard matches(String(localized: entry.title)) || matches(String(localized: english)) else { return false }
            return seen.insert(String(localized: entry.title) + "\(entry.tab.rawValue)").inserted
        }
    }
}
