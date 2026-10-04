//
//  ContentViewModel.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import AVKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

private struct URLListStorage: RawRepresentable {
    var urls: [URL] = []

    init() {}

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let urls = try? JSONDecoder().decode([URL].self, from: data) else {
            return nil
        }
        self.urls = urls
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(urls),
              let value = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return value
    }
}

class ContentViewModel: ObservableObject, DropDelegate {
    @AppStorage("SortingBy", store: .app) var sortingBy: WEWallpaperSortingMethod = .name
    @AppStorage("SortingSequence", store: .app) var sortingSequence: WEWallpaperSortingSequence = .increase
    
    @AppStorage("FRShowOnly", store: .app)                   public var showOnly                     =                   FRShowOnly.all
    @AppStorage("FRType", store: .app)                       public var type                         =                       FRType.all
    @AppStorage("FRAgeRating", store: .app)                  public var ageRating                    =                  FRAgeRating.all
    @AppStorage("FRWidescreenResolution", store: .app)       public var widescreenResolution         =       FRWidescreenResolution.all
    @AppStorage("FRUltraWidescreenResolution", store: .app)  public var ultraWidescreenResolution    =  FRUltraWidescreenResolution.all
    @AppStorage("FRDualscreenResolution", store: .app)       public var dualscreenResolution         =       FRDualscreenResolution.all
    @AppStorage("FRTriplescreenResolution", store: .app)     public var triplescreenResolution       =     FRTriplescreenResolution.all
    @AppStorage("FRPortraitScreenResolution", store: .app)   public var potraitscreenResolution      =   FRPortraitScreenResolution.all
    @AppStorage("FRMiscResolution", store: .app)             public var miscResolution               =             FRMiscResolution.all
    @AppStorage("FRSource", store: .app)                     public var source                       =                     FRSource.all
    @AppStorage("FRTag", store: .app)                        public var tag                          =                        FRTag.all
    
    @AppStorage("FilterReveal", store: .app) var isFilterReveal = false
    @AppStorage("WallpaperURLs", store: .app) private var storedWallpaperUrls = URLListStorage()
    @AppStorage("SelectedIndex", store: .app) var selectedIndex = 0
    
    @AppStorage("ExplorerIconSize", store: .app) var explorerIconSize: Double = 200
    
    @Published var isDisplaySettingsReveal = false
    @Published var importAlertPresented = false
    @Published var isStaging = false
    
    @Published var topTabBarSelection: Int = 0
    /// The Workshop collection and Steam library imports (Installed's Add menu, the Workshop tab).
    @Published var isCollectionImportPresented = false
    @Published var isSteamLibraryImportPresented = false
    /// The Playlists tab's list of playlists, in the main window's sidebar.
    @Published var isPlaylistSidebarReveal = true
    /// The Installed tab's Details inspector.
    @Published var isDetailsReveal = true
    
    @Published var imageScaleIndex: Int = -1
    @Published var isApplicationActive = true
    
    @Published var wallpapers = [WEWallpaper]()
    
    @Published var isUnsafeWallpaperWarningPresented = false
    
    @Published var hoveredWallpaper: WEWallpaper?
    
    @Published var isUnsubscribeConfirming = false

    @Published var selectedWallpapers = Set<URL>()
    @Published var isBatchUnsubscribeConfirming = false
    private var selectionAnchor: URL?

    var wallpaperUrls: [URL] {
        get { storedWallpaperUrls.urls }
        set { storedWallpaperUrls.urls = newValue }
    }

    lazy var steamCmd: SteamCmdService = {
        let svc = SteamCmdService()
        steamCmdCancellable = svc.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        return svc
    }()
    lazy var workshopVM: WorkshopViewModel = WorkshopViewModel(steamCmd: steamCmd)
    private var steamCmdCancellable: AnyCancellable?

    @Published var searchText = ""
    
    @Published private(set) var installedItemsPerPage = 21
    
    var importAlertError: WPImportError? = nil

    @Published var deletionAlertPresented = false
    var deletionAlertError: WallpaperDeletion.Failure? = nil

    init() {
        _ = steamCmd
        memoCancellables = [
            objectWillChange.sink { [weak self] _ in self?.invalidateSortedMemo() },
            FavoritesStore.shared.objectWillChange.sink { [weak self] _ in self?.invalidateSortedMemo() },
            // Steam tags arriving for installed wallpapers: the grid, Details and filters use them.
            DownloadedWallpaperIndex.shared.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.sortedMemo = nil
                    self?.objectWillChange.send()
                }
            },
            // The filters and sorting are app storage.
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .sink { [weak self] _ in self?.invalidateSortedMemo() },
        ]
    }

    /// Changes can be announced on any thread; the memo is main-thread state.
    private func invalidateSortedMemo() {
        if Thread.isMainThread {
            sortedMemo = nil
        } else {
            DispatchQueue.main.async { [weak self] in self?.sortedMemo = nil }
        }
    }
    
    convenience init(isStaging: Bool, topTabBarSelection: Int = 0) {
        self.init()
        
        let wallpapers = autoRefreshWallpapers
        
        self.isStaging = isStaging
        self.topTabBarSelection = topTabBarSelection
        self.wallpapers = wallpapers
    }
    
    /// current page index number is starting from '1'
    @Published public var currentPage: Int = 1
//    {
//        willSet {
//            self.currentPage = newValue > self.maxPage ? self.maxPage : newValue
//        }
//    }
    
    /// Re-reads only the wallpapers that changed on disk.
    private let library: InstalledLibraryCache = {
        let cache = InstalledLibraryCache()
        // Downloads and imports are prepared in the background for a warm first show.
        cache.onArrival = { LibraryPreparationScheduler.shared.prepare($0) }
        return cache
    }()
    /// `sortedWallpapers` for the current update: the Installed tab reads it many times per redraw
    /// (grid, page count, pagination, selection). Cleared whenever this model changes, when
    /// favourites or stored filters and sorting change, and after the current main-queue turn, so a
    /// redraw never sees stale data. Main thread only, like every reader of the list.
    private var sortedMemo: [WEWallpaper]?
    private var memoCancellables: [AnyCancellable] = []

    /// Reads the Steam tags of installed wallpapers whose project.json has too few.
    private let tagSync = InstalledWorkshopTagSync()

    /// The Installed wallpapers, before search and filters: no asset items, no dependency-only items.
    var allWallpapers: [WEWallpaper] {
        let wallpapers = library.wallpapers(in: FileManager.default.wallpapersDirectory,
                                            hiding: steamCmd.dependencyIndex.ids)
        tagSync.schedule(wallpapers)
        return wallpapers
    }

    /// The wallpaper's tags to show and filter by: project.json's, then the Workshop item's
    /// stored ones, without "Wallpaper".
    func tags(of wallpaper: WEWallpaper) -> [String] {
        InstalledWorkshopTags.tags(of: wallpaper, in: .shared)
    }

    /// A wallpaper was deleted: drops it from the library index and removes its loading snapshots.
    func forgetDeletedWallpaper(at directory: URL) {
        DownloadedWallpaperIndex.shared.remove(directory: directory)
        let store = SceneLoadingSnapshotStore.current
        Task.detached(priority: .utility) { store.removeSnapshots(forWallpaperAt: directory) }
    }

    /// Deletes the wallpapers' folders, or moves them to the Trash, off the main thread. Then each
    /// one that is gone is forgotten, every one leaves the screens showing it, and a failure is
    /// shown in an alert.
    func deleteWallpapers(at directories: [URL], toTrash: Bool, wallpaperViewModel: WallpaperViewModel) {
        Task { @MainActor in
            let result: (deleted: [URL], failure: WallpaperDeletion.Failure?) = await Task.detached(priority: .userInitiated) {
                WallpaperDeletion.delete(directories, toTrash: toTrash)
            }.value
            for directory in result.deleted { forgetDeletedWallpaper(at: directory) }
            for directory in directories { wallpaperViewModel.removeWallpaperFromAllScreens(directory: directory) }
            removeUnusedWorkshopDependencies()
            if let failure = result.failure {
                deletionAlertError = failure
                deletionAlertPresented = true
            }
        }
    }

    /// After wallpapers were deleted: removes the dependency-only items none of the remaining ones use.
    func removeUnusedWorkshopDependencies() {
        let library = FileManager.default.wallpapersDirectory
        let index = steamCmd.dependencyIndex
        Task.detached(priority: .utility) {
            let removed = WorkshopDependencyCleanup.removeOrphans(in: library, index: index)
            guard !removed.isEmpty else { return }
            await MainActor.run {
                for id in removed {
                    DownloadedWallpaperIndex.shared.remove(directory: library.appending(path: id))
                }
            }
        }
    }
    
    private var searchedWallpapers: [WEWallpaper] {
        allWallpapers.filter { wallpaper in
            let project = wallpaper.project
            let searchText = searchText.lowercased()
            
            guard !searchText.isEmpty else { return true }
            
            guard !project.title.lowercased().contains(searchText) else { return true }
            
            guard !project.type.lowercased().contains(searchText) else { return true }
            
            if let description = project.description?.lowercased() {
                guard !description.contains(searchText) else { return true }
            }
            
            guard !tags(of: wallpaper).contains(where: { $0.lowercased().contains(searchText) })
            else { return true }
            
            if let workshopid = project.workshopid {
                guard !workshopid.rawValue.contains(searchText) else { return true }
            }
            
            guard !wallpaper.wallpaperDirectory.lastPathComponent
                .lowercased()
                .contains(searchText) else { return true }
            
            return false
        }
    }
    
    private var filteredWallpapers: [WEWallpaper] {
        let resolutionGroups: [[String]] = [
            InstalledTagFilter.checked(widescreenResolution), InstalledTagFilter.checked(ultraWidescreenResolution),
            InstalledTagFilter.checked(dualscreenResolution), InstalledTagFilter.checked(triplescreenResolution),
            InstalledTagFilter.checked(potraitscreenResolution), InstalledTagFilter.checked(miscResolution),
        ]
        let resolutions = Set<String>(resolutionGroups.joined())
        return searchedWallpapers.filter { wallpaper in
            let wallpaperTags = self.tags(of: wallpaper)

            // Show Only
            var showOnly = FRShowOnly.none
            if wallpaper.project.approved == true
                || wallpaperTags.contains(where: { $0.caseInsensitiveCompare(WorkshopTags.approved) == .orderedSame }) {
                showOnly.insert(.approved)
            }
            if FavoritesStore.shared.contains(wallpaper) { showOnly.insert(.myFavourites) }
            if wallpaper.isMobileCompatible { showOnly.insert(.mobileCompatible) }
            if wallpaper.isAudioResponsive { showOnly.insert(.audioResponsive) }
            if library.hasCustomizableProperties(wallpaper) { showOnly.insert(.customizable) }
            guard self.showOnly.isEmpty || !self.showOnly.intersection(showOnly).isEmpty else { return false }
            
            // Type
            var type = FRType.none
            switch wallpaper.project.type.lowercased() {
            case "video":
                type = .video
            case "scene":
                type = .scene
            case "web":
                type = .web
            case "application":
                type = .application
            default:
                break
            }
            guard self.type.contains(type) else { return false }
            
            // 
            
            // Age Rating
            var ageRating: FRAgeRating
            switch wallpaper.project.contentrating ?? InstalledWorkshopTags.contentRating(in: wallpaperTags) {
            case "Everyone":
                ageRating = .everyone
            case "Questionable":
                ageRating = .partialNudity
            case "Mature":
                ageRating = .mature
            default:
                ageRating = .none
            }
            guard self.ageRating.contains(ageRating) else { return false }
            
            guard InstalledTagFilter.matchesResolutions(wallpaperTags, checked: resolutions) else { return false }
            guard InstalledTagFilter.matchesGenres(wallpaperTags, checked: self.tag) else { return false }
            
            // Finish Filtering
            return true
        }
    }
    
    private var sortedWallpapers: [WEWallpaper] {
        if let sortedMemo { return sortedMemo }
        let sorted = computeSortedWallpapers()
        sortedMemo = sorted
        DispatchQueue.main.async { [weak self] in self?.sortedMemo = nil }
        return sorted
    }

    private func computeSortedWallpapers() -> [WEWallpaper] {
        filteredWallpapers.sorted {
            switch sortingBy {
            case .name:
                return Self.precedes($0.project.title, $1.project.title, in: sortingSequence)
            case .rating:
                return Self.precedes($0.project.contentrating ?? "0", $1.project.contentrating ?? "0",
                                     in: sortingSequence)
//            case .favorite:
//                return false
            case .fileSize:
                return Self.precedes(library.size(of: $0), library.size(of: $1), in: sortingSequence)
            case .dateAdded:
                let firstDate = DownloadedWallpaperIndex.shared.dateAdded(for: $0.wallpaperDirectory)
                let secondDate = DownloadedWallpaperIndex.shared.dateAdded(for: $1.wallpaperDirectory)
                if sortingSequence == .increase {
                    return firstDate < secondDate
                }
                return firstDate > secondDate
//            case .subDate:
//                return false
//            case .lastUpdated:
//                return false
            }
        }
    }
    
    /// Whether `lhs` sorts before `rhs` for the title, rating and file size orders: `.increase` puts
    /// the larger value first and `.decrease` the smaller, as the library has always ordered them.
    static func precedes<Value: Comparable>(_ lhs: Value, _ rhs: Value,
                                            in sequence: WEWallpaperSortingSequence) -> Bool {
        switch sequence {
        case .increase: return lhs > rhs
        case .decrease: return lhs < rhs
        }
    }

    /// Provide wallpapers information for UI, being filtered by FilterResults and divided in pages
    public var autoRefreshWallpapers: [WEWallpaper] {
        sortedWallpapers
    }

    var displayedWallpapers: [WEWallpaper] {
        let startIndex = (InstalledPageWindow.clamp(currentPage, total: maxPage) - 1) * installedItemsPerPage
        guard startIndex < sortedWallpapers.count else { return [] }
        let endIndex = min(startIndex + installedItemsPerPage, sortedWallpapers.count)
        return Array(sortedWallpapers[startIndex..<endIndex])
    }

    var hasNextWallpaperPage: Bool {
        currentPage < maxPage
    }

    func updateInstalledItemsPerPage(for size: CGSize) {
        let itemSize = max(explorerIconSize, 1)
        let spacing: CGFloat = 8
        let columns = max(1, Int((size.width + spacing) / (itemSize + spacing)))
        let rows = max(1, Int((size.height + spacing) / (itemSize + spacing)))
        let pageSize = columns * rows
        guard installedItemsPerPage != pageSize else { return }
        installedItemsPerPage = pageSize
        clampCurrentPage()
    }

    /// Keeps the current page inside the library after the page count changed (wallpapers
    /// removed, a search or filter narrowed the list, a new page size).
    func clampCurrentPage() {
        let page = InstalledPageWindow.clamp(currentPage, total: maxPage)
        if page != currentPage { currentPage = page }
    }
    
    /// Caculates the maximium possible page index for all wallpapers in your application wallpaper directory
    var maxPage: Int {
        max(1, Int(ceil(Double(sortedWallpapers.count) / Double(installedItemsPerPage))))
    }
    
    func toggleSelection(for wallpaper: WEWallpaper) {
        let url = wallpaper.wallpaperDirectory
        if selectedWallpapers.contains(url) {
            selectedWallpapers.remove(url)
        } else {
            selectedWallpapers.insert(url)
        }
        selectionAnchor = url
    }

    func selectWallpaper(
        _ wallpaper: WEWallpaper,
        from wallpapers: [WEWallpaper],
        inspectingWith wallpaperViewModel: WallpaperViewModel
    ) {
        let url = wallpaper.wallpaperDirectory
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isAdditive = modifiers.contains(.control) || modifiers.contains(.command)

        if modifiers.contains(.shift), !isAdditive,
           let anchor = selectionAnchor,
           let start = wallpapers.firstIndex(where: { $0.wallpaperDirectory == anchor }),
           let end = wallpapers.firstIndex(where: { $0.wallpaperDirectory == url }) {
            selectedWallpapers = Set(wallpapers[min(start, end)...max(start, end)].map(\.wallpaperDirectory))
        } else if isAdditive {
            toggleSelection(for: wallpaper)
        } else {
            clearSelection()
            wallpaperViewModel.inspect(wallpaper)
            selectionAnchor = url
        }
    }

    func clearSelection() {
        selectedWallpapers.removeAll()
        selectionAnchor = nil
    }

    func isSelected(_ wallpaper: WEWallpaper) -> Bool {
        selectedWallpapers.contains(wallpaper.wallpaperDirectory)
    }

    func selectedWallpaperItems() -> [WEWallpaper] {
        autoRefreshWallpapers.filter { selectedWallpapers.contains($0.wallpaperDirectory) }
    }

    /// Animated, so the sidebar slides in and out as it did before it was a split view column.
    func toggleFilter() {
        withAnimation { isFilterReveal.toggle() }
    }
    
    func alertImportModal(which error: WPImportError) {
        self.importAlertError = error
        self.importAlertPresented = true
    }
    
    func warningUnsafeWallpaperModal(which wallpaper: WEWallpaper) {
        self.isUnsafeWallpaperWarningPresented = true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let proposal = DropProposal(operation: .copy)
        return proposal
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [UTType.fileURL]).first
        else {
            alertImportModal(which: .unkown)
            return false
        }
        itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil)
            else {
                self?.alertImportModal(which: .unkown)
                return
            }
            // Do something with the file url
            // remember to dispatch on main in case of a @State change
            guard let wallpaper = try? FileWrapper(url: url)
            else{
                self?.alertImportModal(which: .unkown)
                return
            }
            
            if wallpaper.isDirectory {
                guard wallpaper.fileWrappers?["project.json"] != nil
                else{
                    self?.alertImportModal(which: .doesNotContainWallpaper)
                    return
                }
                DispatchQueue.main.async {
                    let destination = FileManager.default.wallpapersDirectory.appending(path: url.lastPathComponent)
                    do {
                        try ImportedFolderLinks.copyWithoutLinks(from: url, to: destination)
                    } catch {
                        OWELog.error(.importer, "Can't import dropped folder \(url.path): \(error)")
                    }
                }
            } else if wallpaper.isRegularFile, url.pathExtension.lowercased() == "zip" {
                DispatchQueue.main.async {
                    let count = ZipImporter.importZip(at: url)
                    if count == 0 {
                        self?.alertImportModal(which: .doesNotContainWallpaper)
                    }
                }
            } else if wallpaper.isRegularFile {
                guard wallpaper.filename != nil,
                      ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) else { return }
                AppDelegate.shared.wallpaperViewModel.importVideoWallpaper(from: url)
            }
        }
        return true
    }
    
    public func refresh() {
        self.wallpapers = autoRefreshWallpapers
    }
    
    /// Provide a filter reset to default function, usually being used to show all wallpapers without filtered
    public func reset() {
        self.showOnly                   = .none // notice it's show ONLY, it acts oppositely to the others
        self.type                       = .all
        self.ageRating                  = .all
        self.type                       = .all
        self.ageRating                  = .all
        self.widescreenResolution       = .all
        self.ultraWidescreenResolution  = .all
        self.dualscreenResolution       = .all
        self.triplescreenResolution     = .all
        self.potraitscreenResolution    = .all
        self.miscResolution             = .all
        self.source                     = .all
        self.tag                        = .all
    }
}
