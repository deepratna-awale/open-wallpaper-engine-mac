//
//  WallpaperExplorer.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import SwiftUI

struct WallpaperExplorer: SubviewOfContentView {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @State private var isCreatePlaylistPresented = false
    @State private var footerHeight: CGFloat = 44

    init(contentViewModel viewModel: ContentViewModel, wallpaperViewModel: WallpaperViewModel) {
        self.viewModel = viewModel
        self.wallpaperViewModel = wallpaperViewModel
    }

    private func recomputePageSize(in geometry: GeometryProxy) {
        viewModel.updateInstalledItemsPerPage(for: CGSize(
            width: geometry.size.width,
            height: max(geometry.size.height - footerHeight - 8, 1)
        ))
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                if viewModel.displayedWallpapers.isEmpty {
                    // GeometryReader places its content top-leading, so the message takes the
                    // whole area to sit in its centre.
                    Text("No wallpapers found for your search.")
                        .font(.title)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVGrid(columns: [
                        GridItem(
                            .adaptive(
                                minimum: viewModel.explorerIconSize,
                                maximum: viewModel.explorerIconSize
                            ),
                            spacing: 8
                        )
                    ], alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.displayedWallpapers.enumerated()), id: \.0) { (index, wallpaper) in
                            ExplorerItem(viewModel: viewModel, wallpaperViewModel: wallpaperViewModel, wallpaper: wallpaper, index: index)
                                .contextMenu {
                                    ExplorerItemMenu(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel, current: wallpaper)
                                    ExplorerGlobalMenu(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel)
                                }
                                .animation(.spring(), value: viewModel.imageScaleIndex)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                GlassGroup {
                    VStack(spacing: 8) {
                        InstalledPagination(viewModel: viewModel)
                            .padding(.vertical, 8)
                        Button {
                            isCreatePlaylistPresented = true
                        } label: {
                            Label("Create Playlist", systemImage: "rectangle.stack.badge.plus")
                        }
                        .glassButtonStyle()
                        .disabled(viewModel.selectedWallpapers.isEmpty)
                    }
                }
                .background(GeometryReader { footer in
                    Color.clear.preference(key: ExplorerFooterHeightKey.self, value: footer.size.height)
                })
            }
            .onPreferenceChange(ExplorerFooterHeightKey.self) { height in
                footerHeight = height
            }
            .onAppear {
                recomputePageSize(in: geometry)
                viewModel.clampCurrentPage()
            }
            .onChange(of: geometry.size) { recomputePageSize(in: geometry) }
            // Tile size changes the row/column count, so the page size has to be recomputed too;
            // otherwise the grid overflows and pushes the footer controls out of view.
            .onChange(of: viewModel.explorerIconSize) { recomputePageSize(in: geometry) }
            .onChange(of: footerHeight) { recomputePageSize(in: geometry) }
            // Removing wallpapers or narrowing the search or filters can leave the current page past the last one.
            .onChange(of: viewModel.maxPage) { viewModel.clampCurrentPage() }
            .sheet(isPresented: $isCreatePlaylistPresented) {
                CreatePlaylistSheet(
                    wallpapers: viewModel.selectedWallpaperItems(),
                    wallpaperViewModel: wallpaperViewModel,
                    onComplete: {
                        viewModel.clearSelection()
                        isCreatePlaylistPresented = false
                    }
                )
                .frame(width: 480, height: 360)
                .presentationBackground(.regularMaterial)
            }
        }
    }
}

private struct ExplorerFooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 44
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CreatePlaylistSheet: View {
    let wallpapers: [WEWallpaper]
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    let onComplete: () -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Playlist").font(.title2.bold())
            TextField("Playlist name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("\(wallpapers.count) wallpapers will be added")
                .foregroundStyle(.secondary)
            List(wallpapers) { wallpaper in
                Text(verbatim: wallpaper.project.displayTitle)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onComplete)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard wallpaperViewModel.createPlaylist(named: name, wallpapers: wallpapers) else { return }
                    onComplete()
                }
                .keyboardShortcut(.defaultAction)
                .glassButtonStyle(.prominent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}

private struct InstalledPagination: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.currentPage -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(Text("Previous Page"))
            .disabled(viewModel.currentPage <= 1)

            ForEach(pageNumbers, id: \.self) { page in
                if page == viewModel.currentPage {
                    pageButton(page)
                        .glassButtonStyle(.prominent)
                } else {
                    pageButton(page)
                        .glassButtonStyle()
                }
            }

            Button {
                viewModel.currentPage += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(Text("Next Page"))
            .disabled(!viewModel.hasNextWallpaperPage)
        }
    }

    private var pageNumbers: [Int] {
        InstalledPageWindow.pageNumbers(current: viewModel.currentPage, total: viewModel.maxPage)
    }

    private func pageButton(_ page: Int) -> some View {
        Button("\(page)") {
            viewModel.currentPage = page
        }
    }
}

// MARK: - View Modifiers Extension
struct SelectedItem: ViewModifier {
    var selected: Bool
    
    init(_ selected: Bool) {
        self.selected = selected
    }
    
    func body(content: Content) -> some View {
        return content
            .border(Color.accentColor, width: selected ? 3 : 0)
    }
}

extension View {
    func selected(_ selected: Bool = true) -> some View {
        return modifier(SelectedItem(selected))
    }
}
