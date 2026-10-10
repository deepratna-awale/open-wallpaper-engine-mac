import SwiftUI

/// The path to the folder shown, above the grid: Installed › Games › Retro. Each step opens
/// that folder (Installed is the top level, WE's Home), and wallpapers or folders dropped on one
/// move there.
struct InstalledFolderBreadcrumbs: View {
    var viewModel: ContentViewModel

    var body: some View {
        let path = viewModel.library.folderPath
        HStack(spacing: 4) {
            Button {
                viewModel.library.open(folder: path.dropLast().last?.id)
            } label: {
                Image(systemName: "chevron.backward")
            }
            .buttonStyle(.borderless)
            .help("Back")
            .keyboardShortcut("[", modifiers: .command)
            BreadcrumbStep(library: viewModel.library, folder: nil, isLast: false)
            ForEach(Array(path.enumerated()), id: \.element.id) { index, folder in
                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                BreadcrumbStep(library: viewModel.library, folder: folder, isLast: index == path.count - 1)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BreadcrumbStep: View {
    var library: InstalledLibraryModel
    /// nil is the top level.
    var folder: InstalledFolder?
    var isLast: Bool
    @State private var isTargeted = false

    var body: some View {
        Button {
            library.open(folder: folder?.id)
        } label: {
            Group {
                if let folder {
                    Label {
                        Text(verbatim: folder.title)
                    } icon: {
                        Image(systemName: folder.icon?.systemImage ?? "folder.fill")
                            .foregroundStyle(folder.color?.color ?? Color.secondary)
                    }
                } else {
                    Label("Installed", systemImage: "house")
                }
            }
            .fontWeight(isLast ? .semibold : .regular)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(isTargeted ? Color.accentColor.opacity(0.3) : .clear))
        }
        .buttonStyle(.borderless)
        .disabled(isLast)
        .dropDestination(for: String.self) { texts, _ in
            library.drop(texts, into: folder?.id)
        } isTargeted: { isTargeted = $0 }
    }
}
