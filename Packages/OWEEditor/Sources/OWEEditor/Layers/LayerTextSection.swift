import SwiftUI
import OWEInspectorKit
import OWESceneEditing

/// A text layer's Text section: what it says (or the script that writes it, a clock or a date,
/// with the script's options), its font, size, alignment and padding.
struct LayerTextSection: View {
    @ObservedObject var session: SceneEditSession
    @ObservedObject var tools: EditorTools
    let services: WallpaperEditorServices
    let layer: SceneLayer

    var body: some View {
        Section(L("Text")) {
            let script = session.textScript(of: layer.id)
            let known = SceneLayerFactory.TextScript(source: script)
            LabeledContent(L("Content")) {
                Picker(selection: Binding<String>(
                    get: { known?.rawValue ?? (script == nil ? "none" : "custom") },
                    set: { choice in
                        guard choice != "custom" else { return }
                        session.setTextScript(SceneLayerFactory.TextScript(rawValue: choice), of: layer.id,
                                              actionName: L("Change Text Script"))
                    })) {
                    Text(L("Text")).tag("none")
                    Text(L("Clock")).tag(SceneLayerFactory.TextScript.clock.rawValue)
                    Text(L("Date")).tag(SceneLayerFactory.TextScript.date.rawValue)
                    if script != nil && known == nil { Text(L("Script")).tag("custom") }
                } label: { EmptyView() }
                .labelsHidden()
                .disabled(!session.isEditable("text", of: layer.id))
            }
            if script == nil {
                TextEditor(text: Binding(
                    get: { session.textContent(of: layer.id) ?? "" },
                    set: { session.setText($0, of: layer.id, actionName: L("Change Text")) }))
                    .font(.body)
                    .frame(minHeight: 54, maxHeight: 120)
                    .disabled(!session.isEditable("text", of: layer.id))
            } else if known == .clock {
                scriptToggle("use24hFormat", title: L("24-Hour Clock"), default: true)
                scriptToggle("showSeconds", title: L("Show Seconds"), default: false)
                LabeledContent(L("Separator")) {
                    TextField(L("Separator"), text: Binding(
                        get: { session.textScriptProperties(of: layer.id)["delimiter"]?.stringValue ?? ":" },
                        set: { session.setTextScriptProperty("delimiter", to: .string($0), of: layer.id,
                                                             actionName: L("Change Text Script")) }))
                    .labelsHidden()
                    .frame(width: 60)
                }
            } else if known == .date {
                scriptToggle("showWeekday", title: L("Show Weekday"), default: true)
            } else {
                Text(L("A script writes this text. Its code is edited in the Script editor."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            fontRow
            fieldRow("pointsize", title: L("Size")) {
                NumericSliderInput(value: Binding(
                    get: { session.number("pointsize", of: layer.id, default: 32) },
                    set: { session.setValue(.number($0.rounded()), for: "pointsize", of: layer.id,
                                            actionName: L("Change Text Size"), coalescing: true) }),
                    range: 4...256, defaultValue: 32, step: 1, fractionDigits: 0, fieldWidth: 48, clampsTypedValue: false)
            }
            fieldRow("horizontalalign", title: L("Alignment")) {
                Picker(selection: Binding(
                    get: { session.value("horizontalalign", of: layer.id)?.stringValue ?? "center" },
                    set: { session.setValue(.string($0), for: "horizontalalign", of: layer.id, actionName: L("Change Alignment")) })) {
                    Image(systemName: "text.alignleft").help(L("Left")).tag("left")
                    Image(systemName: "text.aligncenter").help(L("Center")).tag("center")
                    Image(systemName: "text.alignright").help(L("Right")).tag("right")
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            fieldRow("verticalalign", title: L("Vertical Alignment")) {
                Picker(selection: Binding(
                    get: { session.value("verticalalign", of: layer.id)?.stringValue ?? "center" },
                    set: { session.setValue(.string($0), for: "verticalalign", of: layer.id, actionName: L("Change Alignment")) })) {
                    Text(L("Top")).tag("top")
                    Text(L("Center")).tag("center")
                    Text(L("Bottom")).tag("bottom")
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            fieldRow("padding", title: L("Padding")) {
                NumericSliderInput(value: Binding(
                    get: { SceneVector.components(session.value("padding", of: layer.id)).first ?? 32 },
                    set: { session.setValue(.number($0.rounded()), for: "padding", of: layer.id,
                                            actionName: L("Change Padding"), coalescing: true) }),
                    range: 0...200, defaultValue: 32, step: 1, fractionDigits: 0, fieldWidth: 48, clampsTypedValue: false)
            }
            Button(L("Edit on Canvas")) { session.editingText = layer.id }
                .disabled(script != nil || session.geometry(of: layer.id) == nil)
        }
    }

    private func scriptToggle(_ name: String, title: String, default fallback: Bool) -> some View {
        Toggle(title, isOn: Binding(
            get: { session.textScriptProperties(of: layer.id)[name]?.boolValue ?? fallback },
            set: { session.setTextScriptProperty(name, to: .bool($0), of: layer.id, actionName: L("Change Text Script")) }))
            .toggleStyle(.checkbox)
    }

    private var fontRow: some View {
        let current = session.value("font", of: layer.id)?.stringValue ?? "systemfont_arial"
        var fonts = services.fonts()
        if !fonts.contains(where: { $0.value == current }) {
            fonts.insert(EditorFont(value: current, title: (current as NSString).lastPathComponent), at: 0)
        }
        return fieldRow("font", title: L("Font")) {
            HStack(spacing: 4) {
                Picker(selection: Binding(
                    get: { current },
                    set: { session.setValue(.string($0), for: "font", of: layer.id, actionName: L("Change Font")) })) {
                    ForEach(fonts) { font in Text(font.title).tag(font.value) }
                } label: { EmptyView() }
                .labelsHidden()
                Button {
                    importFont()
                } label: {
                    Label(L("Import Font…"), systemImage: "plus").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(services.assetStore == nil)
                .help(L("Import Font…"))
            }
        }
    }

    private func importFont() {
        guard let store = services.assetStore, let url = EditorFilePicker.choose(.font).first else { return }
        do {
            let path = try store.importFont(from: url)
            session.setValue(.string(path), for: "font", of: layer.id, actionName: L("Change Font"))
        } catch {
            tools.problem = L("“\(url.lastPathComponent)” couldn’t be added: \(error.localizedDescription)")
        }
    }

    /// The field's control, or, for one a user property sets, which property.
    @ViewBuilder private func fieldRow<Control: View>(_ field: String, title: String,
                                                      @ViewBuilder control: () -> Control) -> some View {
        if case .userProperty(let name) = session.binding(field, of: layer.id) {
            LabeledContent(title) {
                Text(L("Set by the user property “\(name)”")).foregroundStyle(.secondary)
            }
        } else {
            LabeledContent(title) { control() }
        }
    }
}

/// An image layer's size, and a solid layer's fill.
struct LayerSizeRows: View {
    @ObservedObject var session: SceneEditSession
    let layer: SceneLayer

    var body: some View {
        if layer.kind == .image, !layer.fillsScene {
            LabeledContent(L("Size")) {
                HStack {
                    sizeField("W", component: 0)
                    sizeField("H", component: 1)
                }
            }
        }
    }

    private func sizeField(_ axis: String, component: Int) -> some View {
        TextField(value: Binding<Double>(
            get: { SceneVector.components(session.value("size", of: layer.id), fallback: [100, 100])[component] },
            set: { value in
                var size = SceneVector.components(session.value("size", of: layer.id), fallback: [100, 100])
                size[component] = max(value, 1)
                session.setValue(SceneVector.value(size), for: "size", of: layer.id, actionName: L("Change Size"), coalescing: true)
            }), format: .number.precision(.fractionLength(0...1))) {
            Text(verbatim: axis)
        }
        .multilineTextAlignment(.trailing)
        .disabled(!session.isEditable("size", of: layer.id))
    }
}
