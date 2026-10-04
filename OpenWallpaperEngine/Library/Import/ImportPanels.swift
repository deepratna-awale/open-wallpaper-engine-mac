//
//  ImportPanels.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/4.
//

import Cocoa
import UniformTypeIdentifiers

struct WPImportError: LocalizedError {
    var errorDescription: String?
    var failureReason: String?
    var helpAnchor: String?
    var recoverySuggestion: String?
    
    static let permissionDenied         = WPImportError(errorDescription: String(localized: "Permission Denied"),
                                                failureReason: String(localized: "Open Wallpaper Engine doesn't have permission to access the selected folders."),
                                                helpAnchor: "File Permission",
                                                recoverySuggestion: String(localized: "Allow access in System Settings > Privacy & Security."))
    
    static let doesNotContainWallpaper  = WPImportError(errorDescription: String(localized: "No Wallpapers Inside"),
                                                       failureReason: String(localized: "The selected folders don't contain any wallpapers."),
                                                       helpAnchor: "Contents in Folder(s)",
                                                       recoverySuggestion: String(localized: "Check the selected folders and try again."))
    
    static let unkown                   = WPImportError(errorDescription: String(localized: "Unknown Error"),
                                                        failureReason: "",
                                                        helpAnchor: "",
                                                        recoverySuggestion: "")
}

extension AppDelegate {
    @objc func openImportFromFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.folder, .zip]
        panel.beginSheetModal(for: self.mainWindowController.window) { [weak self] response in
            if response != .OK { return }
            guard !panel.urls.isEmpty else { return }

            let fm = FileManager.default
            let docsDir = fm.wallpapersDirectory

            var wallpaperURLs: [URL] = []
            var zipURLs: [URL] = []

            for url in panel.urls {
                if url.pathExtension.lowercased() == "zip" {
                    zipURLs.append(url)
                } else if fm.fileExists(atPath: url.appending(path: "project.json").path) {
                    wallpaperURLs.append(url)
                } else {
                    // Scan immediate children for wallpaper folders
                    guard let children = try? fm.contentsOfDirectory(
                        at: url, includingPropertiesForKeys: [.isDirectoryKey],
                        options: .skipsHiddenFiles
                    ) else { continue }
                    for child in children {
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: child.path, isDirectory: &isDir),
                           isDir.boolValue,
                           fm.fileExists(atPath: child.appending(path: "project.json").path) {
                            wallpaperURLs.append(child)
                        }
                    }
                }
            }

            guard !wallpaperURLs.isEmpty || !zipURLs.isEmpty else {
                DispatchQueue.main.async {
                    self?.contentViewModel.alertImportModal(which: .doesNotContainWallpaper)
                }
                return
            }

            DispatchQueue.main.async {
                for url in wallpaperURLs {
                    let dest = docsDir.appending(path: url.lastPathComponent)
                    guard !fm.fileExists(atPath: dest.path) else { continue }
                    do {
                        try ImportedFolderLinks.copyWithoutLinks(from: url, to: dest)
                    } catch {
                        OWELog.error(.importer, "Can't import \(url.path): \(error)")
                        continue
                    }
                    DispatchQueue.global(qos: .utility).async {
                        WallpaperPreparation.prepare(wallpaperDirectory: dest)
                    }
                }
                for url in zipURLs {
                    ZipImporter.importZip(at: url)
                }
            }
        }
    }

    @objc func openImportVideoPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.beginSheetModal(for: self.mainWindowController.window) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.wallpaperViewModel.importVideoWallpaper(from: url)
            }
        }
    }
}
