import Foundation

extension SceneMetalRenderer {
    /// Whether a scene's content reads system audio, so the renderer holds capture on for it: a
    /// layer that follows audio (`g_AudioSpectrum*`, music sync, a user-bound value that may be
    /// music-synced) or a particle element with an audio response. Scripts' `registerAudioBuffers`
    /// takes its own lease (`SceneScriptAudioBuffersExtension`).
    static func needsAudio(_ analysis: SceneLayerAnalysis, particles: [SceneMetalParticleSystem]) -> Bool {
        analysis.layers.contains { $0.dependencies.contains(.audio) }
            || particles.contains(where: particleSystemReadsAudio)
    }

    /// The User Adjustments a user can sync to music (Details › User Scene Settings): the user
    /// adjustment layer's, the animation speed and the mouse parallax amount.
    static let musicSyncedAdjustments = ["_owe_hue", "_owe_saturation", "_owe_bloom", "_owe_blur",
                                         ScenePlaybackSpeed.propertyKey, "_owe_effect_parallax_amount"]

    /// Whether one of `store`'s User Adjustments follows the music: its sync is on with an amount.
    static func adjustmentsFollowMusic(store: String, services: WallpaperServices = .shared) -> Bool {
        musicSyncedAdjustments.contains { key in
            services.userPropertyString("\(key)_musicSync", wallpaper: store)?.lowercased() == "true"
                && abs(Double(services.userPropertyString("\(key)_musicAmount", wallpaper: store) ?? "") ?? 0) > 0.0001
        }
    }

    /// Whether a User Adjustment follows the music now.
    var adjustmentsFollowMusic: Bool { adjustmentAudioLease != nil }

    /// Holds system audio capture while a User Adjustment of this wallpaper follows the music, and
    /// samples an idle scene meanwhile as one that changes on its own, so the level reaches it.
    func updateAdjustmentMusicSync() {
        let follows = Self.adjustmentsFollowMusic(store: wallpaperKey)
        if follows != (adjustmentAudioLease != nil) {
            adjustmentAudioLease = follows ? WallpaperServices.shared.acquireAudioCapture() : nil
        }
        framePacing.changesOnItsOwn = contentChangesOnItsOwn || follows
    }

    static func particleSystemReadsAudio(_ system: SceneMetalParticleSystem) -> Bool {
        system.emitters.contains { $0.audio != nil }
            || system.program.operators.contains { $0.audio != nil }
            || system.program.initializers.contains { $0.audio != nil }
    }
}
