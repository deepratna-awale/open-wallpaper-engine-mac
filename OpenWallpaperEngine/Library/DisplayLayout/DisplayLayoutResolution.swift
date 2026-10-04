import Foundation

/// The display layout (`DisplayLayoutConfiguration`) on the displays connected now, by display id:
/// which displays clone which, which are flipped or muted, and the groups to outline.
///
/// A clone shows its main display's wallpaper on every member through the one running instance
/// (`WallpaperViewModel.instanceKey(for:)`), as WE renders a clone once and mirrors it; each
/// member places the frame at its own size, and a flipped member mirrors it as it presents.
/// A group with fewer than two connected displays is dormant and changes nothing.
struct DisplayLayoutResolution: Equatable {
    /// A clone on the connected displays.
    struct Clone: Equatable, Identifiable {
        /// The group's id; `DisplayLayoutResolution.globalCloneID` for the clone layout.
        let id: String
        /// Member display ids, in the group's order.
        let screens: [String]
        let source: String
    }

    static let globalCloneID = "clone"

    /// Each member display's main clone display, for the members that aren't it.
    private(set) var cloneSources: [String: String] = [:]
    private(set) var clones: [Clone] = []
    private(set) var flipped: Set<String> = []
    private(set) var muted: Set<String> = []

    static let empty = DisplayLayoutResolution()

    private init() {}

    init(_ configuration: DisplayLayoutConfiguration, displays: [DisplayIdentity]) {
        let screenIds = Dictionary(displays.map { ($0.identity, $0.screenId) }, uniquingKeysWith: { first, _ in first })
        let connected = displays.map(\.identity)
        muted = Set(configuration.muted.compactMap { screenIds[$0] })

        var groups: [(id: String, group: DisplayGroup)] = []
        switch configuration.layout {
        case .clone:
            if let first = connected.first, let clone = configuration.clone(containing: first, connected: connected) {
                groups.append((Self.globalCloneID, clone))
            }
        case .perDisplay:
            groups = configuration.groups.filter { $0.layout == .clone }.map { ($0.id, $0) }
        case .stretch:
            break
        }
        let connectedSet = Set(connected)
        for (id, group) in groups {
            let members = group.members.filter(connectedSet.contains)
            guard members.count >= 2, let main = group.mainDisplay(connected: connectedSet),
                  let source = screenIds[main] else { continue }
            let screens = members.compactMap { screenIds[$0] }
            clones.append(Clone(id: id, screens: screens, source: source))
            for member in members where member != main {
                guard let screen = screenIds[member] else { continue }
                cloneSources[screen] = source
                if group.flipped.contains(member) { flipped.insert(screen) }
            }
        }
    }

    /// The display whose wallpaper `screenId` shows: its main clone display, or itself.
    func source(of screenId: String) -> String { cloneSources[screenId] ?? screenId }

    /// What each display of `selections` (each display's own) shows: a clone member its main
    /// clone display's, the others their own.
    func shown<Wallpaper>(_ selections: [String: Wallpaper]) -> [String: Wallpaper] {
        var shown = selections
        for (member, source) in cloneSources { shown[member] = selections[source] }
        return shown
    }

    /// The clone `screenId` is part of.
    func clone(containing screenId: String) -> Clone? {
        clones.first { $0.screens.contains(screenId) }
    }

    /// `screenIds` and every display that shares a clone with one of them.
    func expandingClones(_ screenIds: Set<String>) -> Set<String> {
        var result = screenIds
        for clone in clones where !screenIds.isDisjoint(with: clone.screens) { result.formUnion(clone.screens) }
        return result
    }
}
