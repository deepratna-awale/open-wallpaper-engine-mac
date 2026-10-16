import Foundation

/// The View menu's and the canvas views' text, from their own catalog
/// (`Resources/CanvasView.xcstrings`), in every language the app ships.
func CV(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "CanvasView", bundle: .module)
}
