import SwiftUI

struct WorkshopView: SubviewOfContentView {
    @ObservedObject var viewModel: ContentViewModel

    init(contentViewModel viewModel: ContentViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.steamCmd.isInstalled {
                SteamCmdNotInstalledView(steamCmd: viewModel.steamCmd)
            } else if !viewModel.steamCmd.isLoggedIn {
                SteamLoginView(steamCmd: viewModel.steamCmd)
            } else {
                WorkshopBrowserView(
                    viewModel: viewModel.workshopVM,
                    contentViewModel: viewModel
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - steamcmd Not Installed

private struct SteamCmdNotInstalledView: View {
    @ObservedObject var steamCmd: SteamCmdService
    @ObservedObject private var installer = AppDelegate.shared.steamCmdInstaller
    @State private var isCopied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: installer.isBusy ? "arrow.down.circle" : "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text(installer.isBusy ? "Setting Up SteamCMD" : "steamcmd Not Found")
                    .font(.title2)
                    .bold()

                Text("Steam Workshop downloads use SteamCMD, Valve's command-line Steam client. Open Wallpaper Engine can download it from Valve for you.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)

                SteamCmdSetupView(installer: installer)

                if !installer.isBusy {
                    alternatives
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .onAppear { installer.detectThenAutoInstall(steamCmd) }
    }

    @ViewBuilder
    private var alternatives: some View {
        Divider().frame(width: 200)

        Text("Or install it with Homebrew:")
            .font(.callout)
            .foregroundStyle(.secondary)

        HStack {
            Text(verbatim: "brew install steamcmd")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassBackground(in: RoundedRectangle(cornerRadius: 8)) { snippet in
                    snippet
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install steamcmd", forType: .string)
                isCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
            } label: {
                Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .glassButtonStyle()
            .help(isCopied ? "Copied" : "Copy the command")
        }

        Text("Or locate an existing steamcmd binary:")
            .font(.callout)
            .foregroundStyle(.secondary)

        Button("Browse...") {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.message = String(localized: "Select the steamcmd executable", comment: "Open panel message; steamcmd is a program name")
            if panel.runModal() == .OK, let url = panel.url {
                steamCmd.setCustomPath(url.path)
            }
        }
        .glassButtonStyle()

        if let error = steamCmd.pathError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }

        Button("Re-detect") {
            steamCmd.detectSteamCmd()
        }
        .buttonStyle(.link)
        .font(.caption)
    }
}

// MARK: - Steam Login

private struct SteamLoginView: View {
    @ObservedObject var steamCmd: SteamCmdService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Steam Login")
                    .font(.title2)
                    .bold()

                SteamLoginForm(steamCmd: steamCmd)

                // API Key section
                VStack(spacing: 6) {
                    Divider().padding(.vertical, 8)
                    Text("You'll also need a Steam Web API key to browse the Workshop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SteamWebAPIKeyView()
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Workshop Browser

private struct WorkshopBrowserView: View {
    @ObservedObject var viewModel: WorkshopViewModel
    @ObservedObject var contentViewModel: ContentViewModel
    @State private var hasAPIKey = true
    /// Measured, so the page size leaves room for the pagination row whatever its style.
    @State private var footerHeight: CGFloat = 44

    private func updateItemsPerPage(in geometry: GeometryProxy) {
        let size = CGSize(width: geometry.size.width, height: max(geometry.size.height - footerHeight - 8, 1))
        Task {
            await viewModel.updateItemsPerPage(for: size, itemSize: contentViewModel.explorerIconSize - 5)
        }
    }

    var body: some View {
        workshopContent
            .padding(.horizontal)
            .padding(.top, 8)
            .onAppear { hasAPIKey = SteamCredentials.webAPIKey().load() != nil }
            .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search wallpapers...")
            .onSubmit(of: .search) {
                viewModel.currentPage = 1
                Task { await viewModel.search() }
            }
            .onChange(of: viewModel.searchText) { oldText, newText in
                // The field's clear button empties it: search again from the first page.
                guard newText.isEmpty, !oldText.isEmpty else { return }
                viewModel.currentPage = 1
                Task { await viewModel.search() }
            }
            .toolbar { browserToolbar }
            .confirmationDialog(
                "Download Selected Wallpapers",
                isPresented: $viewModel.isBatchDownloadConfirming
            ) {
                Button("Download \(viewModel.selectedItemIds.count) Wallpapers") {
                    viewModel.downloadSelectedItems()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Download \(viewModel.selectedItemIds.count) selected wallpapers to your library?")
            }
    }

    @ToolbarContentBuilder private var browserToolbar: some ToolbarContent {
        ToolbarItemGroup {
            if viewModel.authorId != nil {
                Label("Author Workshop", systemImage: "person.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.clearAuthorFilter()
                } label: {
                    Label("Clear author filter", systemImage: "xmark.circle.fill")
                }
                .help("Clear author filter")
            }
        }
        ToolbarItemGroup {
            if !viewModel.selectedItemIds.isEmpty {
                Button {
                    if viewModel.selectedItemIds.count > 1 {
                        viewModel.isBatchDownloadConfirming = true
                    } else {
                        viewModel.downloadSelectedItems()
                    }
                } label: {
                    Label("Download Selected (\(viewModel.selectedItemIds.count))", systemImage: "arrow.down.circle")
                }
                .labelStyle(.titleAndIcon)
                .help("Download the selected wallpapers")

                Button {
                    viewModel.clearSelection()
                } label: {
                    Label("Clear selection", systemImage: "xmark")
                }
                .help("Clear selection")
            }
        }
        ToolbarItem {
            Button {
                contentViewModel.isCollectionImportPresented = true
            } label: {
                Label("Import Workshop Collection…", systemImage: "square.stack.3d.down.right")
            }
            .help("Download the items of a Workshop collection")
        }
        ToolbarItem {
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(WorkshopSortOrder.allCases) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .pickerStyle(.menu)
            .help("Sort")
            .onChange(of: viewModel.sortOrder) {
                viewModel.currentPage = 1
                Task { await viewModel.search() }
            }
        }
    }

    private func searchWithNewKey() {
        hasAPIKey = true
        viewModel.currentPage = 1
        Task { await viewModel.search() }
    }

    private var workshopContent: some View {
        VStack(spacing: 8) {
            // Results
            if viewModel.isLoading && viewModel.items.isEmpty {
                Spacer()
                ProgressView("Searching Workshop...")
                Spacer()
            } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    SteamWebAPIKeyView(onSaved: searchWithNewKey)
                }
                Spacer()
            } else if viewModel.items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Search the Steam Workshop")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Find wallpapers by name, tag, or browse trending content.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)

                    if !hasAPIKey {
                        Divider().frame(width: 300).padding(.vertical, 4)
                        Text("A Steam Web API key is required to browse.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        SteamWebAPIKeyView(onSaved: searchWithNewKey)
                    }
                }
                Spacer()
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 8) {
                        LazyVGrid(columns: [
                            GridItem(
                                .adaptive(
                                    minimum: contentViewModel.explorerIconSize - 5,
                                    maximum: contentViewModel.explorerIconSize - 5
                                ),
                                spacing: 13
                            )
                        ], alignment: .leading, spacing: 13) {
                            ForEach(viewModel.visibleItems) { item in
                                WorkshopItemCard(item: item, viewModel: viewModel)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        WorkshopPagination(viewModel: viewModel)
                            .padding(.bottom, 8)
                            .background(GeometryReader { footer in
                                Color.clear.preference(key: WorkshopFooterHeightKey.self, value: footer.size.height)
                            })
                    }
                    .onPreferenceChange(WorkshopFooterHeightKey.self) { footerHeight = $0 }
                    .onAppear { updateItemsPerPage(in: geometry) }
                    .onChange(of: geometry.size) { updateItemsPerPage(in: geometry) }
                    .onChange(of: contentViewModel.explorerIconSize) { updateItemsPerPage(in: geometry) }
                    .onChange(of: footerHeight) { updateItemsPerPage(in: geometry) }
                }
            }
        }
        .task {
            if viewModel.items.isEmpty {
                await viewModel.search()
            }
        }
    }
}

private struct WorkshopFooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 44
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct WorkshopPagination: View {
    @ObservedObject var viewModel: WorkshopViewModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.currentPage -= 1
                Task { await viewModel.search() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(Text("Previous Page"))
            .disabled(viewModel.currentPage == 1 || viewModel.isLoading)

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
                Task { await viewModel.search() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(Text("Next Page"))
            .disabled(!viewModel.hasNextPage || viewModel.isLoading)
        }
    }

    private var pageNumbers: [Int] {
        let firstPage = max(1, viewModel.currentPage - 2)
        let lastPage = viewModel.hasNextPage ? viewModel.currentPage + 2 : viewModel.currentPage
        return Array(firstPage...lastPage)
    }

    private func pageButton(_ page: Int) -> some View {
        Button("\(page)") {
            viewModel.currentPage = page
            Task { await viewModel.search() }
        }
        .disabled(viewModel.isLoading)
    }
}

/// The Workshop tab's filters, in the main window's sidebar. Every change searches again.
/// Within Show Only, Rating, Type and Resolution any checked option matches (OR); genres match
/// all or any, as the toggle beside them says; the sections narrow the results together.
struct WorkshopFiltersSidebar: View {
    @ObservedObject var viewModel: WorkshopViewModel
    @State private var expandedSections: Set<String> = ["Show Only", "Rating", "Type", "Resolution", "Genre"]

    var body: some View {
        List {
            Button {
                viewModel.resetFilters()
            } label: {
                Label("Reset Filters", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle(.prominent)
            .listRowSeparator(.hidden)

            Section("Show Only:", isExpanded: isExpanded("Show Only")) {
                ShowOnlyFilterRows(
                    isOn: { index in
                        WorkshopShowOnly(rawValue: index).map(viewModel.filter.showOnly.contains) ?? false
                    },
                    set: { index, isOn in
                        guard let option = WorkshopShowOnly(rawValue: index) else { return }
                        viewModel.updateFilter { filter in
                            if isOn { filter.showOnly.insert(option) } else { filter.showOnly.remove(option) }
                        }
                    })
            }
            tagSection("Rating", id: "Rating", tags: WorkshopTags.ratings, \.ratings)
            tagSection("Type", id: "Type", tags: WorkshopTags.types, \.types)
            Section("Resolution", isExpanded: isExpanded("Resolution")) {
                ResolutionFilterRows(
                    isOn: { viewModel.filter.resolutions.contains($0) },
                    set: { tag, isOn in
                        viewModel.updateFilter { filter in
                            if isOn { filter.resolutions.insert(tag) } else { filter.resolutions.remove(tag) }
                        }
                    })
            }
            Section(isExpanded: isExpanded("Genre")) {
                ForEach(WorkshopTags.genres, id: \.self) { tag in
                    toggle(tag: tag, \.genres)
                }
            } header: {
                HStack {
                    Text("Genre")
                    Spacer()
                    genreMatchToggle
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// States the current genre mode and switches it.
    private var genreMatchToggle: some View {
        let matchesAll = viewModel.filter.genreMatch == .all
        return Button(matchesAll ? "Match all (AND)" : "Match any (OR)") {
            viewModel.updateFilter { $0.genreMatch = matchesAll ? .any : .all }
        }
        .buttonStyle(.link)
        .font(.caption)
        .help(matchesAll
              ? "Showing wallpapers with every checked genre. Click to show wallpapers with any of them."
              : "Showing wallpapers with any checked genre. Click to show only wallpapers with all of them.")
    }

    private func isExpanded(_ title: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(title) },
            set: { expanded in
                if expanded { expandedSections.insert(title) } else { expandedSections.remove(title) }
            }
        )
    }

    private func tagSection(_ title: LocalizedStringKey, id: String, tags: [String],
                            _ keyPath: WritableKeyPath<WorkshopFilter, Set<String>>) -> some View {
        Section(title, isExpanded: isExpanded(id)) {
            ForEach(tags, id: \.self) { tag in
                toggle(tag: tag, keyPath)
            }
        }
    }

    private func toggle(tag: String,
                        _ keyPath: WritableKeyPath<WorkshopFilter, Set<String>>) -> some View {
        Toggle(isOn: Binding(
            get: { viewModel.filter[keyPath: keyPath].contains(tag) },
            set: { isOn in
                viewModel.updateFilter { filter in
                    if isOn { filter[keyPath: keyPath].insert(tag) } else { filter[keyPath: keyPath].remove(tag) }
                }
            }
        )) {
            Text(LocalizedLabels.filterOption(tag))
        }
        .toggleStyle(.checkbox)
    }
}

// MARK: - Workshop Item Card

private struct WorkshopItemCard: View {
    let item: WorkshopItem
    @ObservedObject var viewModel: WorkshopViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: item.previewImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                case .failure:
                    placeholder
                default:
                    placeholder
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()

            VStack(spacing: 2) {
                Text(item.title)
                    .lineLimit(2)
                    .font(.footnote)
                if !shownTags.isEmpty {
                    Text(verbatim: shownTags.map { "\u{2068}\($0)\u{2069}" }.joined(separator: " · "))
                        .lineLimit(1)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(4)
            .background(Color(white: 0, opacity: 0.65))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
        }
        .help(shownTags.isEmpty ? item.title : "\(item.title)\n\(shownTags.formatted(.list(type: .and, width: .narrow)))")
        .overlay(alignment: .topTrailing) {
            downloadControl
                .padding(6)
                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
        }
        .overlay(alignment: .topLeading) {
            if !viewModel.selectedItemIds.isEmpty {
                Button {
                    viewModel.selectItem(item)
                } label: {
                    Image(systemName: viewModel.selectedItemIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.selectedItemIds.contains(item.id) ? Color.accentColor : .white)
                }
                .buttonStyle(.plain)
                .padding(6)
                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                .help("Select item")
            }
        }
        .border(Color(nsColor: .separatorColor), width: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            WorkshopItemMenu(item: item, viewModel: viewModel)
        }
        .onTapGesture {
            viewModel.selectItem(item)
        }
        .onTapGesture(count: 2) {
            viewModel.preview(item: item)
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        if viewModel.isPreviewLoading(item) {
            ProgressView()
                .controlSize(.small)
                .help("Preparing preview")
        } else {
        let state = viewModel.downloadState(for: item)
        switch state {
        case .downloading(let status):
            ProgressView()
                .controlSize(.small)
                .help(status)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Downloaded")
        case .failed(let msg):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(msg)
        case .none:
            if viewModel.steamCmd.isLoggedIn {
                Button {
                    viewModel.download(item: item)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Download")
            } else {
                Image(systemName: "person.badge.key")
                    .foregroundStyle(.secondary)
                    .help("Log in to download")
            }
        }
            }
    }

    /// The item's tags, without "Wallpaper", which every wallpaper has, in the UI's language.
    private var shownTags: [String] {
        item.tags.filter { $0.caseInsensitiveCompare("Wallpaper") != .orderedSame }
            .map { String(localized: LocalizedLabels.filterOption($0)) }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Workshop Item Context Menu

private struct WorkshopItemMenu: View {
    let item: WorkshopItem
    @ObservedObject var viewModel: WorkshopViewModel

    var body: some View {
        Button {
            viewModel.download(item: item)
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        .disabled(!viewModel.steamCmd.isLoggedIn || viewModel.isDownloaded(item))

        Menu("Add to Playlist") {
            let playlists = AppDelegate.shared.wallpaperViewModel.playlists
            if playlists.isEmpty {
                Text("Create a playlist first")
            } else {
                ForEach(playlists) { playlist in
                    Button {
                        viewModel.downloadAndAddToPlaylist(item, playlistID: playlist.id, wallpaperViewModel: AppDelegate.shared.wallpaperViewModel)
                    } label: {
                        Label(playlist.name, systemImage: "rectangle.stack")
                    }
                }
            }
        }
        .disabled(!viewModel.steamCmd.isLoggedIn)

        Button {
            viewModel.toggleFavorite(item)
        } label: {
            Label(viewModel.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: viewModel.isFavorite(item) ? "heart.slash" : "heart.fill")
        }
    }
}
