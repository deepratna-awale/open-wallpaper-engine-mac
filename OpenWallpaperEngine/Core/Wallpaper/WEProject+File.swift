import Foundation

/// The one place that finds and reads a wallpaper folder's project.json. Each reader keeps the
/// tolerance it had: `read(in:)` and `object(in:)` are strict (as `JSONDecoder` and
/// `JSONSerialization` are), and a caller that accepts WE's looser JSON decodes `data(in:)` with
/// `decodeTolerant` itself.
extension WEProject {
    /// The project file's name inside a wallpaper folder.
    static let fileName = "project.json"

    /// project.json in `directory`.
    static func url(in directory: URL) -> URL {
        directory.appending(path: fileName)
    }

    /// Whether `directory` has a project.json.
    static func exists(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(in: directory).path)
    }

    /// project.json's bytes as written; throws when it can't be read.
    static func data(in directory: URL) throws -> Data {
        try Data(contentsOf: url(in: directory))
    }

    /// project.json decoded as a `WEProject`; throws when it can't be read or decoded.
    static func read(in directory: URL) throws -> WEProject {
        try JSONDecoder().decode(WEProject.self, from: data(in: directory))
    }

    /// project.json parsed by `JSONSerialization`, for callers that need fields `WEProject` doesn't
    /// model; throws when it can't be read or parsed.
    static func object(in directory: URL) throws -> Any {
        try JSONSerialization.jsonObject(with: data(in: directory))
    }

    /// project.json's root object; nil when the root isn't an object. Throws as `object(in:)`.
    static func json(in directory: URL) throws -> [String: Any]? {
        try object(in: directory) as? [String: Any]
    }
}
