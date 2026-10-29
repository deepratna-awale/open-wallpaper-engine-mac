import OWEInspectorKit
import SwiftUI
import Combine

/// The imports the setup assistant offers, kept while it is open so the summary can count them.
@MainActor
final class OnboardingImports: ObservableObject {
    let collection: WorkshopItemsImportModel
    let subscriptions: WorkshopItemsImportModel
    let library: SteamLibraryImportModel
    /// The probe's last answer for the subscriptions option; nil before one ran.
    @Published private(set) var probe: WorkshopSubscriptions.ProbeResult?
    private let defaults: UserDefaults
    private let loginSteamID: () -> String?
    private var changes: [AnyCancellable] = []

    init(collection: WorkshopItemsImportModel, subscriptions: WorkshopItemsImportModel,
         library: SteamLibraryImportModel, defaults: UserDefaults = .app,
         loginSteamID: @escaping () -> String?) {
        self.collection = collection
        self.subscriptions = subscriptions
        self.library = library
        self.defaults = defaults
        self.loginSteamID = loginSteamID
        probe = defaults.string(forKey: WorkshopSubscriptions.probeResultKey).flatMap(WorkshopSubscriptions.ProbeResult.init(rawValue:))
        for model in [collection.objectWillChange, subscriptions.objectWillChange, library.objectWillChange] {
            changes.append(model.sink { [weak self] _ in self?.objectWillChange.send() })
        }
    }

    /// The app's own wiring: its Steam login, downloads, playlists and rating filter.
    convenience init(contentViewModel: ContentViewModel, wallpaperViewModel: WallpaperViewModel) {
        let ratings = contentViewModel.workshopVM.filter.ratings
        let api = WorkshopAPIService(steam: contentViewModel.steamAccount.client)
        let steamCmd = contentViewModel.steamCmd
        self.init(collection: WorkshopItemsImportModel(api: api, steamCmd: steamCmd,
                                                       wallpaperViewModel: wallpaperViewModel, ratings: ratings),
                  subscriptions: WorkshopItemsImportModel(api: api, steamCmd: steamCmd,
                                                          wallpaperViewModel: wallpaperViewModel, ratings: ratings),
                  library: SteamLibraryImportModel(ratings: ratings, onImported: { folders in
                      OnboardingImports.didImport(folders, contentViewModel: contentViewModel)
                  }),
                  loginSteamID: { [weak steamCmd] in steamCmd?.steamLogin?.steamID })
    }

    /// Copied folders join the library like any import: converted, indexed, their dependencies fetched.
    static func didImport(_ folders: [URL], contentViewModel: ContentViewModel) {
        for folder in folders {
            DownloadedWallpaperIndex.shared.insert(folder.lastPathComponent)
            DispatchQueue.global(qos: .utility).async {
                WallpaperPreparation.prepare(wallpaperDirectory: folder)
            }
            AppDelegate.shared.workshopDependencies.ensureDependencies(ofItemAt: folder)
        }
        contentViewModel.refresh()
    }

    /// Whether to offer "Download my subscriptions": the user is logged in to Steam, and the probe
    /// hasn't found Steam returning nothing.
    var offersSubscriptions: Bool {
        steamID != nil && probe != .empty
    }

    var canProbe: Bool { steamID != nil }

    /// The logged-in account's SteamID64.
    var steamID: String? { loginSteamID() }

    /// Asks Steam once; an empty answer hides the option until the user checks again.
    func probeSubscriptions(steamID: String) async {
        await subscriptions.loadSubscriptions(steamID: steamID)
        switch subscriptions.phase {
        case .loaded: record(.items)
        case .noSubscriptions: record(.empty)
        case .idle, .loading, .failed: break
        }
    }

    /// "Check again" after an empty answer.
    func forgetProbe() {
        defaults.removeObject(forKey: WorkshopSubscriptions.probeResultKey)
        probe = nil
    }

    private func record(_ result: WorkshopSubscriptions.ProbeResult) {
        probe = result
        defaults.set(result.rawValue, forKey: WorkshopSubscriptions.probeResultKey)
    }

    /// For the summary.
    var queuedDownloads: Int { collection.queuedCount + subscriptions.queuedCount }
    var copiedFromSteamLibrary: Int { library.result?.copied.count ?? 0 }
}

// MARK: - 5. Bring your wallpapers

struct OnboardingWallpapersStep: View {
    @Environment(\.appAccentColor) private var accentColor
    @ObservedObject var steamCmd: SteamCmdService
    @ObservedObject var imports: OnboardingImports
    @State private var isCollectionPresented = false
    @State private var isLibraryPresented = false
    @State private var isSubscriptionsPresented = false

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeading(systemImage: "photo.stack.fill",
                              title: "Bring Your Wallpapers",
                              subtitle: "Start from a collection or a Steam install you already have")
            option(systemImage: "square.stack.3d.down.right",
                   title: "Import a Workshop Collection",
                   text: "Paste a collection link. You choose which items to download, and can make them a playlist.",
                   action: "Import Collection…") { isCollectionPresented = true }
            option(systemImage: "externaldrive.badge.person.crop",
                   title: "Import from a Steam Library",
                   text: "Copy the wallpapers of Wallpaper Engine on Windows, in a CrossOver bottle or on a Boot Camp disk.",
                   action: "Choose Library…") { isLibraryPresented = true }
            subscriptionsOption
            Text("Or skip, and browse the Workshop later.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isCollectionPresented) {
            WorkshopCollectionImportView(model: imports.collection)
                .frame(width: 680, height: 560)
        }
        .sheet(isPresented: $isLibraryPresented) {
            SteamLibraryImportView(model: imports.library)
                .frame(width: 680, height: 560)
        }
        .sheet(isPresented: $isSubscriptionsPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Subscriptions")
                    .font(.title2.bold())
                WorkshopItemsImportBody(model: imports.subscriptions, showsPlaylistOption: false)
                HStack {
                    Spacer()
                    Button("Done") { isSubscriptionsPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 680, height: 560)
        }
    }

    private func option(systemImage: String, title: LocalizedStringKey, text: LocalizedStringKey,
                        action: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        OnboardingCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(accentColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action, action: perform)
                    .glassButtonStyle()
            }
        }
    }

    /// Best effort, so it only shows while it can work: with the Steam login, and until Steam has
    /// answered with no subscriptions.
    @ViewBuilder
    private var subscriptionsOption: some View {
        if imports.offersSubscriptions {
            OnboardingCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.title)
                        .foregroundStyle(accentColor)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download My Subscriptions").font(.headline)
                        Text("Asks Steam for your Workshop subscriptions through your Steam login. Steam doesn't always answer; the options above always work.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if imports.subscriptions.phase == .loading {
                            ProgressView().controlSize(.small)
                        } else if case .failed(let message) = imports.subscriptions.phase {
                            Text(message).font(.caption).foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    Button(imports.probe == .items ? "Choose…" : "Check") {
                        guard let id = imports.steamID else { return }
                        Task {
                            await imports.probeSubscriptions(steamID: id)
                            if imports.subscriptions.phase == .loaded { isSubscriptionsPresented = true }
                        }
                    }
                    .glassButtonStyle()
                    .disabled(imports.steamID == nil || imports.subscriptions.phase == .loading)
                }
            }
        } else if imports.probe == .empty && imports.canProbe {
            HStack {
                Text("Steam didn't return your subscriptions. Import a collection or a Steam library instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check Again") { imports.forgetProbe() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}
