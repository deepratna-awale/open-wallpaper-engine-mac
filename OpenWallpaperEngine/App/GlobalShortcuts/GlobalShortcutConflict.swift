import Foundation

/// Something that already uses a shortcut being assigned to a playlist.
enum GlobalShortcutConflict: Equatable {
    /// Another playlist's shortcut.
    case playlist(id: UUID, name: String)
    /// One of this app's menu shortcuts (`AppShortcut.all`).
    case appMenu(AppShortcut.Name)
    /// A macOS shortcut: a symbolic hotkey or a standard menu shortcut. Nil name: one this app
    /// can't name.
    case macOS(name: LocalizedStringResource?)
    /// `RegisterEventHotKey` said the shortcut exists: another app holds it.
    case anotherApp

    static func == (lhs: GlobalShortcutConflict, rhs: GlobalShortcutConflict) -> Bool {
        switch (lhs, rhs) {
        case let (.playlist(a, x), .playlist(b, y)): return a == b && x == y
        case let (.appMenu(a), .appMenu(b)): return a == b
        case let (.macOS(a), .macOS(b)): return a?.key == b?.key
        case (.anotherApp, .anotherApp): return true
        default: return false
        }
    }

    /// One sentence for the warning alert, naming the conflict and what Use Anyway does about it.
    var message: String {
        switch self {
        case let .playlist(_, name):
            return String(localized: "The playlist \u{201C}\(name)\u{201D} uses this shortcut. Use Anyway moves it to this playlist.")
        case let .appMenu(name):
            let title = String(localized: AppShortcut[name].title)
            return String(localized: "The menu command \u{201C}\(title)\u{201D} uses this shortcut. Use Anyway gives it to this playlist, and the menu command no longer responds to it.")
        case let .macOS(name?):
            let title = String(localized: name)
            return String(localized: "macOS uses this shortcut for \u{201C}\(title)\u{201D}. Use Anyway saves it and opens Keyboard Shortcuts in System Settings, where you can turn the macOS one off.")
        case .macOS(nil):
            return String(localized: "This is a macOS shortcut. Use Anyway saves it and opens Keyboard Shortcuts in System Settings, where you can turn the macOS one off.")
        case .anotherApp:
            return String(localized: "Another app uses this shortcut. Use Anyway saves it, but it may not work while that app holds it.")
        }
    }
}

/// Finds what already uses a shortcut. The sources are injected so tests can supply them.
struct GlobalShortcutConflictFinder {
    var appShortcuts: [AppShortcut] = AppShortcut.all
    /// The user's enabled symbolic hotkeys, read when asked (the user may change them any time).
    var symbolicHotKeys: () -> [MacOSShortcut] = { MacOSShortcuts.symbolicHotKeys() }
    var standardShortcuts: [MacOSShortcut] = MacOSShortcuts.standard

    /// What `shortcut` conflicts with, in-app first, macOS after. `RegisterEventHotKey`'s answer
    /// (another app) is the caller's: only a registration can tell.
    func conflicts(for shortcut: GlobalShortcut, playlistID: UUID,
                   playlists: [WallpaperPlaylist]) -> [GlobalShortcutConflict] {
        var conflicts: [GlobalShortcutConflict] = []
        for playlist in playlists where playlist.id != playlistID && playlist.shortcut == shortcut {
            conflicts.append(.playlist(id: playlist.id, name: playlist.name))
        }
        for app in appShortcuts where shortcut.matches(key: app.key, modifiers: app.modifiers) {
            conflicts.append(.appMenu(app.name))
        }
        // One macOS conflict is enough; a named one beats an unnamed one.
        let macOS = (symbolicHotKeys() + standardShortcuts).filter { $0.matches(shortcut) }
        if let named = macOS.first(where: { $0.name != nil }) {
            conflicts.append(.macOS(name: named.name))
        } else if !macOS.isEmpty {
            conflicts.append(.macOS(name: nil))
        }
        return conflicts
    }
}
