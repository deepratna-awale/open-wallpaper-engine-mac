//
//  WEProject.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/6/5.
//

import SwiftUI
import ImageIO

struct WEProjectPropertyOption: Codable, Equatable, Hashable {
    var label: String
    var value: String
}

struct WEProjectProperty: Codable, Equatable, Hashable {
    // optional
    var condition: String?
    var index: Int?
    var options: [WEProjectPropertyOption]?
    var order: Int?
    
    // must have
    var text: String
    var type: String
    var value: String
}

struct WEProjectProperties: Codable, Equatable, Hashable {
    var schemecolor: WEProjectProperty?
}

struct WEProjectGeneral: Codable, Equatable, Hashable {
    var properties: WEProjectProperties
}

enum WorkshopId: Codable, Equatable, Hashable, RawRepresentable {
    case int(Int)
    case string(String)
    
    var rawValue: String {
        switch self {
        case .int(let x):
            return String(x)
        case .string(let x):
            return x
        }
    }
    
    init?(rawValue: String) {
        guard rawValue.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self = .string(rawValue)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            self = .int(x)
            return
        }
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        throw DecodingError.typeMismatch(Self.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Workshop ID"))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let x):
            try container.encode(x)
        case .string(let x):
            try container.encode(x)
        }
    }
}

struct WEProject: Codable, Equatable, Hashable {
    var approved: Bool?
    var contentrating: String?
    var description: String?
    var file: String
    var general: WEProjectGeneral?
    /// The preview image, relative to the wallpaper's folder. WE loads a project without one (the
    /// effect gallery's generated projects have none), so it's optional.
    var preview: String?
    var tags: [String]?
    var title: String
    var visibility: String?
    var workshopid: WorkshopId?
    var workshopurl: String?
    var type: String
    var version: Int?
    
    static let invalid = Self(file: "",
                              title: "Error",
                              type: "video")

    /// The preview image in `directory`; nil when the project names none.
    func previewURL(in directory: URL) -> URL? {
        guard let preview, !preview.isEmpty else { return nil }
        return directory.appending(path: preview)
    }
    
    var inferredContentRating: String? {
        let ratings = ["everyone", "questionable", "mature"]
        return tags?.first { tag in
            ratings.contains(tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).capitalized }
    }
    
    mutating func applyTaggedContentRating() {
        if let rating = inferredContentRating {
            contentrating = rating
        }
    }
}

extension WEProject {
    private enum DecodingKeys: String, CodingKey {
        case approved, contentrating, description, file, general, preview, tags, title, visibility
        case workshopid, workshopurl, type, version, category
    }

    /// Decodes as the synthesized decoder would, except that a project without `type` (WE's own
    /// default projects leave it out) takes the type its `file` implies, as WE does.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        let file = try container.decode(String.self, forKey: .file)
        self.init(approved: try container.decodeIfPresent(Bool.self, forKey: .approved),
                  contentrating: try container.decodeIfPresent(String.self, forKey: .contentrating),
                  description: try container.decodeIfPresent(String.self, forKey: .description),
                  file: file,
                  general: try container.decodeIfPresent(WEProjectGeneral.self, forKey: .general),
                  preview: try container.decodeIfPresent(String.self, forKey: .preview),
                  tags: try container.decodeIfPresent([String].self, forKey: .tags),
                  title: try container.decode(String.self, forKey: .title),
                  visibility: try container.decodeIfPresent(String.self, forKey: .visibility),
                  workshopid: try container.decodeIfPresent(WorkshopId.self, forKey: .workshopid),
                  workshopurl: try container.decodeIfPresent(String.self, forKey: .workshopurl),
                  type: try container.decodeIfPresent(String.self, forKey: .type)
                      ?? Self.impliedType(file: file,
                                          category: try container.decodeIfPresent(String.self, forKey: .category)),
                  version: try container.decodeIfPresent(Int.self, forKey: .version))
    }

    /// The wallpaper type a project's `file` implies when `type` is absent. A Workshop asset pack
    /// (`category` "Asset", `file` usually `assets.json`) has no wallpaper type, so it stays out of
    /// the library as it did when a missing `type` failed to decode.
    static func impliedType(file: String, category: String? = nil) -> String {
        if category?.caseInsensitiveCompare("Asset") == .orderedSame { return "" }
        switch (file as NSString).pathExtension.lowercased() {
        case "json": return "scene"
        case "html", "htm": return "web"
        case "exe": return "application"
        case "mp4", "webm", "mov", "m4v", "avi", "mkv", "wmv": return "video"
        default: return ""
        }
    }
}

/// project.json, read once per wallpaper and kept in memory: property edits, the web bridge, the
/// settings identity and the sidebar ask for it again and again, and none of that should touch
/// the disk. An entry is dropped when the file's modification date or size changes (a Workshop
/// update, an import, a converter write), so a stat is all a repeat costs.
final class WEProjectFileCache: @unchecked Sendable {
    static let shared = WEProjectFileCache()

    /// Entries kept; the oldest go first beyond this (a project.json is a few kilobytes).
    static let capacity = 512

    struct Entry {
        let data: Data
        /// The parsed JSON object; nil when the file isn't a JSON object.
        let root: [String: Any]?
        fileprivate let modified: Date?
        fileprivate let size: Int?
        fileprivate var lastUse: UInt64
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
    /// How many times a project.json was read from disk (for tests and diagnostics).
    private(set) var diskReads = 0

    /// The raw bytes of `directory`/project.json; throws when it can't be read.
    func data(in directory: URL) throws -> Data {
        try entry(in: directory).data
    }

    /// The parsed JSON object of `directory`/project.json; nil when it can't be read or parsed.
    func root(in directory: URL) -> [String: Any]? {
        (try? entry(in: directory))?.root
    }

    /// Forgets `directory` (after the app writes its project.json), or everything.
    func invalidate(_ directory: URL? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let directory { entries[Self.key(directory)] = nil } else { entries.removeAll() }
    }

    private static func key(_ directory: URL) -> String {
        directory.standardizedFileURL.appending(path: "project.json").path
    }

    private func entry(in directory: URL) throws -> Entry {
        let path = Self.key(directory)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? NSNumber)?.intValue
        lock.lock()
        clock &+= 1
        if var cached = entries[path], attributes != nil, cached.modified == modified, cached.size == size {
            cached.lastUse = clock
            entries[path] = cached
            lock.unlock()
            return cached
        }
        lock.unlock()

        let data = try Data(contentsOf: URL(filePath: path))
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        lock.lock(); defer { lock.unlock() }
        diskReads += 1
        let entry = Entry(data: data, root: root, modified: modified, size: size, lastUse: clock)
        entries[path] = entry
        if entries.count > Self.capacity,
           let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key {
            entries[oldest] = nil
        }
        return entry
    }
}
