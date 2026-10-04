import OWETheming
import SwiftUI

/// Settings › General › Theming: macOS follows the scheme colour of the main display's wallpaper
/// (`ThemingController`, docs/theming.md). A master switch and one checkbox per target, all off by
/// default.
struct ThemingSection: View {
    @ObservedObject var viewModel: GlobalSettingsViewModel
    @ObservedObject var controller: ThemingController

    private var theming: Binding<ThemingSettings> { $viewModel.settings.theming }
    private var isOn: Bool { viewModel.settings.theming.isEnabled }

    var body: some View {
        Section {
            Toggle("Theme macOS with the Wallpaper's Color", isOn: theming.isEnabled)
                .changedFromDefault(viewModel.isChanged(\.theming))
                .help("Uses the scheme color of the wallpaper on the main display, which follows its properties. Turning it off puts your own settings back.")
            if isOn {
                LabeledContent("Color") { currentColor }
            }
            Group {
                Toggle("Menu Bar", isOn: theming.menuBar)
                    .help("Fills the top of the wallpaper behind the menu bar, and of the desktop picture Open Wallpaper Engine sets, with the color; the transparent menu bar shows it.")
                Toggle("Accent Color", isOn: theming.accentColor)
                    .help("Sets System Settings › Appearance › Color to the closest of its colors, as macOS has no custom accent color, and the text highlight color to a light tint of the color.")
                Toggle("Tinted Icon Color", isOn: theming.tintedIcons)
                    .help("Sets the icon and widget style to Tinted, in the color.")
                Toggle("Folder Color", isOn: theming.folderColor)
                    .help("Sets the icon, widget and folder color, which folders use with every icon style.")
                Toggle(isOn: theming.restartsDockAutomatically) {
                    Text("Restart the Dock automatically to apply icon and folder colors")
                    Text("The Dock briefly reloads once the color stops changing. Your windows stay open.")
                }
                .help("The Dock shows a new icon style or tint only once it starts again. It restarts 1.5 seconds after the last change, and not at all when the colors are unchanged.")
                if controller.needsDockRestart && !viewModel.settings.theming.restartsDockAutomatically {
                    HStack {
                        Spacer()
                        Button("Restart Dock") { controller.restartDock() }
                            .help("The Dock and the icons show a new style or tint once the Dock starts again. Your windows stay open.")
                    }
                }
                Toggle("Use the wallpaper's main color when it has no scheme color", isOn: theming.usesDominantColor)
                    .help("Finds the most common color in the wallpaper's picture. Otherwise a wallpaper without a scheme color leaves everything as it is.")
                Toggle("Restore on Quit", isOn: theming.restoresOnQuit)
                    .help("Puts your own colors back when Open Wallpaper Engine quits. After a crash they are put back at the next launch.")
            }
            .disabled(!isOn)
        } header: {
            Label("Theming", systemImage: "paintbrush.fill")
        } footer: {
            Text("Your own settings are saved before the first change and put back when an option is turned off. The menu bar is translucent, so its color is a tint, and the accent color is the closest of macOS's colors.")
        }
        .settingsAnchor(SettingsAnchor.theming)
    }

    @ViewBuilder private var currentColor: some View {
        if let color = controller.color {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .overlay(Circle().strokeBorder(.separator))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(controller.isDerivedColor ? "Wallpaper's main color" : "Scheme color")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("None").foregroundStyle(.secondary)
        }
    }
}
