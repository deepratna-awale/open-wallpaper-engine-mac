import Foundation

/// The layer and effect commands' text, from their own catalog (`Resources/LayerCommands.xcstrings`),
/// in every language the app ships. Whole numbers are interpolated as `number`.
func LC(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "LayerCommands", bundle: .module)
}
