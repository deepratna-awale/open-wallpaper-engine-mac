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
    
    @State var isDropTargeted = false
    @State var isParseFinished = false
    @State var isFilterReveal = true
    
    @State var isDockIconHidden = false
    
    @State var project: WEProject!
    @State var projectUrl: URL!
    @State var greet: String = "Hello, world!"
    @State private var isRemoteWallpaperSheetPresented = false
    
    var body: some View {
        ZStack {
            HSplitView {
                if viewModel.isStaging {
                    VStack(spacing: 5) {
                        TopTabBar(contentViewModel: viewModel)
                        switch viewModel.topTabBarSelection {
                        case 0:
                            ExplorerTopBar(contentViewModel: viewModel)
                                .environmentObject(globalSettingsViewModel)
                            HStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    // MARK: Filter Results
                                    FilterResults(viewModel: viewModel)
                                }
                                .frame(width: viewModel.isFilterReveal ? 225 : 0)
                                .opacity(viewModel.isFilterReveal ? 1 : 0)
                                .animation(.spring(), value: viewModel.isFilterReveal)
                                
                                WallpaperExplorer(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel)
                                .onDrop(of: [.fileURL], delegate: viewModel)
                                .contextMenu {
                                    ExplorerGlobalMenu(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel)
                                }
                                .padding(.leading, viewModel.isFilterReveal ? 10 : 0)
                            }
                            .animation(.default, value: viewModel.isFilterReveal)
                        case 1:
                            WorkshopView(contentViewModel: viewModel)
                        case 2:
                            DownloadsView(steamCmd: viewModel.steamCmd)
                        case 3:
                            PlaylistView(wallpaperViewModel: wallpaperViewModel)
                        default:
                            fatalError()
                        }
                        if viewModel.topTabBarSelection == 0 {
                            HStack {
                                Button {
                                    AppDelegate.shared.openImportFromFolderPanel()
                                } label: {
                                    Label("Open Wallpaper", systemImage: "arrow.up.bin.fill")
                                        .frame(width: 220)
                                }
                                Button {
                                    AppDelegate.shared.openImportVideoPanel()
                                } label: {
                                    Label("Add Video Wallpaper", systemImage: "film.stack")
                                }
                                Button {
                                    isRemoteWallpaperSheetPresented = true
                                } label: {
                                    Label("Add Video/Image URL", systemImage: "link")
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding()
                    if viewModel.topTabBarSelection == 0 {
                        WallpaperPreview(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel)
                            .frame(maxWidth: 320)
                    }
                }
            }
            .opacity(viewModel.isStaging ? 1 : 0)
            .blur(radius: viewModel.isStaging ? 0 : 2.0)
            
            // indicate that this view is initializing
            if !viewModel.isStaging {
                HStack(spacing: 20) {
                    Text("Power Saving Mode, Sleeping...")
                        .font(.largeTitle)
                }
            }

            if viewModel.isDisplaySettingsReveal {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.isDisplaySettingsReveal = false
                    }

                DisplaySettings(viewModel: viewModel)
                    .padding()
                    .frame(width: 520, height: 450)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(8)
                    .shadow(radius: 20)
            }
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
        .frame(minWidth: 1000, minHeight: 640, idealHeight: 800)
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
                .buttonStyle(.borderedProminent)
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
