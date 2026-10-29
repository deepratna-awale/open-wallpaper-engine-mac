import XCTest
@testable import OpenWallpaperEngine

/// A Workshop wallpaper's comments, read a page at a time through the Steam login.
@MainActor
final class WorkshopCommentsTests: XCTestCase {
    private static func comment(_ index: Int) -> WorkshopComment {
        WorkshopComment(id: "40000000000000\(index + 10000)", authorId: "7656119000000000\(index % 2)",
                        date: Date(timeIntervalSince1970: 1_750_000_000 + Double(index)), text: "Comment \(index)", upvotes: 0)
    }

    func testReadsTheThreadWithoutHiddenOrDeletedComments() throws {
        let data = Data(#"""
        {"response": {"total_count": 140, "start": 0, "comments": [
            {"gidcomment": "4000000000000000001", "steamid": "76561190000000001", "timestamp": 1750659489,
             "text": "[b]Lovely[/b]<br>so calm &amp; cosy", "upvotes": 2, "hidden": false, "deleted": false},
            {"gidcomment": "4000000000000000002", "steamid": "76561190000000002", "timestamp": 1750659490,
             "text": "spam", "hidden": true},
            {"gidcomment": "4000000000000000003", "steamid": "76561190000000003", "timestamp": 1750659491,
             "text": "gone", "deleted": true}
        ]}}
        """#.utf8)

        let page = try WorkshopComment.page(from: data)

        XCTAssertEqual(page.total, 140)
        XCTAssertEqual(page.comments, [WorkshopComment(id: "4000000000000000001", authorId: "76561190000000001",
                                                       date: Date(timeIntervalSince1970: 1750659489),
                                                       text: "Lovely\nso calm & cosy", upvotes: 2)])
    }

    func testPlainTextKeepsWhatIsntMarkup() {
        XCTAssertEqual(WorkshopComment.plainText("[url=https://example.com]link[/url] [quote=A]hi[/quote] :steamhappy: [1]"),
                       "link hi :steamhappy: [1]")
    }

    func testLoadsPagesFromTheCreatorsThreadAndTheirAuthorsNames() async {
        var requests: [(String, String, Int, Int)] = []
        let model = WorkshopCommentsModel(
            workshopId: "2370927443",
            creator: { _ in "76561198256757249" },
            loadPage: { id, creator, start, count in
                requests.append((id, creator, start, count))
                return WorkshopComment.Page(comments: (start..<min(start + count, 25)).map(Self.comment), total: 25)
            },
            name: { "Name \($0.suffix(1))" })

        await model.loadMore()
        XCTAssertEqual(model.comments.count, 20)
        XCTAssertTrue(model.hasMore)
        XCTAssertEqual(model.names, ["76561190000000000": "Name 0", "76561190000000001": "Name 1"])

        await model.loadMore()
        XCTAssertEqual(model.comments.count, 25)
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(requests.map(\.2), [0, 20])
        XCTAssertTrue(requests.allSatisfy { $0.0 == "2370927443" && $0.1 == "76561198256757249" && $0.3 == 20 })
    }

    func testAFailedFirstPageSaysWhy() async {
        let model = WorkshopCommentsModel(workshopId: "2370927443", creator: { _ in nil },
                                          loadPage: { _, _, _, _ in XCTFail("no creator, no request"); return .init(comments: [], total: 0) },
                                          name: { _ in nil })

        await model.loadMore()

        guard case .failed = model.phase else { return XCTFail("expected a failure, got \(model.phase)") }
    }
}
