import Combine
import Foundation

/// Scene Edit / Export's Screen Saver mode for a video wallpaper: the screen saver of a video
/// is the video itself, played as it is (`ScreenSaverVideoSource`), so there is nothing to record
/// or adjust; the mode sets it as the screen saver, or goes back to the desktop's wallpaper.
@MainActor
final class VideoScreenSaverModel: ObservableObject {
    let wallpaper: WEWallpaper
    let recordings: ScreenSaverRecordingService
    @Published var errorMessage: String?
    private var subscription: AnyCancellable?

    init(wallpaper: WEWallpaper, recordings: ScreenSaverRecordingService) {
        self.wallpaper = wallpaper
        self.recordings = recordings
        subscription = recordings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    var isScreenSaver: Bool { recordings.isSelected(wallpaper) }
    var isWorking: Bool { recordings.isRecording }

    func setAsScreenSaver() {
        errorMessage = nil
        recordings.useVideo(wallpaper) { [weak self] succeeded in
            guard !succeeded else { return }
            self?.errorMessage = String(localized: "The video couldn't be set as the screen saver. The logs say why.")
        }
    }

    func stopUsingAsScreenSaver() {
        recordings.stopUsingSelection()
    }
}
