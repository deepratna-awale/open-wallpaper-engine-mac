import Cocoa
import Combine
import SwiftUI
import ServiceManagement
import Metal

enum GSQuality {
    case low, medium, high, ultra
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

/// How many pixels the scene target gets per point of the display (`SceneRenderResolution`):
/// the display's backing pixels, or one per point (a 2× display drawn at half its pixels and
/// scaled up), which a lower-resolution display would draw.
enum GSRenderResolution: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }
    case native, desktop
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
    /// The scene target's pixels per display point (`GSRenderResolution`).
    var renderResolution = GSRenderResolution.native
    /// The scene's detail (`GSSceneDetail`); drawing no more than the display shows is the default.
    var sceneDetail = GSSceneDetail.matchDisplay
    /// WE's `reflection` setting (default on): the screen-space reflection copy.
    var reflections = true
    /// WE's `shadows` setting; medium is WE's default.
    var shadows = GSLightingQuality.medium
    /// WE's `volumetrics` setting, on the same scale as `shadows` [?: default taken as shadows'].
    var volumetrics = GSLightingQuality.medium
    var fps: Double = 30
    /// The Quality↔Efficiency slider's stop (`QualityEfficiency`): 1 quality … 5 efficiency.
    var qualityEfficiency = QualityEfficiency.defaultStop
    /// The particle budget per scene (`ParticleBudget`).
    var particleBudget = GSParticleBudget.medium
    /// "Optimise textures" (`TexturePreparation`): scenes' colour images are compressed once to
    /// BC7 in the background and load from that cache after. On by default.
    var optimiseTextures = true
    
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
        case laptopOnBattery, textureResolution, shadows, volumetrics, fps, particleBudget, optimiseTextures
        case qualityEfficiency
        case antiAliasing = "msaa"
        case renderResolution, sceneDetail
        case postProcessing = "postProcessingQuality"
        case reflections = "reflection"
        case autoStart, safeMode, language, adjustMenuBarTint, appearance, audioOutput
        case reloadWhenChangingOutputDevice, videoFramework, processPiority, pauseOnVRAMExhausted
        case restartAfterCrashing, logLevel, autoRefresh
        case syncPropertiesAcrossDisplays
        case mediaIntegration
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
        read(.reflections, &reflections)
        read(.shadows, &shadows)
        read(.volumetrics, &volumetrics)
        read(.fps, &fps)
        read(.qualityEfficiency, &qualityEfficiency)
        qualityEfficiency = QualityEfficiency(stop: qualityEfficiency).stop
        read(.particleBudget, &particleBudget)
        read(.optimiseTextures, &optimiseTextures)
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
    }
}
