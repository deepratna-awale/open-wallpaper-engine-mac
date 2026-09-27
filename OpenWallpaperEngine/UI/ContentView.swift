//
//  ContentView.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/6/5.
//

import SwiftUI

protocol SubviewOfContentView: View {
    var viewModel: ContentViewModel { get set }
    
//    init(contentViewModel viewModel: ContentViewModel)
}

struct ContentView: View {
    @EnvironmentObject var globalSettingsViewModel: GlobalSettingsViewModel
    
    @ObservedObject var viewModel: ContentViewModel
    
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    
    @State private var isRemoteWallpaperSheetPresented = false

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
        .confirmationDialog("Unsubscribe Confirmation",
                            isPresented: $viewModel.isUnsubscribeConfirming) {
            if let url = viewModel.hoveredWallpaper?.wallpaperDirectory {
                Button("Delete Immediately", role: .destructive) {
                    if (try? FileManager.default.removeItem(at: url)) != nil {
                        DownloadedWallpaperIndex.shared.remove(directory: url)
                    }
                    wallpaperViewModel.removeWallpaperFromAllScreens(directory: url)
                    viewModel.hoveredWallpaper = nil
                    viewModel.removeUnusedWorkshopDependencies()
                }
                Button("Move to Trash") {
                    if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                        DownloadedWallpaperIndex.shared.remove(directory: url)
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
            Text("\(viewModel.hoveredWallpaper?.project.title ?? "invalid wallpaper")")
        }
        .confirmationDialog("Batch Unsubscribe Confirmation",
                            isPresented: $viewModel.isBatchUnsubscribeConfirming) {
            Button("Delete All \(viewModel.selectedWallpapers.count) Immediately", role: .destructive) {
                for url in viewModel.selectedWallpapers {
                    if (try? FileManager.default.removeItem(at: url)) != nil {
                        DownloadedWallpaperIndex.shared.remove(directory: url)
                    }
                    wallpaperViewModel.removeWallpaperFromAllScreens(directory: url)
                }
                viewModel.clearSelection()
                viewModel.removeUnusedWorkshopDependencies()
            }
            Button("Move All \(viewModel.selectedWallpapers.count) to Trash") {
                for url in viewModel.selectedWallpapers {
                    if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                        DownloadedWallpaperIndex.shared.remove(directory: url)
                    }
                    wallpaperViewModel.removeWallpaperFromAllScreens(directory: url)
                }
                viewModel.clearSelection()
                viewModel.removeUnusedWorkshopDependencies()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let items = viewModel.selectedWallpaperItems()
            let names = items.prefix(3).map(\.project.title).joined(separator: ", ")
            let suffix = items.count > 3 ? " and \(items.count - 3) more" : ""
            Text("Unsubscribe \(items.count) wallpapers: \(names)\(suffix)")
        }
        .alert(isPresented: $viewModel.importAlertPresented, error: viewModel.importAlertError) {

        }
        .sheet(isPresented: $globalSettingsViewModel.isFirstLaunch) {
            FirstLaunchView()
                .environmentObject(globalSettingsViewModel)
        }
        .sheet(isPresented: $viewModel.isUnsafeWallpaperWarningPresented) {
            UnsafeWallpaper(wallpaper: wallpaperViewModel.nextCurrentWallpaper)
                .frame(width: 600, height: 300)
        }
        .sheet(isPresented: $isRemoteWallpaperSheetPresented) {
            RemoteWallpaperURLSheet(wallpaperViewModel: wallpaperViewModel)
                .frame(width: 500, height: 180)
        }
        .sheet(isPresented: $viewModel.isDisplaySettingsReveal) {
            DisplaySettings(viewModel: viewModel)
                .padding()
                .frame(width: 520, height: 450)
        }
        .frame(minWidth: 1000, minHeight: 640, idealHeight: 800)
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
            .help("Settings")
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
                        error = "Enter a valid HTTP or HTTPS image/video URL."
                        return
                    }
                    let extensionName = url.pathExtension.lowercased()
                    guard ["jpg", "jpeg", "png", "gif", "webp", "heic", "mp4", "mov", "m4v", "webm"].contains(extensionName) else {
                        error = "The URL must end in a supported image or video extension."
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
