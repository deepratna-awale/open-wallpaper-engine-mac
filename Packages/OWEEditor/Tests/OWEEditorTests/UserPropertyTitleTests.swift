import SwiftUI
import XCTest
import OWESceneEditing
@testable import OWEEditor

/// The editor names a user property by its label, as the property panels show it: the app's
/// title (a WE localisation key translated, HTML dropped), else an editor-added property's own
/// label, else its key.
final class UserPropertyTitleTests: XCTestCase {
    private func services(_ choices: [EditorUserPropertyChoice]) -> WallpaperEditorServices {
        var services = WallpaperEditorServices(makeCanvas: { AnyView(EmptyView()) }, blendModeTitle: "", blendModes: [],
                                               effectHelp: { _ in "" }, suggestedLocalTitle: "",
                                               saveAsLocalWallpaper: { $0 })
        services.userPropertyChoices = { choices }
        return services
    }

    func testAPropertyIsNamedByItsLabel() {
        let services = services([EditorUserPropertyChoice(key: "clocklocation", title: "Clock Location", type: "combo")])
        XCTAssertEqual(services.userPropertyTitle("clocklocation"), "Clock Location")
        let added = [UserPropertyDraft(key: "glow", kind: .bool, text: "<b>Glow</b>")]
        XCTAssertEqual(services.userPropertyTitle("glow", properties: added), "Glow", "one the editor added")
        XCTAssertEqual(services.userPropertyTitle("missing", properties: added), "missing", "no label: the key")
    }
}
