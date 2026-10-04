import Foundation

/// The display layout's side of the displays' wallpapers (docs/architecture.md "Display layouts"):
/// the Displays sheet changes it by display id, the model keeps it by display identity.
extension WallpaperViewModel {
    /// Resolves the layout on the connected displays (a clone member then shows its main display's
    /// wallpaper, `wallpaper(for:)`, its own selection untouched) and regroups the instances and
    /// the displays' playback.
    func refreshDisplayLayout() {
        let resolution = DisplayLayoutResolution(displayLayout, displays: connectedDisplays())
        if resolution != layoutResolution { layoutResolution = resolution }
        refreshInstanceKeys()
        refreshDisplayPlayback()
    }

    // MARK: Changes from the Displays sheet, by display id

    private func identity(of screenId: String) -> String? {
        connectedDisplays().first { $0.screenId == screenId }?.identity
    }

    private var connectedIdentities: [String] { connectedDisplays().map(\.identity) }

    func setLayout(_ layout: DisplayLayoutMode) {
        displayLayout.layout = layout
    }

    /// Groups `screenIds` (at least two) into a clone group.
    func addCloneGroup(_ screenIds: Set<String>) {
        let displays = connectedDisplays().filter { screenIds.contains($0.screenId) }.map(\.identity)
        displayLayout.addGroup(displays, layout: .clone)
    }

    func removeFromGroup(_ screenId: String) {
        guard let display = identity(of: screenId) else { return }
        displayLayout.removeFromGroup(display)
    }

    /// Whether `screenId` is in a clone (a group, or every display under the clone layout).
    func isCloned(_ screenId: String) -> Bool {
        layoutResolution.clone(containing: screenId) != nil
    }

    /// Whether `screenId` is its clone's main display.
    func isMainCloneDisplay(_ screenId: String) -> Bool {
        layoutResolution.clone(containing: screenId)?.source == screenId
    }

    /// Whether `screenId` is the main display the user chose (rather than the first by default).
    func isChosenMainCloneDisplay(_ screenId: String) -> Bool {
        guard let display = identity(of: screenId),
              let clone = displayLayout.clone(containing: display, connected: connectedIdentities) else { return false }
        return clone.source == display
    }

    func setMainCloneDisplay(_ screenId: String, _ isMain: Bool) {
        guard let display = identity(of: screenId) else { return }
        displayLayout.setCloneSource(display, isSource: isMain, connected: connectedIdentities)
    }

    func isFlipped(_ screenId: String) -> Bool { layoutResolution.flipped.contains(screenId) }

    /// Flips `screenId`'s clone or turns it off; false for a clone's main display, which can't be.
    @discardableResult
    func toggleFlip(_ screenId: String) -> Bool {
        guard let display = identity(of: screenId) else { return false }
        return displayLayout.toggleFlip(display, connected: connectedIdentities)
    }

    func isMuted(_ screenId: String) -> Bool { layoutResolution.muted.contains(screenId) }

    func toggleMute(_ screenId: String) {
        guard let display = identity(of: screenId) else { return }
        displayLayout.toggleMute(display)
    }
}
