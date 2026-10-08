import Foundation

extension WorkshopSetAsFlow.Environment {
    /// The app's: Download's steamcmd path, the Installed library, the Details panel's Set
    /// Wallpaper and the Screen Saver mode's recording service.
    @MainActor
    static func app(workshop: WorkshopViewModel, library: InstalledLibraryModel) -> Self {
        let steamCmd = workshop.steamCmd
        return Self(
            isInstalled: { id in
                DownloadedWallpaperIndex.shared.contains(id) && !steamCmd.dependencyIndex.contains(id)
            },
            installedWallpaper: { id in
                library.allWallpapers.first { SceneWallpaperViewModel.workshopId(of: $0) == id }
            },
            canDownload: { steamCmd.isLoggedIn && steamCmd.steamCmdPath != nil },
            download: { item, completion in
                steamCmd.downloadWorkshopItem(workshopId: item.id, title: item.title, previewURL: item.previewImageURL,
                                              creatorId: item.creatorId, subscriptions: item.subscriptions,
                                              fileSize: item.fileSize) { folder in
                    // steamcmd may call back off the main thread.
                    DispatchQueue.main.async { MainActor.assumeIsolated { completion(folder) } }
                }
            },
            wallpaper: { folder in InstalledLibrary.wallpaper(at: folder, hiding: []) },
            setWallpaper: { AppDelegate.shared.wallpaperViewModel.inspectAndApply($0) },
            isRecordingScreenSaver: { AppDelegate.shared.screenSaverRecordings.isRecording },
            setScreenSaver: { wallpaper, completion in
                AppDelegate.shared.screenSaverRecordings.setAsScreenSaver(wallpaper, completion: completion)
            })
    }
}
