//
//  WallpaperPreview.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import SwiftUI
import OWEInspectorKit

struct WallpaperPreview: SubviewOfContentView {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    
    @Environment(\.undoManager) var undoManager
    
    @State var isEditingId = ""
    @State var title = ""
    @State var newTag = ""
    
    @State var hoveredTag: String?
    /// SwiftUI cannot observe UserDefaults, so this store is what re-renders the music controls
    /// after their bindings write.
    @ObservedObject private var musicSync = VideoMusicSyncStore.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    /// Re-renders the screen saver row as loop renders start and finish.
    @ObservedObject private var screenSaver = AppDelegate.shared.screenSaver
    @State var isTagsHovered = false
    /// Counts the confirmed Resets; `SceneUserPropertiesView` resets on each change.
    @State private var propertyResets = 0
    @State private var isConfirmingPropertyReset = false
    /// Counts applied presets; the property rows reload their values on each change.
    @State private var presetApplications = 0

    init(contentViewModel viewModel: ContentViewModel, wallpaperViewModel: WallpaperViewModel) {
        self.viewModel = viewModel
        self.wallpaperViewModel = wallpaperViewModel
    }
    
    /// The displayed wallpaper's size on disk, measured off the main thread once per wallpaper: it
    /// walks every file, which stalled each redraw of the panel.
    @State private var measuredSize: (directory: URL, text: String)?

    var wallpaperSize: String {
        guard let measuredSize, measuredSize.directory == wallpaperViewModel.displayedWallpaper.wallpaperDirectory
        else { return "…" }
        return measuredSize.text
    }

    private static func sizeText(of directory: URL) -> String {
        // An unreadable folder has no size to show; the placeholder says so.
        guard let sizeBytes = try? directory.directoryTotalAllocatedSize(includingSubfolders: true) else {
            return String(localized: "Unknown Size", comment: "Details panel: the wallpaper's size on disk can't be read")
        }
        return ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
    
    /// The selected wallpaper's loop video: ready, rendering or not made for this type. Nothing
    /// while the plugin is off or an eligible wallpaper has no loop yet.
    @ViewBuilder private var screenSaverStatusRow: some View {
        switch screenSaver.status(for: wallpaperViewModel.displayedWallpaper) {
        case .available:
            screenSaverRow(String(localized: "Screen Saver Available",
                                  comment: "Details panel: a screen saver loop video of this wallpaper is ready"),
                           showsSettings: true) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .rendering:
            screenSaverRow(String(localized: "Rendering Screen Saver",
                                  comment: "Details panel: the screen saver loop video of this wallpaper is being made"),
                           showsSettings: true) {
                ProgressView().controlSize(.small).progressViewStyle(.circular)
            }
        case .notEligible:
            screenSaverRow(String(localized: "Screen Saver Not Available",
                                  comment: "Details panel: no screen saver is made from this wallpaper")) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
            .help(screenSaverNotAvailableReason)
        case .notAvailable(.pageDidNotLoad):
            screenSaverRow(String(localized: "Screen Saver Not Available",
                                  comment: "Details panel: no screen saver is made from this wallpaper")) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            .help(String(localized: "The wallpaper's page didn't load, so no screen saver was recorded",
                         comment: "Details panel: why a web or WebM video wallpaper has no screen saver"))
        case .notAvailable(.doesNotLoop):
            screenSaverRow(String(localized: "Screen Saver Not Available",
                                  comment: "Details panel: no screen saver is made from this wallpaper")) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            .help(String(localized: "This page doesn't loop smoothly",
                         comment: "Details panel: why a web wallpaper has no screen saver: its recording has no seamless loop"))
        case nil:
            EmptyView()
        }
    }

    /// Why the saver doesn't play the selected wallpaper: a video in a format AVFoundation can't
    /// play and WebM can't record, or an application wallpaper.
    private var screenSaverNotAvailableReason: String {
        if wallpaperViewModel.displayedWallpaper.project.type.caseInsensitiveCompare("video") == .orderedSame {
            return String(localized: "The screen saver plays MP4 and MOV videos in H.264 or HEVC, and records WebM videos",
                          comment: "Details panel: why a video wallpaper in another codec has no screen saver")
        }
        return String(localized: "Screen savers are made from scene, web and video wallpapers",
                      comment: "Details panel: why an application wallpaper has no screen saver")
    }

    private func screenSaverRow(_ text: String, showsSettings: Bool = false,
                                @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 6) {
            screenSaverStatus(text, icon: icon)
            if showsSettings {
                let title = String(localized: "Open Screen Saver Settings",
                                   comment: "Details panel: opens System Settings where the screen saver is chosen")
                Button {
                    ScreenSaverInstaller.current.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help(title)
                .accessibilityLabel(title)
            }
        }
    }

    private func screenSaverStatus(_ text: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 6) {
            icon()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Screen Saver"))
        .accessibilityValue(text)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned outside the ScrollView so it stays put while the details scroll.
            Text("Details")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
                .padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        GifImage(contentsOf: wallpaperViewModel.displayedWallpaper.previewURL
                                    ?? Bundle.main.url(forResource: "WallpaperNotFound", withExtension: "mp4")!,
                                 animates: viewModel.isApplicationActive)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .background(Color(nsColor: NSColor.controlBackgroundColor))
                            .frame(width: 280, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16.0))
                            .border(Color.white, width: 4)
                        HStack {
                            if isEditingId == "title" {
                                TextField("Wallpaper Title", text: $title)
                                    .onSubmit {
                                        var wallpaper = wallpaperViewModel.displayedWallpaper
                                        
                                        wallpaper.project.title = title
                                        
                                        guard let data = try? JSONEncoder().encode(wallpaper.project) else { return }
                                        
                                        try? data.write(to: wallpaper.wallpaperDirectory.appending(path: "project.json"), options: .atomic)
                                        
                                        wallpaperViewModel.inspect(wallpaper)
                                        
                                        isEditingId = ""
                                    }
                            } else {
                                Text(verbatim: wallpaperViewModel.displayedWallpaper.project.displayTitle)
                                    .frame(minWidth: 50)
                                    .id("title")
                                    .lineLimit(1)
                                    .onTapGesture(count: 2) {
                                        title = wallpaperViewModel.displayedWallpaper.project.title
                                        isEditingId = "title"
                                    }
                                Image(systemName: "square.and.pencil")
                            }
                            
                        }
                    }
                        HStack {
                            Spacer()
                        AsyncImage(url: wallpaperViewModel.inspectedAuthor?.avatarURL) { phase in
                            if case let .success(image) = phase {
                                image.resizable()
                            } else {
                                Image("we.placeholder").resizable()
                            }
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        let authorID = wallpaperViewModel.inspectedAuthor?.steamId ?? wallpaperViewModel.inspectedWorkshopItem?.creatorId
                        if let authorID {
                            Button {
                                viewModel.topTabBarSelection = 1
                                viewModel.workshopVM.showAuthor(authorID)
                            } label: {
                                Text(wallpaperViewModel.inspectedAuthor?.personaName ?? authorID)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.link)
                            .help("View this author's Workshop items")
                        } else {
                            Text("Unknown Author")
                        }
                        Spacer()
                    }
                    favoriteControl
                    HStack {
                        Text(verbatim: LocalizedLabels.wallpaperType(wallpaperViewModel.displayedWallpaper.project.type))
                        Text(wallpaperSize)
                            .task(id: wallpaperViewModel.displayedWallpaper.wallpaperDirectory) {
                                let directory = wallpaperViewModel.displayedWallpaper.wallpaperDirectory
                                let text = await Task.detached(priority: .utility) { Self.sizeText(of: directory) }.value
                                measuredSize = (directory, text)
                            }
                    }
                    .font(.footnote)
                    
                    ViewThatFits(in: .horizontal) {
                        tags.animation(.spring(), value: isTagsHovered)
                        ScrollView(.horizontal, showsIndicators: false) {
                            tags.animation(.spring(), value: isTagsHovered)
                        }
                    }
                    
                    .onHover { isTagsHovered = $0 }
                    
                    if isEditingId == "tags" {
                        HStack {
                            Button {
                                newTag = ""
                                isEditingId = ""
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            TextField("New Tag", text: $newTag)
                                .onSubmit {
                                    defer {
                                        newTag = ""
                                        isEditingId = ""
                                    }
                                    
                                    guard !newTag.isEmpty else { return }
                                    
                                    var wallpaper = wallpaperViewModel.displayedWallpaper
                                    
                                    var tags = wallpaper.project.tags ?? []
                                    
                                    tags = Array(Set(tags)) // remove duplicate items
                                    
                                    tags.append(newTag)
                                    
                                    tags = Array(Set(tags)) // remove duplicate items
                                    
                                    wallpaper.project.tags = tags.sorted()
                                    
                                    guard let data = try? JSONEncoder().encode(wallpaper.project) else { return }
                                    
                                    try? data.write(to: wallpaper.wallpaperDirectory.appending(path: "project.json"), options: .atomic)
                                    
                                    wallpaperViewModel.inspect(wallpaper)
                                }
                        }
                    }
                    GlassGroup(spacing: 6) {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Button {
                                    wallpaperViewModel.applyInspectedWallpaper()
                                } label: {
                                    Label("Set Wallpaper", systemImage: "checkmark.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .glassButtonStyle(.prominent)

                                Button(role: .destructive) {
                                    viewModel.hoveredWallpaper = wallpaperViewModel.displayedWallpaper
                                    viewModel.isUnsubscribeConfirming = true
                                } label: {
                                    Label("Delete wallpaper", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                                .glassButtonStyle()
                                .help("Delete wallpaper")
                            }
                            Button {
                                AppDelegate.shared.showSceneInspector(for: wallpaperViewModel.displayedWallpaper,
                                                                      scopes: wallpaperViewModel.editedPropertyScopes(of: wallpaperViewModel.displayedWallpaper))
                            } label: {
                                Label("Scene Editor", systemImage: "square.stack.3d.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .glassButtonStyle()
                            .help("Scene Editor", shortcut: .sceneInspector)
                        }
                    }
                    // MARK: Properties
                    CollapsibleSection(title: "Properties") {
                        VStack(alignment: .leading, spacing: 16) {
                            if wallpaperViewModel.displayedWallpaper.project.workshopid == nil {
                                Picker("Age Rating", selection: Binding(
                                    get: { wallpaperViewModel.displayedWallpaper.project.contentrating ?? "Everyone" },
                                    set: { wallpaperViewModel.setContentRating($0, for: wallpaperViewModel.displayedWallpaper) }
                                )) {
                                    ForEach(WorkshopTags.ratings, id: \.self) { rating in
                                        Text(LocalizedLabels.filterOption(rating)).tag(rating)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            HStack {
                                Label("Placement", systemImage: "arrow.up.left.and.arrow.down.right")
                                infoButton(SceneHelp.placement)
                                Spacer()
                                Picker("", selection: $wallpaperViewModel.wallpaperPlacement) {
                                    ForEach(WallpaperPlacement.allCases) { placement in
                                        Text(placement.label).tag(placement)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                            switch wallpaperViewModel.displayedWallpaper.project.type.lowercased() {
                            case "video", "remote-video":
                                HStack {
                                    Label("Volume", systemImage: "speaker.wave.3.fill")
                                    infoButton(SceneHelp.volume)
                                    Spacer()
                                    NumericSliderInput(value: $wallpaperViewModel.playVolume, range: 0...1,
                                                       defaultValue: 1, displayScale: 100, suffix: "%",
                                                       fractionDigits: 0, sliderWidth: 100, fieldWidth: 36)
                                }
                                HStack {
                                    Label("Video Speed", systemImage: "play.fill")
                                    infoButton(SceneHelp.videoSpeed)
                                    Spacer()
                                    NumericSliderInput(value: $wallpaperViewModel.playRate, range: 0...2,
                                                       defaultValue: 1, step: 0.1, suffix: "x",
                                                       fractionDigits: 2, sliderWidth: 100, fieldWidth: 42)
                                }
                                HStack {
                                    Label("Audio Speed", systemImage: "waveform")
                                    infoButton(SceneHelp.audioSpeed)
                                    Spacer()
                                    Button {
                                        wallpaperViewModel.arePlaybackRatesLinked.toggle()
                                    } label: {
                                        Image(systemName: "link")
                                            .foregroundStyle(wallpaperViewModel.arePlaybackRatesLinked ? Color.primary : .gray)
                                    }
                                    .buttonStyle(.plain)
                                    .help(SceneHelp.linkRates)
                                    NumericSliderInput(value: $wallpaperViewModel.audioPlayRate, range: 0...2,
                                                       defaultValue: 1, step: 0.1, suffix: "x",
                                                       fractionDigits: 2, sliderWidth: 76, fieldWidth: 42)
                                        .disabled(wallpaperViewModel.arePlaybackRatesLinked)
                                }
                            case "scene":
                                MissingWorkshopDependenciesBanner(steamCmd: viewModel.steamCmd,
                                                                  dependencies: AppDelegate.shared.workshopDependencies,
                                                                  wallpaper: wallpaperViewModel.displayedWallpaper)
                                    .id(wallpaperViewModel.displayedWallpaper.wallpaperDirectory)
                                if wallpaperHasSceneAudio(wallpaperViewModel.displayedWallpaper) {
                                    sceneMusicControls(for: wallpaperViewModel.displayedWallpaper)
                                }
                            case "web":
                                ChromiumFeatureBadge(wallpaper: wallpaperViewModel.displayedWallpaper)
                                    .id(wallpaperViewModel.displayedWallpaper.wallpaperDirectory)
                            default:
                                EmptyView()
                            }
                            screenSaverStatusRow
                        }
                    }
                    SceneUserPropertiesView(wallpaper: wallpaperViewModel.displayedWallpaper,
                                            scopes: wallpaperViewModel.editedPropertyScopes(of: wallpaperViewModel.displayedWallpaper),
                                            resetRequest: propertyResets)
                        .id([wallpaperViewModel.displayedWallpaper.wallpaperDirectory.path]
                            + wallpaperViewModel.editedPropertyScopes(of: wallpaperViewModel.displayedWallpaper).map(\.description)
                            + [String(presetApplications)])
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            Text("Your Presets")
                            VStack {
                                Divider()
                                    .frame(height: 1)
                                    .overlay(Color.accentColor)
                            }
                        }
                        WallpaperPresetsSection(wallpaper: wallpaperViewModel.displayedWallpaper,
                                                scopes: wallpaperViewModel.editedPropertyScopes(of: wallpaperViewModel.displayedWallpaper),
                                                onApply: { presetApplications += 1 })
                            .id([wallpaperViewModel.displayedWallpaper.wallpaperDirectory.path]
                                + wallpaperViewModel.editedPropertyScopes(of: wallpaperViewModel.displayedWallpaper).map(\.description))
                        // WE's Reset, last in its properties' action rows.
                        Button {
                            isConfirmingPropertyReset = true
                        } label: {
                            Label("Reset", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .glassButtonStyle(.prominent)
                        .tint(.red)
                        .help(PropertyResetConfirmation.help)
                    }
                    .alert(PropertyResetConfirmation.title, isPresented: $isConfirmingPropertyReset) {
                        Button("Reset", role: .destructive) { propertyResets += 1 }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        let wallpaper = wallpaperViewModel.displayedWallpaper
                        Text(verbatim: PropertyResetConfirmation.message(
                            title: wallpaper.project.displayTitle,
                            scopes: wallpaperViewModel.editedPropertyScopes(of: wallpaper)))
                    }
                }
                .blur(radius: wallpaperViewModel.displayedWallpaper.project == .invalid ? 16.0 : 0)
                .overlay {
                    if wallpaperViewModel.displayedWallpaper.project == .invalid {
                        Text("Please select a valid wallpaper")
                    }
                }
                .disabled(wallpaperViewModel.displayedWallpaper.project == .invalid ? true : false)
                .animation(.default, value: wallpaperViewModel.displayedWallpaper.project)
                .padding([.horizontal, .top])
                .padding(.bottom)
            }
        }
    }

    private static var sceneAudioPresenceCache: [String: Bool] = [:]

    private func wallpaperHasSceneAudio(_ wallpaper: WEWallpaper) -> Bool {
        let key = wallpaper.wallpaperDirectory.path
        if let cached = Self.sceneAudioPresenceCache[key] { return cached }
        let extensions: Set<String> = ["mp3", "ogg", "wav", "m4a", "flac"]
        let fm = FileManager.default
        var found = false
        if let enumerator = fm.enumerator(at: wallpaper.wallpaperDirectory, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if extensions.contains(url.pathExtension.lowercased()) {
                    found = true
                    break
                }
                if url.pathExtension.lowercased() == "pkg",
                   let data = try? Data(contentsOf: url),
                   let parser = try? PKGParser(data: data),
                   parser.fileList.contains(where: { extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) {
                    found = true
                    break
                }
            }
        }
        Self.sceneAudioPresenceCache[key] = found
        return found
    }

    private var favoriteControl: some View {
        let wallpaper = wallpaperViewModel.displayedWallpaper
        let isFavorite = favorites.contains(wallpaper)
        let subscriptions = wallpaperViewModel.inspectedWorkshopItem?.subscriptions ?? 0
        return Button {
            favorites.toggle(wallpaper)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(isFavorite ? Color.red : Color.secondary)
                if subscriptions > 0 {
                    Text(formatCount(subscriptions))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }

    private func sceneMusicControls(for wallpaper: WEWallpaper) -> some View {
        let enabledKey = "SceneMusicEnabled.\(wallpaper.wallpaperDirectory.path)"
        let volumeKey = "SceneMusicVolume.\(wallpaper.wallpaperDirectory.path)"
        let enabled = Binding<Bool>(
            get: { UserDefaults.app.object(forKey: enabledKey) == nil ? true : UserDefaults.app.bool(forKey: enabledKey) },
            set: {
                UserDefaults.app.set($0, forKey: enabledKey)
                musicSync.objectWillChange.send()
                NotificationCenter.default.post(name: .sceneMusicSettingsDidChange, object: nil,
                                                userInfo: ["path": wallpaper.wallpaperDirectory.path])
            }
        )
        let volume = Binding<Double>(
            get: { UserDefaults.app.object(forKey: volumeKey) == nil ? 1 : UserDefaults.app.double(forKey: volumeKey) },
            set: {
                UserDefaults.app.set($0, forKey: volumeKey)
                musicSync.objectWillChange.send()
                NotificationCenter.default.post(name: .sceneMusicSettingsDidChange, object: nil,
                                                userInfo: ["path": wallpaper.wallpaperDirectory.path])
            }
        )
        return VStack(alignment: .leading, spacing: 8) {
            Toggle("Scene Music", isOn: enabled)
                .toggleStyle(.checkbox)
                .help(SceneHelp.sceneMusic)
            if enabled.wrappedValue {
                HStack {
                    Label("Scene Music Volume", systemImage: "music.note")
                    infoButton(SceneHelp.sceneMusicVolume)
                    Spacer()
                    NumericSliderInput(value: volume, range: 0...1,
                                       defaultValue: 1, displayScale: 100, suffix: "%",
                                       fractionDigits: 0, sliderWidth: 100, fieldWidth: 36)
                }
            }
        }
    }
    
    /// Shows all tags about current wallpaper in horizontal: project.json's, then the Workshop
    /// item's. Only project.json's can be removed here.
    var tags: some View {
        HStack {
            let tags = viewModel.tags(of: wallpaperViewModel.displayedWallpaper)
            let projectTags = wallpaperViewModel.displayedWallpaper.project.tags ?? []
            if !tags.isEmpty {
                ForEach(tags, id: \.self) { tag in
                    Text(LocalizedLabels.filterOption(tag))
                        .padding(5)
                        .padding(.horizontal, 2)
                        .glassBackground(in: Capsule()) { pill in
                            // Before glass: a frosted pill with the old outline.
                            pill.background {
                                Capsule().fill(.regularMaterial)
                                Capsule().stroke(Color.secondary, lineWidth: 1.6)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if hoveredTag == tag, projectTags.contains(tag) {
                                Button {
                                    var wallpaper = wallpaperViewModel.displayedWallpaper
                                    
                                    guard var tags = wallpaper.project.tags else { return } // else case seems impossible, however much safer
                                    
                                    tags = Array(Set(tags)) // remove duplicate items
                                    
                                    guard let index = tags.firstIndex(where: { $0 == tag }) else { return }
                                    
                                    tags.remove(at: index)
                                    
                                    wallpaper.project.tags = tags
                                    
                                    guard let data = try? JSONEncoder().encode(wallpaper.project) else { return }
                                    
                                    try? data.write(to: wallpaper.wallpaperDirectory.appending(path: "project.json"), options: .atomic)
                                    
                                    wallpaperViewModel.inspect(wallpaper)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white, .red)
                                .symbolRenderingMode(.palette)
                                .offset(x: 5, y: -2.5)
                            }
                        }
                        .onHover { hovered in
                            if hovered {
                                hoveredTag = tag
                            } else {
                                hoveredTag = nil
                            }
                        }
                }
            } else {
                Text("No Tags")
                    .foregroundStyle(Color.secondary)
            }
            
            if isTagsHovered {
                Button {
                    isEditingId = "tags"
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.footnote)
        .lineLimit(1)
    }

    private func formatCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    private func infoButton(_ help: String) -> some View {
        InfoTip(help)
    }
}

/// A web wallpaper that uses APIs only Chromium has (`ChromiumFeatureAdvisor`): a small badge in
/// its details, with the APIs in its tooltip. The wallpaper is scanned when its details show.
private struct ChromiumFeatureBadge: View {
    let wallpaper: WEWallpaper
    @ObservedObject private var advisor = ChromiumFeatureAdvisor.shared
    @ObservedObject private var router = WebEngineRouter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Which engine plays it: Automatic (Chromium only when needed), or forced.
            Picker("Web engine", selection: Binding(get: { router.override(for: wallpaper) },
                                                    set: { router.setOverride($0, for: wallpaper) })) {
                Text("Automatic").tag(WebEngineOverride.automatic)
                Text(verbatim: "WebKit").tag(WebEngineOverride.webKit)
                Text(verbatim: "Chromium").tag(WebEngineOverride.chromium)
                    .selectionDisabled(!router.installed)
            }
            .pickerStyle(.menu)
            .help("Automatic plays this wallpaper in Chromium only if it uses Chromium-only features and the engine is installed; otherwise in WebKit, which uses far less memory.")
            badge
        }
        .task { await advisor.scan(wallpaper) }
    }

    @ViewBuilder private var badge: some View {
        Group {
            if let features = advisor.features(of: wallpaper), !features.isEmpty {
                Label("Some features only available on Chromium", systemImage: "globe.badge.chevron.backward")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .help(Text(verbatim: features.map(\.api).joined(separator: ", ")))
                    .accessibilityValue(Text(verbatim: features.map(\.api).joined(separator: ", ")))
            }
        }
    }
}

/// Shows when a scene wallpaper references effects/materials that live in another Steam Workshop
/// item that isn't installed locally, and lets the user download + link them in. Items that were
/// removed, made private or belong to another app are named with the reason and a link to their
/// Workshop page; the wallpaper plays without them.
private struct MissingWorkshopDependenciesBanner: View {
    @ObservedObject var steamCmd: SteamCmdService
    @ObservedObject var dependencies: WorkshopDependencyService
    let wallpaper: WEWallpaper

    @State private var missingIds: [String] = []

    private var unavailableIds: [String] { missingIds.filter { dependencies.unavailableReason(for: $0) != nil } }
    private var downloadableIds: [String] { missingIds.filter { dependencies.unavailableReason(for: $0) == nil } }

    var body: some View {
        Group {
            if !missingIds.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        if !downloadableIds.isEmpty {
                            Label("This wallpaper needs \(downloadableIds.count) other Workshop items to render correctly.",
                                  systemImage: "shippingbox")
                                .font(.footnote)
                        }
                        if !unavailableIds.isEmpty {
                            Label("\(unavailableIds.count) required Workshop items are unavailable",
                                  systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                        }
                        ForEach(missingIds, id: \.self) { workshopId in
                            row(for: workshopId)
                        }
                        if !unavailableIds.isEmpty {
                            Button("Retry") {
                                dependencies.retry(Set(unavailableIds), forItemAt: wallpaper.wallpaperDirectory)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        if downloadableIds.isEmpty {
                            // Nothing left to download.
                        } else if !steamCmd.isInstalled || !steamCmd.isLoggedIn {
                            Text("Log in on the Workshop tab to download these.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Download All") {
                                for workshopId in downloadableIds {
                                    steamCmd.downloadWorkshopItem(workshopId: workshopId, asDependency: true)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: steamCmd.downloadProgress) { _ in
            for workshopId in missingIds where steamCmd.downloadProgress[workshopId] == .completed {
                WorkshopDependencyResolver.linkInstalledDependencies(for: wallpaper)
            }
            refresh()
        }
    }

    @ViewBuilder
    private func row(for workshopId: String) -> some View {
        if let reason = dependencies.unavailableReason(for: workshopId) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(workshopId).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if let page = WorkshopItemAvailability.workshopPageURL(for: workshopId) {
                        Link("Open in Workshop", destination: page).font(.caption)
                    }
                }
                Text(reason.message).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text(workshopId).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                statusView(for: workshopId)
            }
        }
    }

    @ViewBuilder
    private func statusView(for workshopId: String) -> some View {
        switch steamCmd.downloadProgress[workshopId] {
        case .downloading(let status):
            Text(status).font(.caption).foregroundStyle(.secondary)
        case .completed:
            Label("Linked", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    private func refresh() {
        missingIds = Array(WorkshopDependencyResolver.missingWorkshopIds(for: wallpaper)).sorted()
    }
}

extension URL {
    /// check if the URL is a directory and if it is reachable
    func isDirectoryAndReachable() throws -> Bool {
        guard try resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            return false
        }
        return try checkResourceIsReachable()
    }

    /// returns total allocated size of a the directory including its subFolders or not
    func directoryTotalAllocatedSize(includingSubfolders: Bool = false) throws -> Int? {
        guard try isDirectoryAndReachable() else { return nil }
        if includingSubfolders {
            guard
                let urls = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil)?.allObjects as? [URL] else { return nil }
            return try urls.lazy.reduce(0) {
                    (try $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) + $0
            }
        }
        return try FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil).lazy.reduce(0) {
                 (try $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                    .totalFileAllocatedSize ?? 0) + $0
        }
    }
}
