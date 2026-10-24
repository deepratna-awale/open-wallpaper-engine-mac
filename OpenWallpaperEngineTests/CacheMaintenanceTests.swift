import XCTest
@testable import OpenWallpaperEngine

/// The cache expiry `CacheMaintenance.start()` schedules after launch runs on a utility queue.
final class CacheMaintenanceTests: XCTestCase {
    /// Main-actor work run off the main thread traps in Swift 6: beta.9 crashed two minutes after
    /// every launch when this work inherited `CacheMaintenance`'s main actor.
    @MainActor
    func testLaunchExpiryRunsOnAUtilityQueue() async {
        let ran = expectation(description: "the expiry ran")
        let work = CacheMaintenance.launchExpiryWork {
            XCTAssertFalse(Thread.isMainThread)
            ran.fulfill()
        }
        DispatchQueue.global(qos: .utility).async(execute: work)
        await fulfillment(of: [ran], timeout: 5)
    }
}
