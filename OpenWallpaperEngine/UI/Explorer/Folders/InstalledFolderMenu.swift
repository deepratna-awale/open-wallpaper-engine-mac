import SwiftUI

/// A folder tile's context menu, WE's: Open, Rename, Change Icon, Change Color, Move to Folder
/// and Remove Folder, with Create Folder for a folder inside the one shown.
struct InstalledFolderMenu: View {
    var viewModel: ContentViewModel
    var folder: InstalledFolder

    private var library: InstalledLibraryModel { viewModel.library }

    var body: some View {
        Group {
            Section {
                Button {
                    library.open(folder: folder.id)
                } label: {
                    Label("Open", systemImage: "folder")
                }
                Button {
                    viewModel.presentation.folderNamePrompt = .rename(folder.id, folder.title)
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                iconMenu
                colorMenu
                MoveToFolderMenu(library: library, movingFolder: folder.id) { destination in
                    library.move(folder: folder.id, toFolder: destination)
                }
            }
            Section {
                Button(role: .destructive) {
                    viewModel.presentation.folderRemoval = folder
                } label: {
                    Label {
                        Text("Remove Folder…", comment: "Context menu of a folder in the Installed tab; its wallpapers go back to the top level")
                    } icon: {
                        Image(systemName: "folder.badge.minus")
                    }
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var iconMenu: some View {
        Menu {
            Button {
                library.setIcon(nil, ofFolder: folder.id)
            } label: {
                Label {
                    Text("Default", comment: "Change Icon / Change Color menu item: the plain folder icon or colour")
                } icon: {
                    Image(systemName: folder.icon == nil ? "checkmark" : "folder")
                }
            }
            Divider()
            ForEach(InstalledFolderIcon.allCases, id: \.self) { icon in
                Button {
                    library.setIcon(icon, ofFolder: folder.id)
                } label: {
                    Image(systemName: folder.icon == icon ? "checkmark" : icon.systemImage)
                }
            }
        } label: {
            Label {
                Text("Change Icon", comment: "Context menu of a folder in the Installed tab")
            } icon: {
                Image(systemName: "star.square")
            }
        }
    }

    private var colorMenu: some View {
        Menu {
            Button {
                library.setColor(nil, ofFolder: folder.id)
            } label: {
                Label {
                    Text("Default", comment: "Change Icon / Change Color menu item: the plain folder icon or colour")
                } icon: {
                    Image(systemName: folder.color == nil ? "checkmark" : "circle")
                }
            }
            Divider()
            ForEach(InstalledFolderColor.allCases, id: \.self) { color in
                Button {
                    library.setColor(color, ofFolder: folder.id)
                } label: {
                    Label {
                        Text(color.label)
                    } icon: {
                        Image(systemName: folder.color == color ? "checkmark.circle.fill" : "circle.fill")
                            .foregroundStyle(color.color)
                    }
                }
            }
        } label: {
            Label {
                Text("Change Color", comment: "Context menu of a folder in the Installed tab")
            } icon: {
                Image(systemName: "paintpalette")
            }
        }
    }
}
