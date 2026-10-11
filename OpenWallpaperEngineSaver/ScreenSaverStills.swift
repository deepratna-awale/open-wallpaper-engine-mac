import Foundation

/// Each display's still picture of its wallpaper, which a saver shows until live frames come (the
/// app is starting, a page is loading) or when they can't (the Chromium engine isn't installed):
/// the picture the lock screen shows (`LockScreenPicture`), linked by the app into the shared
/// folder (`ScreenSaverManifest.sharedFolder`), which both savers may read. Written by the app as
/// `stills.json`; Foundation only, shared by the app and the savers.
struct ScreenSaverStills: Codable, Equatable {
    static let revision = 1
    static let fileName = "stills.json"

    var revision = ScreenSaverStills.revision
    /// The picture's file name in the shared folder, by display identity.
    var stills: [String: String] = [:]

    /// The file for the display `display` (its identity; nil when unknown): its own, else any
    /// display's, so a display the app hasn't pictured yet shows the wallpaper rather than black.
    func file(forDisplay display: String?) -> String? {
        if let display, let file = stills[display] { return file }
        return stills.keys.sorted().first.flatMap { stills[$0] }
    }

    /// The stills in `url`; nil when it is missing, unreadable or of another revision.
    static func read(_ url: URL) -> ScreenSaverStills? {
        guard let data = try? Data(contentsOf: url), // Optional: no file means no stills yet.
              let stills = try? JSONDecoder().decode(ScreenSaverStills.self, from: data),
              stills.revision == revision else { return nil }
        return stills
    }

    /// The file name a display's still is linked as.
    static func fileName(display: String, fileExtension: String) -> String {
        let safe = display.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return "still-\(String(safe)).\(fileExtension)"
    }
}
