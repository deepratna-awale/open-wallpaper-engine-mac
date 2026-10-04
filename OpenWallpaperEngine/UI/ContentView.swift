//
//  ContentView.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/6/5.
//

import SwiftUI

protocol SubviewOfContentView: View {
    var viewModel: ContentViewModel { get set }
}

struct ContentView: View {
    @EnvironmentObject var globalSettingsViewModel: GlobalSettingsViewModel
    
    @ObservedObject var viewModel: ContentViewModel
    
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    
    @State private var isRemoteWallpaperSheetPresented = false
    /// Raises the "needs Chromium" alert for a wallpaper just applied.
    @ObservedObject private var chromiumAdvisor = ChromiumFeatureAdvisor.shared
    /// Picked on the setup assistant's last step; opened once the sheet has closed.
    @State private var onboardingShortcut: OnboardingShortcut?

    private var tab: Int { viewModel.topTabBarSelection }

    /// Installed, the Workshop browser and Playlists have a sidebar; Downloads doesn't.
    private var hasSidebar: Bool {
        switch tab {
        case 0, 3: return true
        case 1: return viewModel.steamCmd.isInstalled && viewModel.steamCmd.isLoggedIn
        default: return false
        }
    }

    /// The filter panes share one state, as they did before; the playlist list has its own.
    private var isSidebarRevealed: Bool {
        tab == 3 ? viewModel.isPlaylistSidebarReveal : viewModel.isFilterReveal
    }

    private func setSidebarRevealed(_ revealed: Bool) {
        if tab == 3 {
            viewModel.isPlaylistSidebarReveal = revealed
        } else {
            viewModel.isFilterReveal = revealed
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { hasSidebar && isSidebarRevealed ? .all : .detailOnly },
            set: { visibility in
                guard hasSidebar else { return }
                let revealed = visibility != .detailOnly
                if revealed != isSidebarRevealed { setSidebarRevealed(revealed) }
            }
        )
    }

    private var isDetailsPresented: Binding<Bool> {
        Binding(
            get: { tab == 0 && viewModel.isDetailsReveal },
            set: { presented in
                if tab == 0 { viewModel.isDetailsReveal = presented }
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            sidebar
        } detail: {
            detail
                // Scenes can't draw without the assets; the library says so while they're missing.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if tab == 0 { AssetsMissingBanner(assets: AppDelegate.shared.assets) }
                }
                .inspector(isPresented: isDetailsPresented) {
                    Group {
                        if viewModel.isStaging {
                            WallpaperPreview(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel)
                        }
                    }
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                }
                .toolbar { mainToolbar }
        }
        // Frosted: the live wallpaper shows through the window, blurred, under the panes.
        .frostedWindowBackground()
        .confirmationDialog("Unsubscribe Confirmation",
                            isPresented: $viewModel.isUnsubscribeConfirming) {
            if let url = viewModel.hoveredWallpaper?.wallpaperDirectory {
                Button("Delete Immediately", role: .destructive) {
                    if (try? FileManager.default.removeItem(at: url)) != nil {
                        viewModel.forgetDeletedWallpaper(at: url)
                    }
                    wallpaperViewModel.removeWallpaperFromAllScreens(directory: url)
                    viewModel.hoveredWallpaper = nil
                    viewModel.removeUnusedWorkshopDependencies()
                }
                Button("Move to Trash") {
                    if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                        viewModel.forgetDeletedWallpaper(at: url)
                    }
                    wallpaperViewModel.removeWallpaperFromAllScreens(directory: url)
                    viewModel.hoveredWallpaper = nil
                    viewModel.removeUnusedWorkshopDependencies()
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.hoveredWallpaper = nil
            }
        } message: {
            Text(verbatim: viewModel.hoveredWallpaper?.project.displayTitle ?? "")
        }
        .confirmationDialog("Batch Unsubscribe Confirmation",
                            isPresented: $viewModel.isBatchUnsubscribeConfirming) {
            Button("Delete All \(viewModel.selectedWallpapers.count) Immediately", role: .destructive) {
                for url in viewModel.selectedWallpapers {
                    if (try? FileManager.default.removeItem(at: url)) != nil {
                        viewModel.forgetDeletedWallpaper(at: url)
                    }
                    wallpaperViewModel.removeWallpaperFromAllScreens(directory: url)
                }
                viewModel.clearSelection()
                viewModel.removeUnusedWorkshopDependencies()
            }
            Button("Move All \(viewModel.selectedWallpapers.count) to Trash") {
                for url in viewModel.selectedWallpapers {
                    if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                        viewModel.forgetDeletedWallpaper(at: url)
                    }
                    wallpaperViewModel.removeWallpaperFromAllScreens(directory: url)
                }
                viewModel.clearSelection()
                viewModel.removeUnusedWorkshopDependencies()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            batchUnsubscribeMessage
        }
        .alert(isPresented: $viewModel.importAlertPresented, error: viewModel.importAlertError) {

        }
        .sheet(isPresented: onboardingPresented, onDismiss: openOnboardingShortcut) {
            OnboardingView(steamCmd: viewModel.steamCmd,
                           installer: AppDelegate.shared.steamCmdInstaller,
                           assets: AppDelegate.shared.assets,
                           imports: AppDelegate.shared.onboardingImports,
                           onShortcut: { onboardingShortcut = $0 })
                .environmentObject(globalSettingsViewModel)
                .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: $viewModel.isCollectionImportPresented) {
            WorkshopCollectionImportView(model: AppDelegate.shared.onboardingImports.collection)
                .frame(width: 680, height: 560)
                .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: $viewModel.isSteamLibraryImportPresented) {
            SteamLibraryImportView(model: AppDelegate.shared.onboardingImports.library)
                .frame(width: 680, height: 560)
                .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: $viewModel.isUnsafeWallpaperWarningPresented) {
            UnsafeWallpaper(wallpaper: wallpaperViewModel.nextCurrentWallpaper)
                .frame(width: 600, height: 300)
                .presentationBackground(.regularMaterial)
        }
        // Non-blocking: the wallpaper already plays in WebKit while this is up.
        .alert("This wallpaper uses features that need the Chromium web engine",
               isPresented: chromiumAdvicePresented, presenting: chromiumAdvisor.pendingAdvice) { advice in
            Button("Open Plugins") { chromiumAdvisor.openPlugins(advice) }
            Button("Use Anyway", role: .cancel) { chromiumAdvisor.useAnyway(advice) }
        } message: { advice in
            Text("\(advice.title) uses \(advice.featureList), which the system's WebKit doesn't have. Install the Chromium web engine in Settings › Plugins to play it as in Wallpaper Engine.",
                 comment: "First %@ is the wallpaper's title, the second a list of web APIs such as navigator.serial, EyeDropper")
        }
        .sheet(isPresented: $isRemoteWallpaperSheetPresented) {
            RemoteWallpaperURLSheet(wallpaperViewModel: wallpaperViewModel)
                .frame(width: 500, height: 180)
                .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: $viewModel.isDisplaySettingsReveal) {
            DisplaySettings(viewModel: viewModel)
                .padding()
                .frame(width: 520, height: 450)
                .presentationBackground(.regularMaterial)
        }
        .overlay(alignment: .bottomTrailing) {
            if ThreadGuards.isDevBuild { ThreadGuardIndicator() }
        }
        .frame(minWidth: 1000, minHeight: 640, idealHeight: 800)
    }

    private var chromiumAdvicePresented: Binding<Bool> {
        Binding(get: { chromiumAdvisor.pendingAdvice != nil },
                set: { if !$0 { chromiumAdvisor.pendingAdvice = nil } })
    }

    private func openOnboardingShortcut() {
        defer { onboardingShortcut = nil }
        switch onboardingShortcut {
        case .installed: viewModel.topTabBarSelection = 0
        case .workshop: viewModel.topTabBarSelection = 1
        case .displaySettings: viewModel.isDisplaySettingsReveal = true
        case nil: break
        }
    }

    /// Up to three titles, then "and N more", as one list in the user's language.
    private var batchUnsubscribeMessage: Text {
        let items = viewModel.selectedWallpaperItems()
        var names: [String] = items.prefix(3).map(\.project.displayTitle)
        if items.count > 3 {
            names.append(String(localized: "\(items.count - 3) more", comment: "Ends a list of wallpaper titles: and 2 more"))
        }
        let list: String = names.formatted(.list(type: .and))
        return Text("Unsubscribe \(items.count) wallpapers: \(list)", comment: "%@ lists the wallpaper titles")
    }

    // MARK: Columns

    /// The main toolbar has its own sidebar button, labelled for the tab, instead of the system one.
    private var sidebar: some View {
        ZStack {
            sidebarContent
        }
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewColumnWidth(min: tab == 3 ? 220 : 200, ideal: tab == 3 ? 260 : 225, max: 360)
    }

    /// Every sidebar stays alive and only the current tab's is shown, so switching tabs keeps each
    /// sidebar's scroll position and collapsed sections instead of rebuilding it.
    @ViewBuilder private var sidebarContent: some View {
        if viewModel.isStaging {
            keptAlive(FilterResults(viewModel: viewModel), isShown: tab == 0)
            if viewModel.steamCmd.isInstalled && viewModel.steamCmd.isLoggedIn {
                keptAlive(WorkshopFiltersSidebar(viewModel: viewModel.workshopVM), isShown: tab == 1)
            }
            keptAlive(PlaylistSidebar(wallpaperViewModel: wallpaperViewModel), isShown: tab == 3)
        }
    }

    private func keptAlive(_ view: some View, isShown: Bool) -> some View {
        view
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
    }

    private var detail: some View {
        ZStack {
            if viewModel.isStaging {
                tabContent
                    .transition(.modifier(active: StagingFade(isStaged: false),
                                          identity: StagingFade(isStaged: true)))
            } else {
                // indicate that this view is initializing
                Text("Power Saving Mode, Sleeping...")
                    .font(.largeTitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case 0:
            WallpaperExplorer(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel)
                .onDrop(of: [.fileURL], delegate: viewModel)
                .contextMenu {
                    ExplorerGlobalMenu(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel)
                }
                .padding()
                .modifier(ExplorerTopBar(contentViewModel: viewModel,
                                         onAddURL: { isRemoteWallpaperSheetPresented = true }))
        case 1:
            WorkshopView(contentViewModel: viewModel)
        case 2:
            DownloadsView(steamCmd: viewModel.steamCmd)
        case 3:
            PlaylistView(wallpaperViewModel: wallpaperViewModel)
        default:
            EmptyView()
        }
    }

    /// The setup assistant, or only its notice step when setup is done but the Terms of Use and
    /// Privacy Policy notice is due.
    private var onboardingPresented: Binding<Bool> {
        Binding(get: { globalSettingsViewModel.isFirstLaunch || globalSettingsViewModel.needsLegalNotice },
                set: { presented in
                    guard !presented else { return }
                    globalSettingsViewModel.isFirstLaunch = false
                    globalSettingsViewModel.needsLegalNotice = LegalNotice.isDue(in: .app)
                })
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if hasSidebar {
                Button {
                    withAnimation { setSidebarRevealed(!isSidebarRevealed) }
                } label: {
                    Label(tab == 3 ? "Playlists" : "Filter Results", systemImage: "sidebar.left")
                }
                .help(tab == 3 ? "Show or hide the playlist list" : "Show or hide the filters")
            }
        }
        ToolbarItem(placement: .principal) {
            TopTabBar(contentViewModel: viewModel)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.isDisplaySettingsReveal = true
            } label: {
                Label("Displays", systemImage: "display")
            }
            .help("Display Settings")
            Button {
                AppDelegate.shared.openSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings", shortcut: .settings)
            if tab == 0 {
                Button {
                    withAnimation { viewModel.isDetailsReveal.toggle() }
                } label: {
                    Label("Details", systemImage: "sidebar.right")
                }
                .help("Show or hide the wallpaper details")
            }
        }
    }
}

/// The content fades in from a slight blur when the window restages it.
private struct StagingFade: ViewModifier {
    let isStaged: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isStaged ? 1 : 0)
            .blur(radius: isStaged ? 0 : 2.0)
    }
}

private struct RemoteWallpaperURLSheet: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Video/Image URL").font(.headline)
            TextField("https://example.com/wallpaper.mp4", text: $urlString)
                .textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let url = URL(string: urlString),
                          ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                        error = String(localized: "Enter a valid HTTP or HTTPS image/video URL.")
                        return
                    }
                    let extensionName = url.pathExtension.lowercased()
                    guard ["jpg", "jpeg", "png", "gif", "webp", "heic", "mp4", "mov", "m4v", "webm"].contains(extensionName) else {
                        error = String(localized: "The URL must end in a supported image or video extension.")
                        return
                    }
                    wallpaperViewModel.addRemoteWallpaper(from: url)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .glassButtonStyle(.prominent)
            }
        }
        .padding(20)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: .init(isStaging: true), wallpaperViewModel: .init())
            .environmentObject(GlobalSettingsViewModel())
    }
}
