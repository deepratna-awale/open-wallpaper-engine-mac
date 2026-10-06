import Foundation
import OWESceneEditing

/// The editor's text, from this module's catalog (`Resources/Localizable.xcstrings`), which
/// holds every language the app ships.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

extension SceneLayer.Kind {
    /// The kind as the layer list and the inspector name it.
    var title: String {
        switch self {
        case .image: return L("Image")
        case .text: return L("Text")
        case .particle: return L("Particle System")
        case .sound: return L("Sound")
        case .light: return L("Light")
        case .model: return L("3D Model")
        case .group: return L("Group")
        case .other: return L("Object")
        }
    }
}

extension SceneLayer {
    /// Its authored name, else its kind and position ("Image 3").
    var title: String {
        displayName { kind, number in L("\(kind.title) \(number)") }
    }
}
