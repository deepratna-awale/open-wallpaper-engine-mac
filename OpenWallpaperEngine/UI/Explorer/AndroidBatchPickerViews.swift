import SwiftUI

/// The Installed tab's banner while it picks wallpapers for an Android batch
/// (`AndroidBatchPicker`): what the tab is doing, and the settings the batch uses.
struct AndroidBatchPickerBanner: View {
    var selection: AndroidBatchPicker
    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.down.right")
                .font(.title3)
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose wallpapers to export to Android")
                    .font(.headline)
                Text(verbatim: selection.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentColor.opacity(0.16))
        .accessibilityElement(children: .combine)
    }
}

/// The Installed tab's only actions while it picks wallpapers for an Android batch: how many are
/// picked, Export as .mpkg and Cancel (Esc).
struct AndroidBatchPickerBar: View {
    var selection: AndroidBatchPicker

    var body: some View {
        GlassGroup {
            HStack(spacing: 8) {
                Text("\(selection.count) selected")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                Button("Cancel", role: .cancel) { selection.cancel() }
                    .glassButtonStyle()
                    .keyboardShortcut(.cancelAction)
                Button {
                    selection.export()
                } label: {
                    Label("Export as .mpkg", systemImage: "square.and.arrow.up")
                }
                .glassButtonStyle(.prominent)
                .disabled(selection.count == 0)
            }
            .padding(.vertical, 8)
        }
    }
}

extension View {
    /// The library's context menu, left out while the Installed tab picks wallpapers for an export.
    @ViewBuilder
    func libraryContextMenu<Menu: View>(isEnabled: Bool, @ViewBuilder _ menu: () -> Menu) -> some View {
        if isEnabled {
            contextMenu(menuItems: menu)
        } else {
            self
        }
    }
}
