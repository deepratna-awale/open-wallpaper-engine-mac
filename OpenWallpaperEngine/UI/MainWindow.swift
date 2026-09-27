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
        super.init(window: NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false))
        self.window.delegate = self
        self.window.isReleasedWhenClosed = false
        self.window.title = "Open Wallpaper Engine \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String)"
        // The content's split view, toolbar and inspector draw the window chrome (glass on macOS 26).
        self.window.toolbarStyle = .unified
        // The tabs sit in the toolbar's centre; the title stays for the Window menu and Mission Control.
        self.window.titleVisibility = .hidden
        self.window.setFrameAutosaveName("MainWindow")
        self.window.isMovableByWindowBackground = true
        self.window.contentView = NSHostingView(rootView: ContentView(
                viewModel: AppDelegate.shared.contentViewModel,
                wallpaperViewModel: AppDelegate.shared.wallpaperViewModel
            ).environmentObject(AppDelegate.shared.globalSettingsViewModel)
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    func windowWillClose(_ notification: Notification) {
        AppDelegate.shared.contentViewModel.isStaging = false
    }
    
    func windowDidResignKey(_ notification: Notification) {
//        if !AppDelegate.shared.contentViewModel.isDisplaySettingsReveal {
//            AppDelegate.shared.contentViewModel.isStaging = false
//        }
    }
    
    func windowDidResignMain(_ notification: Notification) {
//        AppDelegate.shared.contentViewModel.isStaging = false
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async {
            withAnimation {
                AppDelegate.shared.contentViewModel.isStaging = true
            }
        }
    }
}
