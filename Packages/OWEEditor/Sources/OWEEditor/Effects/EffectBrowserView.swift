import AppKit
import SwiftUI
import OWESceneEditing

/// Add Effect: WE's built-in effects and the Workshop effects the wallpaper uses, searchable, in
/// WE's groups, each with its preview (or its group's symbol) and description.
struct EffectBrowserView: View {
    let entries: [EffectCatalogEntry]
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
                if groups.isEmpty {
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
                                    EffectTile(entry: entry, isSelected: selection == entry.id)
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
    }

    private var selectedEntry: EffectCatalogEntry? { entries.first { $0.id == selection } }

    private func choose(_ entry: EffectCatalogEntry) {
        dismiss()
        add(entry)
    }
}

private struct EffectTile: View {
    let entry: EffectCatalogEntry
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
                } else {
                    Image(systemName: EffectGroupSymbol.symbol(entry.group))
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
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
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .help(entry.summary)
        .task(id: entry.preview) {
            guard let url = entry.preview else { return }
            preview = NSImage(contentsOf: url)
        }
    }
}

/// A symbol for each of WE's effect groups, for effects without a preview.
enum EffectGroupSymbol {
    static func symbol(_ group: String) -> String {
        switch group.lowercased() {
        case "animate": return "wind"
        case "blur": return "aqi.medium"
        case "distort": return "water.waves"
        case "enhance": return "sparkles"
        case "simulate": return "drop"
        case "adjust", "color": return "slider.horizontal.3"
        case "interactive": return "cursorarrow.motionlines"
        case "mask": return "theatermask.and.paintbrush"
        default: return "wand.and.stars"
        }
    }
}
