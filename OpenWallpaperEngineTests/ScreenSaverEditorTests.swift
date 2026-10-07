import XCTest
@testable import OpenWallpaperEngine

/// The Scene Editor (Live)'s Screen Saver mode: its isolated session never reaches the desktop,
/// its layer and property choices are saved per wallpaper apart from the wallpaper's own and
/// reused, a recording is installed and set as the screen saver (which the plugin then keeps),
/// and the installed video is replaced at once or not at all.
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

    /// What the fake helper was asked to render.
    private final class Runs: @unchecked Sendable {
        private let lock = NSLock()
        private var _targets: [ScreenSaverPlugin.Target] = []
        var targets: [ScreenSaverPlugin.Target] { lock.withLock { _targets } }
        func add(_ target: ScreenSaverPlugin.Target) { lock.withLock { _targets.append(target) } }
    }

    /// A helper that writes `bytes` as the video, or fails.
    private static func runner(_ runs: Runs, bytes: String?) -> ScreenSaverPlugin.Runner {
        { _, target, output in
            runs.add(target)
            guard let bytes else { return .failed }
            do { try Data(bytes.utf8).write(to: output) } catch { return .failed }
            return .rendered
        }
    }

    private final class FakeInstaller: ScreenSaverVideoInstalling, @unchecked Sendable {
        private let lock = NSLock()
        private var _installed: [(file: String, size: SIMD2<Int>, bytes: String)] = []
        var installed: [(file: String, size: SIMD2<Int>, bytes: String)] { lock.withLock { _installed } }

        func install(_ recording: URL, as fileName: String, pixelSize: SIMD2<Int>) throws {
            let bytes = String(decoding: try Data(contentsOf: recording), as: UTF8.self)
            lock.withLock { _installed.append((fileName, pixelSize, bytes)) }
        }
    }

    @MainActor
    private func makePlugin(_ store: ScreenSaverSettingsStore, videos: ScreenSaverVideoStore, runs: Runs) -> ScreenSaverPlugin {
        ScreenSaverPlugin(pool: PreparationPool(maxWorkers: 1), store: videos,
                          installer: ScreenSaverInstaller(bundledSaver: nil, saversDirectory: directory.appending(path: "Savers"),
                                                          mayInstall: false),
                          runner: Self.runner(runs, bytes: nil), settingsStore: store)
    }

    @MainActor
    private func makeService(_ store: ScreenSaverSettingsStore, plugin: ScreenSaverPlugin, videos: ScreenSaverVideoStore,
                             runner: @escaping ScreenSaverPlugin.Runner) -> ScreenSaverRecordingService {
        let recorder = ScreenSaverRecorder(stagingDirectory: directory.appending(path: "Staging"), runner: runner, installer: videos)
        let environment = ScreenSaverRecordingService.Environment(
            screens: { [(pixels: SIMD2(3840, 2160), points: SIMD2(1920, 1080))] },
            isPluginEnabled: { true }, enablePlugin: {}, desktopWallpaper: { nil })
        return ScreenSaverRecordingService(plugin: plugin, environment: environment, store: store, recorder: recorder, videos: videos)
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
        let runs = Runs()
        let plugin = makePlugin(store, videos: videos, runs: runs)
        let service = makeService(store, plugin: plugin, videos: videos, runner: Self.runner(runs, bytes: nil))

        let session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: ScreenSaverEditorModel.purpose,
                                               seededFrom: [.shared], defaults: defaults)
        let model = ScreenSaverEditorModel(session: session, seededFrom: [.shared], recordings: service,
                                           schedule: ScreenSaverDailyScheduler(store: store, record: { false }),
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
        XCTAssertNil(store.selection, "nothing is the screen saver until a recording is made")
        XCTAssertTrue(runs.targets.isEmpty, "editing renders nothing")

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
        let runs = Runs()
        let plugin = makePlugin(store, videos: videos, runs: runs)
        let service = makeService(store, plugin: plugin, videos: videos, runner: Self.runner(runs, bytes: nil))
        let schedule = ScreenSaverDailyScheduler(store: store, record: { false })
        func open(_ wallpaper: WEWallpaper) -> ScreenSaverEditorModel {
            ScreenSaverEditorModel(session: IsolatedSceneEditSession(wallpaper: wallpaper, purpose: ScreenSaverEditorModel.purpose,
                                                                     seededFrom: [.shared], defaults: defaults),
                                   seededFrom: [.shared], recordings: service, schedule: schedule, store: store, defaults: defaults)
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

    // MARK: Recording

    /// Record and Set as Screen Saver: the helper records the session's values with the clock
    /// layers left to the user's choices, the video is installed under a new name, and the
    /// selection and the choices are saved; the plugin then renders nothing for the desktop.
    @MainActor
    func testRecordingIsInstalledAndSetAsTheScreenSaver() throws {
        let wallpaper = try wallpaper()
        let store = ScreenSaverSettingsStore(defaults: defaults)
        let videos = ScreenSaverVideoStore(directory: directory.appending(path: "Videos"))
        let pluginRuns = Runs()
        let plugin = makePlugin(store, videos: videos, runs: pluginRuns)
        let runs = Runs()
        let service = makeService(store, plugin: plugin, videos: videos, runner: Self.runner(runs, bytes: "loop-1"))
        let values = ["speed": "0.7", sceneObjectVisibilityKey(objectID: 2): "false"]

        let done = expectation(description: "recorded")
        service.record(wallpaper, values: values, background: false) { succeeded in
            XCTAssertTrue(succeeded)
            done.fulfill()
        }
        XCTAssertTrue(service.isRecording)
        wait(for: [done], timeout: 10)

        let target = try XCTUnwrap(runs.targets.first)
        XCTAssertTrue(target.isRecording)
        XCTAssertEqual(target.properties, values)
        XCTAssertEqual(target.pixelSize, SIMD2(1920, 1080), "Render Resolution Display records the points")
        let selection = try XCTUnwrap(store.selection)
        XCTAssertEqual(selection.fileName, target.fileName)
        XCTAssertTrue(selection.fileName.contains("-rec"))
        XCTAssertTrue(service.isSelected(wallpaper))
        XCTAssertEqual(store.values(for: WallpaperSettingsIdentity.resolve(wallpaper, defaults: defaults)), values)
        let manifest = try JSONDecoder().decode(ScreenSaverManifest.self, from: Data(contentsOf: videos.manifestURL))
        XCTAssertEqual(manifest.videos.map(\.file), [selection.fileName])
        XCTAssertEqual(service.recordedVideo(of: wallpaper), videos.url(fileName: selection.fileName))
        XCTAssertFalse(service.isRecording)

        // The plugin keeps the recording: showing a wallpaper renders nothing and keeps the manifest.
        plugin.update(enabled: true, wallpaper: wallpaper)
        XCTAssertTrue(plugin.statuses.isEmpty)
        let settled = expectation(description: "file queue")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertTrue(pluginRuns.targets.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(ScreenSaverManifest.self, from: Data(contentsOf: videos.manifestURL)), manifest)

        // Turning the plugin off removes the videos, and the recording stops being the screen saver.
        plugin.update(enabled: false, wallpaper: nil)
        XCTAssertNil(store.selection)
    }

    // MARK: Atomic replace

    /// A failed render installs nothing (the installed video stays); a finished one is installed once.
    func testFailedRecordingLeavesTheInstalledVideo() throws {
        let installer = FakeInstaller()
        let staging = directory.appending(path: "Staging")
        var target = ScreenSaverPlugin.Target(pixelSize: SIMD2(2560, 1440), pointSize: SIMD2(2560, 1440), fileName: "w-rec1.mov")
        target.isRecording = true
        let wallpaperFolder = directory.appending(path: "w", directoryHint: .isDirectory)

        let failing = ScreenSaverRecorder(stagingDirectory: staging, runner: Self.runner(Runs(), bytes: nil), installer: installer)
        XCTAssertFalse(failing.record(wallpaper: wallpaperFolder, target: target))
        XCTAssertTrue(installer.installed.isEmpty)

        let working = ScreenSaverRecorder(stagingDirectory: staging, runner: Self.runner(Runs(), bytes: "frames"), installer: installer)
        XCTAssertTrue(working.record(wallpaper: wallpaperFolder, target: target))
        XCTAssertEqual(installer.installed.count, 1)
        XCTAssertEqual(installer.installed.first?.file, "w-rec1.mov")
        XCTAssertEqual(installer.installed.first?.size, SIMD2(2560, 1440))
        XCTAssertEqual(installer.installed.first?.bytes, "frames")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appending(path: "w-rec1.mov").path(percentEncoded: false)),
                       "nothing is left in the staging folder")
    }

    /// The store's install: the new video is in place before the manifest switches to it, the old
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
        XCTAssertEqual(ScreenSaverVideoStore.recordedFileName("k_c-h-1920x1080-r2.mov", at: Date(timeIntervalSince1970: 42)),
                       "k_c-h-1920x1080-r2-rec42.mov")
    }
}
