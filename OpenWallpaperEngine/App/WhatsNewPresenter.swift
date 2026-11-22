import Cocoa
import SwiftUI

/// Shows What's New as a sheet on the main window the first time it becomes key after an update
/// (never at a relaunch into the menu bar, which opens no window), then the Steam login when
/// wallpapers an earlier version unpacked wait for one.
extension AppDelegate {
    func observeMainWindowForWhatsNew() {
        let whatsNew = WhatsNew(currentVersion: AppUpdateConfiguration.main.versionLabel)
        whatsNew.recordFirstInstall()
        NotificationCenter.default.addObserver(
            self, selector: #selector(mainWindowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: mainWindowController.window)
    }

    @objc private func mainWindowBecameKey(_ notification: Notification) {
        guard let window = mainWindowController.window, window.attachedSheet == nil else { return }
        // Not over the setup assistant.
        guard !globalSettingsViewModel.isFirstLaunch, !globalSettingsViewModel.needsLegalNotice else { return }
        let whatsNew = WhatsNew(currentVersion: AppUpdateConfiguration.main.versionLabel)
        let isUpdate = whatsNew.isUpdate
        guard let pending = whatsNew.takePendingEntries() else {
            // Release notes are turned off.
            if isUpdate { offerLoginForUnpackedWallpapers() }
            return
        }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        sheet.contentView = NSHostingView(rootView: WhatsNewView(version: pending.current, entries: pending.entries) {
            [weak window, weak sheet] in
            if let sheet { window?.endSheet(sheet) }
        }.appAccentTint())
        window.beginSheet(sheet) { [weak self] _ in
            MainActor.assumeIsolated { self?.offerLoginForUnpackedWallpapers() }
        }
    }

    private func offerLoginForUnpackedWallpapers() {
        let account = contentViewModel.steamAccount
        Task {
            guard let waiting = await unpackedBundles.waitingForLogin(account: account) else { return }
            presentLogin(for: waiting, account: account)
        }
    }

    private func presentLogin(for waiting: UnpackedBundleRestoreService.Waiting, account: SteamAccount) {
        guard let window = mainWindowController.window, window.isVisible, window.attachedSheet == nil else { return }
        OWELog.info(.importer, "Unpacked wallpapers: asking for the Steam login to download \(waiting.count)")
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        let content = NSHostingController(rootView: UnpackedWallpapersLoginView(
            account: account, waiting: waiting,
            startDownloads: { [weak self] in self?.unpackedBundles.startDownloads() }) { [weak window, weak sheet] in
                if case .signingIn = account.status { account.cancelSignIn() }
                if let sheet { window?.endSheet(sheet) }
            }.appAccentTint())
        // The login grows and shrinks (the QR code, the password form).
        content.sizingOptions = .preferredContentSize
        sheet.contentViewController = content
        window.beginSheet(sheet)
    }
}
