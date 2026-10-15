import Foundation

/// The effect gizmos' text, from their own catalog (`Resources/EffectGizmos.xcstrings`), in every
/// language the app ships.
func EG(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "EffectGizmos", bundle: .module)
}
