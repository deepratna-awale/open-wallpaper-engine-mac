//
//  ContentViewModel.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import Combine
import Observation
import SwiftUI

/// The main window's state, split by concern so a view redraws only for what it reads:
/// `navigation` (tabs, panes, tile size), `presentation` (alerts, sheets, confirmations),
/// `filters` (the Installed filter sidebar) and `library` (the Installed list: search, sorting,
/// pages, selection). This owner keeps the Workshop services and the trust prompt.
@MainActor @Observable
final class ContentViewModel {
    let navigation = ContentNavigation()
    let presentation = ContentPresentation()
    let filters = FilterResultsViewModel()
    let library: InstalledLibraryModel

    var isUnsafeWallpaperWarningPresented = false

    /// The Installed tab picks wallpapers for an Android batch ("Export More with These
    /// Settings…") while this is set; nil is the library as usual. Never saved.
    private(set) var androidBatchPicker: AndroidBatchPicker?

    /// The Installed tab's own actions (context menus, Details and Set as Wallpaper, dragging into
    /// folders, imports, deleting, the other tabs): off while it picks wallpapers for an export.
    var allowsLibraryActions: Bool { androidBatchPicker == nil }

    /// Whether downloads are logged in: the only part of the service that reaches this model (the
    /// main window's Workshop tab and sidebar depend on it). The Workshop and Downloads views
    /// observe the service itself, so a download's progress doesn't redraw the window.
    private var steamLoginStatus = false
    private let workshopDownloadService = WorkshopDownloadService()
    @ObservationIgnored private var steamLoginCancellable: AnyCancellable?
    @ObservationIgnored private var steamLoginCancellables: Set<AnyCancellable> = []

    /// Reading it observes whether downloads are logged in.
    var workshopDownloads: WorkshopDownloadService {
        _ = steamLoginStatus
        return workshopDownloadService
    }
    /// The Steam login, which the app's Steam helper uses for everything on Steam.
    let steamAccount = SteamAccount()
    /// Workshop wallpapers and authors hidden from the Workshop and Discover tabs.
    @ObservationIgnored lazy var workshopBlockList = WorkshopBlockList()
    @ObservationIgnored lazy var workshopVM: WorkshopViewModel = {
        let model = WorkshopViewModel(workshopDownloads: workshopDownloadService, blockList: workshopBlockList, steam: steamAccount.client)
        model.showsBrowser = { [weak self] in self?.navigation.topTabBarSelection = 1 }
        model.attach(setAs: WorkshopSetAsFlow(environment: .app(workshop: model, library: library)))
        return model
    }()
    /// The Discover tab's lists.
    @ObservationIgnored lazy var discoverVM = WorkshopDiscoverViewModel(blockList: workshopBlockList, steam: steamAccount.client)

    init() {
        library = InstalledLibraryModel(filters: filters, workshopDownloads: workshopDownloadService, presentation: presentation)
        let svc = workshopDownloadService
        steamLoginCancellable = svc.$isLoggedIn
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] status in
                if Thread.isMainThread {
                    MainActor.assumeIsolated { self?.steamLoginStatus = status }
                } else {
                    DispatchQueue.main.async { self?.steamLoginStatus = status }
                }
            }
        // Downloads use the Steam login while there is one, and a download Steam refused it for
        // ends it here too.
        let account = steamAccount
        steamAccount.$login
            .removeDuplicates()
            .sink { [weak svc] login in svc?.useSteamLogin(login) }
            .store(in: &steamLoginCancellables)
        svc.steamLoginRejected
            .sink { [weak account] in Task { await account?.loginRejected() } }
            .store(in: &steamLoginCancellables)
    }

    /// Asks whether to trust `wallpaper` before it runs its code. The sheet is on the main window,
    /// which comes forward first: a wallpaper picked from the menu bar's Recent Wallpapers with the
    /// window closed would otherwise wait for an answer no one can see.
    func warningUnsafeWallpaperModal(which wallpaper: WEWallpaper) {
        OWELog.info(.library, "Asking to trust \(wallpaper.wallpaperDirectory.lastPathComponent) (\(wallpaper.project.type)) before it runs")
        AppDelegate.shared.openMainWindow()
        self.isUnsafeWallpaperWarningPresented = true
    }

    /// The library changed on disk: the next read lists and sorts it again.
    func refresh() {
        library.refresh()
    }

    // MARK: Android export selection

    /// Shows the Installed tab as `selection`'s picker, in place of one already shown.
    func showAndroidBatchPicker(_ selection: AndroidBatchPicker) {
        androidBatchPicker = selection
        navigation.topTabBarSelection = 0
    }

    /// Ends `selection`, if it is the one shown.
    func endAndroidBatchPicker(_ selection: AndroidBatchPicker) {
        guard androidBatchPicker === selection else { return }
        androidBatchPicker = nil
    }

    /// The Android Export mode `model` closed: its selection, if shown, ends.
    func endAndroidBatchPicker(for model: AndroidExportEditorModel) {
        guard let selection = androidBatchPicker, selection.model === model else { return }
        androidBatchPicker = nil
    }
}
