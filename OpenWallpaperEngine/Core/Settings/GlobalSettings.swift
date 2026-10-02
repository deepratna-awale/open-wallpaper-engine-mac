import Cocoa
import Combine
import SwiftUI
import ServiceManagement
import Metal

extension GlobalSettings {
    /// The render resolution and upscaling a quality preset sets: Low draws half of each side and
    /// upscales it with MetalFX; the others draw at the displays' pixels without upscaling. A
    /// later choice of the user's stands until a preset is applied again.
    mutating func applyResolutionPreset(_ quality: GSQuality) {
        switch quality {
        case .low:
            upscaling = .metalFX
            renderScale = .percent50
        case .medium, .high, .ultra:
            upscaling = .off
            renderResolution = .display
        }
    }
}

enum GSQuality {
    case low, medium, high, ultra

    /// The frame rate the preset sets (`GlobalSettings.fps`): Ultra draws at the display's refresh.
    /// WE's own presets set 10, 15, 25 and 30 (`getQualityPreset`, `ui/dist/scripts/scripts.js`);
    /// these follow the Mac's faster displays.
    var fps: Double {
        switch self {
        case .low: return 15
        case .medium: return 30
        case .high: return 60
        case .ultra: return GlobalSettings.unlimitedFPS
        }
    }
}

/// A playback rule's action (Settings › Performance › Playback). With several displays, WE
/// offers "Pause per monitor" (`pause`) and "Pause all" (`pauseAll`) for the rules about other
/// applications' windows (`PlaybackRules`); with one display only "Pause".
enum GSPlayback: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case keepRunning, mute, pause, pauseAll, stop
}

/// WE's `msaa` setting (none, x2, x4, x8): the scene pass draws multisampled and resolves into
/// `_rt_FullFrameBuffer` (`wallpaper64.exe` 0x140181dcc, 0x140183550, 0x1400d3310).
enum GSAntiAliasingQuality: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case none, msaa_x2, msaa_x4, msaa_x8

    /// Samples per pixel.
    var sampleCount: Int {
        switch self {
        case .none: return 1
        case .msaa_x2: return 2
        case .msaa_x4: return 4
        case .msaa_x8: return 8
        }
    }
}

/// WE's `postprocessing` setting (docs/lighting-plan.md §2.6): "disabled" turns bloom off,
/// "ultra" lets a scene with `bloom` and `hdr` draw in HDR, "displayhdr" also outputs HDR.
enum GSPostProcessingQuality: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case disabled, enabled, ultra, displayhdr
}

/// WE's `shadows` and `volumetrics` settings: disabled, low, medium, high, ultra.
enum GSLightingQuality: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case disabled, low, medium, high, ultra

    /// WE's number for the setting, 0 (disabled) … 4 (ultra).
    var level: Int {
        switch self {
        case .disabled: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .ultra: return 4
        }
    }
}

extension GSQuality {
    /// The `shadows` value WE's quality preset sets (`getQualityPreset` in WE's
    /// `ui/dist/scripts/scripts.js`): the preset's own name.
    var shadows: GSLightingQuality {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        case .ultra: return .ultra
        }
    }

    /// The `volumetrics` value the same preset sets: also the preset's own name.
    var volumetrics: GSLightingQuality { shadows }
}

/// The most particles one scene may hold (`ParticleBudget`); a scene authored with more is thinned
/// to it, every system alike.
enum GSParticleBudget: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case low, medium, high, unlimited

    /// The budget in particles; nil for no limit.
    var limit: Int? {
        switch self {
        case .low: return 10_000
        case .medium: return 25_000
        case .high: return 50_000
        case .unlimited: return nil
        }
    }
}

/// WE's "Texture Resolution" (config `resolution`: `full`, `half`, `auto`; `TextureReduction`).
/// WE's settings offer these three, labelled High Quality, High Performance and Automatic
/// (`ui/dist/scripts/scripts.js`, `textureResolutionOptions`).
enum GSTextureResolutionQuality: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case highQuality, highPerformance, automatic

    /// The setting a WE `config.json` `resolution` value means, as `wallpaper64.exe` reads it
    /// (0x1401155f6…0x14011562f): `full` and `half` exactly; anything else, including `auto`, a
    /// hand-written `quarter` or no value, is automatic.
    init(weConfigValue value: String?) {
        switch value {
        case "full": self = .highQuality
        case "half": self = .highPerformance
        default: self = .automatic
        }
    }
}

/// What the scene target is sized for (`SceneRenderResolution`): `display` draws at the
/// displays' size in points (a 2× display's looks-like size, a quarter of its pixels) and the
/// composite scales the frame up to the backing pixels; `retina` draws at the backing pixels, 1:1;
/// `full` draws at the wallpaper's authored size and scales that onto the display with WE's
/// placement. Earlier stored values: "native" reads as `retina`, "desktop" as `display`
/// (`init(storedValue:)`).
enum GSRenderResolution: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case display, retina, full

    /// The choice a stored value means, including the values earlier versions wrote; nil for an
    /// unknown value.
    init?(storedValue value: String) {
        switch value {
        case "display", "desktop": self = .display
        case "retina", "native": self = .retina
        case "full": self = .full
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let resolution = GSRenderResolution(storedValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown render resolution \(value)")
        }
        self = resolution
    }
}

/// "Upscaling": the scene drawn at `GSRenderScale` of its size and scaled up to it, by MetalFX's
/// spatial scaler where the GPU and the frame's format allow it, else bilinearly (`SceneUpscaler`).
enum GSUpscaling: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case off, metalFX
}

/// "Render scale": the share of each side of the scene target drawn when upscaling.
enum GSRenderScale: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case percent50, percent67, percent75

    var factor: Float {
        switch self {
        case .percent50: return 0.5
        case .percent67: return 2.0 / 3
        case .percent75: return 0.75
        }
    }
}

/// How much detail a scene is drawn with (`SceneDetail`). `full` draws as WE does: the scene
/// target never below its authored size, and effects at their layer's texture size. `matchDisplay`
/// draws no more than the display shows: the scene target at most the display's size, and each
/// layer's effects at most its on-screen size.
enum GSSceneDetail: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case matchDisplay, full
}

enum GSAppearance: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case light, dark, followSystem
}

/// The app's language: the system's order, or one of the languages the app is translated into.
/// The raw values of English and Simplified Chinese predate the others and stay as stored.
enum GSLocalization: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case followSystem
    case en_US, zh_CN
    case de, fr, es, ptBR = "pt-BR", it, ja, ko, zhHant = "zh-Hant", ru, pl, tr, uk, ar, hi

    /// The BCP 47 language the app runs in; nil to follow the system.
    var languageIdentifier: String? {
        switch self {
        case .followSystem: return nil
        case .en_US: return "en"
        case .zh_CN: return "zh-Hans"
        default: return rawValue
        }
    }

    /// The language's name in that language, as language pickers show it; nil to follow the system.
    var endonym: String? {
        languageIdentifier.map { identifier in
            Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier
        }
    }

    /// Writes the choice where macOS reads an app's language (`AppleLanguages` in the app's
    /// defaults, which is also what System Settings › Language & Region sets per app). It takes
    /// effect at the next launch.
    func apply(to defaults: UserDefaults) {
        if let languageIdentifier {
            defaults.set([languageIdentifier], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}

enum GSVideoFramework: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case avkit
    /// Draws video through the scene renderer on the GPU, so the effect stack applies to it, the
    /// way Wallpaper Engine does. The default wherever Metal is available (every Apple silicon Mac).
    case metal

    /// Metal when the Mac has a Metal device, AVKit otherwise.
    static let preferred: GSVideoFramework = MTLCreateSystemDefaultDevice() != nil ? .metal : .avkit
}

enum GSProcessPiority: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case normal, belowNormal
}

enum GSLogLevel: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case error, verbose, none
}

struct GlobalSettings: Codable, Equatable {
    /// The FPS setting's top: no limit but the display's refresh.
    static let unlimitedFPS: Double = 240

    
    // MARK: Playback
    var otherApplicationFocused = GSPlayback.keepRunning
    var otherApplicationMaximized = GSPlayback.keepRunning
    var otherApplicationFullscreen = GSPlayback.keepRunning
    var otherApplicationPlayingAudio = GSPlayback.keepRunning
    var displayAsleep = GSPlayback.keepRunning
    var laptopOnBattery = GSPlayback.keepRunning
    
    // MARK: Quality
    /// WE's default is none (`config.json` `"msaa": "none"`).
    var antiAliasing = GSAntiAliasingQuality.none
    /// "enabled" draws WE's bloom as the app always has. WE's own UI default is unknown (its
    /// engine reads a missing key as "disabled"; docs/lighting-plan.md §5).
    var postProcessing = GSPostProcessingQuality.enabled
    var textureResolution = GSTextureResolutionQuality.automatic
    /// What the scene target is sized for (`GSRenderResolution`).
    var renderResolution = GSRenderResolution.display
    /// "Upscaling" (`GSUpscaling`): off draws the scene at its full size.
    var upscaling = GSUpscaling.off
    /// "Render scale" while upscaling (`GSRenderScale`).
    var renderScale = GSRenderScale.percent75
    /// The scene's detail (`GSSceneDetail`); drawing no more than the display shows is the default.
    var sceneDetail = GSSceneDetail.matchDisplay
    /// WE's `reflection` setting (default on): the screen-space reflection copy.
    var reflections = true
    /// WE's `shadows` setting; medium is WE's default.
    var shadows = GSLightingQuality.medium
    /// WE's `volumetrics` setting, on the same scale as `shadows` [?: default taken as shadows'].
    var volumetrics = GSLightingQuality.medium
    /// "Cheaper shadows" (on by default): shadow maps at half WE's size, smoothed by the
    /// comparison filter (`SceneShadowAtlas.mapSize`).
    var cheaperShadows = true
    /// WE's FPS setting: the most frames a second a scene draws. `unlimitedFPS` (the Ultra
    /// preset's, the slider's top) draws at the display's refresh.
    var fps: Double = 30
    /// The user moved the FPS slider themselves rather than through a quality preset: their rate
    /// then wins over the Quality↔Efficiency stop's cap on smooth motion (`FramePacing.Limits`).
    var fpsSetByUser = false
    /// The Quality↔Efficiency slider's stop (`QualityEfficiency`): 1 quality … 5 efficiency.
    var qualityEfficiency = QualityEfficiency.defaultStop
    /// The particle budget per scene (`ParticleBudget`).
    var particleBudget = GSParticleBudget.medium
    /// "Optimise textures" (`TexturePreparation`): scenes' colour images are compressed once to
    /// BC7 in the background and load from that cache after. On by default.
    var optimiseTextures = true
    /// Web wallpapers render at 1 point per pixel on Retina displays (`WebPageScale`): a quarter
    /// of the pixels for pages that size their canvas by `devicePixelRatio`. Off by default.
    var webStandardResolution = false
    /// Large additive particle systems of 2D scenes draw at half resolution and are added back
    /// (`SceneRenderSettings.reducedResolutionParticles`). Off by default.
    var reducedResolutionParticles = false
    
    // MARK: Automatic Setup
    var autoStart = false
    var safeMode = false
    
    // MARK: Basic Setup
    var language = GSLocalization.followSystem
    
    // MARK: macOS
    var adjustMenuBarTint = true
    
    // MARK: Appearance
    var appearance = GSAppearance.followSystem
    
    // MARK: Displays
    /// "Sync properties across displays": one set of user properties for a wallpaper on every
    /// display. Off is WE's default: its "Wallpaper per display" layout keeps each display's
    /// properties (`WallpaperPropertyScope`).
    var syncPropertiesAcrossDisplays = false

    // MARK: Audio
    var audioOutput = true
    /// WE's "Media integration support" (`mediaintegration`, on by default): wallpapers hear the
    /// system's Now Playing session (`MacMediaSessionSource`).
    var mediaIntegration = true
    var reloadWhenChangingOutputDevice = true // Not putting in use
    
    // MARK: Video
    var videoFramework = GSVideoFramework.preferred
    
    // MARK: Advanced
    var processPiority = GSProcessPiority.normal // Not putting in use
    var pauseOnVRAMExhausted = false // Not putting in use
    var restartAfterCrashing = false // Not putting in use
    
    // MARK: Developer
    var logLevel = GSLogLevel.none
    
    // MARK: Misc
    var autoRefresh = true

    /// The stored keys. `postProcessing`, `reflections` and `antiAliasing` moved to new keys when
    /// the renderer started reading them: the old keys hold values saved while the settings did
    /// nothing (post-processing then defaulted to "disabled", anti-aliasing to MSAA x2), so they
    /// are left behind.
    enum CodingKeys: String, CodingKey {
        case otherApplicationFocused, otherApplicationMaximized, otherApplicationFullscreen, otherApplicationPlayingAudio
        case displayAsleep
        case laptopOnBattery, textureResolution, shadows, volumetrics, fps, fpsSetByUser, particleBudget, optimiseTextures
        case webStandardResolution, reducedResolutionParticles
        case qualityEfficiency
        case antiAliasing = "msaa"
        case renderResolution, sceneDetail, upscaling, renderScale
        case postProcessing = "postProcessingQuality"
        case reflections = "reflection"
        case autoStart, safeMode, language, adjustMenuBarTint, appearance, audioOutput
        case reloadWhenChangingOutputDevice, videoFramework, processPiority, pauseOnVRAMExhausted
        case restartAfterCrashing, logLevel, autoRefresh
        case syncPropertiesAcrossDisplays
        case mediaIntegration
        case cheaperShadows
    }
}

extension GlobalSettings {
    /// Reads each stored setting on its own: a key that is missing (a setting added since the
    /// settings were saved) or unreadable keeps its default, and the others are kept.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func read<Value: Decodable>(_ key: CodingKeys, _ value: inout Value) {
            do {
                if let stored = try container.decodeIfPresent(Value.self, forKey: key) { value = stored }
            } catch {
                OWELog.error(.settings, "Setting \(key.stringValue) can't be read and keeps its default: \(error)")
            }
        }
        read(.otherApplicationFocused, &otherApplicationFocused)
        read(.otherApplicationMaximized, &otherApplicationMaximized)
        read(.otherApplicationFullscreen, &otherApplicationFullscreen)
        read(.otherApplicationPlayingAudio, &otherApplicationPlayingAudio)
        read(.displayAsleep, &displayAsleep)
        read(.laptopOnBattery, &laptopOnBattery)
        read(.antiAliasing, &antiAliasing)
        read(.postProcessing, &postProcessing)
        read(.textureResolution, &textureResolution)
        read(.renderResolution, &renderResolution)
        read(.sceneDetail, &sceneDetail)
        read(.upscaling, &upscaling)
        read(.renderScale, &renderScale)
        read(.reflections, &reflections)
        read(.shadows, &shadows)
        read(.volumetrics, &volumetrics)
        read(.fps, &fps)
        read(.fpsSetByUser, &fpsSetByUser)
        read(.qualityEfficiency, &qualityEfficiency)
        qualityEfficiency = QualityEfficiency(stop: qualityEfficiency).stop
        read(.particleBudget, &particleBudget)
        read(.optimiseTextures, &optimiseTextures)
        read(.webStandardResolution, &webStandardResolution)
        read(.reducedResolutionParticles, &reducedResolutionParticles)
        read(.autoStart, &autoStart)
        read(.safeMode, &safeMode)
        read(.language, &language)
        read(.adjustMenuBarTint, &adjustMenuBarTint)
        read(.appearance, &appearance)
        read(.audioOutput, &audioOutput)
        read(.reloadWhenChangingOutputDevice, &reloadWhenChangingOutputDevice)
        read(.videoFramework, &videoFramework)
        read(.processPiority, &processPiority)
        read(.pauseOnVRAMExhausted, &pauseOnVRAMExhausted)
        read(.restartAfterCrashing, &restartAfterCrashing)
        read(.logLevel, &logLevel)
        read(.autoRefresh, &autoRefresh)
        read(.syncPropertiesAcrossDisplays, &syncPropertiesAcrossDisplays)
        read(.mediaIntegration, &mediaIntegration)
        read(.cheaperShadows, &cheaperShadows)
    }
}
