import AppKit
import Darwin

/// Gives this process its own name where macOS shows running apps (the Dock, the menu bar,
/// ⌘-Tab, Force Quit), which otherwise read the bundle's: the Wallpaper Editor runs the app's
/// executable but isn't Open Wallpaper Engine.
///
/// LaunchServices has no public call for it; this uses the one Chromium names its helper
/// processes with (`_LSSetApplicationInformationItem` with `_kLSDisplayNameKey`), looked up at
/// run time. Without it (a future macOS dropping it) the process keeps the bundle's name, logged.
enum ProcessDisplayName {
    private typealias GetCurrentASN = @convention(c) () -> Unmanaged<CFTypeRef>?
    private typealias SetInformationItem = @convention(c) (Int32, CFTypeRef, CFString, CFTypeRef, UnsafeMutablePointer<Unmanaged<CFDictionary>?>?) -> OSStatus
    /// `kLSDefaultSessionID`.
    private static let defaultSession: Int32 = -2

    @MainActor
    static func set(_ name: String) {
        ProcessInfo.processInfo.processName = name
        let services = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices"
        guard let handle = dlopen(services, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(services, RTLD_LAZY),
              let currentSymbol = dlsym(handle, "_LSGetCurrentApplicationASN"),
              let setSymbol = dlsym(handle, "_LSSetApplicationInformationItem"),
              let keySymbol = dlsym(handle, "_kLSDisplayNameKey") else {
            OWELog.info(.app, "This macOS can't rename the process; it shows as the app")
            return
        }
        let current = unsafeBitCast(currentSymbol, to: GetCurrentASN.self)
        let setItem = unsafeBitCast(setSymbol, to: SetInformationItem.self)
        // A `CFStringRef` constant: the symbol is its address.
        let key = keySymbol.assumingMemoryBound(to: CFString.self).pointee
        // Get rule: the identity isn't ours to release.
        guard let asn = current()?.takeUnretainedValue() else {
            OWELog.info(.app, "The process has no LaunchServices identity to rename")
            return
        }
        let status = setItem(defaultSession, asn, key, name as CFString, nil)
        if status != 0 { OWELog.error(.app, "Can't rename the process to \(name): \(status)") }
    }
}
