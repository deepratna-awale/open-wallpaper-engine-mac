import Foundation

/// One pre-rendered Android video, handed to the helper run (`ShaderPrewarmCommand`,
/// `--render-android-video <job.json>`, `AndroidVideoRenderer`) as a JSON file: the wallpaper,
/// the user-property snapshot it renders with, the crop, the frame rate, the loop's length, the
/// bit rate and where the `.mp4` goes.
struct AndroidVideoJob: Codable, Equatable {
    var wallpaperDirectory: String
    var properties: [String: String]
    var sceneSize: [Double]
    var outputPixels: [Int]
    var center: [Double]
    var frameRate: Int
    var seconds: Int
    var bitRate: Int
    var outputPath: String

    init(wallpaperDirectory: URL, properties: [String: String], crop: LivePhotoCrop, frameRate: Int,
         seconds: Int = AndroidExportOptions.videoSeconds, bitRate: Int, output: URL) {
        self.wallpaperDirectory = wallpaperDirectory.path(percentEncoded: false)
        self.properties = properties
        sceneSize = [crop.sceneSize.x, crop.sceneSize.y]
        outputPixels = [crop.outputPixels.x, crop.outputPixels.y]
        center = [crop.center.x, crop.center.y]
        self.frameRate = frameRate
        self.seconds = seconds
        self.bitRate = bitRate
        outputPath = output.path(percentEncoded: false)
    }

    var crop: LivePhotoCrop? {
        guard sceneSize.count == 2, outputPixels.count == 2, center.count == 2 else { return nil }
        return LivePhotoCrop(sceneSize: SIMD2(sceneSize[0], sceneSize[1]), outputPixels: SIMD2(outputPixels[0], outputPixels[1]),
                             center: SIMD2(center[0], center[1]))
    }

    var output: URL { URL(filePath: outputPath, directoryHint: .notDirectory) }

    /// Frames in the loop.
    var frameCount: Int { max(1, frameRate * seconds) }
}
