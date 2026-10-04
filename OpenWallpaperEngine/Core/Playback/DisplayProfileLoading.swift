import Foundation

/// Saved display profiles, WE's "Save profile" / "Load profile": the displays' wallpapers and
/// layout under a name. An application rule's "Load profile" loads one by name (WE's
/// `loadprofile`), and its editor lists them.
@MainActor
protocol DisplayProfileLoading: AnyObject {
    /// Whether this app can save and load profiles at all. While it can't, the rule editor
    /// still offers "Load profile" and says when profiles become available.
    var isAvailable: Bool { get }
    /// The saved profiles' names, in the order the user sees them.
    var profileNames: [String] { get }
    /// Loads the profile named `name`; false when there is none by that name.
    func load(name: String) -> Bool
}

/// The profiles before display layouts can be saved: none to list or load.
@MainActor
final class UnavailableDisplayProfiles: DisplayProfileLoading {
    var isAvailable: Bool { false }
    var profileNames: [String] { [] }
    func load(name: String) -> Bool { false }
}
