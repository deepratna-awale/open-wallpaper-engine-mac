//
//  PerformancePage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/12.
//

import SwiftUI
import OWEInspectorKit

struct PerformancePage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel
    /// A display can show HDR, so "Ultra (Display HDR)" is offered (`DisplayHDRSupport`).
    private let displayHDR = DisplayHDRSupport.isAvailable()
    @State private var isEditingApplicationRules = false
    
    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }
    
    /// WE's pause actions for the rules about other applications' windows: with several displays
    /// "Pause per Display" (the display the window is on) and "Pause All"; with one, "Pause".
    /// "Pause All" stays listed while chosen, so the picker shows it with one display too.
    @ViewBuilder
    private func pauseOptions(_ selected: GSPlayback) -> some View {
        if NSScreen.screens.count > 1 || selected == .pauseAll {
            Text("Pause per Display").tag(GSPlayback.pause)
            Text("Pause All").tag(GSPlayback.pauseAll)
        } else {
            Text("Pause").tag(GSPlayback.pause)
        }
    }

    var body: some View {
        SettingsForm {
            Section {
                Picker("Other Application Focused:", selection: $viewModel.settings.otherApplicationFocused) {
                    Text("Keep Running").tag(GSPlayback.keepRunning)
                    Text("Mute").tag(GSPlayback.mute)
                    pauseOptions(viewModel.settings.otherApplicationFocused)
                }
                .changedFromDefault(viewModel.isChanged(\.otherApplicationFocused))
                .help("What wallpapers do while another app's window is active. Pause per Display pauses only the display that window is on; Pause All pauses every display.")

                Picker("Other Application Maximized:", selection: $viewModel.settings.otherApplicationMaximized) {
                    Text("Keep Running").tag(GSPlayback.keepRunning)
                    Text("Mute").tag(GSPlayback.mute)
                    pauseOptions(viewModel.settings.otherApplicationMaximized)
                    Text("Stop (free memory)").tag(GSPlayback.stop)
                }
                .changedFromDefault(viewModel.isChanged(\.otherApplicationMaximized))
                .help("What wallpapers do while another app's window fills their display. Stop (free memory) hides the wallpaper to free its memory.")

                Picker("Other Application Fullscreen:", selection: $viewModel.settings.otherApplicationFullscreen) {
                    Text("Keep Running").tag(GSPlayback.keepRunning)
                    Text("Mute").tag(GSPlayback.mute)
                    pauseOptions(viewModel.settings.otherApplicationFullscreen)
                    Text("Stop (free memory)").tag(GSPlayback.stop)
                }
                .changedFromDefault(viewModel.isChanged(\.otherApplicationFullscreen))
                .help("What wallpapers do while another app is in full screen on their display. Pause and Stop save the work of drawing a wallpaper no one can see.")
                
                Picker("Other Application Playing Audio:", selection: $viewModel.settings.otherApplicationPlayingAudio) {
                    Text("Keep Running").tag(GSPlayback.keepRunning)
                    Text("Mute").tag(GSPlayback.mute)
                    Text("Pause").tag(GSPlayback.pause)
                }
                .changedFromDefault(viewModel.isChanged(\.otherApplicationPlayingAudio))
                .help("What wallpapers do while another app plays sound, on every display. Mute silences only the wallpapers' own sound.")
                
                Picker("Display asleep", selection: $viewModel.settings.displayAsleep) {
                    Text("Keep Running").tag(GSPlayback.keepRunning)
                    Text("Pause").tag(GSPlayback.pause)
                    Text("Stop (free memory)").tag(GSPlayback.stop)
                }
                .changedFromDefault(viewModel.isChanged(\.displayAsleep))
                .help("What wallpapers do while the displays sleep. Pause keeps the last frame; Stop (free memory) also hides the wallpaper to free its memory.")
                
                Picker("Laptop on battery", selection: $viewModel.settings.laptopOnBattery) {
                    Text("Keep Running").tag(GSPlayback.keepRunning)
                    Text("Pause").tag(GSPlayback.pause)
                    Text("Stop (free memory)").tag(GSPlayback.stop)
                }
                .changedFromDefault(viewModel.isChanged(\.laptopOnBattery))
                .help("What wallpapers do while your Mac runs on battery. Pause or Stop saves the most battery.")
                
                HStack {
                    Text("Application Rules")
                    Spacer()
                    Button {
                        isEditingApplicationRules = true
                    } label: {
                        Text("Edit").frame(minWidth: 100)
                    }
                    .glassButtonStyle(.prominent)
                }
                .changedFromDefault(viewModel.isChanged(\.applicationRules))
                .help("Choose what wallpapers do while specific apps are running or in front, such as pausing during a game.")
                .sheet(isPresented: $isEditingApplicationRules) {
                    ApplicationRulesSheet(rules: $viewModel.settings.applicationRules)
                }
            } header: {
                Label("Playback", systemImage: "play.fill")
            }
            .settingsAnchor(SettingsAnchor.playback)
            Section {
                // Each button applies a preset to the settings below; none of them stays selected.
                LabeledContent("Preset") {
                    ControlGroup {
                        Button("Low") { viewModel.setQuality(.low) }
                        Button("Medium") { viewModel.setQuality(.medium) }
                        Button("High") { viewModel.setQuality(.high) }
                        Button("Ultra") { viewModel.setQuality(.ultra) }
                    }
                    .fixedSize()
                }
                .help("Sets the quality settings below, the frame rate and the Quality ↔ Efficiency slider in one step. Low also turns on MetalFX upscaling from half size.")
                Picker(selection: $viewModel.settings.antiAliasing) {
                    Text("None").tag(GSAntiAliasingQuality.none)
                    Text("MSAA x2").tag(GSAntiAliasingQuality.msaa_x2)
                    Text("MSAA x4").tag(GSAntiAliasingQuality.msaa_x4)
                    Text("MSAA x8").tag(GSAntiAliasingQuality.msaa_x8)
                } label: {
                    warningLabel("Anti-aliasing",
                                 warning: viewModel.settings.antiAliasing == .msaa_x8 ? .red : nil,
                                 help: "×8 MSAA is only recommended for powerful high-end desktop graphics cards.")
                }
                .changedFromDefault(viewModel.isChanged(\.antiAliasing))
                .help("Smooths jagged edges in scenes by sampling each pixel 2, 4 or 8 times (MSAA). More samples cost more GPU time and memory; None by default.")
                Picker(selection: $viewModel.settings.postProcessing) {
                    Text("Disabled").tag(GSPostProcessingQuality.disabled)
                    Text("Enabled").tag(GSPostProcessingQuality.enabled)
                    Text("Ultra").tag(GSPostProcessingQuality.ultra)
                    if displayHDR {
                        Text("Ultra (Display HDR)").tag(GSPostProcessingQuality.displayhdr)
                    }
                } label: {
                    warningLabel("Post-Processing",
                                 warning: viewModel.settings.postProcessing.allowsHDR ? .yellow : nil,
                                 help: "Ultra mode adds HDR bloom to supported wallpapers and is only recommended for powerful high-end desktop graphics cards.")
                }
                .changedFromDefault(viewModel.isChanged(\.postProcessing))
                .help("Disabled turns bloom off in scenes. Ultra lets scenes made for HDR draw their bloom in HDR, and Ultra (Display HDR) also sends HDR to the display.")
                .onAppear {
                    let kept = DisplayHDRSupport.coerced(viewModel.settings.postProcessing, available: displayHDR)
                    if kept != viewModel.settings.postProcessing { viewModel.settings.postProcessing = kept }
                }
                Picker("Texture Resolution", selection: $viewModel.settings.textureResolution) {
                    Text("High Quality").tag(GSTextureResolutionQuality.highQuality)
                    Text("High Performance").tag(GSTextureResolutionQuality.highPerformance)
                    Text("Automatic").tag(GSTextureResolutionQuality.automatic)
                }
                .changedFromDefault(viewModel.isChanged(\.textureResolution))
                .help("Wallpaper Engine's setting: High Performance loads textures at half their size and runs effects at half size too; Automatic does so for a scene with more than 3.9 times the display's pixels (a 4K scene on a 1080p display), and for a 3D scene on a display smaller than 1080p.")
                Picker("Scene Detail", selection: $viewModel.settings.sceneDetail) {
                    Text("Match Display").tag(GSSceneDetail.matchDisplay)
                    Text("Full (Wallpaper Engine)").tag(GSSceneDetail.full)
                }
                .changedFromDefault(viewModel.isChanged(\.sceneDetail))
                .help("Match Display draws no more detail than the display shows: a scene larger than the display is drawn at the display's size, and each layer's effects at the size the layer appears on screen. Full draws every effect at its texture's full size, as Wallpaper Engine does.")
                Picker("Render Resolution", selection: $viewModel.settings.renderResolution) {
                    Text("Display", comment: "Render resolution: the display's size in points").tag(GSRenderResolution.display)
                    Text("Retina", comment: "Render resolution: the display's native backing pixels").tag(GSRenderResolution.retina)
                    Text("Full", comment: "Render resolution: the wallpaper's authored size").tag(GSRenderResolution.full)
                }
                .changedFromDefault(viewModel.isChanged(\.renderResolution))
                .help("Display, the default, renders at the display's size in points (a quarter of the pixels on Retina) and scales up; web wallpapers then draw at standard resolution too. Retina renders the native pixels one for one, and Full renders the wallpaper's authored size scaled to fit.")
                Picker("Upscaling", selection: $viewModel.settings.upscaling) {
                    Text("Off", comment: "Upscaling: none").tag(GSUpscaling.off)
                    Text("MetalFX").tag(GSUpscaling.metalFX)
                }
                .changedFromDefault(viewModel.isChanged(\.upscaling))
                .help("MetalFX draws the scene at the render scale and scales it up to full size, for less work. Where MetalFX isn't available, or for HDR, the frame is scaled smoothly instead.")
                if viewModel.settings.upscaling != .off {
                    Picker("Render Scale", selection: $viewModel.settings.renderScale) {
                        ForEach(GSRenderScale.allCases) { scale in
                            Text(verbatim: Double(scale.factor).formatted(.percent.precision(.fractionLength(0)))).tag(scale)
                        }
                    }
                    .changedFromDefault(viewModel.isChanged(\.renderScale))
                    .help("How large scenes render before MetalFX upscales them, per side. Lower is faster and softer.")
                }
                Picker("Shadows", selection: $viewModel.settings.shadows) {
                    Text("Disabled").tag(GSLightingQuality.disabled)
                    Text("Low").tag(GSLightingQuality.low)
                    Text("Medium").tag(GSLightingQuality.medium)
                    Text("High").tag(GSLightingQuality.high)
                    Text("Ultra").tag(GSLightingQuality.ultra)
                }
                .changedFromDefault(viewModel.isChanged(\.shadows))
                .help("Shadows cast by wallpapers' lights. Higher qualities draw larger shadow maps.")
                Picker("Volumetrics", selection: $viewModel.settings.volumetrics) {
                    Text("Disabled").tag(GSLightingQuality.disabled)
                    Text("Low").tag(GSLightingQuality.low)
                    Text("Medium").tag(GSLightingQuality.medium)
                    Text("High").tag(GSLightingQuality.high)
                    Text("Ultra").tag(GSLightingQuality.ultra)
                }
                .changedFromDefault(viewModel.isChanged(\.volumetrics))
                .help("Light shafts from wallpapers' volumetric lights. Higher qualities march more samples at a finer resolution; low and medium blur a coarser buffer.")
                HStack {
                    warningLabel("FPS",
                                 warning: viewModel.settings.fps > 60 ? .red : viewModel.settings.fps > 30 ? .yellow : nil,
                                 help: viewModel.settings.fps > 60
                                    ? "High FPS may slow down your Mac! We're serious, this is too much 🔥."
                                    : "High FPS may slow down your Mac!")
                    Spacer()
                    NumericSliderInput(value: fps, range: 10...GlobalSettings.unlimitedFPS,
                                       defaultValue: 30, step: 1, fractionDigits: 0,
                                       sliderWidth: 150, fieldWidth: 44)
                }
                .changedFromDefault(viewModel.isChanged(\.fps))
                .help("The most frames per second scene and web wallpapers draw; 240 means no limit. Higher rates use more GPU and battery.")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quality ↔ Efficiency")
                    Slider(value: qualityEfficiency, in: Double(QualityEfficiency.stops.lowerBound)...Double(QualityEfficiency.stops.upperBound),
                           step: 1) {
                        Text("Quality ↔ Efficiency")
                    } minimumValueLabel: {
                        Text("Quality")
                    } maximumValueLabel: {
                        Text("Efficiency")
                    }
                    .labelsHidden()
                }
                .changedFromDefault(viewModel.isChanged(\.qualityEfficiency))
                .help("Toward Efficiency, scenes cap smooth motion at 60 and then 30 fps, redraw slow changes less often, and draw blurs and glows at half or quarter size. A scene that isn't changing isn't redrawn, and a hot Mac or Low Power Mode moves further toward Efficiency.")
                Picker("Particle Budget", selection: $viewModel.settings.particleBudget) {
                    Text("Low (10,000)").tag(GSParticleBudget.low)
                    Text("Medium (25,000)").tag(GSParticleBudget.medium)
                    Text("High (50,000)").tag(GSParticleBudget.high)
                    Text("Unlimited").tag(GSParticleBudget.unlimited)
                }
                .changedFromDefault(viewModel.isChanged(\.particleBudget))
                .help("The most particles one wallpaper may hold. A wallpaper made with more draws every particle system thinner, keeping its look.")
                HStack {
                    Text("Reflections")
                    Spacer()
                    Toggle("Reflection", isOn: $viewModel.settings.reflections)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                }
                .changedFromDefault(viewModel.isChanged(\.reflections))
                .help("Lets scenes draw their reflection effects, such as water or glass. Off skips that work in scenes that use them.")
            } header: {
                Label("Quality", systemImage: "memorychip.fill")
                Text("These settings are for scene wallpapers. FPS and Render Resolution apply to web wallpapers too.")
            }
            .settingsAnchor(SettingsAnchor.quality)
        }
    }

    /// The slider's stop as the `Slider` reads it.
    /// The FPS slider: a rate set here is the user's own and wins over the slider stop's cap.
    private var fps: Binding<Double> {
        Binding(get: { viewModel.settings.fps },
                set: {
                    viewModel.settings.fps = $0
                    viewModel.settings.fpsSetByUser = true
                })
    }

    private var qualityEfficiency: Binding<Double> {
        Binding(get: { Double(viewModel.settings.qualityEfficiency) },
                set: { viewModel.settings.qualityEfficiency = QualityEfficiency(stop: Int($0.rounded())).stop })
    }

    /// A setting's title, followed by a warning triangle (with `help`) when `warning` is set.
    private func warningLabel(_ title: LocalizedStringKey, warning: Color?, help: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if let warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(warning)
                    .help(help)
                    .accessibilityLabel(Text(help))
            }
        }
    }
}
