import Foundation

/// The canvas gizmos' text, from their own catalog (`Resources/Gizmos.xcstrings`), in every
/// language the app ships.
func G(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "Gizmos", bundle: .module)
}
