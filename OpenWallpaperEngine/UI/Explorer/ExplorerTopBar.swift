//
//  ExplorerTopBar.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import SwiftUI

/// The Installed tab's search and toolbar items, attached to the tab's content so they show in the
/// window toolbar only while that tab is selected.
struct ExplorerTopBar: ViewModifier {
    @ObservedObject var viewModel: ContentViewModel

    @EnvironmentObject var globalSettingsViewModel: GlobalSettingsViewModel

    /// Opens the sheet that adds a video or image by URL.
    let onAddURL: () -> Void

    init(contentViewModel viewModel: ContentViewModel, onAddURL: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onAddURL = onAddURL
    }

    func body(content: Content) -> some View {
        content
            .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("Open Wallpaper…", systemImage: "arrow.up.bin.fill") {
                            AppDelegate.shared.openImportFromFolderPanel()
                        }
                        Button("Add Video Wallpaper…", systemImage: "film.stack") {
                            AppDelegate.shared.openImportVideoPanel()
                        }
                        Button("Add Video/Image URL…", systemImage: "link", action: onAddURL)
                    } label: {
                        Label("Add Wallpaper", systemImage: "plus")
                    }
                    .help("Open a wallpaper, or add a video or an image")
                }
                ToolbarItemGroup {
                    if !viewModel.selectedWallpapers.isEmpty {
                        Button(role: .destructive) {
                            viewModel.isBatchUnsubscribeConfirming = true
                        } label: {
                            Label("Delete Selected (\(viewModel.selectedWallpapers.count))", systemImage: "trash")
                        }
                        .labelStyle(.titleAndIcon)
                        .help("Unsubscribe from the selected wallpapers")
                    }
                    if globalSettingsViewModel.settings.autoRefresh {
                        Button {
                            viewModel.refresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .help("Refresh the wallpaper list")
                    }
                }
                ToolbarItemGroup {
                    Button {
                        if viewModel.sortingSequence == .decrease {
                            viewModel.sortingSequence = .increase
                        } else {
                            viewModel.sortingSequence = .decrease
                        }
                    } label: {
                        Label(viewModel.sortingSequence == .increase ? "Ascending" : "Descending",
                              systemImage: viewModel.sortingSequence == .increase ?
                              "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .help(viewModel.sortingSequence == .increase
                          ? "Sorted ascending. Click to sort descending."
                          : "Sorted descending. Click to sort ascending.")
                    Picker("Sort By", selection: $viewModel.sortingBy) {
                        ForEach(WEWallpaperSortingMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Sort By")
                }
            }
    }
}
