import SwiftUI
import OWESceneEditing

/// The brush's controls while a mask is painted on the canvas, and Done, which saves the mask
/// and sets it on the effect in one undo step (Cancel leaves the effect as it was).
struct MaskPaintingHUD: View {
    @ObservedObject var painting: MaskPainting
    @ObservedObject var session: SceneEditSession
    @ObservedObject var tools: EditorTools
    let services: WallpaperEditorServices

    var body: some View {
        HStack(spacing: 12) {
            Label(L("Painting the mask of “\(painting.effectTitle)”"), systemImage: "paintbrush.pointed")
                .lineLimit(1)
                .font(.callout.weight(.medium))
            Picker(selection: $painting.mode) {
                Text(L("Paint")).tag(MaskPainting.Mode.paint)
                Text(L("Erase")).tag(MaskPainting.Mode.erase)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(L("Paint shows the effect; Erase hides it"))
            labeledSlider(L("Size"), value: $painting.brushSize,
                          range: 1...max(2, max(painting.layerSize.x, painting.layerSize.y) / 2))
            labeledSlider(L("Softness"), value: $painting.softness, range: 0...1)
            labeledSlider(L("Strength"), value: $painting.strength, range: 0.02...1)
            Menu {
                Button(L("Fill With White")) { painting.fill(white: true) }
                Button(L("Fill With Black")) { painting.fill(white: false) }
            } label: {
                Label(L("Fill"), systemImage: "paintbrush")
            }
            .fixedSize()
            Button { painting.undoStroke() } label: {
                Label(L("Undo Stroke"), systemImage: "arrow.uturn.backward").labelStyle(.iconOnly)
            }
            .disabled(!painting.canUndoStroke)
            .help(L("Undo Stroke"))
            Button(L("Cancel")) { tools.maskPainting = nil }
            Button(L("Done")) { finish() }
                .buttonStyle(.borderedProminent)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .editorGlass(in: Capsule())
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range).frame(width: 80)
        }
    }

    private func finish() {
        defer { tools.maskPainting = nil }
        guard let store = services.assetStore, let png = painting.pngData else { return }
        do {
            let path = try store.saveMask(png, title: painting.effectTitle)
            session.setEffectTexture(path, slot: painting.slot.slot, effect: painting.effectKey, of: painting.layer,
                                     combo: painting.slot.combo, actionName: L("Paint Mask"))
        } catch {
            tools.problem = L("The mask couldn’t be saved: \(error.localizedDescription)")
        }
    }
}
