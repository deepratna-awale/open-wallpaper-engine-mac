//
//  MainWindowController.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/8.
//

import Cocoa
import SwiftUI

class MainWindowController: NSWindowController, NSWindowDelegate {
    override var window: NSWindow! {
        get {
            return super.window
        }
        set {
            super.window = newValue
        }
    }
    
    override init(window: NSWindow?) {
        super.init(window: Self.makeWindow())
        self.window.delegate = self
        self.window.contentView = NSHostingView(rootView: ContentView(
                viewModel: AppDelegate.shared.contentViewModel,
                wallpaperViewModel: AppDelegate.shared.wallpaperViewModel
            ).environmentObject(AppDelegate.shared.globalSettingsViewModel)
            .appAccentTint()
        )
    }

    /// The main window, without its content. It moves by its title bar and toolbar only: moved
    /// by its background as well, AppKit moves it from any mouse-down on a view that allows it,
    /// which SwiftUI's hosting view and every non-opaque view do, so a drag on a wallpaper or
    /// folder tile moved the window instead of starting the drag.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Open Wallpaper Engine \(AppVersion.current)"
        // The content's split view, toolbar and inspector draw the window chrome (glass on macOS 26).
        window.toolbarStyle = .unified
        // The tabs sit in the toolbar's centre; the title stays for the Window menu and Mission Control.
        window.titleVisibility = .hidden
        // The frame autosaves into UserDefaults.standard, which an isolated copy must not write.
        if !AppStorageLocation.current.isIsolated { window.setFrameAutosaveName(frameAutosaveName) }
        return window
    }
    
    /// The window's frame before Details Only narrowed it; restored when it ends.
    private var libraryFrame: NSRect?
    /// Details Only was asked for in full screen: it starts once the window has left it.
    private var entersDetailsOnlyAfterFullScreen = false

    private static let detailsOnlyWidth: CGFloat = 340
    private static let frameAutosaveName = "MainWindow"

    /// Narrows the window to the Installed tab's Details panel, kept where the panel was on screen
    /// with the window's height, or gives the window back its library and its earlier frame.
    func setDetailsOnly(_ detailsOnly: Bool, animate: Bool = true) {
        let navigation = AppDelegate.shared.contentViewModel.navigation
        guard let window, detailsOnly != navigation.isDetailsOnly else { return }
        if detailsOnly, window.styleMask.contains(.fullScreen) {
            entersDetailsOnlyAfterFullScreen = true
            window.toggleFullScreen(nil)
            return
        }
        if detailsOnly {
            libraryFrame = window.frame
            // The narrow frame isn't the library's: the saved one stays the full window's.
            window.setFrameAutosaveName("")
            navigation.topTabBarSelection = 0
            navigation.isDetailsReveal = true
        }
        navigation.isDetailsOnly = detailsOnly
        // The content's minimum size changes with the mode; the frame follows once it has.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, navigation.isDetailsOnly == detailsOnly else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            let current = window.frame
            var frame: NSRect
            if detailsOnly {
                frame = NSRect(x: current.maxX - Self.detailsOnlyWidth, y: current.minY,
                               width: Self.detailsOnlyWidth, height: current.height)
            } else {
                let size = self.libraryFrame?.size ?? current.size
                frame = NSRect(x: current.maxX - size.width, y: current.maxY - size.height,
                               width: size.width, height: size.height)
                if let screen = window.screen { frame = window.constrainFrameRect(frame, to: screen) }
                self.libraryFrame = nil
            }
            window.setFrame(frame, display: true, animate: animate && window.isVisible)
            if !detailsOnly, !AppStorageLocation.current.isIsolated {
                window.setFrameAutosaveName(Self.frameAutosaveName)
            }
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard entersDetailsOnlyAfterFullScreen else { return }
        entersDetailsOnlyAfterFullScreen = false
        setDetailsOnly(true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    /// Edit › Select All (⌘A) when no text field took it: every wallpaper or card the Installed,
    /// Workshop or Discover tab shows. It reaches the window's controller through the responder
    /// chain, so a focused text field (the search, a name prompt) keeps selecting its own text.
    override func selectAll(_ sender: Any?) {
        Self.selectAllAction?()
    }

    /// What Select All does in the tab shown; nil when it shows nothing to select.
    private static var selectAllAction: (() -> Void)? {
        let content = AppDelegate.shared.contentViewModel
        guard !content.navigation.isDetailsOnly else { return nil }
        switch content.navigation.topTabBarSelection {
        case 0:
            let library = content.library
            guard !library.displayedWallpapers.isEmpty else { return nil }
            // Picking wallpapers for an export: every exportable one shown joins the picks.
            if let selection = content.androidBatchPicker {
                return { selection.selectAll(library.displayedWallpapers) }
            }
            return { library.selectAll() }
        case 1:
            let workshop = content.workshopVM
            return workshop.items.isEmpty ? nil : { workshop.selectAll() }
        case 4:
            let shown = content.discoverVM.shownItems, workshop = content.workshopVM
            return shown.isEmpty ? nil : { workshop.selectAll(shown) }
        default:
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        // The window opens again with its library.
        setDetailsOnly(false, animate: false)
        AppDelegate.shared.contentViewModel.navigation.isStaging = false
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        stageLibrary()
    }

    /// A window opened behind another app never becomes key: the library loads once it's on screen.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard window?.occlusionState.contains(.visible) == true else { return }
        stageLibrary()
    }

    /// Builds the library again (closing the window tears it down) and fades it in.
    private func stageLibrary() {
        guard !AppDelegate.shared.contentViewModel.navigation.isStaging else { return }
        DispatchQueue.main.async {
            withAnimation {
                AppDelegate.shared.contentViewModel.navigation.isStaging = true
            }
        }
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(selectAll(_:)) else { return true }
        return Self.selectAllAction != nil
    }
}
