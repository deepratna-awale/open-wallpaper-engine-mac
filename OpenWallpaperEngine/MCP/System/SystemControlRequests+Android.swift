import Foundation
import OWEControlProtocol

/// "Export for Android…": WE's `.mpkg` packages for its Android app, one per wallpaper
/// (`AndroidExportOptions`, `AndroidExportQueue`).
extension SystemControlRequests {
    func exportAndroid(_ params: ControlParameters, lookup: ControlLookup) async throws -> JSONValue {
        var ids = try params.strings("wallpaper_ids")
        if let id = try params.string("wallpaper_id") { ids.insert(id, at: 0) }
        guard !ids.isEmpty else { throw ControlError(.invalidParams, "Give wallpaper_id or wallpaper_ids.") }
        let wallpapers = try ids.map { try lookup.wallpaper($0) }
        let request = SystemAndroidRequest(wallpapers: wallpapers, options: try Self.androidOptions(params),
                                           outputFolder: try params.string("output_folder").map(Self.outputFolder))
        let batch = try await service.exportAndroid(request)
        return Self.json(batch)
    }

    /// The request's mode and options, checked as the sheet's controls limit them.
    static func androidOptions(_ params: ControlParameters) throws -> AndroidExportOptions {
        var options = AndroidExportOptions(mode: .balanced)
        if let name = try params.string("mode") {
            guard let mode = AndroidExportOptions.Mode(rawValue: name) else {
                throw ControlError(.invalidParams, "mode must be high_quality, balanced or pre_rendered.")
            }
            options.choose(mode)
        }
        guard let settings = try object(params, "options") else { return options }
        if let pixelArt = try settings.bool("pixel_art") { options.pixelArt = pixelArt }
        if let reduction = try settings.int("texture_reduction") {
            guard let value = AndroidExportOptions.TextureReduction(rawValue: reduction) else {
                throw ControlError(.invalidParams, "options.texture_reduction must be 1, 2 or 4.")
            }
            options.textureReduction = value
        }
        if let name = try settings.string("cropping") {
            guard let cropping = AndroidExportOptions.Cropping(rawValue: name) else {
                throw ControlError(.invalidParams, "options.cropping must be phone or original.")
            }
            options.cropping = cropping
        }
        if let name = try settings.string("video_preset") {
            guard let preset = AndroidExportOptions.VideoPreset(rawValue: name) else {
                throw ControlError(.invalidParams, "options.video_preset must be original, full_hd or uhd_4k.")
            }
            options.videoPreset = preset
        }
        if let fps = try settings.int("fps") {
            guard AndroidExportOptions.frameRates.contains(fps) else {
                throw ControlError(.invalidParams, "options.fps must be 24, 30 or 60.")
            }
            options.frameRate = fps
        }
        if let alignment = try settings.double("alignment") {
            guard (0...1).contains(alignment) else { throw ControlError(.invalidParams, "options.alignment must be 0 to 1.") }
            options.alignment = alignment
        }
        return options
    }

    static func json(_ batch: AndroidExportBatch) -> JSONValue {
        var message = batch.outputs.isEmpty ? "Nothing was exported."
            : "Exported \(batch.outputs.count) \(batch.outputs.count == 1 ? "package" : "packages") into \(batch.folder.path(percentEncoded: false)): "
                + batch.outputs.map(\.url.lastPathComponent).joined(separator: ", ") + "."
        if !batch.skipped.isEmpty {
            message += " Skipped " + batch.skipped.map { "\"\($0.title)\" (\($0.reason))" }.joined(separator: ", ") + "."
        }
        if !batch.failed.isEmpty {
            message += " Failed " + batch.failed.map { "\"\($0.title)\" (\($0.reason))" }.joined(separator: ", ") + "."
        }
        if !batch.outputs.isEmpty { message += " Copy them to the Android device and import them in the Wallpaper Engine app." }
        func entry(_ skipped: AndroidExportBatch.Skipped) -> JSONValue {
            ["wallpaper_id": .string(skipped.wallpaperID), "title": .string(skipped.title), "reason": .string(skipped.reason)]
        }
        return [
            "folder": .string(batch.folder.path(percentEncoded: false)),
            "packages": .array(batch.outputs.map { output in
                [
                    "wallpaper_id": .string(output.wallpaperID), "title": .string(output.title), "type": .string(output.type),
                    "mode": output.mode.map { .string($0.rawValue) } ?? .null,
                    "path": .string(output.url.path(percentEncoded: false)), "size": .number(Double(output.size)),
                    "preview": output.previewURL.map { .string($0.path(percentEncoded: false)) } ?? .null,
                ]
            }),
            "skipped": .array(batch.skipped.map(entry)),
            "failed": .array(batch.failed.map(entry)),
            "cancelled": .bool(batch.wasCancelled),
            "message": .string(message),
        ]
    }
}
