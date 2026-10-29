import Foundation

/// Wallpaper Engine's favourites as `FavoritesStore` keys.
///
/// Wallpaper Engine has no favourites file: its heart calls `setFavorited` with the items'
/// Workshop ids, which favourites them in the Steam account, and the Installed tab reads them back
/// with Steam's favourited-items query. `config.json` keeps only the Discover page's followed
/// searches (`general.browser.explore.favorites`), and the Steam Cloud folder of app 431960 holds
/// only `statsutility.bin`. Only Workshop items can be favourited (the context menu skips items
/// without a `workshopid`), so every favourite maps to `workshop-<id>`, the key a Workshop
/// wallpaper has here whether or not it is installed (`FavoritesStore.key(for:)`).
enum WallpaperEngineFavorites {
    /// The keys of the favourited Workshop ids, in order, without repeats or ids that aren't one.
    static func keys(forWorkshopIDs ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter(WorkshopCollection.isID).compactMap { id in
            let key = "workshop-\(id)"
            return seen.insert(key).inserted ? key : nil
        }
    }

    /// The Workshop id a `FavoritesStore` key names; nil for a local wallpaper's key.
    static func workshopID(forKey key: String) -> String? {
        guard key.hasPrefix("workshop-") else { return nil }
        let id = String(key.dropFirst("workshop-".count))
        return WorkshopCollection.isID(id) ? id : nil
    }
}
