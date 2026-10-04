import XCTest
@testable import OpenWallpaperEngine

/// The iPhone & iPad Export mode: the device table, the device combo box's search, the lock-screen
/// guide, the isolated session (edits there never reach the desktop) and the Export Settings
/// reaching the export's job.
final class LivePhotoExportTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!

    private static let project = """
    {"file": "scene.json", "title": "Export Me", "type": "scene", "workshopid": "515151",
     "general": {"properties": {
       "speed": {"type": "slider", "text": "Speed", "value": 0.25, "min": 0, "max": 1}
     }}}
    """

    override func setUpWithError() throws {
        suite = "owe-livephoto-export-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(Self.project.utf8).write(to: directory.appending(path: "project.json"))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory) // scratch cleanup
    }

    private func wallpaper() throws -> WEWallpaper {
        WEWallpaper(using: try decodeTolerant(WEProject.self, from: Data(Self.project.utf8)), where: directory)
    }

    private func save(_ values: [String: String], _ scope: WallpaperPropertyScope, of wallpaper: WEWallpaper) {
        let identity = WallpaperSettingsIdentity.resolve(wallpaper)
        defaults.set(values, forKey: identity.key(.userProperties, scope: scope))
        defaults.set(true, forKey: identity.key(.explicitUserProperties, scope: scope))
    }

    private func stored(_ scope: WallpaperPropertyScope, of wallpaper: WEWallpaper) -> [String: String]? {
        defaults.dictionary(forKey: WallpaperSettingsIdentity.resolve(wallpaper).key(.userProperties, scope: scope)) as? [String: String]
    }

    // MARK: Device table

    func testDeviceTableIsUniqueValidAndNewestFirst() {
        let all = DeviceModel.all
        XCTAssertEqual(Set(all.map(\.name)).count, all.count, "device names repeat")
        for device in all {
            XCTAssertGreaterThan(device.pixelSize.x, 0, device.name)
            XCTAssertGreaterThan(device.pixelSize.y, device.pixelSize.x, "\(device.name) isn't portrait")
            XCTAssertGreaterThanOrEqual(device.year, 2017, device.name)
            XCTAssertTrue(device.name.hasPrefix(device.family.name), device.name)
        }
        for index in all.indices.dropFirst() {
            XCTAssertGreaterThanOrEqual(all[index - 1].year, all[index].year, "\(all[index].name) is out of order")
        }
        let iPhones = all.filter { $0.family == .iPhone }
        let iPads = all.filter { $0.family == .iPad }
        XCTAssertGreaterThanOrEqual(iPhones.count, 30)
        XCTAssertGreaterThanOrEqual(iPads.count, 25)
        // iOS 17's oldest iPhones and iPadOS 17's oldest iPads are in.
        for name in ["iPhone XR", "iPhone XS", "iPhone SE (2nd generation)", "iPad (6th generation)",
                     "iPad Pro 10.5-inch", "iPad Pro 12.9-inch (2nd generation)", "iPad mini (5th generation)"] {
            XCTAssertEqual(DeviceModel.model(id: name).name, name)
        }
    }

    func testOnlyIPadsTurnToLandscape() throws {
        let iPad = DeviceModel.model(id: "iPad Pro 13-inch (M5)")
        let portrait: SIMD2<Int> = SIMD2(2064, 2752)
        let landscape: SIMD2<Int> = SIMD2(2752, 2064)
        XCTAssertEqual(iPad.pixelSize, portrait)
        XCTAssertEqual(try XCTUnwrap(iPad.landscapePixelSize), landscape)
        XCTAssertNil(DeviceModel.model(id: "iPhone 17 Pro Max").landscapePixelSize)
    }

    // MARK: Combo box search

    func testSearchMatchesNameFamilyYearAndResolution() {
        let all = DeviceModel.all
        XCTAssertEqual(DeviceModelSearch.filter(all, query: ""), all)
        XCTAssertEqual(DeviceModelSearch.filter(all, query: "   "), all)
        XCTAssertTrue(DeviceModelSearch.filter(all, query: "ipad").allSatisfy { $0.family == .iPad })
        XCTAssertTrue(DeviceModelSearch.filter(all, query: "2025").allSatisfy { $0.year == 2025 })
        let byResolution = DeviceModelSearch.filter(all, query: "1320x2868").map(\.name)
        XCTAssertEqual(byResolution, ["iPhone 17 Pro Max", "iPhone 16 Pro Max"])
        XCTAssertEqual(DeviceModelSearch.filter(all, query: "1320 × 2868").map(\.name), byResolution)
        XCTAssertEqual(DeviceModelSearch.filter(all, query: "2868x1320").map(\.name), byResolution)
        XCTAssertEqual(DeviceModelSearch.filter(all, query: "Pro Max 2024").map(\.name), ["iPhone 16 Pro Max"])
        XCTAssertEqual(DeviceModelSearch.filter(all, query: "mini A17").map(\.name), ["iPad mini (A17 Pro)"])
        XCTAssertTrue(DeviceModelSearch.filter(all, query: "nokia").isEmpty)
    }

    func testSearchResultsAreGroupedIPhoneFirstInTableOrder() {
        let matches = DeviceModelSearch.filter(DeviceModel.all, query: "air")
        let groups = DeviceModelSearch.groups(matches)
        XCTAssertEqual(groups.map(\.family), [.iPhone, .iPad])
        XCTAssertEqual(groups[0].models.map(\.name), ["iPhone Air"])
        XCTAssertEqual(groups[1].models, matches.filter { $0.family == .iPad })
        XCTAssertEqual(DeviceModelSearch.groups(DeviceModelSearch.filter(DeviceModel.all, query: "ipad")).map(\.family), [.iPad])
        XCTAssertTrue(DeviceModelSearch.groups([]).isEmpty)
    }

    // MARK: Lock-screen guide

    func testGuideFollowsTheDeviceAndOrientation() {
        let phone = LockScreenLayout.layout(for: .iPhone, landscape: false)
        let padPortrait = LockScreenLayout.layout(for: .iPad, landscape: false)
        let padLandscape = LockScreenLayout.layout(for: .iPad, landscape: true)
        XCTAssertEqual(phone.alignment, .center)
        XCTAssertEqual(padPortrait.alignment, .center)
        XCTAssertEqual(padLandscape.alignment, .leading)
        XCTAssertLessThan(padPortrait.clockSize, phone.clockSize)
        XCTAssertEqual(LockScreenLayout.layout(for: .iPhone, landscape: true), phone)
    }

    // MARK: Isolation

    /// Edits in the export mode go to its isolated store and private instance only: the shared
    /// store's saved values and the shared running values stay as they were, no display regroups,
    /// and ending the session leaves nothing behind.
    @MainActor
    func testExportEditsLeaveTheSharedInstanceAndStoredPropertiesUnchanged() throws {
        let wallpaper = try wallpaper()
        let visibility = sceneObjectVisibilityKey(objectID: 3)
        let shared: [String: String] = ["speed": "0.25", visibility: "true"]
        save(shared, .shared, of: wallpaper)
        let sharedKey = WallpaperPropertyScope.shared.runtimeKey(directory: wallpaper.settingsDirectory)
        WallpaperServices.shared.setUserProperties(shared, wallpaper: sharedKey, replacing: true)

        let session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: LivePhotoExportModel.purpose,
                                               seededFrom: [.shared], defaults: defaults)
        XCTAssertEqual(session.values, shared)
        XCTAssertNotEqual(session.instanceKey, WallpaperInstanceKey(wallpaper))
        XCTAssertNotEqual(session.runtimeKey, sharedKey)

        let regrouped = expectation(forNotification: .wallpaperPropertiesDidSave, object: nil)
        regrouped.isInverted = true
        // A layer hidden and a property changed in the mode, as its panel does, and through the
        // stores the editor's models write (`WallpaperPropertyTargets` on the session's scope).
        session.setLayerVisible(false, objectID: 3)
        session.setValues(["speed": "0.9"])
        let editor = WallpaperPropertyTargets(wallpaper: wallpaper, scopes: [session.scope])
        var edited = session.values
        edited["_owe_scene_object_3_scale"] = "2 2 1"
        editor.publish(edited)
        editor.save(edited, defaults: defaults)
        wait(for: [regrouped], timeout: 0.3)

        XCTAssertEqual(stored(.shared, of: wallpaper), shared)
        XCTAssertEqual(WallpaperServices.shared.userProperties(wallpaper: sharedKey), shared)
        let running = WallpaperServices.shared.userProperties(wallpaper: session.runtimeKey)
        XCTAssertEqual(running["speed"], "0.9")
        XCTAssertEqual(running[visibility], "false")
        XCTAssertEqual(session.layerEdits, [visibility: "false", "_owe_scene_object_3_scale": "2 2 1"])
        XCTAssertEqual(session.properties, ["speed": "0.9"])
        // The private instance runs in the session's own registry, never the displays'.
        XCTAssertNil(session.instances.instance(for: WallpaperInstanceKey(wallpaper)))

        // The export renders the isolated values.
        let model = LivePhotoExportModel(session: session, sceneSize: SIMD2(1920, 1080), defaults: defaults)
        XCTAssertEqual(model.exportProperties, session.values)

        session.end()
        XCTAssertNil(stored(session.scope, of: wallpaper))
        XCTAssertTrue(WallpaperServices.shared.userProperties(wallpaper: session.runtimeKey).isEmpty)
        XCTAssertEqual(stored(.shared, of: wallpaper), shared)
        XCTAssertEqual(WallpaperServices.shared.userProperties(wallpaper: sharedKey), shared)
        session.setValues(["speed": "0.1"])
        XCTAssertNil(stored(session.scope, of: wallpaper), "an ended session writes nothing")
    }

    /// The copy starts from the store the editor showed: a display's own when it has one.
    @MainActor
    func testSessionIsSeededFromTheEditedDisplaysStore() throws {
        let wallpaper = try wallpaper()
        save(["speed": "0.25"], .shared, of: wallpaper)
        save(["speed": "0.6"], .display("2"), of: wallpaper)
        let session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: "seed-test", seededFrom: [.display("2")],
                                               defaults: defaults)
        XCTAssertEqual(session.values, ["speed": "0.6"])
        session.end()
        XCTAssertEqual(stored(.display("2"), of: wallpaper), ["speed": "0.6"])
    }

    // MARK: Export Settings into the export

    @MainActor
    func testExportSettingsReachTheExportJob() throws {
        let wallpaper = try wallpaper()
        save(["speed": "0.25"], .shared, of: wallpaper)
        let session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: "settings-test", seededFrom: [.shared],
                                               defaults: defaults)
        defer { session.end() }
        session.setValues(["speed": "0.75", sceneObjectVisibilityKey(objectID: 9): "false"])
        let model = LivePhotoExportModel(session: session, sceneSize: SIMD2(1920, 1080), defaults: defaults)
        let iPad = DeviceModel.model(id: "iPad Air 13-inch (M3)")
        model.device = iPad
        model.zoom = 2
        model.clipLength = 2
        model.clipStart = 3
        model.quality = .smaller
        model.pan(by: SIMD2(40, -20))

        let settings = model.settings
        let files = LivePhotoHelper.Files(directory: directory, still: directory.appending(path: "a.HEIC"),
                                          movie: directory.appending(path: "a.MOV"), identifier: "id")
        let job = LivePhotoHelper.exportJob(wallpaper, properties: model.exportProperties, settings: settings, files: files)
        let decoded = try JSONDecoder().decode(LivePhotoJob.self, from: JSONEncoder().encode(job))
        let crop = try XCTUnwrap(decoded.crop)
        XCTAssertEqual(crop.outputPixels, iPad.pixelSize)
        XCTAssertEqual(crop, settings.crop)
        XCTAssertEqual(crop.zoom, 2)
        XCTAssertEqual(decoded.clip.length, 2, accuracy: 1e-9)
        XCTAssertEqual(decoded.clip.start, 3, accuracy: 1e-9)
        XCTAssertEqual(decoded.qualityLevel, .smaller)
        XCTAssertEqual(decoded.properties, session.values)
        XCTAssertEqual(decoded.properties["speed"], "0.75")
        XCTAssertEqual(decoded.still?.path(percentEncoded: false), files.still.path(percentEncoded: false))
        XCTAssertEqual(decoded.movie.path(percentEncoded: false), files.movie.path(percentEncoded: false))

        // The device chosen is the next model's too.
        XCTAssertEqual(LivePhotoExportModel(session: session, sceneSize: SIMD2(1920, 1080), defaults: defaults).device, iPad)
    }

    @MainActor
    func testExportIsConfirmedInTheSettingsSheet() throws {
        let session = IsolatedSceneEditSession(wallpaper: try wallpaper(), purpose: "sheet-test", seededFrom: [.shared],
                                               defaults: defaults)
        defer { session.end() }
        let model = LivePhotoExportModel(session: session, sceneSize: SIMD2(1920, 1080), defaults: defaults)
        model.requestExport(.save)
        XCTAssertEqual(model.sheet, .confirm(.save))
        model.sheet = nil
        model.showSettings()
        XCTAssertEqual(model.sheet, .settings)
    }
}
