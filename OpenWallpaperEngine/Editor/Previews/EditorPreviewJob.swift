import Foundation
import OWESceneEditing

/// The previews one helper run renders (`--render-editor-previews <job.json>`), in order. The
/// helper writes a line `done <index>` to standard output as each one is finished, written or not.
struct EditorPreviewJob: Codable, Equatable {
    struct Item: Codable, Equatable {
        var subject: EditorPreviewSubject
        /// The file to write, without its extension (`EditorPreviewCache.outputBase`).
        var outputBase: String
    }

    var items: [Item]

    static func doneLine(_ index: Int) -> String { "done \(index)\n" }

    /// The index a `done` line reports; nil for any other line.
    static func doneIndex(fromLine line: Substring) -> Int? {
        guard line.hasPrefix("done ") else { return nil }
        return Int(line.dropFirst("done ".count).trimmingCharacters(in: .whitespaces))
    }
}
