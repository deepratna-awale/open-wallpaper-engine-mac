//
//  UnsafeWallpaper.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/9/2.
//

import SwiftUI

struct UnsafeWallpaper: View {
    @Environment(\.dismiss) var dismiss
    
    var wallpaper: WEWallpaper
    
    @State var seconds: Int = 5
    @State var isIgnored = false
    
    init(wallpaper: WEWallpaper) {
        self.wallpaper = wallpaper
    }
    
    /// `trusted` with `path` added once, earlier duplicates dropped, in the order trust was given.
    static func trustList(_ trusted: [String], adding path: String) -> [String] {
        var seen = Set<String>()
        return (trusted + [path]).filter { seen.insert($0).inserted }
    }

    private var title: LocalizedStringKey {
        switch wallpaper.project.type.lowercased() {
        case "web": return "Opening an Unknown Web Page"
        case "application": return "Opening an Unknown Application"
        default: return "Opening an Unknown Wallpaper"
        }
    }

    private var intro: LocalizedStringKey {
        switch wallpaper.project.type.lowercased() {
        case "web": return "You are about to open an external web page as a wallpaper:"
        case "application": return "You are about to open an external application as a wallpaper:"
        default: return "You are about to open an external file of an unknown type as a wallpaper:"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .font(.title2)
            Divider()
            HStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .shadow(radius: 6)
                    .frame(maxWidth: 100)
                VStack(alignment: .leading, spacing: 10) {
                    Text(intro)
                    Text(verbatim: wallpaper.wallpaperDirectory.appending(path: wallpaper.project.file).path(percentEncoded: false)).bold()
                    Text("Open Wallpaper Engine has no control over this file. Make sure it comes from a reliable source before proceeding.")
                    Text(seconds > 0 ? "Please wait \(seconds) seconds." : "Please be aware of malware.")
                    Toggle("Don't ask again for this wallpaper", isOn: $isIgnored)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal)
            Divider()
            HStack {
                Button {
                    AppDelegate.shared.wallpaperViewModel.currentWallpaper =
                    AppDelegate.shared.wallpaperViewModel.nextCurrentWallpaper
                    ChromiumFeatureAdvisor.shared.wallpaperApplied(AppDelegate.shared.wallpaperViewModel.nextCurrentWallpaper)

                    if isIgnored {
                        let trusted = UserDefaults.app.array(forKey: "TrustedWallpapers") as? [String] ?? []
                        let path = AppDelegate.shared.wallpaperViewModel.nextCurrentWallpaper.wallpaperDirectory.path(percentEncoded: false)
                        UserDefaults.app.set(Self.trustList(trusted, adding: path), forKey: "TrustedWallpapers")
                    }
                    
                    dismiss()
                } label: {
                    Text("Proceed")
                        .padding(.horizontal, 10)
                }
                .animation(.default, value: seconds)
                .glassButtonStyle(.prominent)
                .tint(.red)
                .disabled(seconds > 0 ? true : false)
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .padding(.horizontal, 10)
                }
                .glassButtonStyle()
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // Counts down while the sheet is shown, in every run-loop mode, and stops with it.
        .task {
            while seconds > 0 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                seconds -= 1
            }
        }
    }
}
