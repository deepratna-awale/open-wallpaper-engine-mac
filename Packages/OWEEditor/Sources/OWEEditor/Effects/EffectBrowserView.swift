import AppKit
import SwiftUI
import OWEInspectorKit
import OWESceneEditing

/// Add Effect: WE's built-in effects and the Workshop effects the wallpaper uses, searchable, in
/// WE's groups, each with its preview and description. A preview is the effect at its defaults
/// on the editor's test card, rendered on first view and cached (`EditorPreviewProvider`); a
/// moving effect's is a short loop. Without WE's assets it offers to install them.
struct EffectBrowserView: View {
    let entries: [EffectCatalogEntry]
    let previews: EditorPreviewProvider?
    let hasWEAssets: Bool
    let openAssetsSetup: () -> Void
    let add: (EffectCatalogEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: EffectCatalogEntry.ID?

    private static let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Add Effect")).font(.headline)
                Spacer()
                TextField(L("Search Effects"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }
            .padding(14)
            Divider()
            ScrollView {
                let groups = EffectCatalog.grouped(EffectCatalog.filter(entries, query: query))
                if !hasWEAssets {
                    EditorAssetsPrompt(message: L("Wallpaper Engine’s effects come with its assets, which aren’t installed."),
                                       openSetup: openSetup)
                } else if groups.isEmpty {
                    Text(entries.isEmpty ? L("Wallpaper Engine’s effects aren’t installed.") : L("No effects match."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                }
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title.isEmpty ? L("Other") : group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 12) {
                                ForEach(group.entries) { entry in
                                    EffectTile(entry: entry, previews: previews, isSelected: selection == entry.id)
                                        .onTapGesture(count: 2) { choose(entry) }
                                        .onTapGesture { selection = entry.id }
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
            Divider()
            HStack {
                if let entry = selectedEntry, !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(L("Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Add")) { selectedEntry.map(choose) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedEntry == nil)
            }
            .padding(14)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 480, idealHeight: 600)
        .onAppear { previews?.beginOpen(.effects) }
        .onDisappear { previews?.endOpen() }
    }

    private var selectedEntry: EffectCatalogEntry? { entries.first { $0.id == selection } }

    private func openSetup() {
        dismiss()
        openAssetsSetup()
    }

    private func choose(_ entry: EffectCatalogEntry) {
        dismiss()
        add(entry)
    }
}

private struct EffectTile: View {
    @Environment(\.appAccentColor) private var accentColor
    let entry: EffectCatalogEntry
    let previews: EditorPreviewProvider?
    let isSelected: Bool
    @State private var preview: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6))
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if entry.preview == nil, let previews {
                    EditorPreviewView(provider: previews, subject: entry.previewSubject,
                                      symbol: EffectGroupSymbol.symbol(entry.group))
                } else {
                    SymbolPreview(symbol: EffectGroupSymbol.symbol(entry.group))
                }
            }
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 4) {
                Text(entry.title).font(.callout.weight(.medium)).lineLimit(1)
                if entry.isWorkshop {
                    Text(L("Workshop"))
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
            if !entry.summary.isEmpty {
                Text(entry.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(8)
        .background(isSelected ? accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? accentColor : .clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .help(entry.summary)
        .task(id: entry.preview) {
            // A picture the effect's folder ships, where it has one.
            guard let url = entry.preview else { return }
            preview = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
        }
    }
}

/// A symbol for each of WE's effect groups, while an effect's preview renders or when it has none.
/// Never `sparkles`, which stands for particle systems.
enum EffectGroupSymbol {
    static func symbol(_ group: String) -> String {
        switch group.lowercased() {
        case "animate": return "wind"
        case "blur": return "aqi.medium"
        case "distort": return "water.waves"
        case "enhance": return "wand.and.rays"
        case "simulate": return "drop"
        case "adjust", "color": return "slider.horizontal.3"
        case "interactive": return "cursorarrow.motionlines"
        case "mask": return "theatermask.and.paintbrush"
        default: return "slider.horizontal.3"
        }
    }
}
