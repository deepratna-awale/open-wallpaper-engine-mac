//
//  PluginsPage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/12.
//

import SwiftUI

struct PluginsPage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel
    
    @State var bigGearAngle = 0.0
    @State var smallGearAngle = 0.0
    
    @AppStorage("TestAnimates", store: .app) var animates = false
    
    @State var isExpanded = false
    
    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 20) {
                    Toggle("Animates", isOn: $animates)
                    if isExpanded {
                        HStack {
                            GifImage("maxwell-cat", animates: animates)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 100, maxHeight: 100)
                                .padding(4)
                                .glassBackground(in: RoundedRectangle(cornerRadius: 16.0)) { tile in
                                    tile
                                        .background(Material.thin)
                                        .clipShape(RoundedRectangle(cornerRadius: 16.0))
                                }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("This plugin animates the GIF thumbnails in the wallpaper explorer.")
                                Spacer()
                                Text("􀄪 Toggle it to see a preview.")
                                Spacer()
                                Text("This may affect performance.")
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        VStack {
                            if isExpanded {
                                Image(systemName: "chevron.up")
                                    .bold()
                                    .imageScale(.large)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Description…")
                            }
                        }
                    }
                    .tint(.accentColor)
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                }
                Text("Coming soon…")
            } header: {
                Label("Internal", systemImage: "square.dashed.inset.filled")
            }
            Section {
                Text("None")
            } header: {
                Label("Third-party", systemImage: "person.3.fill")
            } footer: {
                Text("These settings take effect without saving.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct PluginPage_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject({ () -> GlobalSettingsViewModel in
                let viewModel = GlobalSettingsViewModel()
                viewModel.selection = 3
                return viewModel
            }())
            .frame(width: 500, height: 600)
    }
}
