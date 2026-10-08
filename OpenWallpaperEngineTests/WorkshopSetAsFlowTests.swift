import XCTest
@testable import OpenWallpaperEngine

/// The Discover and Workshop menus' Set as Wallpaper and Set as Screen Saver, with the download,
/// the library and the screen saver stubbed: nothing is downloaded or recorded.
@MainActor
final class WorkshopSetAsFlowTests: XCTestCase {
    private final class Stub {
        var installed: [String: WEWallpaper] = [:]
        var canDownload = true
        var isRecording = false
        var downloads: [String] = []
        var finishDownload: ((URL?) -> Void)?
        var folders: [URL: WEWallpaper] = [:]
        var applied: [WEWallpaper] = []
        var screenSavers: [WEWallpaper] = []
        var finishScreenSaver: ((Bool) -> Void)?

        var environment: WorkshopSetAsFlow.Environment {
            WorkshopSetAsFlow.Environment(
                isInstalled: { [unowned self] in installed[$0] != nil },
                installedWallpaper: { [unowned self] in installed[$0] },
                canDownload: { [unowned self] in canDownload },
                download: { [unowned self] item, completion in
                    downloads.append(item.id)
                    finishDownload = completion
                },
                wallpaper: { [unowned self] in folders[$0] },
                setWallpaper: { [unowned self] in applied.append($0) },
                isRecordingScreenSaver: { [unowned self] in isRecording },
                setScreenSaver: { [unowned self] wallpaper, completion in
                    screenSavers.append(wallpaper)
                    finishScreenSaver = completion
                })
        }
    }

    private let root = FileManager.default.temporaryDirectory.appending(path: "WorkshopSetAsFlowTests")

    private func wallpaper(_ id: String, type: String = "scene", file: String = "scene.json") -> WEWallpaper {
        WEWallpaper(using: WEProject(file: file, preview: "p.jpg", title: id, type: type), where: root.appending(path: id))
    }

    private func item(_ id: String, tags: [String] = ["Scene"]) -> WorkshopItem {
        WorkshopItem(id: id, title: id, previewURL: nil, tags: tags, subscriptions: 0, fileSize: 0,
                     creatorAppId: nil, creatorId: nil, description: nil, votesUp: 0, votesDown: 0)
    }

    func testAnInstalledItemIsSetWithoutADownload() {
        let stub = Stub()
        stub.installed["1"] = wallpaper("1")
        let flow = WorkshopSetAsFlow(environment: stub.environment)
        flow.run(.wallpaper, for: item("1"))
        XCTAssertEqual(stub.downloads, [])
        XCTAssertEqual(stub.applied.map(\.wallpaperDirectory), [root.appending(path: "1")])
        XCTAssertNil(flow.phases["1"])
    }

    func testSetAsWallpaperDownloadsThenApplies() {
        let stub = Stub()
        let flow = WorkshopSetAsFlow(environment: stub.environment)
        flow.run(.wallpaper, for: item("2"))
        XCTAssertEqual(stub.downloads, ["2"])
        XCTAssertEqual(flow.phases["2"], .downloading(.wallpaper))
        XCTAssertFalse(flow.canRun(.wallpaper, for: item("2")), "a running item can't start again")
        XCTAssertNil(flow.downloadState(for: "2"), "the download shows its own progress")
        XCTAssertTrue(stub.applied.isEmpty)

        let folder = root.appending(path: "2")
        stub.folders[folder] = wallpaper("2")
        stub.finishDownload?(folder)
        XCTAssertEqual(stub.applied.map(\.wallpaperDirectory), [folder])
        XCTAssertNil(flow.phases["2"])
    }

    func testAFailedDownloadSetsNothingAndLeavesItsErrorToTheDownload() {
        let stub = Stub()
        let flow = WorkshopSetAsFlow(environment: stub.environment)
        flow.run(.screenSaver, for: item("3"))
        stub.finishDownload?(nil)
        XCTAssertTrue(stub.applied.isEmpty)
        XCTAssertTrue(stub.screenSavers.isEmpty)
        XCTAssertNil(flow.phases["3"])
        XCTAssertTrue(flow.canRun(.screenSaver, for: item("3")), "it can be tried again")
    }

    func testSetAsScreenSaverRecordsTheDownloadedWallpaper() {
        let stub = Stub()
        let flow = WorkshopSetAsFlow(environment: stub.environment)
        flow.run(.screenSaver, for: item("4"))
        let folder = root.appending(path: "4")
        stub.folders[folder] = wallpaper("4")
        stub.finishDownload?(folder)
        XCTAssertEqual(stub.screenSavers.map(\.wallpaperDirectory), [folder])
        XCTAssertTrue(stub.applied.isEmpty, "the desktop's wallpaper doesn't change")
        XCTAssertEqual(flow.phases["4"], .recording)
        guard case .downloading? = flow.downloadState(for: "4") else { return XCTFail("the card shows the recording") }

        stub.finishScreenSaver?(true)
        XCTAssertNil(flow.phases["4"])
        XCTAssertNil(flow.downloadState(for: "4"))
    }

    func testAFailedRecordingShowsItsError() {
        let stub = Stub()
        stub.installed["5"] = wallpaper("5")
        let flow = WorkshopSetAsFlow(environment: stub.environment)
        flow.run(.screenSaver, for: item("5"))
        stub.finishScreenSaver?(false)
        guard case .failed? = flow.downloadState(for: "5") else { return XCTFail("the card shows the failure") }
        XCTAssertTrue(flow.canRun(.screenSaver, for: item("5")), "it can be tried again")
    }

    func testADownloadedItemTheScreenSaverCantPlayFails() {
        let stub = Stub()
        let flow = WorkshopSetAsFlow(environment: stub.environment)
        // A preset has no type tag; once downloaded it turns out to be a web page.
        flow.run(.screenSaver, for: item("6", tags: ["Preset"]))
        let folder = root.appending(path: "6")
        stub.folders[folder] = wallpaper("6", type: "web", file: "index.html")
        stub.finishDownload?(folder)
        XCTAssertTrue(stub.screenSavers.isEmpty)
        guard case .failed? = flow.phases["6"] else { return XCTFail("it says why") }
    }

    func testADownloadedApplicationIsNotApplied() {
        let stub = Stub()
        let flow = WorkshopSetAsFlow(environment: stub.environment)
        flow.run(.wallpaper, for: item("7", tags: ["Preset"]))
        let folder = root.appending(path: "7")
        stub.folders[folder] = wallpaper("7", type: "application", file: "a.exe")
        stub.finishDownload?(folder)
        XCTAssertTrue(stub.applied.isEmpty)
        guard case .failed? = flow.phases["7"] else { return XCTFail("it says why") }
    }

    func testMenuItemsAreDisabledWhenTheyCantApply() {
        let stub = Stub()
        let flow = WorkshopSetAsFlow(environment: stub.environment)
        XCTAssertFalse(flow.canRun(.wallpaper, for: item("8", tags: ["Application"])))
        XCTAssertFalse(flow.canRun(.screenSaver, for: item("8", tags: ["Application"])))
        XCTAssertTrue(flow.canRun(.wallpaper, for: item("8", tags: ["Web"])))
        XCTAssertFalse(flow.canRun(.screenSaver, for: item("8", tags: ["Web"])))

        stub.isRecording = true
        XCTAssertFalse(flow.canRun(.screenSaver, for: item("9")), "one recording at a time")
        XCTAssertTrue(flow.canRun(.wallpaper, for: item("9")))

        stub.isRecording = false
        stub.canDownload = false
        XCTAssertFalse(flow.canRun(.wallpaper, for: item("10")), "not installed and steamcmd can't download")
        stub.installed["10"] = wallpaper("10")
        XCTAssertTrue(flow.canRun(.wallpaper, for: item("10")))
        XCTAssertTrue(flow.canRun(.screenSaver, for: item("10")))

        flow.run(.wallpaper, for: item("11"))
        XCTAssertTrue(stub.downloads.isEmpty, "a disabled item does nothing")
    }
}
