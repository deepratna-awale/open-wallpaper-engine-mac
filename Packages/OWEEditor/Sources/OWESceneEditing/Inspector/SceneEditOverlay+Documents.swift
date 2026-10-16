import Foundation

/// The JSON documents the scene's own layers read that the editor changed (an image layer's
/// material, for Lighting & Reflections), kept in the overlay (`SceneEditOverlay.documents`) by
/// their path in the wallpaper. The scene loader reads them, with the particle editor's, in place
/// of the wallpaper's files; a change of one reads the scene again; Save as New Wallpaper writes
/// them into the copy.
extension SceneEditOverlay {
    /// The edited document at `path`, nil when the editor didn't change it.
    public func document(_ path: String) -> SceneJSONValue? { documents?[path] }

    /// Sets the document at `path`; nil drops the edit (the wallpaper's file again).
    public mutating func setDocument(_ path: String, to value: SceneJSONValue?) {
        var edited = documents ?? [:]
        edited[path] = value
        documents = edited.isEmpty ? nil : edited
    }

    var hasDocumentEdits: Bool { !(documents ?? [:]).isEmpty }

    /// Every file the scene loader reads in place of the wallpaper's: the particle editor's
    /// documents and the effects' files (`editorFileData`) with these, as compact JSON.
    public func editorDocumentData() -> [String: Data] {
        var files = editorFileData()
        for (path, document) in documents ?? [:] {
            // Values read from JSON always write back as JSON.
            if let data = try? JSONSerialization.data(withJSONObject: document.any, options: [.fragmentsAllowed]) {
                files[path] = data
            }
        }
        return files
    }

    /// Every edited document as a file of a saved copy, written as WE writes its JSON.
    public func editorDocumentFiles() throws -> [String: Data] {
        var files = try editorFiles()
        for (path, document) in documents ?? [:] { files[path] = try ParticleDefinition.encode(document) }
        return files
    }
}
