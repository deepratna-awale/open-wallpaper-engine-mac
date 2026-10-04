import SwiftUI
import ImageIO

struct WEWallpaper: Codable, RawRepresentable, Identifiable {
    
    var id: Int { self.project.hashValue }
    var rawValue: String {
        do {
            let rawValueData = try JSONEncoder().encode(self)
            return String(data: rawValueData, encoding: .utf8)!
        } catch {
            OWELog.error(.library, "Encoding wallpaper failed: \(error)")
            return ""
        }
    }
    
    var wallpaperDirectory: URL
    var project: WEProject
    /// For a Workshop preset item (`WorkshopPresetItem`), the item's own folder; `wallpaperDirectory`
    /// is then its base wallpaper's. Nil for every other wallpaper.
    var presetDirectory: URL?

    var isWorkshopPreset: Bool { presetDirectory != nil }

    /// Where the wallpaper's own project.json lives: its stored settings, its running property
    /// store (`WallpaperPropertyScope.runtimeKey`) and its preview are keyed by it.
    var settingsDirectory: URL { presetDirectory ?? wallpaperDirectory }

    /// The preview image; a preset item shows its own.
    var previewURL: URL? { project.previewURL(in: settingsDirectory) }

    /// A remote wallpaper stores an absolute URL in `project.file`; everything else stores a path
    /// relative to its folder.
    var mediaURL: URL {
        if let remote = URL(string: project.file), let scheme = remote.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return remote
        }
        return wallpaperDirectory.appending(path: project.file)
    }

    var isRemoteMedia: Bool {
        guard let scheme = URL(string: project.file)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
    
    var wallpaperSize: Int {
        guard let sizeBytes = try? self.wallpaperDirectory.directoryTotalAllocatedSize(includingSubfolders: true)
        else { return 0 }
        return sizeBytes
    }
    
    init(using project: WEProject, where url: URL) {
        self.wallpaperDirectory = url
        self.project = project
    }
    
    enum CodingKeys: CodingKey {
        case wallpaperDirectory
        case project
        case presetDirectory
        // <all the other elements too>
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wallpaperDirectory = try container.decode(URL.self, forKey: .wallpaperDirectory)
        self.project = try container.decode(WEProject.self, forKey: .project)
        self.presetDirectory = try container.decodeIfPresent(URL.self, forKey: .presetDirectory)
        // <and so on>
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wallpaperDirectory, forKey: .wallpaperDirectory)
        try container.encode(project, forKey: .project)
        try container.encodeIfPresent(presetDirectory, forKey: .presetDirectory)
        // <and so on>
    }
    
    init?(rawValue: String) {
        if let rawValueData = rawValue.data(using: .utf8),
           let wallpaper = try? JSONDecoder().decode(WEWallpaper.self, from: rawValueData) {
            self = wallpaper
        } else {
            return nil
        }
    }

    var isMobileCompatible: Bool {
        (project.tags ?? []).contains { $0.localizedCaseInsensitiveContains("mobile") }
    }

    var isAudioResponsive: Bool {
        (project.tags ?? []).contains { $0.localizedCaseInsensitiveContains("audio") }
    }

    var hasCustomizableProperties: Bool {
        projectHasCustomizableProperties(at: wallpaperDirectory)
    }
}

enum WEWallpaperSortingMethod: String, CaseIterable, Identifiable {
    
    var id: Self { self }
    
    case name = "Name"
    case rating = "Rating"
    case fileSize = "File Size"
    case dateAdded = "Date Added"

    var displayName: LocalizedStringResource {
        switch self {
        case .name: return LocalizedStringResource("Name", comment: "Sort wallpapers by name")
        case .rating: return LocalizedStringResource("Rating", comment: "Sort wallpapers by age rating")
        case .fileSize: return LocalizedStringResource("File Size", comment: "Sort wallpapers by size on disk")
        case .dateAdded: return LocalizedStringResource("Date Downloaded", comment: "Sort wallpapers by when they were added")
        }
    }
}

enum WEWallpaperSortingSequence: Int {
    case decrease = 0, increase = 1
}
