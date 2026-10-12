import Combine
import Foundation

/// Scene Edit / Export's Screen Saver mode for a video wallpaper: the screen saver of a video
/// is the video itself, played as it is (`ScreenSaverVideoSource`), so there is nothing to draw
/// or adjust; the mode sets it as the screen saver, or goes back to the desktop's wallpaper.
@MainActor
final class VideoScreenSaverModel: ObservableObject {
    let wallpaper: WEWallpaper
    let selectionService: ScreenSaverSelectionService
    @Published var errorMessage: String?
    private var subscription: AnyCancellable?

    init(wallpaper: WEWallpaper, selectionService: ScreenSaverSelectionService) {
        self.wallpaper = wallpaper
        self.selectionService = selectionService
        subscription = selectionService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    var isScreenSaver: Bool { selectionService.isSelected(wallpaper) }
    var isWorking: Bool { selectionService.isSettingVideo }

    func setAsScreenSaver() {
        errorMessage = nil
        selectionService.useVideo(wallpaper) { [weak self] succeeded in
            guard !succeeded else { return }
            self?.errorMessage = String(localized: "The video couldn't be set as the screen saver. The logs say why.")
        }
    }

    func stopUsingAsScreenSaver() {
        selectionService.stopUsingSelection()
    }
}
