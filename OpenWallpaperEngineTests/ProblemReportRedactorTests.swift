import XCTest
@testable import OpenWallpaperEngine

final class ProblemReportRedactorTests: XCTestCase {
    private let redactor = ProblemReportRedactor(homeDirectory: "/Users/jdoe",
                                                 names: ["jdoe", "Jane Doe", "Janes-MacBook-Pro", "Jane’s MacBook Pro", "jd"])

    func testHomeFolderBecomesTilde() {
        XCTAssertEqual(redactor.redact("Loading /Users/jdoe/Wallpapers/123/scene.json"), "Loading ~/Wallpapers/123/scene.json")
        XCTAssertEqual(redactor.redact("home is /Users/jdoe."), "home is ~.")
        XCTAssertEqual(redactor.redact("/Users/jdoe2/file"), "/Users/jdoe2/file", "another account's folder")
    }

    func testNamesGoWhereverTheyAreWords() {
        XCTAssertEqual(redactor.redact("Hello Jane Doe on Janes-MacBook-Pro.local"), "Hello <user> on <user>.local")
        XCTAssertEqual(redactor.redact("owner jdoe, computer Jane’s MacBook Pro"), "owner <user>, computer <user>")
        XCTAssertEqual(redactor.redact("JDOE logged in"), "<user> logged in")
        XCTAssertEqual(redactor.redact("jdoes and xjdoe"), "jdoes and xjdoe", "only whole words")
        XCTAssertEqual(redactor.redact("jd is too short to remove"), "jd is too short to remove")
    }

    func testEmailsAndCrashReportIdentifiersGo() {
        XCTAssertEqual(redactor.redact("signed in as someone@example.com"), "signed in as <email>")
        let report = #"{"crashReporterKey" : "ABCD-1234", "sleepWakeUUID":"F00", "pid" : 77}"#
        XCTAssertEqual(redactor.redact(report), #"{"crashReporterKey" : "<removed>", "sleepWakeUUID":"<removed>", "pid" : 77}"#)
    }

    func testWallpaperDetailsStay() {
        let text = "Applying “Forest Rain” (scene, folder 2345678901) from Workshop"
        XCTAssertEqual(redactor.redact(text), text)
    }
}
