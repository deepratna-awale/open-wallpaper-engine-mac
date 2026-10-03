import Foundation

/// One Live Photo render, handed to the helper run (`ShaderPrewarmCommand`, `--render-live-photo
/// <job.json>`) as a JSON file: the wallpaper, its user properties as the inspector holds them,
/// the crop, the device's pixels, the clip and where the files go.
struct LivePhotoJob: Codable, Equatable {
    var wallpaperDirectory: String
    /// The user-property snapshot the render uses, whatever the helper's defaults hold.
    var properties: [String: String]
    var sceneSize: [Double]
    var outputPixels: [Int]
    var zoom: Double
    var center: [Double]
    var clipStart: Double
    var clipLength: Double
    /// The HEIC; nil renders the movie only (the clip's preview).
    var stillPath: String?
    var moviePath: String
    var identifier: String

    init(wallpaperDirectory: URL, properties: [String: String], crop: LivePhotoCrop, clip: LivePhotoClip,
         still: URL?, movie: URL, identifier: String) {
        self.wallpaperDirectory = wallpaperDirectory.path(percentEncoded: false)
        self.properties = properties
        sceneSize = [crop.sceneSize.x, crop.sceneSize.y]
        outputPixels = [crop.outputPixels.x, crop.outputPixels.y]
        zoom = crop.zoom
        center = [crop.center.x, crop.center.y]
        clipStart = clip.start
        clipLength = clip.length
        stillPath = still?.path(percentEncoded: false)
        moviePath = movie.path(percentEncoded: false)
        self.identifier = identifier
    }

    var crop: LivePhotoCrop? {
        guard sceneSize.count == 2, outputPixels.count == 2, center.count == 2 else { return nil }
        return LivePhotoCrop(sceneSize: SIMD2(sceneSize[0], sceneSize[1]), outputPixels: SIMD2(outputPixels[0], outputPixels[1]),
                             zoom: zoom, center: SIMD2(center[0], center[1]))
    }

    var clip: LivePhotoClip { LivePhotoClip(start: clipStart, length: clipLength) }
    var still: URL? { stillPath.map { URL(filePath: $0, directoryHint: .notDirectory) } }
    var movie: URL { URL(filePath: moviePath, directoryHint: .notDirectory) }

    // MARK: Progress over the pipe

    static let progressPrefix = "progress "

    /// The line the helper writes to standard output for `fraction` done.
    static func progressLine(_ fraction: Double) -> String {
        progressPrefix + String(format: "%.4f", min(max(fraction, 0), 1)) + "\n"
    }

    /// The fraction a line reports, nil for any other line.
    static func progress(fromLine line: Substring) -> Double? {
        guard line.hasPrefix(progressPrefix) else { return nil }
        return Double(line.dropFirst(progressPrefix.count).trimmingCharacters(in: .whitespaces))
    }
}
