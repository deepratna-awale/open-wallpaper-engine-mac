//
//  FilterResults.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/6/29.
//

import SwiftUI

/// The Installed tab's filters, in the main window's sidebar.
struct FilterResults: View {
    @ObservedObject var viewModel: FilterResultsViewModel

    @State private var expandedSections: Set<String> = ["Show Only", "Type", "Age Rating", "Resolution", "Source", "Tags"]

    var body: some View {
        List {
            Button {
                viewModel.reset()
            } label: {
                Label("Reset Filters", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .glassButtonStyle(.prominent)
            .listRowSeparator(.hidden)

            Section("Show Only:", isExpanded: isExpanded("Show Only")) {
                ForEach(Array(zip(FRShowOnly.allOptions.indices, FRShowOnly.allOptions)), id: \.0) { (i, option) in
                    let (option, image) = option
                    let color: Color = {
                        if i == 0 {
                            return Color.green
                        } else if i == 1 {
                            return Color.pink
                        } else if i == 2 {
                            return Color.orange
                        } else {
                            return Color.accentColor
                        }
                    }()
                    Toggle(isOn: Binding<Bool>(get: {
                        viewModel.showOnly.contains(FRShowOnly(rawValue: 1 << i))
                    }, set: {
                        if $0 {
                            viewModel.showOnly.insert(FRShowOnly(rawValue: 1 << i))
                        } else {
                            viewModel.showOnly.remove(FRShowOnly(rawValue: 1 << i))
                        }
                        OWELog.debug(.ui, "Filter viewModel.showOnly = \(String(describing: viewModel.showOnly))")
                    })) {
                        HStack(spacing: 2) {
                            Image(systemName: image)
                                .foregroundStyle(color)
                            Text(option)
                        }
                    }
                }
            }
            Section("Type", isExpanded: isExpanded("Type")) {
                toggles(\.type, name: "type")
            }
            Section("Age Rating", isExpanded: isExpanded("Age Rating")) {
                toggles(\.ageRating, name: "ageRating")
            }
            // Resolution, Source and Tags aren't matched against wallpapers yet.
            Group {
                Section("Resolution", isExpanded: isExpanded("Resolution")) {
                    resolutionGroup("Widescreen", \.widescreenResolution, name: "widescreenResolution")
                    resolutionGroup("Ultra Widescreen", \.ultraWidescreenResolution, name: "ultraWidescreenResolution")
                    resolutionGroup("Dual Monitor", \.dualscreenResolution, name: "dualscreenResolution")
                    resolutionGroup("Triple Monitor", \.triplescreenResolution, name: "triplescreenResolution")
                    resolutionGroup("Potrait Monitor / Phone", \.potraitscreenResolution, name: "potraitscreenResolution")
                    toggles(\.miscResolution, name: "miscResolution")
                }
                Section("Source", isExpanded: isExpanded("Source")) {
                    toggles(\.source, name: "source")
                }
                Section("Tags", isExpanded: isExpanded("Tags")) {
                    allNoneButtons(\.tag)
                    toggles(\.tag, name: "tag")
                }
            }
            .disabled(true)
        }
        .listStyle(.sidebar)
        .toggleStyle(.checkbox)
        .lineLimit(1)
    }

    private func isExpanded(_ title: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(title) },
            set: { expanded in
                withAnimation {
                    if expanded { expandedSections.insert(title) } else { expandedSections.remove(title) }
                }
            }
        )
    }

    /// One checkbox per option; option `i` is bit `1 << i`.
    private func toggles<Option: FilterResultsModel>(
        _ keyPath: ReferenceWritableKeyPath<FilterResultsViewModel, Option>, name: String
    ) -> some View {
        ForEach(Array(zip(Option.allOptions.indices, Option.allOptions)), id: \.0) { (i, option) in
            Toggle(option, isOn: Binding<Bool>(get: {
                viewModel[keyPath: keyPath].contains(Option(rawValue: 1 << i))
            }, set: {
                if $0 {
                    viewModel[keyPath: keyPath].insert(Option(rawValue: 1 << i))
                } else {
                    viewModel[keyPath: keyPath].remove(Option(rawValue: 1 << i))
                }
                OWELog.debug(.ui, "Filter viewModel.\(name) = \(String(describing: viewModel[keyPath: keyPath]))")
            }))
        }
    }

    private func allNoneButtons<Option: FilterResultsModel>(
        _ keyPath: ReferenceWritableKeyPath<FilterResultsViewModel, Option>
    ) -> some View {
        HStack {
            Button("All") {
                viewModel[keyPath: keyPath] = .all
            }
            Button("None") {
                viewModel[keyPath: keyPath] = .none
            }
        }
        .buttonStyle(.link)
    }

    @ViewBuilder
    private func resolutionGroup<Option: FilterResultsModel>(
        _ title: LocalizedStringKey,
        _ keyPath: ReferenceWritableKeyPath<FilterResultsViewModel, Option>, name: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .bold()
            allNoneButtons(keyPath)
        }
        .padding(.top, 5)
        toggles(keyPath, name: name)
    }
}
