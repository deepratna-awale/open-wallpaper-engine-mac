import XCTest
@testable import OpenWallpaperEngine

/// Scene Edit / Export's Screen Saver mode: its isolated session never reaches the desktop,
/// its layer and property choices are saved per wallpaper apart from the wallpaper's own and
/// reused, Set as Screen Saver picks the scene to be drawn live with them, an earlier recording
/// migrates to that pick, and an installed video is replaced at once or not at all.
final class ScreenSaverEditorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!

    private static func project(id: String) -> String {
        """
        {"file": "scene.json", "title": "Saver \(id)", "type": "scene", "workshopid": "\(id)",
         "general": {"properties": {
           "speed": {"type": "slider", "text": "Speed", "value": 0.25, "min": 0, "max": 1}
         }}}
        """
    }

    override func setUpWithError() throws {
        suite = "owe-screensaver-editor-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory) // scratch cleanup
    }

    private func wallpaper(id: String = "626262") throws -> WEWallpaper {
        let folder = directory.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let project = Self.project(id: id)
        try Data(project.utf8).write(to: folder.appending(path: "project.json"))
        try Data("{}".utf8).write(to: folder.appending(path: "scene.json"))
        return WEWallpaper(using: try decodeTolerant(WEProject.self, from: Data(project.utf8)), where: folder)
    }

    private func save(_ values: [String: String], _ scope: WallpaperPropertyScope, of wallpaper: WEWallpaper) {
        let identity = WallpaperSettingsIdentity.resolve(wallpaper, defaults: defaults)
        defaults.set(values, forKey: identity.key(.userProperties, scope: scope))
        defaults.set(true, forKey: identity.key(.explicitUserProperties, scope: scope))
    }

    private func stored(_ scope: WallpaperPropertyScope, of wallpaper: WEWallpaper) -> [String: String]? {
        let identity = WallpaperSettingsIdentity.resolve(wallpaper, defaults: defaults)
        return defaults.dictionary(forKey: identity.key(.userProperties, scope: scope)) as? [String: String]
    }

    @MainActor
    private func makePlugin(_ store: ScreenSaverSettingsStore, videos: ScreenSaverVideoStore) -> ScreenSaverPlugin {
        ScreenSaverPlugin(store: videos,
                          installer: ScreenSaverInstaller(bundledSaver: nil, saversDirectory: directory.appending(path: "Savers"),
                                                          mayInstall: false),
                          settingsStore: store)
    }

    @MainActor
    private func makeService(_ store: ScreenSaverSettingsStore, plugin: ScreenSaverPlugin,
                             videos: ScreenSaverVideoStore) -> ScreenSaverSelectionService {
        let environment = ScreenSaverSelectionService.Environment(isPluginEnabled: { true }, enablePlugin: {},
                                                                  desktopWallpaper: { nil })
        return ScreenSaverSelectionService(plugin: plugin, environment: environment, store: store, videos: videos)
    }

    // MARK: Isolation

    /// The mode's layer and property edits go to its own store and private instance: the
    /// wallpaper's stored and running values stay as they were, no display regroups, and nothing
    /// is set as the screen saver until a recording is made.
    @MainActor
    func testScreenSaverEditsLeaveTheDesktopUntouched() throws {
        let wallpaper = try wallpaper()
        let visibility = sceneObjectVisibilityKey(objectID: 3)
        let shared: [String: String] = ["speed": "0.25", visibility: "true"]
        save(shared, .shared, of: wallpaper)
        let sharedKey = WallpaperPropertyScope.shared.runtimeKey(directory: wallpaper.settingsDirectory)
        WallpaperServices.shared.setUserProperties(shared, wallpaper: sharedKey, replacing: true)
        let store = ScreenSaverSettingsStore(defaults: defaults)
        let videos = ScreenSaverVideoStore(directory: directory.appending(path: "Videos"))
        let plugin = makePlugin(store, videos: videos)
        let service = makeService(store, plugin: plugin, videos: videos)

        let session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: ScreenSaverEditorModel.purpose,
                                               seededFrom: [.shared], defaults: defaults)
        let model = ScreenSaverEditorModel(session: session, seededFrom: [.shared], selectionService: service,
                                           store: store, defaults: defaults)
        XCTAssertEqual(session.values, shared)
        XCTAssertEqual(session.scope, .isolated(ScreenSaverEditorModel.purpose))
        XCTAssertNotEqual(session.instanceKey, WallpaperInstanceKey(wallpaper))

        let regrouped = expectation(forNotification: .wallpaperPropertiesDidSave, object: nil)
        regrouped.isInverted = true
        session.setLayerVisible(false, objectID: 3)
        session.setValues(["speed": "0.9"])
        model.persist()
        wait(for: [regrouped], timeout: 0.3)

        XCTAssertEqual(stored(.shared, of: wallpaper), shared)
        XCTAssertEqual(WallpaperServices.shared.userProperties(wallpaper: sharedKey), shared)
        XCTAssertEqual(WallpaperServices.shared.userProperties(wallpaper: session.runtimeKey)[visibility], "false")
        XCTAssertNil(session.instances.instance(for: WallpaperInstanceKey(wallpaper)))
        XCTAssertNil(store.selection, "nothing is the screen saver until it is set")
        XCTAssertNil(store.livePick)

        model.close()
        session.end()
        XCTAssertNil(stored(session.scope, of: wallpaper))
        XCTAssertEqual(stored(.shared, of: wallpaper), shared)
        XCTAssertEqual(WallpaperServices.shared.userProperties(wallpaper: sharedKey), shared)
    }

    // MARK: Persistence

    /// The choices are the screen saver's own, per wallpaper: the next session of that wallpaper
    /// starts from them, another wallpaper doesn't see them, and the wallpaper's own values never change.
    @MainActor
    func testChoicesArePersistedPerWallpaperAndReused() throws {
        let first = try wallpaper(id: "111")
        let second = try wallpaper(id: "222")
        save(["speed": "0.25"], .shared, of: first)
        save(["speed": "0.5"], .shared, of: second)
        let store = ScreenSaverSettingsStore(defaults: defaults)
        let videos = ScreenSaverVideoStore(directory: directory.appending(path: "Videos"))
        let plugin = makePlugin(store, videos: videos)
        let service = makeService(store, plugin: plugin, videos: videos)
        func open(_ wallpaper: WEWallpaper) -> ScreenSaverEditorModel {
            ScreenSaverEditorModel(session: IsolatedSceneEditSession(wallpaper: wallpaper, purpose: ScreenSaverEditorModel.purpose,
                                                                     seededFrom: [.shared], defaults: defaults),
                                   seededFrom: [.shared], selectionService: service, store: store, defaults: defaults)
        }

        // Opening and closing without a change saves nothing: the screen saver follows the wallpaper.
        let untouched = open(first)
        untouched.close()
        untouched.session.end()
        XCTAssertNil(store.values(for: WallpaperSettingsIdentity.resolve(first, defaults: defaults)))

        let hidden = sceneObjectVisibilityKey(objectID: 7)
        let edited = open(first)
        edited.session.setValues(["speed": "0.8", hidden: "false"])
        edited.close()
        edited.session.end()
        let saved = try XCTUnwrap(store.values(for: WallpaperSettingsIdentity.resolve(first, defaults: defaults)))
        XCTAssertEqual(saved, ["speed": "0.8", hidden: "false"])
        XCTAssertEqual(stored(.shared, of: first), ["speed": "0.25"], "the wallpaper's own values are untouched")

        let reopened = open(first)
        XCTAssertEqual(reopened.session.values, saved)
        reopened.session.end()
        let other = open(second)
        XCTAssertEqual(other.session.values, ["speed": "0.5"])
        other.session.end()

        // A later change to the wallpaper doesn't change the screen saver's choices.
        save(["speed": "0.1"], .shared, of: first)
        let again = open(first)
        XCTAssertEqual(again.session.values, saved)
        again.session.end()
    }

    // MARK: Setting it

    /// Set as Screen Saver: the scene is picked, not recorded. The pick and the choices are saved,
    /// nothing renders, and the plugin lists no video, so the saver shows the pick's still and its
    /// live frames. Turning the plugin off keeps the pick (there is no video to remove).
    @MainActor
    func testSettingASceneAsTheScreenSaverPicksItLive() throws {
        let wallpaper = try wallpaper()
        let store = ScreenSaverSettingsStore(defaults: defaults)
        let videos = ScreenSaverVideoStore(directory: directory.appending(path: "Videos"))
        let plugin = makePlugin(store, videos: videos)
        plugin.update(enabled: true, wallpaper: nil)
        let service = makeService(store, plugin: plugin, videos: videos)
        let values = ["speed": "0.7", sceneObjectVisibilityKey(objectID: 2): "false"]

        var succeeded: Bool?
        service.set(wallpaper, values: values) { succeeded = $0 }
        XCTAssertEqual(succeeded, true, "at once: nothing is recorded")
        XCTAssertFalse(service.isSettingVideo)
        let pick = try XCTUnwrap(store.livePick)
        XCTAssertEqual(pick.wallpaperDirectory, wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false))
        XCTAssertNil(store.selection)
        XCTAssertTrue(service.isSelected(wallpaper))
        XCTAssertEqual(store.values(for: WallpaperSettingsIdentity.resolve(wallpaper, defaults: defaults)), values)
        XCTAssertFalse(plugin.followsDesktop)
        XCTAssertEqual(plugin.livePick?.wallpaperDirectory.standardizedFileURL, wallpaper.wallpaperDirectory.standardizedFileURL)

        let settled = expectation(description: "file queue")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(try JSONDecoder().decode(ScreenSaverManifest.self, from: Data(contentsOf: videos.manifestURL)).videos, [])

        plugin.update(enabled: false, wallpaper: nil)
        XCTAssertNotNil(store.livePick)
        service.stopUsingSelection()
        XCTAssertNil(store.livePick)
        XCTAssertFalse(service.isSelected(wallpaper))
    }

    /// The menus' and the Details panel's Set as Screen Saver: the wallpaper at once, with its
    /// default settings: what the Screen Saver tab saved for it is cleared.
    @MainActor
    func testMenuSetUsesTheDefaultSettings() throws {
        let wallpaper = try wallpaper()
        let store = ScreenSaverSettingsStore(defaults: defaults)
        let videos = ScreenSaverVideoStore(directory: directory.appending(path: "Videos"))
        let plugin = makePlugin(store, videos: videos)
        let service = makeService(store, plugin: plugin, videos: videos)
        let identity = WallpaperSettingsIdentity.resolve(wallpaper, defaults: defaults)
        save(["speed": "0.3"], .shared, of: wallpaper)
        store.setValues(["speed": "0.9", sceneObjectVisibilityKey(objectID: 4): "false"], for: identity)

        var succeeded: Bool?
        service.setAsScreenSaver(wallpaper) { succeeded = $0 }
        XCTAssertEqual(succeeded, true)
        XCTAssertTrue(service.isSelected(wallpaper))
        XCTAssertEqual(store.values(for: identity), [:], "no saved choices: every layer as authored, the property defaults")
        ScreenSaverPlugin.publishPickValues(for: wallpaper, store: store)
        XCTAssertEqual(stored(ScreenSaverPlugin.pickScope, of: wallpaper), [:], "not the desktop's values either")
        XCTAssertNil(service.chromiumOffer)
    }

    /// A web wallpaper is set from the menu once the Chromium engine is there; without it the
    /// install is offered and nothing is set.
    @MainActor
    func testMenuSetOfAWebWallpaperNeedsChromium() throws {
        let folder = directory.appending(path: "web", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let web = WEWallpaper(using: WEProject(file: "index.html", preview: "p.jpg", title: "Web", type: "web"), where: folder)
        let store = ScreenSaverSettingsStore(defaults: defaults)
        let videos = ScreenSaverVideoStore(directory: directory.appending(path: "Videos"))
        let service = makeService(store, plugin: makePlugin(store, videos: videos), videos: videos)
        var succeeded: Bool?
        service.setAsScreenSaver(web) { succeeded = $0 }
        if ChromiumEngineInstaller.hasActiveInstall {
            XCTAssertEqual(succeeded, true)
            XCTAssertTrue(service.isSelected(web), "drawn live through Chromium")
            XCTAssertNil(service.chromiumOffer)
        } else {
            XCTAssertEqual(succeeded, false)
            XCTAssertFalse(service.isSelected(web))
            XCTAssertEqual(service.chromiumOffer?.wallpaperDirectory, folder, "the install is offered instead")
        }
    }

    /// A video an earlier version linked from another volume (a symbolic link the saver can't
    /// follow) is set again at launch; one in place is left as it is.
    @MainActor
    func testALinkedSelectionIsSetAgain() throws {
        let wallpaper = try wallpaper()
        let store = ScreenSaverSettingsStore(defaults: defaults)
        let videos = ScreenSaverVideoStore(directory: directory.appending(path: "Videos"))
        let service = makeService(store, plugin: makePlugin(store, videos: videos), videos: videos)
        try FileManager.default.createDirectory(at: videos.directory, withIntermediateDirectories: true)
        let folder = wallpaper.wallpaperDirectory.standardizedFileURL.path(percentEncoded: false)
        store.selection = .init(wallpaperDirectory: folder, fileName: "copy.mp4", width: 1, height: 1, recorded: Date())
        try Data("movie".utf8).write(to: videos.url(fileName: "copy.mp4"))
        XCTAssertFalse(service.replaceLinkedSelection(wallpaper), "a file in the folder plays")

        let target = directory.appending(path: "elsewhere.mp4")
        try Data("movie".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: videos.url(fileName: "link.mp4"), withDestinationURL: target)
        store.selection = .init(wallpaperDirectory: folder, fileName: "link.mp4", width: 1, height: 1, recorded: Date())
        XCTAssertTrue(service.replaceLinkedSelection(wallpaper))
        store.selection = .init(wallpaperDirectory: "/another", fileName: "link.mp4", width: 1, height: 1, recorded: Date())
        XCTAssertFalse(service.replaceLinkedSelection(wallpaper), "only the selected wallpaper's")
    }

    /// What Set as Screen Saver takes: scenes, playable video files, web pages and WebM videos
    /// (these two through Chromium), never an application.
    func testAvailability() throws {
        func make(_ type: String, _ file: String) -> WEWallpaper {
            WEWallpaper(using: WEProject(file: file, preview: "p.jpg", title: "T", type: type), where: directory.appending(path: type))
        }
        typealias Service = ScreenSaverSelectionService
        for chromium in [false, true] {
            XCTAssertEqual(Service.availability(of: make("scene", "scene.json"), chromiumInstalled: chromium), .available)
            XCTAssertEqual(Service.availability(of: make("video", "a.mp4"), chromiumInstalled: chromium), .available)
            XCTAssertEqual(Service.availability(of: make("video", "a.mov"), chromiumInstalled: chromium), .available)
            XCTAssertEqual(Service.availability(of: make("web", "index.html"), chromiumInstalled: chromium),
                           chromium ? .available : .needsChromium)
            guard case .unavailable = Service.availability(of: make("application", "a.exe"), chromiumInstalled: chromium) else {
                return XCTFail("an application can't be the screen saver")
            }
            guard case .unavailable = Service.availability(of: make("video", "a.avi"), chromiumInstalled: chromium) else {
                return XCTFail("a container the saver can't play")
            }
        }
        let webm = make("video", "a.webm")
        if WebKitVideoPlayer.handles(webm.mediaURL) {
            XCTAssertEqual(Service.availability(of: webm, chromiumInstalled: false), .needsChromium)
            XCTAssertEqual(Service.availability(of: webm, chromiumInstalled: true), .available)
        }
        XCTAssertTrue(Service.canSet(make("web", "index.html")), "the menu offers it; without Chromium it offers the install")
        XCTAssertFalse(Service.canSet(make("application", "a.exe")))
    }

    /// A scene's recording set as the screen saver by an earlier version becomes the live pick of
    /// its wallpaper; a video's own file stays the selection.
    func testARecordedSelectionMigratesToTheLivePick() throws {
        let store = ScreenSaverSettingsStore(defaults: defaults)
        let recorded = Date(timeIntervalSince1970: 1_790_000_000)
        let selection = ScreenSaverSettingsStore.Selection(wallpaperDirectory: "/w/3810943704", fileName: "a-rec1.mov",
                                                           width: 3840, height: 2160, recorded: recorded)
        store.selection = selection
        XCTAssertFalse(store.migrateRecordedSelection(isVideo: { _ in true }))
        XCTAssertEqual(store.selection, selection, "a video's file stays")
        XCTAssertNil(store.livePick)

        XCTAssertTrue(store.migrateRecordedSelection(isVideo: { _ in false }))
        XCTAssertNil(store.selection)
        XCTAssertEqual(store.livePick, ScreenSaverSettingsStore.LivePick(wallpaperDirectory: "/w/3810943704", picked: recorded))
        XCTAssertFalse(store.migrateRecordedSelection(isVideo: { _ in false }), "once")
    }

    /// The pick is drawn with the screen saver's own values (properties and layer edits), put in
    /// its isolated store; the wallpaper's own stay as they are.
    @MainActor
    func testThePickIsDrawnWithTheScreenSaversOwnValues() throws {
        let wallpaper = try wallpaper()
        let store = ScreenSaverSettingsStore(defaults: defaults)
        save(["speed": "0.3"], .shared, of: wallpaper)
        ScreenSaverPlugin.publishPickValues(for: wallpaper, store: store)
        XCTAssertEqual(stored(ScreenSaverPlugin.pickScope, of: wallpaper), ["speed": "0.3"], "the wallpaper's own until the screen saver has its own")

        let own = ["speed": "0.9", sceneObjectVisibilityKey(objectID: 4): "false"]
        store.setValues(own, for: WallpaperSettingsIdentity.resolve(wallpaper, defaults: defaults))
        ScreenSaverPlugin.publishPickValues(for: wallpaper, store: store)
        XCTAssertEqual(stored(ScreenSaverPlugin.pickScope, of: wallpaper), own)
        XCTAssertEqual(stored(.shared, of: wallpaper), ["speed": "0.3"])
    }

    // MARK: Atomic replace

    /// The store's install (a video wallpaper's own file set as the screen saver): the new video is in place before the manifest switches to it, the old
    /// one goes only after, and an install that fails leaves the manifest and old video as they were.
    func testStoreInstallSwitchesTheVideoAtOnce() throws {
        let videos = ScreenSaverVideoStore(directory: directory.appending(path: "Videos"))
        let staged = directory.appending(path: "staged.mov")
        try Data("day-1".utf8).write(to: staged)
        try videos.install(staged, as: "a-rec1.mov", pixelSize: SIMD2(1920, 1080))
        try Data("day-2".utf8).write(to: staged)
        try videos.install(staged, as: "a-rec2.mov", pixelSize: SIMD2(1920, 1080))

        let manifest = try JSONDecoder().decode(ScreenSaverManifest.self, from: Data(contentsOf: videos.manifestURL))
        XCTAssertEqual(manifest.videos, [ScreenSaverManifest.Video(file: "a-rec2.mov", width: 1920, height: 1080)])
        XCTAssertEqual(try String(contentsOf: videos.url(fileName: "a-rec2.mov"), encoding: .utf8), "day-2")
        XCTAssertFalse(videos.exists(fileName: "a-rec1.mov"), "the previous video goes once the manifest moved on")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path(percentEncoded: false)))

        XCTAssertThrowsError(try videos.install(directory.appending(path: "missing.mov"), as: "a-rec3.mov", pixelSize: SIMD2(1920, 1080)))
        let unchanged = try JSONDecoder().decode(ScreenSaverManifest.self, from: Data(contentsOf: videos.manifestURL))
        XCTAssertEqual(unchanged, manifest)
        XCTAssertTrue(videos.exists(fileName: "a-rec2.mov"))
    }
}
