import Foundation

/// One of the Installed tab's folders, as Wallpaper Engine organises its Installed list
/// (`general.browser.folders` of WE's `config.json`, see `WallpaperEngineFolders`): a title, an
/// optional colour and icon, the wallpapers filed in it and its subfolders.
///
/// Wallpapers are filed by their `FavoritesStore.key(for:)` (`workshop-<id>` for a Workshop
/// item), as WE files them by Workshop id, so a wallpaper deleted and downloaded again is back
/// in its folder. A wallpaper is in at most one folder; one in none is at the top level.
struct InstalledFolder: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    /// nil is WE's Default colour.
    var color: InstalledFolderColor?
    /// nil is WE's plain folder icon.
    var icon: InstalledFolderIcon?
    /// The wallpapers' keys.
    var items: Set<String>
    var subfolders: [InstalledFolder]

    init(id: UUID = UUID(), title: String, color: InstalledFolderColor? = nil, icon: InstalledFolderIcon? = nil,
         items: Set<String> = [], subfolders: [InstalledFolder] = []) {
        self.id = id
        self.title = title
        self.color = color
        self.icon = icon
        self.items = items
        self.subfolders = subfolders
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, color, icon, items, subfolders
    }

    /// Decoded field by field: an unknown colour or icon (from a newer version) is the default,
    /// and one subfolder that doesn't decode doesn't drop its siblings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        // Optional by design: a value this version doesn't know shows the default.
        color = (try? container.decodeIfPresent(String.self, forKey: .color)).flatMap(InstalledFolderColor.init(rawValue:))
        icon = (try? container.decodeIfPresent(String.self, forKey: .icon)).flatMap(InstalledFolderIcon.init(rawValue:))
        items = Set(try container.decodeIfPresent([String].self, forKey: .items) ?? [])
        subfolders = try container.decodeIfPresent([Lossy<InstalledFolder>].self, forKey: .subfolders)?
            .compactMap(\.value) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(color?.rawValue, forKey: .color)
        try container.encodeIfPresent(icon?.rawValue, forKey: .icon)
        // Sorted, so the stored and exported JSON is stable.
        try container.encode(items.sorted(), forKey: .items)
        try container.encode(subfolders, forKey: .subfolders)
    }
}

/// The tree is stored and exported as its list of top-level folders, read folder by folder.
extension InstalledFolderTree: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        folders = try container.decode([Lossy<InstalledFolder>].self).compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(folders)
    }
}

/// One element of a list decoded on its own: nil, logged, when it doesn't decode.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        do {
            value = try Value(from: decoder)
        } catch {
            OWELog.error(.library, "Skipped an Installed folder that can't be read: \(error)")
            value = nil
        }
    }
}

/// Wallpaper Engine's folder colours (Change Color), stored by WE's own names (its
/// `folderColor` values) so its folders import as they are.
enum InstalledFolderColor: String, CaseIterable, Codable {
    case brightBlue = "browseFolderColorBrightBlue"
    case blue = "browseFolderColorBlue"
    case purple = "browseFolderColorPurple"
    case magenta = "browseFolderColorMagenta"
    case red = "browseFolderColorRed"
    case yellow = "browseFolderColorYellow"
    case brightYellow = "browseFolderColorBrightYellow"
    case green = "browseFolderColorGreen"
    case darkGreen = "browseFolderColorDarkGreen"

    /// WE's colour (its stylesheet's `.browseFolderColor…`), as sRGB 0–255.
    var rgb: (red: Int, green: Int, blue: Int) {
        switch self {
        case .brightBlue: return (0x00, 0xF5, 0xFF)
        case .blue: return (0x29, 0x73, 0xF3)
        case .purple: return (0x78, 0x0C, 0xFF)
        case .magenta: return (0xCC, 0x1A, 0x7A)
        case .red: return (0xCC, 0x1A, 0x00)
        case .yellow: return (0xCC, 0x7A, 0x00)
        case .brightYellow: return (0xEF, 0xDA, 0x00)
        case .green: return (0x7A, 0xCC, 0x00)
        case .darkGreen: return (0x2F, 0x67, 0x44)
        }
    }

    /// The colour's name as the menu shows it: WE's swatches have none, so they are named by
    /// what they look like (WE's "Yellow" is orange).
    var label: LocalizedStringResource {
        switch self {
        case .brightBlue: return LocalizedStringResource("Cyan", comment: "Folder colour (Installed tab › Change Colour)")
        case .blue: return LocalizedStringResource("Blue", comment: "Folder colour (Installed tab › Change Colour)")
        case .purple: return LocalizedStringResource("Purple", comment: "Folder colour (Installed tab › Change Colour)")
        case .magenta: return LocalizedStringResource("Magenta", comment: "Folder colour (Installed tab › Change Colour)")
        case .red: return LocalizedStringResource("Red", comment: "Folder colour (Installed tab › Change Colour)")
        case .yellow: return LocalizedStringResource("Orange", comment: "Folder colour (Installed tab › Change Colour)")
        case .brightYellow: return LocalizedStringResource("Yellow", comment: "Folder colour (Installed tab › Change Colour)")
        case .green: return LocalizedStringResource("Green", comment: "Folder colour (Installed tab › Change Colour)")
        case .darkGreen: return LocalizedStringResource("Dark Green", comment: "Folder colour (Installed tab › Change Colour)")
        }
    }

    /// The colour's id for the control channel (`folders_list`).
    var controlName: String {
        switch self {
        case .brightBlue: return "cyan"
        case .blue: return "blue"
        case .purple: return "purple"
        case .magenta: return "magenta"
        case .red: return "red"
        case .yellow: return "orange"
        case .brightYellow: return "yellow"
        case .green: return "green"
        case .darkGreen: return "dark_green"
        }
    }
}

/// Wallpaper Engine's folder icons (Change Icon), stored by WE's own Font Awesome class (its
/// `folderIcon` values), each shown as the closest SF Symbol.
enum InstalledFolderIcon: String, CaseIterable, Codable {
    case star = "fas fa-star"
    case heart = "fas fa-heart"
    case gem = "fas fa-gem"
    case car = "fas fa-car"
    case rocket = "fas fa-rocket"
    case snowflake = "fas fa-snowflake"
    case thumbsUp = "fas fa-thumbs-up"
    case gamepad = "fas fa-gamepad-modern"
    case gift = "fas fa-gift"
    case music = "fas fa-music"
    case trash = "fas fa-trash"
    case bug = "fas fa-bug"
    case magic = "fas fa-magic"
    case banana = "fas fa-banana"
    case alien = "fas fa-alien"
    case alien8bit = "fas fa-alien-8bit"
    case bat = "fas fa-bat"
    case bomb = "fas fa-bomb"
    case boombox = "fas fa-boombox"
    case candle = "fas fa-candle-holder"
    case dragon = "fas fa-dragon"
    case fire = "fas fa-fire"
    case meteor = "fas fa-meteor"
    case palmTree = "fas fa-tree-palm"
    case skull = "fas fa-skull-crossbones"
    case christmasTree = "fas fa-tree-christmas"
    case tv = "fas fa-tv-retro"
    case balloons = "fas fa-balloons"
    case bone = "fas fa-bone"

    /// The SF Symbol drawn for it.
    var systemImage: String {
        switch self {
        case .star: return "star.fill"
        case .heart: return "heart.fill"
        case .gem: return "diamond.fill"
        case .car: return "car.fill"
        case .rocket: return "airplane.departure"
        case .snowflake: return "snowflake"
        case .thumbsUp: return "hand.thumbsup.fill"
        case .gamepad: return "gamecontroller.fill"
        case .gift: return "gift.fill"
        case .music: return "music.note"
        case .trash: return "trash.fill"
        case .bug: return "ladybug.fill"
        case .magic: return "wand.and.stars"
        case .banana: return "carrot.fill"
        case .alien: return "eyes"
        case .alien8bit: return "square.grid.3x3.fill"
        case .bat: return "moon.stars.fill"
        case .bomb: return "burst.fill"
        case .boombox: return "hifispeaker.fill"
        case .candle: return "flame"
        case .dragon: return "lizard.fill"
        case .fire: return "flame.fill"
        case .meteor: return "sparkles"
        case .palmTree: return "beach.umbrella.fill"
        case .skull: return "xmark.octagon.fill"
        case .christmasTree: return "tree.fill"
        case .tv: return "tv.fill"
        case .balloons: return "balloon.2.fill"
        case .bone: return "pawprint.fill"
        }
    }

    /// WE's icon for a stored `folderIcon`: its own classes, and the outline snowflake its
    /// picker shows (`far fa-snowflake`) for the solid one it stores.
    init?(weClass: String) {
        let normalized = weClass.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "far fa-", with: "fas fa-")
        self.init(rawValue: normalized)
    }
}
