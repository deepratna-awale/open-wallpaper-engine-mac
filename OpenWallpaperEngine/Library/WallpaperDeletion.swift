import Foundation

/// Deleting installed wallpapers' folders, or moving them to the Trash.
enum WallpaperDeletion {
    /// Wallpapers that couldn't be deleted, shown in the library's alert with the system's reasons.
    struct Failure: LocalizedError {
        let reasons: [String]

        var errorDescription: String? {
            String(localized: "Couldn't Delete Wallpaper", comment: "Alert title: deleting or trashing a wallpaper failed")
        }

        var failureReason: String? { reasons.joined(separator: "\n") }
    }

    /// Deletes each folder, or moves it to the Trash: file IO, so never on the main thread.
    /// Returns the folders that are gone, and the failure when any isn't.
    static func delete(_ directories: [URL], toTrash: Bool,
                       fileManager: FileManager = .default) -> (deleted: [URL], failure: Failure?) {
        ThreadGuards.assertBackground("wallpaper deletion")
        var deleted: [URL] = []
        var reasons: [String] = []
        for directory in directories {
            do {
                if toTrash {
                    try fileManager.trashItem(at: directory, resultingItemURL: nil)
                } else {
                    try fileManager.removeItem(at: directory)
                }
                deleted.append(directory)
            } catch {
                OWELog.error(.library, "Can't \(toTrash ? "trash" : "delete") the wallpaper at \(directory.path): \(error)")
                reasons.append(error.localizedDescription)
            }
        }
        return (deleted, reasons.isEmpty ? nil : Failure(reasons: reasons))
    }
}
