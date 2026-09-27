# UI capability inventory

Every user-facing capability of the app's windows, written down before the Liquid Glass redesign so
none is lost. Each item says where it lived before (file and line at the time of writing). After the
redesign, each item is ticked and says where it lives now.

`[ ]` = not yet checked against the new UI. `[x]` = present in the new UI (see "Now").

Paths are relative to `OpenWallpaperEngine/`.

## W. Windows and window behaviour

- [ ] **W1** Main window: titled, closable, miniaturizable, resizable; title "Open Wallpaper Engine &lt;version&gt;"; frame autosaved as `MainWindow`; not released when closed; transparent titlebar; movable by window background. Before: `UI/MainWindow.swift:21-36`.
- [ ] **W2** Main window content minimum 1000 × 640, ideal height 800. Before: `UI/ContentView.swift:196`.
- [ ] **W3** Power saving: closing the main window sets `isStaging = false`, which tears the content down and shows "Power Saving Mode, Sleeping..."; the window becoming key restages it with an animated fade and 2 pt blur. Before: `UI/MainWindow.swift:47-67`, `UI/ContentView.swift:37,99-108`.
- [ ] **W4** Clicking the Dock icon reopens the main window when neither it nor Settings is visible. Before: `App/AppDelegate.swift:207-213`.
- [ ] **W5** First launch centres and shows the main window. Before: `App/AppDelegate.swift:185-188`.
- [ ] **W6** Settings window: titled, closable, resizable, full-size content; preference-style toolbar; centred when opened; closing it without OK discards edits (`windowWillClose` → `reset()`). Before: `App/AppDelegate.swift:243-247,286-304,407-409`.
- [ ] **W7** Scene Inspector window: 1120 × 560, one reused window whose content is replaced for a new wallpaper; cannot shrink below the view's minimum size. Before: `Scene/UI/SceneInspectorView.swift:777-805`.
- [ ] **W8** Workshop preview window: 960 × 540, titled with the wallpaper title, reused; Esc or the close button hides it and tears playback down; losing key status dismisses it the same way. Before: `App/AppDelegate.swift:14-34,346-389`.
- [ ] **W9** About window: titled, closable, centred. Before: `Settings/AboutUsView.swift:10-20`.
- [ ] **W10** Safe-restart notice: non-activating floating utility panel at the top right of the main screen, on all Spaces, stays visible when the app deactivates. Before: `App/SafeRestartNotice.swift:12-44`.
- [ ] **W11** Desktop wallpaper windows (one per enabled screen). Not part of the redesign; must stay untouched. Before: `App/WallpaperWindow.swift`, `App/AppDelegate.swift:307-344`.

## M. Main window: tab bar

- [ ] **M1** Four tabs, each with an icon: Installed, Workshop, Downloads, Playlists; the selected tab is highlighted. Before: `UI/Explorer/TopTabBar.swift:19-104`.
- [ ] **M2** Tabs highlight on hover, animated. Before: `UI/Explorer/TopTabBar.swift:31-102`.
- [ ] **M3** Displays button opens Display Settings. Before: `UI/Explorer/TopTabBar.swift:109-114`.
- [ ] **M4** Settings button opens the Settings window. Before: `UI/Explorer/TopTabBar.swift:116-121`.
- [ ] **M5** Other places switch tab: status menu "Browse Workshop" and the author link in Details open the Workshop tab. Before: `App/Menus/StatusBar.swift:31-35`, `UI/Explorer/WallpaperPreview.swift:108-116`.

## E. Installed tab: top bar

- [ ] **E1** Search field; matches title, type, description, tags, Workshop id and folder name. Before: `UI/Explorer/ExplorerTopBar.swift:21-23`, `UI/ContentViewModel.swift:143-173`.
- [ ] **E2** "Filter Results" button shows or hides the filter pane. Before: `UI/Explorer/ExplorerTopBar.swift:24-29`.
- [ ] **E3** "Delete Selected (N)" button, shown while several wallpapers are selected; opens the batch unsubscribe confirmation. Before: `UI/Explorer/ExplorerTopBar.swift:30-37`.
- [ ] **E4** Refresh button, shown when auto refresh is on in Settings. Before: `UI/Explorer/ExplorerTopBar.swift:38-44`.
- [ ] **E5** Sort direction shown as text ("Ascending"/"Descending") with a one-click button that reverses it. Before: `UI/Explorer/ExplorerTopBar.swift:46-59`.
- [ ] **E6** "Sort By" picker (every `WEWallpaperSortingMethod`); method and direction persist (`SortingBy`, `SortingSequence`). Before: `UI/Explorer/ExplorerTopBar.swift:60-66`, `UI/ContentViewModel.swift:36-37`.

## F. Installed tab: filter pane

- [ ] **F1** Pane 225 pt wide that animates open and closed (width, opacity, explorer padding, spring); state persists (`FilterReveal`); also toggled from View ▸ Show Filter Results (⌃⌘S). Before: `UI/ContentView.swift:44-60`, `App/AppDelegate.swift:254-256`, `App/Menus/MainMenu.swift:68-72`.
- [ ] **F2** Reset Filters button. Before: `UI/Explorer/FilterResults.swift:56-63`.
- [ ] **F3** "Show Only" group box: five checkboxes with coloured icons (Approved, My Favourites, Mobile Compatible, Audio Responsive, Customizable). Before: `UI/Explorer/FilterResults.swift:64-117`.
- [ ] **F4** Collapsible sections with an animated disclosure arrow: Type (Scene, Video, Web, Application), Age Rating (Everyone, Partial Nudity, Mature). Before: `UI/Explorer/FilterResults.swift:10-47,119-146`.
- [ ] **F5** Resolution section: Widescreen, Ultra Widescreen, Dual Monitor, Triple Monitor, Portrait groups, each with All/None links and checkboxes, plus other resolutions. Shown disabled (not implemented yet). Before: `UI/Explorer/FilterResults.swift:147-330,375`.
- [ ] **F6** Source and Tags sections (Tags with All/None), shown disabled. Before: `UI/Explorer/FilterResults.swift:331-375`.
- [ ] **F7** Every filter value persists (`FR*` app storage keys). Before: `UI/ContentViewModel.swift:39-49`.
- [ ] **F8** The pane scrolls; labels stay on one line. Before: `UI/Explorer/FilterResults.swift:54,381`.

## X. Installed tab: wallpaper grid

- [ ] **X1** Adaptive grid; tile size from View ▸ Icon Size (100/125/150/200), 8 pt spacing. Before: `UI/Explorer/WallpaperExplorer.swift:39-57`.
- [ ] **X2** Pagination sized to the visible area (minus the measured footer), recomputed on resize, icon size and footer changes; previous/next chevrons and up to five page numbers, current page prominent. Before: `UI/Explorer/WallpaperExplorer.swift:21-26,60-83,137-179`.
- [ ] **X3** "Create Playlist" button (disabled with no selection) opens a sheet: name field, count, list of wallpapers, Cancel/Save. Before: `UI/Explorer/WallpaperExplorer.swift:63-69,84-135`.
- [ ] **X4** Empty state "No wallpapers found for your search." Before: `UI/Explorer/WallpaperExplorer.swift:31-37`.
- [ ] **X5** Tile: preview (animated GIF when the Animates plugin is on and the app is active), title strip, the displayed wallpaper outlined. Before: `UI/Explorer/ExplorerItem.swift:21-58`.
- [ ] **X6** Selection checkbox on each tile while a multi-selection exists (help "Select wallpaper"). Before: `UI/Explorer/ExplorerItem.swift:59-72`.
- [ ] **X7** Warning triangle on a tile flagged by safe restart, with an explanatory tooltip. Before: `UI/Explorer/ExplorerItem.swift:73-81`.
- [ ] **X8** Click selects and inspects; ⌘- or ⌃-click toggles; ⇧-click selects a range from the anchor. Before: `UI/Explorer/ExplorerItem.swift:83-90`, `UI/ContentViewModel.swift:318-339`.
- [ ] **X9** Double-click opens the Workshop preview window. Before: `UI/Explorer/ExplorerItem.swift:91-94`.
- [ ] **X10** Tile context menu: Add to Playlist ▸ (the selection, or this tile), Unsubscribe, Unsubscribe Selected (N) when more than one is selected, Add/Remove Favorites, Open in Finder; disabled placeholders Open in Workshop, Related Wallpapers, Report & Block, Assign Hotkey; followed by the background menu. Before: `UI/Explorer/ContextMenus/ExplorerItemMenu.swift`, `UI/Explorer/WallpaperExplorer.swift:50-53`.
- [ ] **X11** Background context menu: Open All in Finder; View ▸ Icon Size (Small, Medium, Large, XL). Before: `UI/Explorer/ContextMenus/ExplorerGlobalMenu.swift`, `UI/ContentView.swift:55-57`.
- [ ] **X12** Drag and drop onto the grid: a wallpaper folder (copied into the library), a .zip (imported), an mp4/mov/m4v (video wallpaper); an alert for anything else. Before: `UI/ContentView.swift:54`, `UI/ContentViewModel.swift:367-419`.
- [ ] **X13** Unsubscribe confirmation: Delete Immediately / Move to Trash / Cancel, titled with the wallpaper. Before: `UI/ContentView.swift:126-151`.
- [ ] **X14** Batch unsubscribe confirmation: Delete All N Immediately / Move All N to Trash / Cancel, naming up to three. Before: `UI/ContentView.swift:152-180`.
- [ ] **X15** Import error alert. Before: `UI/ContentView.swift:181-183`.

## I. Installed tab: import buttons

- [ ] **I1** "Open Wallpaper" (import a wallpaper folder). Before: `UI/ContentView.swift:72-77`.
- [ ] **I2** "Add Video Wallpaper". Before: `UI/ContentView.swift:78-82`.
- [ ] **I3** "Add Video/Image URL" opens a sheet: URL field, validation messages, Cancel/Add. Before: `UI/ContentView.swift:83-87,192-195,200-234`.

## D. Details panel (Installed tab)

- [ ] **D1** "Details" header; panel up to 320 pt wide; shown only on the Installed tab. Before: `UI/ContentView.swift:93-96`, `UI/Explorer/WallpaperPreview.swift:43-47`.
- [ ] **D2** Preview image, animated while the app is active. Before: `UI/Explorer/WallpaperPreview.swift:51-64`.
- [ ] **D3** Title; double-click to rename (Return saves to project.json). Before: `UI/Explorer/WallpaperPreview.swift:65-93`.
- [ ] **D4** Author avatar and name; the name opens the Workshop tab filtered to that author (help text); "Unknown Author" otherwise. Before: `UI/Explorer/WallpaperPreview.swift:95-121`.
- [ ] **D5** Favourite heart with subscriber count (help text). Before: `UI/Explorer/WallpaperPreview.swift:374-395`.
- [ ] **D6** Type and size on disk. Before: `UI/Explorer/WallpaperPreview.swift:123-127`.
- [ ] **D7** Tag pills; hovering a tag shows its remove button; hovering the row shows "+" to add; the add field has a revert button and saves on Return; the row scrolls sideways when it doesn't fit; changes animate. Before: `UI/Explorer/WallpaperPreview.swift:129-174,436-503`.
- [ ] **D8** Set Wallpaper (prominent), Delete (trash, help, opens the unsubscribe confirmation), Scene Inspector. Before: `UI/Explorer/WallpaperPreview.swift:175-201`.
- [ ] **D9** Properties section (collapsible): Age Rating (local wallpapers only), Placement with info tip; for videos Volume, Video Speed, Audio Speed with the link-rates toggle; for scenes the missing Workshop dependencies banner (Download All, per-item status, login hint) and Scene Music toggle and volume. Before: `UI/Explorer/WallpaperPreview.swift:203-274,397-433,514-580`.
- [ ] **D10** Wallpaper properties (`SceneUserPropertiesView`): Wallpaper Settings (sliders with number fields and double-click reset, checkboxes, combos, text, colours, file/folder pickers, Sync to Music with amount), User Scene Settings (Sync Video to Music, User Adjustments, Our Text). Before: `Scene/UI/SceneUserPropertiesView.swift`, `UI/Explorer/WallpaperPreview.swift:275-278`.
- [ ] **D11** "Your Presets" block: Load, Save, Apply to all Wallpapers, Share JSON, Reset (disabled placeholders). Before: `UI/Explorer/WallpaperPreview.swift:279-316`.
- [ ] **D12** No valid wallpaper: content blurred and disabled, "Please select a valid wallpaper". Before: `UI/Explorer/WallpaperPreview.swift:318-325`.
- [ ] **D13** OK and Cancel buttons; both close the main window. Before: `UI/Explorer/WallpaperPreview.swift:329-343`.
- [ ] **D14** Info tips: click for a selectable popover, hover for a tooltip. Before: `Scene/UI/SceneHelp.swift:5-28`.

## DS. Display Settings

- [ ] **DS1** Opens over the main window as a 520 × 450 card on a 25 % black dim; clicking the dim or the chevron button closes it. Before: `UI/ContentView.swift:110-124`, `UI/Explorer/Alerts/DisplaySettings.swift:21-28`.
- [ ] **DS2** Instructions; "All Desktops" checkbox selects every display. Before: `UI/Explorer/Alerts/DisplaySettings.swift:30-48`.
- [ ] **DS3** Monitor layout diagram: click selects a display, ⇧-click adds to the selection; main display starred; each shows its name and wallpaper or "Disabled"; selection highlighted. Before: `UI/Explorer/Alerts/DisplaySettings.swift:128-223`.
- [ ] **DS4** Selected display card: name, resolution, Enabled switch, thumbnail, wallpaper title and type, Remove (disabled when empty), or "disabled on this screen". Before: `UI/Explorer/Alerts/DisplaySettings.swift:54-110`.

## WS. Workshop tab

- [ ] **WS1** steamcmd missing: `brew install steamcmd` snippet with a copy button (checkmark for 2 s), Browse… for a binary, path error, Re-detect. Before: `Workshop/WorkshopView.swift:29-98`.
- [ ] **WS2** Steam login: username, password, Steam Guard code on demand, error, Log In, Use Cached Session, progress; Web API key section. Before: `Workshop/WorkshopView.swift:102-192`.
- [ ] **WS3** Search field: Return searches from page 1; the clear button empties it and searches again. Before: `Workshop/WorkshopView.swift:246-264`.
- [ ] **WS4** Author filter chip ("Author Workshop") with a clear button (help). Before: `Workshop/WorkshopView.swift:235-245`.
- [ ] **WS5** Sort picker; changing it searches from page 1. Before: `Workshop/WorkshopView.swift:266-275`.
- [ ] **WS6** Filter button (help "Show filters") toggles the filter sidebar (225 pt, animated), sharing the Installed tab's state. Before: `Workshop/WorkshopView.swift:202-210,277-283`.
- [ ] **WS7** "Download Selected (N)" (confirmation when more than one) and Clear selection (help). Before: `Workshop/WorkshopView.swift:285-304,212-222`.
- [ ] **WS8** Filter sidebar: Reset Filters, collapsible Rating/Type/Resolution/Genre tag checkboxes; each change searches. Before: `Workshop/WorkshopView.swift:455-495`.
- [ ] **WS9** Result states: searching spinner; error with API key entry; intro with API key entry when no key. Before: `Workshop/WorkshopView.swift:312-351`.
- [ ] **WS10** Card grid (icon size − 5, 13 pt spacing) with pagination (disabled while loading); page size from the area left above the footer. Before: `Workshop/WorkshopView.swift:352-453`.
- [ ] **WS11** Card: preview, title, download control (preparing, downloading with status, done, failed with message, download button, log-in-needed), selection checkbox, click selects, double-click previews, context menu (Download, Add to Playlist, Add/Remove Favorites). Before: `Workshop/WorkshopView.swift:499-647`.
- [ ] **WS12** First visit searches automatically. Before: `Workshop/WorkshopView.swift:399-403`.

## DL. Downloads tab

- [ ] **DL1** "Downloads" title; empty state. Before: `UI/ContentView.swift:356-380`.
- [ ] **DL2** Row per download: preview, title, creator, subscribers, size, retry button for failures (help shows the error), progress bar coloured by state with an estimated progress while running, percentage, status text, Workshop id. Before: `UI/ContentView.swift:383-523`.
- [ ] **DL3** Rows ordered by queue position. Before: `UI/ContentView.swift:336-354`.

## PL. Playlists tab

- [ ] **PL1** Playlist list (260 pt): title, "+" (help "Create playlist"), new-playlist field with add button (disabled when empty), playlists with count, active one checked; clicking one makes it active. Before: `UI/Explorer/WallpaperExplorer.swift:185-220`.
- [ ] **PL2** Playlist detail: name, delete (help), Rotate automatically, Shuffle, Repeat, Change when video ends, Wallpaper duration slider (5–3600 s) with value, Previous/Next, count, items with thumbnail, title, move up/down (disabled at the ends), remove. Before: `UI/Explorer/WallpaperExplorer.swift:222-288`.
- [ ] **PL3** Empty state "Create a Playlist". Before: `UI/Explorer/WallpaperExplorer.swift:283-287`.

## S. Settings (6 pages)

- [ ] **S0** Toolbar tabs Performance, General, Plugins, Permissions, Diagnostics, About (icon + label, selected highlighted); "Edited" indicator while unsaved; OK saves and closes; Cancel closes and discards; page height 400–800, width ≥ 500. Before: `Settings/SettingsView.swift:43-155`, `Settings/SettingsToolbarIdentifiers.swift`.
- [ ] **S1** Performance ▸ Playback: Other Application Focused / Fullscreen / Playing Audio, Display asleep, Laptop on battery pickers; Application Rules Edit (disabled). Before: `Settings/PerformancePage.swift:21-66`.
- [ ] **S2** Performance ▸ Quality: header note; Low/Medium/High/Ultra preset buttons; Anti-aliasing (red warning with help at ×8); Post-Processing (HDR option only with an HDR display, coerced on appear; yellow warning with help for Ultra); Texture Resolution, Scene Detail, Render Resolution, Volumetrics (help on each); FPS slider and field 10–120 (yellow warning over 30, red over 60, with help); Particle Budget (help); Reflections. Before: `Settings/PerformancePage.swift:67-203`.
- [ ] **S3** General: Start with macOS; Language (disabled); Wallpaper Storage path, Choose… with the move/empty-folder confirmation, disconnected-volume warning, Use Default Location, error; Wallpaper Engine Assets path, Choose…, Use Built-in Assets; Remove original packages toggle, reclaimable size, Reclaim Now, result; Steam Web API key (masked key, Replace…, Remove, entry with Check & Save and Cancel, link); Adjust Menu Bar Color; Theme; Sync properties across displays; Audio Output; Reload when changing output device (disabled); Video Framework; Process Priority; Pause when VRAM is exhausted; Restart after crashing; Log Level; Reset Config. Before: `Settings/GeneralPage.swift`, `Workshop/SteamWebAPIKeyView.swift`.
- [ ] **S4** Plugins: Animates toggle; Description expander (animated) with a GIF preview on a translucent tile and notes; Third-party "None"; footer. Before: `Settings/PluginsPage.swift`.
- [ ] **S5** Permissions: permission row with status, Grant Access (disabled once granted), Open Privacy Settings, Recheck; refreshes on appear. Before: `Settings/PermissionsPage.swift`.
- [ ] **S6** Diagnostics: assets source and path, built-in compiler, fallback compiler paths, Re-detect, translated variant count, Refresh; values selectable. Before: `Settings/DiagnosticsPage.swift`.
- [ ] **S7** About page inside Settings (same view as the About window). Before: `Settings/SettingsView.swift:60-61`.

## SI. Scene Inspector

- [ ] **SI1** Object list (300 pt): Versions section; Scene Objects with a per-object visibility switch (help Hide/Show object) and a kind icon; selection; initially the stored version or the first object. Before: `Scene/UI/SceneInspectorView.swift:877-907,845-849`.
- [ ] **SI2** Search in the toolbar: capsule field that widens (240 → 300) and gains an accent ring while focused; clear button; ⌘K focuses it; filters by name, kind, paths, effects and parameters. Before: `Scene/UI/SceneInspectorView.swift:821-840,862-874,931-968`.
- [ ] **SI3** Copy Path toolbar button: copies the wallpaper folder, shows "Copied" for 1.5 s, help shows the path. Before: `Scene/UI/SceneInspectorView.swift:970-993`.
- [ ] **SI4** Titles: "Scene Inspector", then the selected object's name. Before: `Scene/UI/SceneInspectorView.swift:906,1022`.
- [ ] **SI5** Object detail: Type, Use This Version, Source, Material, Textures with decoded previews, Shaders, Effects (enable checkbox, info tip, disclosure with mask preview, combos with grouped options and requirements, colour pickers anchored beside the control, sliders with linked X/Y toggle, Sync to Music and Music Amount), Object Properties JSON editor with Save, Layer Details for video layers, Particle System and Material JSON editors with Save. Before: `Scene/UI/SceneInspectorView.swift:995-1176,1418-1528`.
- [ ] **SI6** Empty states: "Scene Unavailable" with the error, "Select a Scene Object". Before: `Scene/UI/SceneInspectorView.swift:909-921`.
- [ ] **SI7** Movement column (300 pt): Move Element card with position readout and arrow buttons (help gives the steps), disabled without a selection; Size slider (0.05–5×), Reset to 1x, Blend mode picker for images; Align Element horizontal Left/Center/Right and vertical Top/Center/Bottom; step legend. Before: `Scene/UI/SceneInspectorView.swift:1178-1380`.
- [ ] **SI8** Arrow keys move the selected object while the detail or movement panel has focus (Shift 50 px, Control 1 px, otherwise 10 px). Before: `Scene/UI/SceneInspectorView.swift:925-928,1382-1403`.
- [ ] **SI9** Minimum size 1120 × 560. Before: `Scene/UI/SceneInspectorView.swift:844`.

## WP. Workshop preview window

- [ ] **WP1** Live wallpaper (Metal, AVKit or web). Before: `App/AppDelegate.swift:41-45`.
- [ ] **WP2** Bottom-right controls: Play/Pause (videos, with help), volume slider and field (videos), Set Wallpaper (prominent). Before: `App/AppDelegate.swift:47-69`.

## AB. About

- [ ] **AB1** App icon, name, subtitle, version, contributors with GitHub links and roles. Before: `Settings/AboutUsView.swift:22-68`.

## FL. First Launch

- [ ] **FL1** Sheet over the main window with four pages: header, feature rows, page dots, "Never show this again until next update", Back (disabled on the first page), Next/Finish (Return), selectable text, fade between pages. Help ▸ Debug ▸ Reset First Launch shows it again. Before: `UI/FirstLaunchView.swift`, `UI/ContentView.swift:184-187`.

## SR. Safe-restart notice and unsafe wallpaper warning

- [ ] **SR1** Notice: warning icon, message, Dismiss, Retry (prominent). Before: `App/SafeRestartNotice.swift:46-70`.
- [ ] **SR2** Unsafe wallpaper sheet: 5 s countdown, Proceed (red, disabled until the countdown ends), Cancel, "Don't ask again for this wallpaper", file path. Before: `UI/Explorer/Alerts/UnsafeWallpaper.swift`, `UI/ContentView.swift:188-191`.

## MN. Main menu

- [ ] **MN1** App menu: About, Settings… (⌘,), Quit (⌘Q), Hide (⌘H), Hide Others (⌥⌘H). Before: `App/Menus/MainMenu.swift:13-29`.
- [ ] **MN2** File: Import ▸ Wallpaper from Folder (⌘I), Wallpapers in Folders; Close Window (⌘W). Before: `App/Menus/MainMenu.swift:32-47`.
- [ ] **MN3** Edit: Undo, Redo, Cut, Copy, Paste, Delete All, Select All. Before: `App/Menus/MainMenu.swift:50-62`.
- [ ] **MN4** View: Show Filter Results (⌃⌘S), Enter Full Screen (⌃⌘F). Before: `App/Menus/MainMenu.swift:65-79`.
- [ ] **MN5** Window: Wallpaper Explorer (⇧⌘1). Before: `App/Menus/MainMenu.swift:82-90`.
- [ ] **MN6** Help ▸ Debug: Reset First Launch, Toggle Desktop Wallpaper Window, Reset All Trusted Wallpapers. Before: `App/Menus/MainMenu.swift:93-106`.

## SB. Status bar and Dock menu

- [ ] **SB1** Status item (app icon, or a symbol fallback) with: Show Open Wallpaper Engine, Recent Wallpapers ▸ (rebuilt each time the menu opens), Browse Workshop, Settings, Support & FAQ, Mute, Pause, Quit. Before: `App/Menus/StatusBar.swift`.
- [ ] **DK1** Dock menu: the status menu without Quit. Before: `App/AppDelegate.swift:167-171`.

## AL. Other alerts

- [ ] **AL1** Audio permission alert: Grant Access, Open Permissions Page, Later, Don't Ask Again. Before: `App/AppDelegate.swift:260-283`.

## K. Keyboard and accessibility

- [ ] **K1** ⌘K focuses the Scene Inspector search. Before: `Scene/UI/SceneInspectorView.swift:870-874`.
- [ ] **K2** Arrow keys nudge in the Scene Inspector (see SI8).
- [ ] **K3** Return triggers Next/Finish in First Launch. Before: `UI/FirstLaunchView.swift:97`.
- [ ] **K4** Help text on icon-only buttons: tile selection, safe-restart warning, delete wallpaper, favourite, author link, link rates, playlist create/delete, download retry, Workshop filters/author/clear selection/download state, Scene Inspector switches, arrows, alignment, link toggle, Copy Path, preview Play/Pause.
