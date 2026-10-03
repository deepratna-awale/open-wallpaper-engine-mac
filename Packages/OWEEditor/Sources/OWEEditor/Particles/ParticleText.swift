import Foundation
import OWESceneEditing

/// The particle editor's text, from its own catalog (`Particles/Resources/Particles.xcstrings`),
/// which holds every language the app ships.
func PL(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "Particles", bundle: .module)
}

/// A text the schema names (a field's label, a component's name, an option): WE's English
/// wording, translated by the same catalog.
func PLSchema(_ english: String) -> String {
    Bundle.module.localizedString(forKey: english, value: english, table: "Particles")
}

extension ParticleEditorSchema.Section {
    /// The panel section's heading.
    var title: String {
        switch self {
        case .emitter: return PL("Emitters")
        case .initializer: return PL("Initializers")
        case .operator: return PL("Operators")
        case .renderer: return PL("Renderers")
        case .children: return PL("Children")
        case .controlpoint: return PL("Control Points")
        case .system: return PL("General")
        case .instanceoverride: return PL("Instance Override")
        }
    }

    /// The Add menu's title for the section.
    var addTitle: String {
        switch self {
        case .emitter: return PL("Add Emitter")
        case .initializer: return PL("Add Initializer")
        case .operator: return PL("Add Operator")
        case .renderer: return PL("Add Renderer")
        case .children: return PL("Add Child")
        case .controlpoint: return PL("Add Control Point")
        case .system, .instanceoverride: return PL("Add")
        }
    }

    /// Shown when the list is empty.
    var emptyText: String {
        switch self {
        case .emitter: return PL("No emitters: the system spawns nothing.")
        case .initializer: return PL("No initializers")
        case .operator: return PL("No operators")
        case .renderer: return PL("No renderer: sprites are drawn.")
        case .children: return PL("No child systems")
        case .controlpoint: return PL("No control points")
        case .system, .instanceoverride: return ""
        }
    }
}

extension ParticleEditorSchema.Component {
    var localizedTitle: String { PLSchema(title) }
}

extension ParticleEditorSchema.Field {
    var localizedLabel: String { PLSchema(label) }

    /// A vector component's name: the axis letters as they are, words translated.
    func localizedComponent(_ index: Int) -> String {
        guard components.indices.contains(index) else { return ["X", "Y", "Z", "W"][min(index, 3)] }
        let name = components[index]
        return name.count == 1 ? name : PLSchema(name)
    }
}

extension ParticleEditorSchema.Option {
    var localizedLabel: String { PLSchema(label) }
}
