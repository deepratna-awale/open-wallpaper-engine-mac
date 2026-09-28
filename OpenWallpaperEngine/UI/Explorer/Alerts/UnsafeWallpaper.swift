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
                    Text(verbatim: wallpaper.wallpaperDirectory.path(percentEncoded: false) + wallpaper.project.file).bold()
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
                    
                    if isIgnored {
                        var trustedWallpapers =
                        UserDefaults.app.array(forKey: "TrustedWallpapers") as? [String] ?? [String]()
                        
                        trustedWallpapers.append(AppDelegate.shared.wallpaperViewModel.nextCurrentWallpaper.wallpaperDirectory.path(percentEncoded: false))
                        
                        UserDefaults.app.set(trustedWallpapers, forKey: "TrustedWallpapers")
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
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onAppear {
            let _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                if self.seconds <= 0 {
                    timer.invalidate()
                } else {
                    self.seconds -= 1
                }
            }
        }
    }
}
