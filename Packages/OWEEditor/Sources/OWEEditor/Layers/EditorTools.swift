import AppKit
import UniformTypeIdentifiers
import SwiftUI
import OWESceneEditing

/// The window's tool state the canvas, the layer list and the inspector share: snapping and its
/// guides, mask painting, and the sidebar's tab.
@MainActor
final class EditorTools: ObservableObject {
    enum SidebarTab: String, CaseIterable, Identifiable {
        case layers, assets
        var id: String { rawValue }
    }

    /// Dragged layers snap to the scene's edges and centre and to other layers (Command while
    /// dragging turns it off for that drag).
    @Published var snapping = true
    /// Where the drag in progress snapped, drawn on the canvas.
    @Published var guides: [LayerSnapping.Guide] = []
    @Published var maskPainting: MaskPainting?
    @Published var sidebarTab: SidebarTab = .layers
    /// The layer whose name is being edited in the list.
    @Published var renaming: Int?
    /// A message for the window's banner (an import that failed, say).
    @Published var problem: String?

    /// Canvas points within which a drag snaps.
    static let snapDistance: Double = 6
}

/// Choosing files to import, as the Add menu and the asset browser do.
@MainActor
enum EditorFilePicker {
    enum Kind {
        case image, sound, font, mask

        var allowedExtensions: [String] {
            switch self {
            case .image, .mask: return ["png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "heic", "webp", "psd", "tga"]
            case .sound: return EditorAssetStore.soundTypes.sorted()
            case .font: return EditorAssetStore.fontTypes.sorted()
            }
        }
    }

    /// The files chosen; empty when the panel was cancelled.
    static func choose(_ kind: Kind, multiple: Bool = false) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        panel.allowedContentTypes = kind.allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
