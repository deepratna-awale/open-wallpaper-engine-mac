import XCTest
import simd
@testable import OpenWallpaperEngine

/// The two captured puppets (the Knight 2515150033 and the Cyberpunk Samurai 2321732083) against
/// WE's 5-second puppet clips' stills (tools/peer README, batch 3: `<id>/puppet5s`), drawn by
/// `WEReferenceRenderer` at the stills' times. It reports, it doesn't judge: the metrics go to the
/// log and `OWE_WE_REFERENCE_OUT/puppets` (WE | ours | difference pictures). Both rigs' bind pose
/// is their sheet laid out flat; WE shows them assembled by their `idle` clip's pose, which
/// skinning (docs/models-plan.md M6, P2) draws. Runs only with `OWE_WE_REFERENCE` and the library.
final class ScenePuppetReferenceTests: XCTestCase {
    func testPuppetsAgainstWEsPuppetClips() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let root = environment["OWE_WE_REFERENCE"], !root.isEmpty else {
            throw XCTSkip("set OWE_WE_REFERENCE to the captures' tools/peer folder")
        }
        let captures = URL(fileURLWithPath: root, isDirectory: true)
        let library = LibrarySweepTests.libraryRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: library.path), "wallpaper library not present")
        let output = (environment["OWE_WE_REFERENCE_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appending(path: "owe-we-reference-out")).appending(path: "puppets")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let storage = FileManager.default.temporaryDirectory.appending(path: "owe-puppet-reference-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: storage) } // scratch cleanup
        let config = try WEReferenceConfig.load()
        var report = "item\tstill\tmean abs Δ\tSSIM\n"
        var compared = 0
        for id in ["2515150033", "2321732083"] {
            let directory = library.appending(path: id, directoryHint: .isDirectory)
            let folder = captures.appending(path: "\(id)/puppet5s", directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: folder.path),
                  let data = FileManager.default.contents(atPath: directory.appending(path: "project.json").path) else {
                report += "\(id)\tno capture or not in the library\n"
                continue
            }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            let project = try decodeTolerant(WEProject.self, from: Data(text.utf8))
            var settings = SceneRenderSettings()
            settings.postProcessing = .enabled
            settings.reflection = true
            settings.particleBudget = .unlimited
            settings.textureReduction = 1
            settings.sceneDetail = .full
            settings.renderResolution = .native
            let size = WEReferenceRenderer.size
            let center = SIMD2(Double(size.x) / 2, Double(size.y) / 2)
            let renderer = WEReferenceRenderer(directory: directory, project: project, settings: settings, storage: storage)
            let stills = [("still1.png", 10.0), ("still2.png", 12.0)]
            let frames = try renderer.render(stills.map { WEReferenceRenderer.Shot(time: $0.1, cursor: center) })
            let mask = WEReferenceMask(width: size.x, height: size.y, masks: [], taskbar: config.taskbarHeight)
            for ((file, _), frame) in zip(stills, frames) {
                let url = folder.appending(path: file)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let we = try WEReferenceImage.load(url)
                let metrics = WEReferenceMetrics.compare(we: we, ours: frame, mask: mask, grid: config.grid,
                                                         taskbar: config.taskbarHeight)
                report += "\(id)\t\(file)\t\(String(format: "%.1f", metrics.meanAbs))\t"
                    + "\(String(format: "%.3f", metrics.ssim))\n"
                let difference = WEReferenceMetrics.differenceImage(we: we, ours: frame, mask: mask)
                try WEReferenceImage.sideBySide([we.reduced(by: 2), frame.reduced(by: 2), difference])
                    .write(to: output.appending(path: "\(id)-puppet5s-\((file as NSString).deletingPathExtension)-compare.png"))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "no puppet still was compared")
        try report.write(to: output.appending(path: "report.tsv"), atomically: true, encoding: .utf8)
        print("Puppets against WE's puppet5s clips:\n\(report)")
    }
}
