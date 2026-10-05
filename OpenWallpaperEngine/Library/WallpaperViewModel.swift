//
//  WallpaperViewModel.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/14.
//

import SwiftUI
import AVKit
import Combine

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Provide Wallpaper Database for WallpaperView and ContentView etc.
@MainActor
class WallpaperViewModel: ObservableObject {
    let persistsWallpapers: Bool

    @Published var nextCurrentWallpaper: WEWallpaper =
    WEWallpaper(using: .invalid, where: AppBundleLayout.wallpaperNotFoundURL) {
        willSet {
            guard confirmApply?(newValue) ?? true else { return }
            if Self.runsCode(newValue) {
                if !Self.needsTrust(newValue) {
                    self.setWallpaper(newValue, for: selectedScreenIds, transition: .manual)
                    // Points out a wallpaper that needs Chromium while it isn't installed.
                    ChromiumFeatureAdvisor.shared.wallpaperApplied(newValue)
                } else {
                    AppDelegate.shared.contentViewModel.warningUnsafeWallpaperModal(which: newValue)
                }
            } else {
                self.setWallpaper(newValue, for: selectedScreenIds, transition: .manual)
            }
        }
    }

    /// A web or application wallpaper, which runs its own code; whatever the case of the
    /// project's type, as the library reads it ("Web" is common).
    static func runsCode(_ wallpaper: WEWallpaper) -> Bool {
        ["web", "application"].contains(wallpaper.project.type.lowercased())
    }

    /// A wallpaper that runs code and that the user hasn't trusted yet: applying it asks first.
    static func needsTrust(_ wallpaper: WEWallpaper) -> Bool {
        guard runsCode(wallpaper) else { return false }
        let trusted = UserDefaults.app.array(forKey: "TrustedWallpapers") as? [String] ?? []
        return !trusted.contains(wallpaper.wallpaperDirectory.path(percentEncoded: false))
    }

    /// Per-screen wallpaper selections, keyed by CGDirectDisplayID as String: each display's own,
    /// kept while it clones another (WE keeps `selectedwallpapers` per monitor under a clone).
    /// What a display shows is `wallpaper(for:)`.
    @Published var wallpapers: [String: WEWallpaper] = [:] {
        didSet {
            if persistsWallpapers {
                saveWallpapers()
            }
            refreshInstanceKeys()
        }
    }

    /// How wallpapers spread over the displays: a wallpaper per display (with clone and stretch
    /// groups of some of them, and splits), or one stretched over or cloned onto every display
    /// (docs/architecture.md "Display layouts").
    @Published var displayLayout = DisplayLayoutConfiguration() {
        didSet {
            guard displayLayout != oldValue else { return }
            if persistsWallpapers { displayLayout.save(to: .app) }
            refreshDisplayLayout()
        }
    }

    /// The display layout on the displays connected now (`refreshDisplayLayout`).
    @Published internal(set) var layoutResolution = DisplayLayoutResolution.empty

    /// The screen saver's layout: the wallpapers' ("Same as wallpaper", the default) or its own.
    @Published var screenSaverLayout = ScreenSaverDisplayLayout() {
        didSet {
            guard screenSaverLayout != oldValue, persistsWallpapers else { return }
            screenSaverLayout.save(to: .app)
        }
    }

    /// The user's display profiles (WE's "Save Profile" / "Load Profile"), applied to these displays.
    lazy var displayProfiles = DisplayProfiles(model: self, fileURL: DisplayProfiles.defaultURL)

    /// The connected displays with their identities, main display first; tests pass their own.
    var connectedDisplays: @MainActor () -> [DisplayIdentity] = { DisplayIdentity.connected() }

    /// Screens where wallpaper display is enabled.
    @Published var enabledScreens: Set<String> = [] {
        didSet {
            UserDefaults.app.set(Array(enabledScreens), forKey: "EnabledScreens")
        }
    }

    /// The screen currently selected in the UI for configuration.
    @Published var selectedScreenId: String = ""

    /// Screens selected for the next wallpaper assignment.
    @Published var selectedScreenIds: Set<String> = []

    /// Wallpaper currently inspected in the sidebar or preview window.
    @Published var inspectedWallpaper: WEWallpaper?
    @Published var inspectedWorkshopItem: WorkshopItem?
    @Published var inspectedAuthor: SteamPlayer?
    /// Guards against firing a second Steam request for a lookup already in progress.
    private var inFlightWorkshopId: String?

    @Published var wallpaperPlacement: WallpaperPlacement = .fill {
        didSet {
            // A preview's placement (the Wallpaper Editor's canvas) isn't the user's setting.
            guard persistsWallpapers else { return }
            UserDefaults.app.set(wallpaperPlacement.rawValue, forKey: "WallpaperPlacement")
        }
    }

    static let defaultWallpaper = WEWallpaper(using: .invalid, where: AppBundleLayout.wallpaperNotFoundURL)

    // MARK: - Recent wallpapers

    private static let maxRecents = 10
    private static let recentsKey = "RecentWallpapers"

    @Published var recentWallpapers: [WEWallpaper] = []

    /// Each display's wallpapers, for Previous Wallpaper outside a playlist.
    @Published var wallpaperHistory = WallpaperHistory() {
        didSet { if persistsWallpapers { wallpaperHistory.save(to: .app) } }
    }

    @Published var playlists: [WallpaperPlaylist] = [] {
        didSet { savePlaylists() }
    }
    @Published var activePlaylistID: UUID? {
        didSet {
            // Each playlist continues where it left off when it becomes active again.
            if oldValue != activePlaylistID {
                if let oldValue { playlistPositions[oldValue] = playlistIndex }
                playlistIndex = activePlaylistID.flatMap { playlistPositions[$0] } ?? 0
            }
            savePlaylistSettings(); restartPlaylistTimer()
            if oldValue != activePlaylistID { applyPlaylistSchedule(force: true) }
        }
    }
    /// Where each playlist that isn't active stopped, for when it is chosen again.
    private var playlistPositions: [UUID: Int] = [:]
    /// The connected displays' ids; a playlist's shortcut starts it on those it last used.
    var connectedScreenIds: @MainActor () -> Set<String> = { Set(NSScreen.screens.map(WallpaperViewModel.screenId(for:))) }
    @Published var playlistShuffle = false {
        didSet { savePlaylistSettings() }
    }
    @Published var playlistRepeats = true {
        didSet { savePlaylistSettings() }
    }
    @Published var playlistEnabled = false {
        didSet {
            savePlaylistSettings(); restartPlaylistTimer()
            if playlistEnabled && !oldValue { applyPlaylistSchedule(force: true) }
        }
    }

    /// The timer's next change, or a scheduled playlist's next slot (`restartPlaylistTimer`).
    var playlistTimer: Timer?
    /// A timer playlist's time left, which stands still while the wallpaper is paused.
    var playlistCountdown: PlaylistCountdown?
    /// Looks at a scheduled playlist again after sleep and clock changes.
    var playlistClockObserver: PlaylistClockObserver?
    /// The item a scheduled playlist last showed for its slot: Next and Previous stay until the
    /// slot changes.
    var playlistScheduledIndex: Int?
    /// The clock and calendar a scheduled playlist reads (tests set their own).
    var playlistClock: () -> Date = { Date() }
    var playlistCalendar: () -> Calendar = { Calendar.autoupdatingCurrent }
    /// Plays transitions between wallpapers on the displays; nil (previews, tests): none.
    var transitions: WallpaperTransitionPerforming?

    /// Holds the playlist still after safe restart stopped a wallpaper; the setting is untouched.
    var isPlaylistSuspended = false {
        didSet { restartPlaylistTimer() }
    }
    /// Asked before a wallpaper is applied; returning false cancels it. Set by `SafeRestart`.
    var confirmApply: ((WEWallpaper) -> Bool)?
    /// Set by `SafeRestart`: whether a wallpaper is flagged, so auto-advance can pass it over.
    var isFlaggedBySafeRestart: ((WEWallpaper) -> Bool)?
    /// Moves a Workshop preview being applied into the storage folder and returns it there; nil
    /// when the wallpaper isn't a preview. Set by the app delegate.
    var keepWorkshopPreview: ((WEWallpaper) throws -> WEWallpaper?)?
    /// Receives wallpaper frame times. Set by `SafeRestart`.
    var renderWatchdog: RenderWatchdog?
    /// The settings and script services this model's scenes run with; nil: Open Wallpaper
    /// Engine's. Set by the Wallpaper Editor's process for its canvas.
    var sceneHost: SceneWallpaperHost?
    /// Lets the displays that show the same web wallpaper share one WebContent process.
    let webProcessGroup = WebProcessGroup()
    /// The scenes (and Metal videos) running on this model's displays, one per wallpaper however
    /// many displays show it (docs/architecture.md "Wallpaper instances").
    let sceneInstances = WallpaperInstanceRegistry<WallpaperInstanceKey, SceneWallpaperInstance>(teardown: { $0.shutdown() })
    /// The scenes' loading snapshots refreshed this launch (`SceneLoadingSnapshotCapture`).
    let loadingSnapshots = SceneLoadingSnapshotSession(store: .current)
    /// The AVKit videos running on this model's displays, one player per video.
    let videoInstances = WallpaperInstanceRegistry<WallpaperInstanceKey, VideoWallpaperViewModel>(teardown: { $0.stop() })
    /// The active playlist's current item.
    var playlistIndex = 0

    private func loadRecents() {
        guard let data = UserDefaults.app.data(forKey: Self.recentsKey),
              let saved = try? JSONDecoder().decode([WEWallpaper].self, from: data) else { return }
        recentWallpapers = saved.filter { $0.project != .invalid }
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recentWallpapers) {
            UserDefaults.app.set(data, forKey: Self.recentsKey)
        }
    }

    func addToRecents(_ wallpaper: WEWallpaper) {
        guard wallpaper.project != .invalid else { return }
        recentWallpapers.removeAll { $0.wallpaperDirectory == wallpaper.wallpaperDirectory }
        recentWallpapers.insert(wallpaper, at: 0)
        if recentWallpapers.count > Self.maxRecents {
            recentWallpapers = Array(recentWallpapers.prefix(Self.maxRecents))
        }
        saveRecents()
    }

    // MARK: - Wallpaper access

    /// Convenience: wallpaper for the currently selected screen in the UI.
    var currentWallpaper: WEWallpaper {
        get {
            wallpaper(for: selectedScreenId)
        }
        set {
            setWallpaper(newValue, for: selectedScreenIds)
        }
    }

    var displayedWallpaper: WEWallpaper {
        inspectedWallpaper ?? currentWallpaper
    }

    func inspect(_ wallpaper: WEWallpaper) {
        var wallpaper = wallpaper
        wallpaper.project.applyTaggedContentRating()
        // A tile tap inspects twice (once via selectWallpaper, once from the tile itself). Clearing
        // and refetching on the second call raced the first request, and Steam rejected the
        // duplicate, so the metadata stayed empty until a later visit read it from cache.
        let isSameWallpaper = inspectedWallpaper?.wallpaperDirectory == wallpaper.wallpaperDirectory
        inspectedWallpaper = wallpaper
        if !isSameWallpaper {
            inspectedWorkshopItem = nil
            inspectedAuthor = nil
        }

        let projectWorkshopId = wallpaper.project.workshopid?.rawValue
        let folderWorkshopId = wallpaper.wallpaperDirectory.lastPathComponent
        let workshopId = (projectWorkshopId?.allSatisfy(\.isNumber) == true ? projectWorkshopId : nil)
            ?? (folderWorkshopId.allSatisfy(\.isNumber) ? folderWorkshopId : nil)
        guard let workshopId else { return }
        guard inFlightWorkshopId != workshopId else { return }

        if let cachedItem = WorkshopMetadataStore.shared.item(for: workshopId) {
            inspectedWorkshopItem = cachedItem
            if let creatorId = cachedItem.creatorId,
               let cachedAuthor = SteamPlayerStore.shared.player(for: creatorId) {
                inspectedAuthor = cachedAuthor
                return
            }
        } else if isSameWallpaper, inspectedWorkshopItem != nil {
            return
        }
        inFlightWorkshopId = workshopId
        Task { [weak self] in
            defer { self?.inFlightWorkshopId = nil }
            let fetched = try? await WorkshopAPIService().getItemDetails(workshopIds: [workshopId]).first
            guard let self else { return }
            guard let item = fetched ?? WorkshopMetadataStore.shared.item(for: workshopId) else { return }
            guard self.displayedWallpaper.wallpaperDirectory.lastPathComponent == folderWorkshopId else { return }
            self.inspectedWorkshopItem = item
            if let creatorId = item.creatorId,
               let author = try? await WorkshopAPIService().getPlayerSummary(steamId: creatorId) {
                guard self.displayedWallpaper.wallpaperDirectory.lastPathComponent == folderWorkshopId else { return }
                self.inspectedAuthor = author
            }
        }
    }

    func applyInspectedWallpaper() {
        let wallpaper: WEWallpaper
        do {
            wallpaper = try keepWorkshopPreview?(displayedWallpaper) ?? displayedWallpaper
        } catch {
            // Applying it from the preview cache would lose it at the next cache trim.
            OWELog.error(.workshop, "Can't keep Workshop preview \(displayedWallpaper.wallpaperDirectory.lastPathComponent): \(error)")
            NSAlert(error: error).runModal()
            return
        }
        inspectedWallpaper = wallpaper
        nextCurrentWallpaper = wallpaper
    }

    func relocateWallpapers(from sourceDirectory: URL, to destinationDirectory: URL) {
        func relocated(_ wallpaper: WEWallpaper) -> WEWallpaper {
            let path = wallpaper.wallpaperDirectory.standardizedFileURL.path
            let sourcePath = sourceDirectory.standardizedFileURL.path + "/"
            guard path.hasPrefix(sourcePath) else { return wallpaper }
            let suffix = String(path.dropFirst(sourcePath.count))
            return WEWallpaper(using: wallpaper.project, where: destinationDirectory.appending(path: suffix))
        }

        wallpapers = wallpapers.mapValues(relocated)
        recentWallpapers = recentWallpapers.map(relocated)
        inspectedWallpaper = inspectedWallpaper.map(relocated)
        saveRecents()
    }

    /// The wallpaper `screenId` (a display or a split display's region) shows: its clone's or
    /// stretch's source display's while it is in one, else its own.
    func wallpaper(for screenId: String) -> WEWallpaper {
        wallpapers[layoutResolution.source(of: screenId)] ?? Self.defaultWallpaper
    }

    /// Each display's shown wallpaper (`wallpaper(for:)`), for the displays with a selection.
    var displayedWallpapers: [String: WEWallpaper] { layoutResolution.shown(wallpapers) }

    /// Set wallpaper for a specific screen.
    func setWallpaper(_ wallpaper: WEWallpaper, for screenId: String) {
        setWallpaper(wallpaper, for: [screenId])
    }

    /// Sets `wallpaper` on `screenIds`; for a display in a clone or stretch, on its source display,
    /// so every member shows it and the members' own selections stay for when they leave; for a
    /// split display, on each of its regions.
    ///
    /// `transition`: the transition shown on the displays that change, played by `transitions`
    /// (a playlist's own, or Settings' for wallpapers chosen by hand). The change applies at once
    /// without one; with one, as soon as the outgoing pictures are captured, and before any later
    /// change.
    func setWallpaper(_ wallpaper: WEWallpaper, for screenIds: Set<String>,
                      transition: WallpaperChangeTransition = .none) {
        transitions?.flushPending()
        let targets = layoutResolution.targets(of: screenIds)
        let apply: @MainActor () -> Void = { [weak self] in self?.assign(wallpaper, to: targets) }
        let changing = targets.filter { !self.wallpaper(for: $0).isSameWallpaper(as: wallpaper) }
        guard let transitions, !changing.isEmpty,
              let settings = transition.settings(manual: transitions.manualSettings),
              let kind = settings.pick() else {
            apply()
            return
        }
        transitions.perform(kind, duration: settings.duration, on: Set(changing), apply: apply)
    }

    private func assign(_ wallpaper: WEWallpaper, to targets: Set<String>) {
        for screenId in targets.sorted() {
            // The outgoing one too: it may have been restored at launch rather than set.
            wallpaperHistory.push(self.wallpaper(for: screenId), for: screenId)
            wallpaperHistory.push(wallpaper, for: screenId)
            wallpapers[screenId] = wallpaper
        }
        addToRecents(wallpaper)
    }

    var activePlaylist: WallpaperPlaylist? {
        playlists.first { $0.id == activePlaylistID }
    }

    func createPlaylist(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let playlist = WallpaperPlaylist(name: trimmed)
        playlists.append(playlist)
        activePlaylistID = playlist.id
    }

    @discardableResult
    func createPlaylist(named name: String, wallpapers: [WEWallpaper]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let playlist = WallpaperPlaylist(name: trimmed,
                                          items: wallpapers
                                            .filter { $0.project != .invalid }
                                            .map { WallpaperPlaylistItem(wallpaper: $0) })
        playlists.append(playlist)
        activePlaylistID = playlist.id
        return true
    }

    func addToPlaylist(_ wallpapers: [WEWallpaper], playlistID: UUID) {
        for wallpaper in wallpapers { addToPlaylist(wallpaper, playlistID: playlistID) }
    }

    func deletePlaylist(_ playlist: WallpaperPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        if activePlaylistID == playlist.id { activePlaylistID = playlists.first?.id }
    }

    func addToPlaylist(_ wallpaper: WEWallpaper, playlistID: UUID? = nil) {
        guard wallpaper.project != .invalid,
              let id = playlistID ?? activePlaylistID,
              let index = playlists.firstIndex(where: { $0.id == id }),
              !playlists[index].items.contains(where: { $0.wallpaper.wallpaperDirectory == wallpaper.wallpaperDirectory }) else { return }
        // WE's limit: a day-of-week playlist has a wallpaper per day at most.
        if playlists[index].timing == .dayofweek, playlists[index].items.count >= PlaylistTiming.maxDayOfWeekItems {
            OWELog.info(.app, "Playlist \"\(playlists[index].name)\" is a day-of-week playlist with 7 wallpapers; \"\(wallpaper.project.title)\" wasn't added")
            return
        }
        playlists[index].items.append(WallpaperPlaylistItem(wallpaper: wallpaper))
    }

    func removeFromPlaylist(itemID: UUID, playlistID: UUID? = nil) {
        guard let id = playlistID ?? activePlaylistID,
              let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].items.removeAll { $0.id == itemID }
    }

    func movePlaylistItem(itemID: UUID, offset: Int, playlistID: UUID? = nil) {
        guard let id = playlistID ?? activePlaylistID,
              let playlistIndex = playlists.firstIndex(where: { $0.id == id }),
              let itemIndex = playlists[playlistIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        let destination = itemIndex + offset
        guard playlists[playlistIndex].items.indices.contains(destination) else { return }
        playlists[playlistIndex].items.swapAt(itemIndex, destination)
    }

        func setPlaylistDuration(_ duration: TimeInterval, playlistID: UUID? = nil) {
          guard let id = playlistID ?? activePlaylistID,
              let index = playlists.firstIndex(where: { $0.id == id }) else { return }
          playlists[index].duration = max(duration, 1)
          restartPlaylistTimer()
        }

        func setPlaylistChangeWhenVideoEnds(_ enabled: Bool, playlistID: UUID? = nil) {
          guard let id = playlistID ?? activePlaylistID,
              let index = playlists.firstIndex(where: { $0.id == id }) else { return }
          playlists[index].changeWhenVideoEnds = enabled
          restartPlaylistTimer()
        }

        func advancePlaylistIfVideoEnds(_ wallpaper: WEWallpaper) {
          guard let playlist = activePlaylist, playlist.changeWhenVideoEnds, playlist.timing.usesTimerOptions,
              playlist.items.indices.contains(playlistIndex),
              playlist.items[playlistIndex].wallpaper.wallpaperDirectory == wallpaper.wallpaperDirectory else { return }
          advancePlaylistAutomatically()
        }

    func importVideoWallpaper(from url: URL) {
        let fileManager = FileManager.default
        let baseName = url.deletingPathExtension().lastPathComponent
        var destination = fileManager.wallpapersDirectory.appending(path: baseName)
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = fileManager.wallpapersDirectory.appending(path: "\(baseName) \(suffix)")
            suffix += 1
        }
        let fileName = url.lastPathComponent
        let project = WEProject(file: fileName, preview: "preview.jpg", title: baseName, type: "video")
        let generator = AVAssetImageGenerator(asset: AVAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0, preferredTimescale: 600))]) { [weak self] _, cgImage, _, _, _ in
            // AVFoundation can't decode every video it imports (WebM plays through WebKit), so a
            // missing first frame leaves the wallpaper without a preview instead of unimported.
            let previewData = cgImage.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .jpeg, properties: [:]) }
            if previewData == nil { OWELog.info(.importer, "No preview frame for \(fileName); importing it without one") }
            DispatchQueue.main.async {
                do {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                    try fileManager.copyItem(at: url, to: destination.appending(path: fileName))
                    if let previewData { try previewData.write(to: destination.appending(path: "preview.jpg"), options: .atomic) }
                    try JSONEncoder().encode(project).write(to: destination.appending(path: "project.json"), options: .atomic)
                    DispatchQueue.global(qos: .utility).async {
                        WallpaperPreparation.prepareVideo(wallpaperDirectory: destination)
                    }
                } catch {
                    OWELog.error(.importer, "Failed to import video: \(error.localizedDescription)")
                }
            }
        }
    }

    func addRemoteWallpaper(from url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let pathExtension = url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
        let videoExtensions = ["mp4", "mov", "m4v", "webm"]
        if imageExtensions.contains(pathExtension) {
            importImageAsScene(from: url)
            return
        }
        guard videoExtensions.contains(pathExtension) else { return }
        importRemoteVideo(from: url)
    }

    /// Remote videos used to live only in memory, so the library — which lists folders on disk —
    /// never showed a tile for them. They now get a real wallpaper folder whose project.json keeps
    /// the absolute URL as its file.
    private func importRemoteVideo(from url: URL) {
        let fileManager = FileManager.default
        let baseName = url.deletingPathExtension().lastPathComponent
        let title = baseName.isEmpty ? (url.host ?? String(localized: "Remote Video", comment: "Title of a video wallpaper added by URL")) : baseName
        var destination = fileManager.wallpapersDirectory.appending(path: title)
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = fileManager.wallpapersDirectory.appending(path: "\(title) \(suffix)")
            suffix += 1
        }
        let finalDestination = destination
        let project = WEProject(file: url.absoluteString, preview: "preview.jpg", title: title, type: "remote-video")
        do {
            try fileManager.createDirectory(at: finalDestination, withIntermediateDirectories: true)
            try JSONEncoder().encode(project)
                .write(to: finalDestination.appending(path: "project.json"), options: .atomic)
        } catch {
            OWELog.error(.importer, "Failed to add remote video: \(error.localizedDescription)")
            return
        }
        let wallpaper = WEWallpaper(using: project, where: finalDestination)
        setWallpaper(wallpaper, for: selectedScreenIds)
        inspect(wallpaper)

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0, preferredTimescale: 600))]) { _, cgImage, _, _, _ in
            guard let cgImage,
                  let previewData = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [:]) else { return }
            try? previewData.write(to: finalDestination.appending(path: "preview.jpg"), options: .atomic)
        }
    }

    /// Downloads the image and writes a minimal Wallpaper Engine scene around it, so it renders
    /// through the normal scene pipeline and the whole effect stack applies to it.
    private func importImageAsScene(from url: URL) {
        let fileManager = FileManager.default
        let baseName = url.deletingPathExtension().lastPathComponent
        let title = baseName.isEmpty ? (url.host ?? String(localized: "Image Wallpaper", comment: "Title of an image wallpaper added by URL")) : baseName
        var destination = fileManager.wallpapersDirectory.appending(path: title)
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = fileManager.wallpapersDirectory.appending(path: "\(title) \(suffix)")
            suffix += 1
        }
        let finalDestination = destination

        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data), image.size.width > 0 else {
                OWELog.error(.importer, "Could not download image at \(url.absoluteString)")
                return
            }
            // The scene texture loader looks for materials/<name>.<ext>, so the bytes are stored
            // under the name the generated material references.
            let textureExtension = ["png", "jpg", "jpeg", "gif"].contains(url.pathExtension.lowercased())
                ? url.pathExtension.lowercased()
                : "png"
            let textureData = textureExtension == "png"
                ? (NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) ?? data)
                : data
            let width = Int(image.size.width)
            let height = Int(image.size.height)

            let scene: [String: Any] = [
                "camera": [:],
                "general": [
                    "clearcolor": "0 0 0",
                    "orthogonalprojection": ["width": width, "height": height]
                ],
                "objects": [[
                    "id": 0,
                    "name": "Image",
                    "image": "models/image.json",
                    "origin": "\(width / 2) \(height / 2) 0",
                    "scale": "1 1 1",
                    "angles": "0 0 0",
                    "size": "\(width) \(height)",
                    "visible": true
                ]]
            ]
            let model: [String: Any] = ["material": "materials/image.json"]
            let material: [String: Any] = ["passes": [["textures": ["image"]]]]

            do {
                try fileManager.createDirectory(at: finalDestination.appending(path: "models"), withIntermediateDirectories: true)
                try fileManager.createDirectory(at: finalDestination.appending(path: "materials"), withIntermediateDirectories: true)
                try textureData.write(to: finalDestination.appending(path: "materials/image.\(textureExtension)"), options: .atomic)
                try JSONSerialization.data(withJSONObject: scene)
                    .write(to: finalDestination.appending(path: "scene.json"), options: .atomic)
                try JSONSerialization.data(withJSONObject: model)
                    .write(to: finalDestination.appending(path: "models/image.json"), options: .atomic)
                try JSONSerialization.data(withJSONObject: material)
                    .write(to: finalDestination.appending(path: "materials/image.json"), options: .atomic)
                if let preview = NSBitmapImageRep(data: data)?.representation(using: .jpeg, properties: [:]) {
                    try preview.write(to: finalDestination.appending(path: "preview.jpg"), options: .atomic)
                }
                let project = WEProject(file: "scene.json", preview: "preview.jpg", title: title, type: "scene")
                try JSONEncoder().encode(project)
                    .write(to: finalDestination.appending(path: "project.json"), options: .atomic)

                guard let self else { return }
                let wallpaper = WEWallpaper(using: project, where: finalDestination)
                self.setWallpaper(wallpaper, for: self.selectedScreenIds)
                self.inspect(wallpaper)
            } catch {
                OWELog.error(.importer, "Failed to build image scene: \(error.localizedDescription)")
            }
        }
    }

    func setContentRating(_ rating: String, for wallpaper: WEWallpaper) {
        guard wallpaper.project.workshopid == nil else { return }
        var updated = wallpaper
        updated.project.contentrating = rating
        guard WallpaperProjectFileEdit.setLogging(["contentrating": rating], inProjectAt: updated.wallpaperDirectory) else { return }
        for key in wallpapers.keys where wallpapers[key]?.wallpaperDirectory == updated.wallpaperDirectory {
            wallpapers[key] = updated
        }
        inspect(updated)
    }

    func nextPlaylistWallpaper() {
        advancePlaylist(skippingFlagged: false)
    }

    /// Timer and video-end advances. Nobody is there to confirm a wallpaper safe restart
    /// flagged, so those are passed over instead of asking.
    func advancePlaylistAutomatically() {
        advancePlaylist(skippingFlagged: true)
    }

    private func advancePlaylist(skippingFlagged: Bool) {
        guard let playlist = activePlaylist, !playlist.items.isEmpty else { return }
        syncPlaylistIndex(with: playlist)
        let isFlagged = isFlaggedBySafeRestart
        let isSkipped = { (index: Int) -> Bool in
            // "First wallpaper played at startup only": the rotation leaves it out.
            if index == 0 && playlist.leavesOutFirstItem { return true }
            let wallpaper = playlist.items[index].wallpaper
            guard skippingFlagged, isFlagged?(wallpaper) == true else { return false }
            OWELog.info(.app, "Playlist skips \"\(wallpaper.project.title)\": flagged by safe restart")
            return true
        }
        let shown = playlistShownWallpaper(of: playlist)
        // Never the wallpaper shown now (a playlist may list a folder twice) while another can play.
        let next = playlist.nextIndex(after: playlistIndex, shuffle: playlistShuffle, repeats: playlistRepeats) { index in
            shown.map { playlist.items[index].wallpaper.isSameWallpaper(as: $0) } == true || isSkipped(index)
        } ?? playlist.nextIndex(after: playlistIndex, shuffle: playlistShuffle, repeats: playlistRepeats,
                                isSkipped: isSkipped)
        guard let next else {
            if playlistRepeats {
                OWELog.info(.app, "Playlist \"\(playlist.name)\" has nothing left to show: every item is flagged by safe restart")
            } else {
                playlistEnabled = false
            }
            return
        }
        playlistIndex = next
        showPlaylistItem(of: playlist)
        restartPlaylistTimer()
    }

    func previousPlaylistWallpaper() {
        guard let playlist = activePlaylist, !playlist.items.isEmpty else { return }
        syncPlaylistIndex(with: playlist)
        let count = playlist.items.count
        let shown = playlistShownWallpaper(of: playlist)
        // As Next: passes over items that are the wallpaper shown now, while another exists.
        var index = playlistIndex
        for _ in 0..<count {
            index = (index - 1 + count) % count
            if index == 0 && playlist.leavesOutFirstItem { continue }
            if shown.map({ playlist.items[index].wallpaper.isSameWallpaper(as: $0) }) != true { break }
        }
        playlistIndex = index
        showPlaylistItem(of: playlist)
        restartPlaylistTimer()
    }

    /// Where Next and Previous step from: the selected display's wallpaper when that is one of
    /// the playlist's items, so one applied by hand (or shown on another display before) moves
    /// the position there instead of stepping from a stale one.
    private func syncPlaylistIndex(with playlist: WallpaperPlaylist) {
        guard let screenId = steppingScreenId else { return }
        let shown = wallpaper(for: screenId)
        if playlist.items[safe: playlistIndex]?.wallpaper.isSameWallpaper(as: shown) == true { return }
        if let index = playlist.items.firstIndex(where: { $0.wallpaper.isSameWallpaper(as: shown) }) {
            playlistIndex = index
        }
    }

    /// The wallpaper a step must move away from: the selected display's, else the current item.
    private func playlistShownWallpaper(of playlist: WallpaperPlaylist) -> WEWallpaper? {
        steppingScreenId.map { wallpaper(for: $0) } ?? playlist.items[safe: playlistIndex]?.wallpaper
    }

    /// Shows the playlist's current item on the selected displays (where it is not already
    /// shown) and remembers those displays as the playlist's.
    /// `transitions`: the playlist's own transition, except where nothing showed before (the app
    /// starting).
    func showPlaylistItem(of playlist: WallpaperPlaylist, transitions: Bool = true) {
        guard let item = playlist.items[safe: playlistIndex] else { return }
        let wallpaper = item.wallpaper
        let targets = selectedScreenIds.filter { !self.wallpaper(for: $0).isSameWallpaper(as: wallpaper) }
        if !targets.isEmpty {
            setWallpaper(wallpaper, for: targets, transition: transitions ? .playlist(playlist.transition) : .none)
        }
        let displays = selectedScreenIds.sorted()
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }), playlists[index].displays != displays {
            playlists[index].displays = displays
        }
    }

    /// A playlist's global shortcut: makes it the active playlist and starts it. Rotate
    /// automatically turns on and its wallpaper shows (the first, or where it left off) on the
    /// displays it last used that are connected, else on the selected ones.
    func startPlaylist(id: UUID) {
        guard let playlist = playlists.first(where: { $0.id == id }) else { return }
        activePlaylistID = id
        let connected = connectedScreenIds()
        let displays = Set(playlist.displays ?? []).intersection(connected)
        if !displays.isEmpty { selectedScreenIds = displays }
        if !playlist.items.isEmpty {
            // "Always begin with the first wallpaper" starts it at its first item.
            if !playlist.items.indices.contains(playlistIndex)
                || (playlist.timing.usesTimerOptions && playlist.beginsWithFirst) { playlistIndex = 0 }
            if let scheduled = playlist.scheduledIndex(at: playlistClock(), calendar: playlistCalendar()) {
                playlistIndex = scheduled
                playlistScheduledIndex = scheduled
            }
            showPlaylistItem(of: playlist)
        }
        playlistEnabled = true
    }

    private func savePlaylists() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.app.set(data, forKey: "WallpaperPlaylists")
    }

    private func savePlaylistSettings() {
        UserDefaults.app.set(activePlaylistID?.uuidString, forKey: "ActiveWallpaperPlaylist")
        UserDefaults.app.set(playlistShuffle, forKey: "WallpaperPlaylistShuffle")
        UserDefaults.app.set(playlistRepeats, forKey: "WallpaperPlaylistRepeats")
        UserDefaults.app.set(playlistEnabled, forKey: "WallpaperPlaylistEnabled")
    }

    func selectScreen(_ screenId: String, extendingSelection: Bool) {
        if extendingSelection {
            if selectedScreenIds.contains(screenId) {
                selectedScreenIds.remove(screenId)
            } else {
                selectedScreenIds.insert(screenId)
            }
        } else {
            selectedScreenIds = [screenId]
        }
        selectedScreenId = screenId
    }

    /// Whether wallpapers show on `screenId`, or on the display a region of a split is on.
    func isScreenEnabled(_ screenId: String) -> Bool {
        enabledScreens.contains(DisplayLayoutResolution.screen(of: screenId))
    }

    /// The enabled displays, a split one with its regions, as the playback and audio routing count
    /// them (each region is a display with its own view).
    var routedScreens: Set<String> {
        var screens = enabledScreens
        for (screen, regions) in layoutResolution.regions where enabledScreens.contains(screen) {
            screens.formUnion(regions.map(\.id))
        }
        return screens
    }

    /// The app's "Audio Output" setting; off silences every wallpaper. Set by the app delegate.
    @Published var audioOutputEnabled = true

    /// Whether a running wallpaper instance (scene, video) plays its sound: each plays it once,
    /// however many displays show it (`WallpaperAudioRouting`).
    var playsInstanceAudio: Bool { audioOutputEnabled }

    /// Whether the instance `key` plays its wallpaper's sound: a wallpaper plays once, so when its
    /// displays run it as several instances (different properties), only the instance on its
    /// audible display does (`WallpaperAudioRouting.audibleInstance`).
    func playsAudio(for key: WallpaperInstanceKey) -> Bool {
        guard audioOutputEnabled else { return false }
        guard persistsWallpapers else { return true }
        let audible = WallpaperAudioRouting.audibleInstance(
            of: key.wallpaper, instanceKeys: instanceKeys, enabledScreens: audibleCandidates(of: key),
            mainScreen: NSScreen.main.map(Self.screenId(for:)))
        return audible.map { $0 == key } ?? true
    }

    // MARK: - Playback rules per display

    /// Each display's playback under Settings › Performance › Playback (`PlaybackRules`), set by the
    /// app delegate's `DisplayPlaybackMonitor`.
    var rulePlayback: [String: DisplayPlayback] = [:] {
        didSet { refreshDisplayPlayback(); updatePlaylistPause() }
    }

    /// Each display's playback: the playback rules', and muted where the display is muted
    /// (`DisplayLayoutConfiguration.muted`). Empty in the Workshop preview: every display plays.
    @Published private(set) var displayPlayback: [String: DisplayPlayback] = [:]

    /// Merges the displays' mute into the playback rules' states; a split display's regions take
    /// its state.
    func refreshDisplayPlayback() {
        var states = rulePlayback
        for screen in layoutResolution.muted { states[screen] = max(states[screen] ?? .run, .mute) }
        for (screen, regions) in layoutResolution.regions {
            guard let state = states[screen] else { continue }
            for region in regions { states[region.id] = state }
        }
        guard states != displayPlayback else { return }
        displayPlayback = states
        let summary = states.keys.sorted().map { "\($0)=\(states[$0] ?? .run)" }.joined(separator: ", ")
        OWELog.debug(.app, "Display playback with mute: \(summary.isEmpty ? "all run" : summary)")
    }

    /// `screenId`'s own playback: whether its view draws new frames.
    func playback(onScreen screenId: String) -> DisplayPlayback {
        persistsWallpapers ? displayPlayback[screenId] ?? .run : .run
    }

    /// What the displays showing the instance `key` agree on: whether it renders
    /// (`DisplayPlaybackRouting.instance`).
    func playback(of key: WallpaperInstanceKey) -> DisplayPlayback {
        guard persistsWallpapers else { return .run }
        return DisplayPlaybackRouting.instance(key, instanceKeys: instanceKeys, enabledScreens: routedScreens,
                                               states: displayPlayback)
    }

    /// What the displays showing `key`'s wallpaper agree on, whatever their properties: whether its
    /// sound plays (`DisplayPlaybackRouting.wallpaper`).
    func wallpaperPlayback(of key: WallpaperInstanceKey) -> DisplayPlayback {
        guard persistsWallpapers else { return .run }
        return DisplayPlaybackRouting.wallpaper(key, instanceKeys: instanceKeys, enabledScreens: routedScreens,
                                                states: displayPlayback)
    }

    private func audibleCandidates(of key: WallpaperInstanceKey) -> Set<String> {
        DisplayPlaybackRouting.audibleCandidates(of: key, instanceKeys: instanceKeys, enabledScreens: routedScreens,
                                                 states: displayPlayback)
    }

    // MARK: - User properties per display

    /// "Sync properties across displays" (Settings → General); set by the app delegate.
    @Published var syncsPropertiesAcrossDisplays = GlobalSettings().syncPropertiesAcrossDisplays {
        didSet {
            guard oldValue != syncsPropertiesAcrossDisplays else { return }
            if syncsPropertiesAcrossDisplays, persistsWallpapers { shareDisplayedProperties() }
            refreshInstanceKeys()
        }
    }

    /// Syncing starts from what the displays ran: each wallpaper's shared store takes the
    /// properties of the display `WallpaperPropertyGroups.sharingDisplays` picks.
    private func shareDisplayedProperties() {
        let assignments = displayedWallpapers.mapValues { WallpaperInstanceKey($0) }
        for (key, screen) in WallpaperPropertyGroups.sharingDisplays(assignments: assignments, selected: selectedScreenId) {
            settingsIdentity(directory: key.directory)?.share(.display(screen))
        }
    }

    /// Each display's running instance: its wallpaper and the user properties it runs with
    /// (`WallpaperPropertyGroups`). Refreshed when a display's wallpaper, the sync setting or saved
    /// properties change; `WallpaperView` keys a display's view by it.
    @Published private(set) var instanceKeys: [String: WallpaperInstanceKey] = [:]
    private var settingsIdentities: [String: WallpaperSettingsIdentity] = [:]
    private var propertiesSavedObserver: NSObjectProtocol?

    /// The instance `screenId` shows.
    func instanceKey(for screenId: String) -> WallpaperInstanceKey {
        instanceKeys[screenId] ?? WallpaperInstanceKey(wallpaper(for: screenId))
    }

    /// Whose properties editing `screenId`'s wallpaper changes: the shared store while synced
    /// (and in the Workshop preview, which has no real display), else the display's own.
    /// A display in a clone or stretch edits and runs its source display's.
    func propertyScope(for screenId: String) -> WallpaperPropertyScope {
        syncsPropertiesAcrossDisplays || !persistsWallpapers ? .shared : .display(layoutResolution.source(of: screenId))
    }

    /// The scopes an edit of `wallpaper`'s properties in the sidebar or inspector goes to: the
    /// selected display's, then those of the other selected displays showing it. The first is shown.
    func editedPropertyScopes(of wallpaper: WEWallpaper) -> [WallpaperPropertyScope] {
        let others = selectedScreenIds.sorted().filter {
            $0 != selectedScreenId && self.wallpaper(for: $0).wallpaperDirectory == wallpaper.wallpaperDirectory
        }
        var scopes: [WallpaperPropertyScope] = []
        for screen in [selectedScreenId] + others where !screen.isEmpty {
            let scope = propertyScope(for: screen)
            if !scopes.contains(scope) { scopes.append(scope) }
        }
        return scopes.isEmpty ? [.shared] : scopes
    }

    /// Regroups the displays by their properties. Each display showing a wallpaper with properties
    /// unsynced gets its own store, started from the shared one (`WallpaperSettingsIdentity.seed`).
    func refreshInstanceKeys() {
        let synced = syncsPropertiesAcrossDisplays || !persistsWallpapers
        let assignments = displayedWallpapers.mapValues { WallpaperInstanceKey($0) }
        var keys = WallpaperPropertyGroups.instanceKeys(assignments: assignments, synced: synced) { [self] key, scope in
            guard let identity = settingsIdentity(directory: key.directory) else { return [:] }
            identity.seed(scope)
            return identity.stored(.userProperties, scope: scope) as? [String: String] ?? [:]
        }
        // A clone or a stretch runs once: its members show their source display's instance,
        // whatever their own properties (WE renders a clone or a span once).
        for (member, source) in layoutResolution.sources {
            if let key = keys[source] { keys[member] = key }
        }
        if keys != instanceKeys { instanceKeys = keys }
    }

    /// The settings identity of the wallpaper in `directory`, resolved once; nil for a folder
    /// without a project.json (the placeholder), which has no properties.
    private func settingsIdentity(directory: String) -> WallpaperSettingsIdentity? {
        if let identity = settingsIdentities[directory] { return identity }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.appending(path: "project.json").path) else { return nil }
        let identity = WallpaperSettingsIdentity.resolve(directory: url)
        settingsIdentities[directory] = identity
        return identity
    }

    /// Whether `screenId`'s view of its wallpaper plays the sound, for wallpapers that keep a view
    /// per display (web): only the one on the wallpaper's audible display does.
    func shouldPlayAudio(on screenId: String) -> Bool {
        guard audioOutputEnabled else { return false }
        guard persistsWallpapers else { return true }
        let key = WallpaperInstanceKey(wallpaper(for: screenId))
        let audible = WallpaperAudioRouting.audibleScreen(
            of: key, assignments: displayedWallpapers.mapValues { WallpaperInstanceKey($0) },
            enabledScreens: audibleCandidates(of: key), mainScreen: NSScreen.main.map(Self.screenId(for:)))
        return audible == screenId
    }

    /// Turns wallpapers on `screenId` (a display, or the display a region is on) on or off.
    func toggleScreen(_ id: String) {
        let screenId = DisplayLayoutResolution.screen(of: id)
        if enabledScreens.contains(screenId) {
            enabledScreens.remove(screenId)
        } else {
            enabledScreens.insert(screenId)
        }
        AppDelegate.shared.rebuildWallpaperWindows()
    }

    /// Remove a wallpaper from all screens (e.g., when unsubscribing).
    func removeWallpaperFromAllScreens(directory: URL) {
        for (key, wp) in wallpapers {
            if wp.wallpaperDirectory == directory {
                wallpapers[key] = Self.defaultWallpaper
            }
        }
    }

    // MARK: - Display options

    /// WE's per-wallpaper display options (offset, zoom, flip, playback rate), per display.
    let displayOptions: WallpaperDisplayOptionsStore
    /// Republishes the options' changes as this model's, so views showing wallpapers follow them.
    private var displayOptionsForwarding: AnyCancellable?

    /// The display options of the wallpaper on `screenId` there.
    func displayOptions(on screenId: String) -> WallpaperDisplayOptions {
        displayOptions.options(for: wallpaper(for: screenId), on: screenId)
    }

    /// Sets `wallpaper`'s display options on `screenIds`.
    func setDisplayOptions(_ options: WallpaperDisplayOptions, for wallpaper: WEWallpaper, on screenIds: Set<String>) {
        displayOptions.set(options, for: wallpaper, on: screenIds)
    }

    /// The playback rate (`WallpaperDisplayOptions.playbackRate`) a video running once for every
    /// display showing it plays at: its rate on the main display when that shows it, else on the
    /// display with the lowest id that does; 1 when no display shows it.
    func displayPlaybackRate(of wallpaper: WEWallpaper) -> Float {
        let directory = wallpaper.wallpaperDirectory.standardizedFileURL
        let screens = wallpapers.filter { $0.value.wallpaperDirectory.standardizedFileURL == directory }.keys
        let main = NSScreen.main.map(Self.screenId(for:))
        guard let screen = screens.first(where: { $0 == main }) ?? screens.sorted().first else { return 1 }
        return Float(displayOptions.options(for: wallpaper, on: screen).playbackRate)
    }

    var lastPlayRate: Float = 1.0
    @Published public var playRate: Float = 1.0 {
        willSet {
            guard persistsWallpapers else { return }
            // Matched by action: the titles are localized.
            if newValue == 0.0 {
                for (index, item) in AppDelegate.shared.statusItem.menu!.items.enumerated() {
                    if item.action == #selector(AppDelegate.shared.pause) {
                        AppDelegate.shared.statusItem.menu!.items[index] =
                            .init(title: String(localized: "Resume"), systemImage: "play.fill", action: #selector(AppDelegate.shared.resume), keyEquivalent: "")
                    }
                }
            } else {
                for (index, item) in AppDelegate.shared.statusItem.menu!.items.enumerated() {
                    if item.action == #selector(AppDelegate.shared.resume) {
                        AppDelegate.shared.statusItem.menu!.items[index] =
                            .init(title: String(localized: "Pause"), systemImage: "pause.fill", action: #selector(AppDelegate.shared.pause), keyEquivalent: "")
                    }
                }
            }
        }
        didSet {
            self.lastPlayRate = oldValue
            if arePlaybackRatesLinked {
                audioPlayRate = playRate
            }
            if (oldValue == 0) != (playRate == 0) { updatePlaylistPause() }
        }
    }

    @Published var audioPlayRate: Float = 1.0
    @Published var arePlaybackRatesLinked = true {
        didSet {
            if arePlaybackRatesLinked {
                audioPlayRate = playRate
            }
        }
    }

    var lastPlayVolume: Float = 1.0
    @Published public var playVolume: Float = 1.0 {
        willSet {
            guard persistsWallpapers else { return }
            if newValue == 0.0 {
                for (index, item) in AppDelegate.shared.statusItem.menu!.items.enumerated() {
                    if item.action == #selector(AppDelegate.shared.mute) {
                        AppDelegate.shared.statusItem.menu!.items[index] =
                            .init(title: String(localized: "Unmute"), systemImage: "speaker.fill", action: #selector(AppDelegate.shared.unmute), keyEquivalent: "")
                    }
                }
            } else {
                for (index, item) in AppDelegate.shared.statusItem.menu!.items.enumerated() {
                    if item.action == #selector(AppDelegate.shared.unmute) {
                        AppDelegate.shared.statusItem.menu!.items[index] =
                            .init(title: String(localized: "Mute"), systemImage: "speaker.slash.fill", action: #selector(AppDelegate.shared.mute), keyEquivalent: "")
                    }
                }
            }
        }
        didSet {
            self.lastPlayVolume = oldValue
        }
    }

    init(persistsWallpapers: Bool = true) {
        self.persistsWallpapers = persistsWallpapers
        // A preview's options aren't the user's: kept in memory only.
        displayOptions = WallpaperDisplayOptionsStore(defaults: persistsWallpapers ? .app : nil)
        displayOptionsForwarding = displayOptions.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        if let storedPlacement = UserDefaults.app.string(forKey: "WallpaperPlacement"),
           let placement = WallpaperPlacement(rawValue: storedPlacement) {
            wallpaperPlacement = placement
        }
        propertiesSavedObserver = NotificationCenter.default.addObserver(
            forName: .wallpaperPropertiesDidSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshInstanceKeys() }
        }
        guard persistsWallpapers else {
            self.selectedScreenId = "preview"
            self.selectedScreenIds = [selectedScreenId]
            refreshInstanceKeys()
            return
        }

        if let data = UserDefaults.app.data(forKey: "WallpaperPlaylists"),
           let saved = try? JSONDecoder().decode([WallpaperPlaylist].self, from: data) {
            self.playlists = saved
        }
        if let value = UserDefaults.app.string(forKey: "ActiveWallpaperPlaylist") {
            self.activePlaylistID = UUID(uuidString: value)
        }
        if self.activePlaylistID == nil {
            self.activePlaylistID = self.playlists.first?.id
        }
        self.playlistShuffle = UserDefaults.app.bool(forKey: "WallpaperPlaylistShuffle")
        self.playlistRepeats = UserDefaults.app.object(forKey: "WallpaperPlaylistRepeats") == nil
            ? true : UserDefaults.app.bool(forKey: "WallpaperPlaylistRepeats")
        self.playlistEnabled = UserDefaults.app.bool(forKey: "WallpaperPlaylistEnabled")

        // Load per-screen wallpapers. They stay as they are: without a saved display layout every
        // display shows its own.
        if let data = UserDefaults.app.data(forKey: "ScreenWallpapers"),
           let saved = try? JSONDecoder().decode([String: WEWallpaper].self, from: data) {
            // Filter out any compound keys (screenId_spaceId) from previous per-space experiment
            self.wallpapers = saved.filter { !$0.key.contains("_") }
        }
        // Migrate legacy single wallpaper
        else if let json = UserDefaults.app.data(forKey: "CurrentWallpaper"),
                let wallpaper = try? JSONDecoder().decode(WEWallpaper.self, from: json) {
            let mainId = Self.mainScreenId()
            self.wallpapers = [mainId: wallpaper]
        }

        // Load enabled screens (default: all connected screens enabled)
        if let saved = UserDefaults.app.array(forKey: "EnabledScreens") as? [String] {
            self.enabledScreens = Set(saved)
        } else {
            self.enabledScreens = Set(NSScreen.screens.map { Self.screenId(for: $0) })
        }

        // Default the active screen to main while assigning wallpapers to all desktops.
        self.selectedScreenId = Self.mainScreenId()
        self.selectedScreenIds = Set(NSScreen.screens.map { Self.screenId(for: $0) })

        displayLayout = DisplayLayoutConfiguration.load(from: .app)
        screenSaverLayout = ScreenSaverDisplayLayout.load(from: .app)
        refreshDisplayLayout()

        // Load recent wallpapers
        loadRecents()
        wallpaperHistory = WallpaperHistory.load(from: .app)
        restartPlaylistTimer()
        refreshInstanceKeys()
    }

    // MARK: - Screen ID helpers

    static func screenId(for screen: NSScreen) -> String {
        let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return String(displayId)
    }

    static func mainScreenId() -> String {
        guard let main = NSScreen.main else { return "0" }
        return screenId(for: main)
    }

    static func screenName(for screen: NSScreen) -> String {
        screen.localizedName
    }

    // MARK: - Persistence

    private func saveWallpapers() {
        if let data = try? JSONEncoder().encode(wallpapers) {
            UserDefaults.app.set(data, forKey: "ScreenWallpapers")
        }
        // Keep legacy key updated for backward compat
        if let data = try? JSONEncoder().encode(currentWallpaper) {
            UserDefaults.app.set(data, forKey: "CurrentWallpaper")
        }
    }
}
