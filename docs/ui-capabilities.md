# UI capability inventory

Every user-facing capability of the app's windows, written down before the Liquid Glass redesign so
none is lost. Each item says where it lived before (file and line at the time of writing) and, after
the redesign, where it lives now.

`[ ]` = not yet checked against the new UI. `[x]` = present in the new UI (see "Now"); where a detail
could not be carried over, the item says so in bold.

## Not carried over

- **M1** The tab icons: the native segmented control draws only the segment text.
- **M2** The custom blue hover fill on tabs (the segmented control has its own hover feedback).
- **D13** The Details OK/Cancel buttons (both closed the window; the close button and ⌘W still do).
- **DS1** Closing Display Settings by clicking outside it (it is a sheet: Done, Return or Esc).
- **SI2** The Scene Inspector search field's widen-on-focus animation and accent ring (the native
  field has the system focus ring).

Paths are relative to `OpenWallpaperEngine/`.

## Frosted surfaces ("acrylic")

Window and pane backgrounds are frosted on every macOS version: `FrostedBackground`
(`UI/Components/FrostedBackground.swift`) is an `NSVisualEffectView` that blends behind the window,
so the desktop's live wallpaper shows through blurred. It follows the window's active state (it
doesn't force `.active`), so inactive windows dim as usual and Reduce Transparency makes it opaque.
It sits under the main window (sidebar, grid area, Details), the Settings window and its pages
(`scrollContentBackground(.hidden)` on the grouped Forms), the Scene Inspector and About. The
restart notice is frosted before macOS 26 and glass on 26. Sheets use `presentationBackground(.regularMaterial)`.

Before macOS 26 the glass pieces fall back to materials where that reads well: the tag pills,
the `brew install steamcmd` snippet, the Plugins GIF tile and the controls capsule over the
Workshop preview. Buttons keep the bordered styles. Content stays opaque: wallpaper previews,
grid tiles, thumbnails, the Metal/AV/Web views, JSON editors and texture previews.
No capability changed.

Switching to the Installed tab no longer rebuilds the sidebars (their scroll position and
collapsed sections survive a switch) and no longer rescans the library several times per redraw
(`Library/InstalledLibraryCache.swift`).

## W. Windows and window behaviour

- [x] **W1** Main window: titled, closable, miniaturizable, resizable; title "Open Wallpaper Engine &lt;version&gt;"; frame autosaved as `MainWindow`; not released when closed; transparent titlebar; movable by window background. Before: `UI/MainWindow.swift:21-36`. **Now:** Same window, now with a unified toolbar and full-size content view (`UI/MainWindow.swift`); still movable by its background. The title is kept for the Window menu and Mission Control but hidden in the toolbar, whose centre holds the tabs.
- [x] **W2** Main window content minimum 1000 × 640, ideal height 800. Before: `UI/ContentView.swift:196`. **Now:** Unchanged (`UI/ContentView.swift`, `.frame(minWidth: 1000, minHeight: 640, idealHeight: 800)`).
- [x] **W3** Power saving: closing the main window sets `isStaging = false`, which tears the content down and shows "Power Saving Mode, Sleeping..."; the window becoming key restages it with an animated fade and 2 pt blur. Before: `UI/MainWindow.swift:47-67`, `UI/ContentView.swift:37,99-108`. **Now:** Unchanged in `UI/MainWindow.swift`; the sidebar, detail and inspector contents are all torn down while not staged, and the detail fades in from the 2 pt blur through the `StagingFade` transition (`UI/ContentView.swift`).
- [x] **W4** Clicking the Dock icon reopens the main window when neither it nor Settings is visible. Before: `App/AppDelegate.swift:207-213`. **Now:** Unchanged (`App/AppDelegate.swift`).
- [x] **W5** First launch centres and shows the main window. Before: `App/AppDelegate.swift:185-188`. **Now:** Unchanged (`App/AppDelegate.swift`).
- [x] **W6** Settings window: titled, closable, resizable, full-size content; preference-style toolbar; centred when opened; closing it without OK discards edits (`windowWillClose` → `reset()`). Before: `App/AppDelegate.swift:243-247,286-304,407-409`. **Now:** Unchanged: same window and preference-style NSToolbar, which macOS 26 draws as glass (`App/AppDelegate.swift`, `Settings/SettingsView.swift`).
- [x] **W7** Scene Inspector window: 1120 × 560, one reused window whose content is replaced for a new wallpaper; cannot shrink below the view's minimum size. Before: `Scene/UI/SceneInspectorView.swift:777-805`. **Now:** Unchanged window code (`Scene/UI/SceneInspectorView.swift`); the content is now a NavigationSplitView with an inspector.
- [x] **W8** Workshop preview window: 960 × 540, titled with the wallpaper title, reused; Esc or the close button hides it and tears playback down; losing key status dismisses it the same way. Before: `App/AppDelegate.swift:14-34,346-389`. **Now:** Unchanged (`App/AppDelegate.swift`).
- [x] **W9** About window: titled, closable, centred. Before: `Settings/AboutUsView.swift:10-20`. **Now:** Unchanged (`Settings/AboutUsView.swift`).
- [x] **W10** Safe-restart notice: non-activating floating utility panel at the top right of the main screen, on all Spaces, stays visible when the app deactivates. Before: `App/SafeRestartNotice.swift:12-44`. **Now:** Unchanged panel behaviour (`App/SafeRestartNotice.swift`); on macOS 26 its content is an `NSGlassEffectView`.
- [x] **W11** Desktop wallpaper windows (one per enabled screen). Not part of the redesign; must stay untouched. Before: `App/WallpaperWindow.swift`, `App/AppDelegate.swift:307-344`. **Now:** Untouched.

## M. Main window: tab bar

- [x] **M1** Four tabs, each with an icon: Installed, Workshop, Downloads, Playlists; the selected tab is highlighted. Before: `UI/Explorer/TopTabBar.swift:19-104`. **Now:** Segmented control in the toolbar centre (`UI/Explorer/TopTabBar.swift`), selected segment highlighted. **Icons not carried over:** the native segmented control draws text only (an inline symbol in the segment text is dropped by AppKit). Listed in the report.
- [x] **M2** Tabs highlight on hover, animated. Before: `UI/Explorer/TopTabBar.swift:31-102`. **Now:** The segmented control's own hover and press feedback replaces the custom blue hover fill.
- [x] **M3** Displays button opens Display Settings. Before: `UI/Explorer/TopTabBar.swift:109-114`. **Now:** Toolbar button "Displays" with help text (`UI/ContentView.swift`, `mainToolbar`).
- [x] **M4** Settings button opens the Settings window. Before: `UI/Explorer/TopTabBar.swift:116-121`. **Now:** Toolbar button "Settings" with help text (`UI/ContentView.swift`, `mainToolbar`).
- [x] **M5** Other places switch tab: status menu "Browse Workshop" and the author link in Details open the Workshop tab. Before: `App/Menus/StatusBar.swift:31-35`, `UI/Explorer/WallpaperPreview.swift:108-116`. **Now:** Unchanged: both still set `topTabBarSelection = 1`.

## E. Installed tab: top bar

- [x] **E1** Search field; matches title, type, description, tags, Workshop id and folder name. Before: `UI/Explorer/ExplorerTopBar.swift:21-23`, `UI/ContentViewModel.swift:143-173`. **Now:** Native toolbar search field (`.searchable`) bound to the same `searchText` (`UI/Explorer/ExplorerTopBar.swift`). The tags it matches are the ones the grid shows (project.json's and the Workshop item's, below), and any one tag containing the text matches (it used to need every tag to contain it).
- [x] **E2** "Filter Results" button shows or hides the filter pane. Before: `UI/Explorer/ExplorerTopBar.swift:24-29`. **Now:** Toolbar sidebar button "Filter Results" at the leading edge, plus dragging the split view divider (`UI/ContentView.swift`).
- [x] **E3** "Delete Selected (N)" button, shown while several wallpapers are selected; opens the batch unsubscribe confirmation. Before: `UI/Explorer/ExplorerTopBar.swift:30-37`. **Now:** Toolbar button "Delete Selected (N)", shown while wallpapers are selected (`UI/Explorer/ExplorerTopBar.swift`).
- [x] **E4** Refresh button, shown when auto refresh is on in Settings. Before: `UI/Explorer/ExplorerTopBar.swift:38-44`. **Now:** Toolbar button "Refresh" when auto refresh is on (`UI/Explorer/ExplorerTopBar.swift`).
- [x] **E5** Sort direction shown as text ("Ascending"/"Descending") with a one-click button that reverses it. Before: `UI/Explorer/ExplorerTopBar.swift:46-59`. **Now:** Toolbar button whose label is the direction text and arrow; one click reverses it; help says what it does (`UI/Explorer/ExplorerTopBar.swift`).
- [x] **E6** "Sort By" picker (every `WEWallpaperSortingMethod`); method and direction persist (`SortingBy`, `SortingSequence`). Before: `UI/Explorer/ExplorerTopBar.swift:60-66`, `UI/ContentViewModel.swift:36-37`. **Now:** Toolbar menu picker "Sort By", same storage (`UI/Explorer/ExplorerTopBar.swift`).

## F. Installed tab: filter pane

- [x] **F1** Pane 225 pt wide that animates open and closed (width, opacity, explorer padding, spring); state persists (`FilterReveal`); also toggled from View ▸ Show Filter Results (⌃⌘S). Before: `UI/ContentView.swift:44-60`, `App/AppDelegate.swift:254-256`, `App/Menus/MainMenu.swift:68-72`. **Now:** The split view sidebar (`UI/ContentView.swift`), 225 pt ideal and resizable 200–360; the toolbar button and the menu item animate it in and out (`ContentViewModel.toggleFilter`); still stored in `FilterReveal`.
- [x] **F2** Reset Filters button. Before: `UI/Explorer/FilterResults.swift:56-63`. **Now:** First row of the sidebar list, glass prominent on macOS 26 (`UI/Explorer/FilterResults.swift`).
- [x] **F3** "Show Only" group box: five checkboxes with coloured icons (Approved, My Favourites, Mobile Compatible, Audio Responsive, Customizable). Before: `UI/Explorer/FilterResults.swift:64-117`. **Now:** "Show Only:" sidebar section with the same five coloured checkboxes (`UI/Explorer/FilterResults.swift`).
- [x] **F4** Collapsible sections with an animated disclosure arrow: Type (Scene, Video, Web, Application), Age Rating (Everyone, Partial Nudity, Mature). Before: `UI/Explorer/FilterResults.swift:10-47,119-146`. **Now:** Collapsible sidebar sections with the system disclosure animation (`UI/Explorer/FilterResults.swift`); every section, Show Only included, can collapse.
- [x] **F5** Resolution section: Widescreen, Ultra Widescreen, Dual Monitor, Triple Monitor, Portrait groups, each with All/None links and checkboxes, plus other resolutions. Shown disabled (not implemented yet). Before: `UI/Explorer/FilterResults.swift:147-330,375`. **Now:** Resolution section with the same five groups, All/None links and checkboxes, still disabled (`UI/Explorer/FilterResults.swift`). All/None set each filter's own `all`/`none` (`FilterResultsModelTests`). The groups are the shared `ResolutionFilterRows` with WE's tag spellings and labels (1366 x 768 added, as WE lists it); still disabled on the Installed tab. **Since the installed-tags work:** enabled; a wallpaper matches when one of its tags (project.json's or its Workshop item's) is a checked resolution; everything checked doesn't filter, nothing checked matches nothing (`UI/Explorer/InstalledTagFilter.swift`).
- [x] **F6** Source and Tags sections (Tags with All/None), shown disabled. Before: `UI/Explorer/FilterResults.swift:331-375`. **Now:** Source and Tags sections, Tags with All/None, still disabled (`UI/Explorer/FilterResults.swift`). **Since the installed-tags work:** Tags is enabled and matches the same merged tags (any checked genre; All doesn't filter; None matches nothing, as before); Source stays disabled. Age Rating falls back to the rating tag when project.json has no `contentrating`, and Show Only ▸ Approved also matches the "Approved" tag.
- [x] **F7** Every filter value persists (`FR*` app storage keys). Before: `UI/ContentViewModel.swift:39-49`. **Now:** Unchanged (`UI/ContentViewModel.swift`).
- [x] **F8** The pane scrolls; labels stay on one line. Before: `UI/Explorer/FilterResults.swift:54,381`. **Now:** The sidebar List scrolls; labels stay on one line.

## X. Installed tab: wallpaper grid

- [x] **X1** Adaptive grid; tile size from View ▸ Icon Size (100/125/150/200), 8 pt spacing. Before: `UI/Explorer/WallpaperExplorer.swift:39-57`. **Now:** Unchanged (`UI/Explorer/WallpaperExplorer.swift`).
- [x] **X2** Pagination sized to the visible area (minus the measured footer), recomputed on resize, icon size and footer changes; previous/next chevrons and up to five page numbers, current page prominent. Before: `UI/Explorer/WallpaperExplorer.swift:21-26,60-83,137-179`. **Now:** Unchanged logic; page buttons are glass on macOS 26 (`UI/Explorer/WallpaperExplorer.swift`).
- [x] **X3** "Create Playlist" button (disabled with no selection) opens a sheet: name field, count, list of wallpapers, Cancel/Save. Before: `UI/Explorer/WallpaperExplorer.swift:63-69,84-135`. **Now:** Unchanged; glass button, and the sheet's Cancel/Save answer Esc/Return (`UI/Explorer/WallpaperExplorer.swift`).
- [x] **X4** Empty state "No wallpapers found for your search." Before: `UI/Explorer/WallpaperExplorer.swift:31-37`. **Now:** Unchanged.
- [x] **X5** Tile: preview (animated GIF when the Animates plugin is on and the app is active), title strip, the displayed wallpaper outlined. Before: `UI/Explorer/ExplorerItem.swift:21-58`. **Now:** Unchanged (`UI/Explorer/ExplorerItem.swift`, content, no glass). **Since the installed-tags work:** the title strip also shows the wallpaper's tags (without "Wallpaper") on one line, and the tooltip lists them all, as on the Workshop cards. The tags are project.json's followed by the Workshop item's: when project.json has at most one tag and the wallpaper has a Workshop id, `InstalledWorkshopTagSync` (`Library/`) reads the item's tags with GetPublishedFileDetails in the background (50 ids per request, one request a second, only with a Steam Web API key) and stores them with the installed ids in `DownloadedWallpaperIndex` (defaults key `DownloadedWorkshopWallpaperTags`), once per item; a later Steam response with a newer `time_updated` replaces them. Offline, the stored tags are used.
- [x] **X6** Selection checkbox on each tile while a multi-selection exists (help "Select wallpaper"). Before: `UI/Explorer/ExplorerItem.swift:59-72`. **Now:** Unchanged.
- [x] **X7** Warning triangle on a tile flagged by safe restart, with an explanatory tooltip. Before: `UI/Explorer/ExplorerItem.swift:73-81`. **Now:** Unchanged.
- [x] **X8** Click selects and inspects; ⌘- or ⌃-click toggles; ⇧-click selects a range from the anchor. Before: `UI/Explorer/ExplorerItem.swift:83-90`, `UI/ContentViewModel.swift:318-339`. **Now:** Unchanged.
- [x] **X9** Double-click opens the Workshop preview window. Before: `UI/Explorer/ExplorerItem.swift:91-94`. **Now:** Unchanged.
- [x] **X10** Tile context menu: Add to Playlist ▸ (the selection, or this tile), Unsubscribe, Unsubscribe Selected (N) when more than one is selected, Add/Remove Favorites, Open in Finder; disabled placeholders Open in Workshop, Related Wallpapers, Report & Block, Assign Hotkey; followed by the background menu. Before: `UI/Explorer/ContextMenus/ExplorerItemMenu.swift`, `UI/Explorer/WallpaperExplorer.swift:50-53`. **Now:** Unchanged (`UI/Explorer/ContextMenus/ExplorerItemMenu.swift`).
- [x] **X11** Background context menu: Open All in Finder; View ▸ Icon Size (Small, Medium, Large, XL). Before: `UI/Explorer/ContextMenus/ExplorerGlobalMenu.swift`, `UI/ContentView.swift:55-57`. **Now:** Unchanged; attached to the Installed tab's grid (`UI/ContentView.swift`).
- [x] **X12** Drag and drop onto the grid: a wallpaper folder (copied into the library), a .zip (imported), an mp4/mov/m4v (video wallpaper); an alert for anything else. Before: `UI/ContentView.swift:54`, `UI/ContentViewModel.swift:367-419`. **Now:** Unchanged; attached to the Installed tab's grid (`UI/ContentView.swift`).
- [x] **X13** Unsubscribe confirmation: Delete Immediately / Move to Trash / Cancel, titled with the wallpaper. Before: `UI/ContentView.swift:126-151`. **Now:** Unchanged (`UI/ContentView.swift`).
- [x] **X14** Batch unsubscribe confirmation: Delete All N Immediately / Move All N to Trash / Cancel, naming up to three. Before: `UI/ContentView.swift:152-180`. **Now:** Unchanged (`UI/ContentView.swift`).
- [x] **X15** Import error alert. Before: `UI/ContentView.swift:181-183`. **Now:** Unchanged (`UI/ContentView.swift`).

## I. Installed tab: import buttons

- [x] **I1** "Open Wallpaper" (import a wallpaper folder). Before: `UI/ContentView.swift:72-77`. **Now:** Toolbar "Add Wallpaper" (+) menu ▸ Open Wallpaper… (`UI/Explorer/ExplorerTopBar.swift`); also File ▸ Import ▸ Wallpaper from Folder (⌘I).
- [x] **I2** "Add Video Wallpaper". Before: `UI/ContentView.swift:78-82`. **Now:** Toolbar "Add Wallpaper" (+) menu ▸ Add Video Wallpaper…
- [x] **I3** "Add Video/Image URL" opens a sheet: URL field, validation messages, Cancel/Add. Before: `UI/ContentView.swift:83-87,192-195,200-234`. **Now:** Toolbar "Add Wallpaper" (+) menu ▸ Add Video/Image URL…; the sheet is unchanged and its Cancel/Add answer Esc/Return (`UI/ContentView.swift`).

## D. Details panel (Installed tab)

- [x] **D1** "Details" header; panel up to 320 pt wide; shown only on the Installed tab. Before: `UI/ContentView.swift:93-96`, `UI/Explorer/WallpaperPreview.swift:43-47`. **Now:** Inspector column (280–420 pt, 320 ideal), shown only on the Installed tab, with a new toolbar button to hide it (`UI/ContentView.swift`); same "Details" header (`UI/Explorer/WallpaperPreview.swift`).
- [x] **D2** Preview image, animated while the app is active. Before: `UI/Explorer/WallpaperPreview.swift:51-64`. **Now:** Unchanged (content, no glass).
- [x] **D3** Title; double-click to rename (Return saves to project.json). Before: `UI/Explorer/WallpaperPreview.swift:65-93`. **Now:** Unchanged.
- [x] **D4** Author avatar and name; the name opens the Workshop tab filtered to that author (help text); "Unknown Author" otherwise. Before: `UI/Explorer/WallpaperPreview.swift:95-121`. **Now:** Unchanged.
- [x] **D5** Favourite heart with subscriber count (help text). Before: `UI/Explorer/WallpaperPreview.swift:374-395`. **Now:** Unchanged.
- [x] **D6** Type and size on disk. Before: `UI/Explorer/WallpaperPreview.swift:123-127`. **Now:** Unchanged.
- [x] **D7** Tag pills; hovering a tag shows its remove button; hovering the row shows "+" to add; the add field has a revert button and saves on Return; the row scrolls sideways when it doesn't fit; changes animate. Before: `UI/Explorer/WallpaperPreview.swift:129-174,436-503`. **Now:** Same behaviour; the pills are glass capsules on macOS 26 and the old drawn capsules before (`UI/Explorer/WallpaperPreview.swift`). **Since the installed-tags work:** the pills are project.json's tags followed by the Workshop item's stored tags (see X5); only project.json's have the remove button.
- [x] **D8** Set Wallpaper (prominent), Delete (trash, help, opens the unsubscribe confirmation), Scene Inspector. Before: `UI/Explorer/WallpaperPreview.swift:175-201`. **Now:** Same three actions as glass buttons in one glass group; Delete keeps its help and gains an accessibility label (`UI/Explorer/WallpaperPreview.swift`).
- [x] **D9** Properties section (collapsible): Age Rating (local wallpapers only), Placement with info tip; for videos Volume, Video Speed, Audio Speed with the link-rates toggle; for scenes the missing Workshop dependencies banner (Download All, per-item status, login hint) and Scene Music toggle and volume. Before: `UI/Explorer/WallpaperPreview.swift:203-274,397-433,514-580`. **Now:** Unchanged; the dependencies banner is a GroupBox (`UI/Explorer/WallpaperPreview.swift`).
- [x] **D10** Wallpaper properties (`SceneUserPropertiesView`): Wallpaper Settings (sliders with number fields and double-click reset, checkboxes, combos, text, colours, file/folder pickers, Sync to Music with amount), User Scene Settings (Sync Video to Music, User Adjustments, Our Text). Before: `Scene/UI/SceneUserPropertiesView.swift`, `UI/Explorer/WallpaperPreview.swift:275-278`. **Now:** Unchanged (`Scene/UI/SceneUserPropertiesView.swift`).
- [x] **D11** "Your Presets" block: Load, Save, Apply to all Wallpapers, Share JSON, Reset (disabled placeholders). Before: `UI/Explorer/WallpaperPreview.swift:279-316`. **Now:** Unchanged, still disabled; Reset is glass prominent red.
- [x] **D12** No valid wallpaper: content blurred and disabled, "Please select a valid wallpaper". Before: `UI/Explorer/WallpaperPreview.swift:318-325`. **Now:** Unchanged.
- [x] **D13** OK and Cancel buttons; both close the main window. Before: `UI/Explorer/WallpaperPreview.swift:329-343`. **Now:** **Buttons removed, function kept:** both only called `mainWindowController.close()`; the window's close button and File ▸ Close Window (⌘W) do the same. Listed in the report.
- [x] **D14** Info tips: click for a selectable popover, hover for a tooltip. Before: `Scene/UI/SceneHelp.swift:5-28`. **Now:** Unchanged (`Scene/UI/SceneHelp.swift`).

## DS. Display Settings

- [x] **DS1** Opens over the main window as a 520 × 450 card on a 25 % black dim; clicking the dim or the chevron button closes it. Before: `UI/ContentView.swift:110-124`, `UI/Explorer/Alerts/DisplaySettings.swift:21-28`. **Now:** A sheet (520 × 450) opened by the toolbar Displays button (`UI/ContentView.swift`); closes with its Done button (Return) or Esc. Clicking outside no longer closes it, as sheets don't; listed in the report.
- [x] **DS2** Instructions; "All Desktops" checkbox selects every display. Before: `UI/Explorer/Alerts/DisplaySettings.swift:30-48`. **Now:** Unchanged (`UI/Explorer/Alerts/DisplaySettings.swift`).
- [x] **DS3** Monitor layout diagram: click selects a display, ⇧-click adds to the selection; main display starred; each shows its name and wallpaper or "Disabled"; selection highlighted. Before: `UI/Explorer/Alerts/DisplaySettings.swift:128-223`. **Now:** Unchanged (content, no glass).
- [x] **DS4** Selected display card: name, resolution, Enabled switch, thumbnail, wallpaper title and type, Remove (disabled when empty), or "disabled on this screen". Before: `UI/Explorer/Alerts/DisplaySettings.swift:54-110`. **Now:** Same controls in a GroupBox; Remove is a glass button (`UI/Explorer/Alerts/DisplaySettings.swift`).

## WS. Workshop tab

- [x] **WS1** steamcmd missing: `brew install steamcmd` snippet with a copy button (checkmark for 2 s), Browse… for a binary, path error, Re-detect. Before: `Workshop/WorkshopView.swift:29-98`. **Now:** Unchanged; the snippet is on glass and the copy button is glass with help (`Workshop/WorkshopView.swift`).
- [x] **WS2** Steam login: username, password, Steam Guard code on demand, error, Log In, Use Cached Session, progress; Web API key section. Before: `Workshop/WorkshopView.swift:102-192`. **Now:** Unchanged; Log In and Use Cached Session are glass buttons.
- [x] **WS3** Search field: Return searches from page 1; the clear button empties it and searches again. Before: `Workshop/WorkshopView.swift:246-264`. **Now:** Native toolbar search field: Return searches from page 1 (`onSubmit(of: .search)`); its clear button empties it and searches again (`Workshop/WorkshopView.swift`).
- [x] **WS4** Author filter chip ("Author Workshop") with a clear button (help). Before: `Workshop/WorkshopView.swift:235-245`. **Now:** Toolbar items "Author Workshop" and a clear button with help, shown while filtering by author.
- [x] **WS5** Sort picker; changing it searches from page 1. Before: `Workshop/WorkshopView.swift:266-275`. **Now:** Toolbar menu picker "Sort"; changing it searches from page 1.
- [x] **WS6** Filter button (help "Show filters") toggles the filter sidebar (225 pt, animated), sharing the Installed tab's state. Before: `Workshop/WorkshopView.swift:202-210,277-283`. **Now:** The main toolbar's sidebar button, sharing the Installed tab's state; the sidebar animates (`UI/ContentView.swift`). Help reads "Show or hide the filters".
- [x] **WS7** "Download Selected (N)" (confirmation when more than one) and Clear selection (help). Before: `Workshop/WorkshopView.swift:285-304,212-222`. **Now:** Toolbar buttons "Download Selected (N)" (confirmation when more than one) and "Clear selection" with help.
- [x] **WS8** Filter sidebar: Reset Filters, collapsible Rating/Type/Resolution/Genre tag checkboxes; each change searches. Before: `Workshop/WorkshopView.swift:455-495`. **Now:** The split view sidebar (`WorkshopFiltersSidebar` in `Workshop/WorkshopView.swift`), Reset Filters then collapsible List sections; each change searches. Since the Workshop filter rework the sidebar has, in order: Reset Filters; Show Only (the Installed tab's five options, one shared component); Rating; Type; Resolution (WE's resolution groups with All/None, the same shared component as the Installed tab); Genre with a "Match all (AND)" / "Match any (OR)" toggle in its header. Within Show Only, Rating, Type and Resolution any checked option matches; sections narrow together. Tags are spelled as WE sends them (`Workshop/WorkshopFilter.swift`), so the ultrawide/portrait resolutions and "Pixel art" now match. **Fixed (2026-09-27):** a second or third ticked genre narrows the results again. Every click starts a search; an overtaken, slower search used to finish last and show its results (and cache its pages under the new search), so only the first tick seemed to work. Only the newest search shows its results now, the grid shows the search in progress instead of stale results, and a short last page is reachable. An author's Workshop is checked against the whole filter.
- [x] **WS9** Result states: searching spinner; error with API key entry; intro with API key entry when no key. Before: `Workshop/WorkshopView.swift:312-351`. **Now:** Unchanged.
- [x] **WS10** Card grid (icon size − 5, 13 pt spacing) with pagination (disabled while loading); page size from the area left above the footer. Before: `Workshop/WorkshopView.swift:352-453`. **Now:** Unchanged grid; glass page buttons; the page size now measures the pagination row instead of assuming 44 pt.
- [x] **WS11** Card: preview, title, download control (preparing, downloading with status, done, failed with message, download button, log-in-needed), selection checkbox, click selects, double-click previews, context menu (Download, Add to Playlist, Add/Remove Favorites). Before: `Workshop/WorkshopView.swift:499-647`. **Now:** Unchanged (content, no glass). Each card now shows its tags (without "Wallpaper") under the title, and all of them in the tooltip.
- [x] **WS12** First visit searches automatically. Before: `Workshop/WorkshopView.swift:399-403`. **Now:** Unchanged.

## DL. Downloads tab

- [x] **DL1** "Downloads" title; empty state. Before: `UI/ContentView.swift:356-380`. **Now:** Unchanged (`UI/Downloads/DownloadsView.swift`).
- [x] **DL2** Row per download: preview, title, creator, subscribers, size, retry button for failures (help shows the error), progress bar coloured by state with an estimated progress while running, percentage, status text, Workshop id. Before: `UI/ContentView.swift:383-523`. **Now:** Same row contents in a GroupBox; retry is a glass button with help and an accessibility label.
- [x] **DL3** Rows ordered by queue position. Before: `UI/ContentView.swift:336-354`. **Now:** Unchanged.

## PL. Playlists tab

- [x] **PL1** Playlist list (260 pt): title, "+" (help "Create playlist"), new-playlist field with add button (disabled when empty), playlists with count, active one checked; clicking one makes it active. Before: `UI/Explorer/WallpaperExplorer.swift:185-220`. **Now:** The split view sidebar (`UI/Playlists/PlaylistSidebar.swift`): header "Playlists" with "+" (help; it now also focuses the name field), the new-playlist field and add button at the bottom (Return also adds), playlists with count and the active one checked and selected. Choosing one makes it active; the toolbar sidebar button hides the list.
- [x] **PL2** Playlist detail: name, delete (help), Rotate automatically, Shuffle, Repeat, Change when video ends, Wallpaper duration slider (5–3600 s) with value, Previous/Next, count, items with thumbnail, title, move up/down (disabled at the ends), remove. Before: `UI/Explorer/WallpaperExplorer.swift:222-288`. **Now:** Unchanged controls (`UI/Playlists/PlaylistView.swift`); Delete, Previous and Next are glass; move up/down and remove gained help text. Deleting a playlist now asks first: a confirmation names the playlist, says its wallpapers stay in the library, and deletes only on Delete (the only delete path; there is no menu or shortcut for it). The duration label reads "45s", "1m", "1m15s" … "1h" and the slider snaps to 5 s steps below a minute and 15 s steps from a minute on (`UI/Playlists/PlaylistDurationFormat.swift`, `PlaylistDurationFormatTests`); the value is still stored in seconds.
- [x] **PL3** Empty state "Create a Playlist". Before: `UI/Explorer/WallpaperExplorer.swift:283-287`. **Now:** Unchanged.

## S. Settings (6 pages)

- [x] **S0** Toolbar tabs Performance, General, Plugins, Permissions, Diagnostics, About (icon + label, selected highlighted); "Edited" indicator while unsaved; OK saves and closes; Cancel closes and discards; page height 400–800, width ≥ 500. Before: `Settings/SettingsView.swift:43-155`, `Settings/SettingsToolbarIdentifiers.swift`. **Now:** Unchanged toolbar and Edited indicator; OK/Cancel are glass buttons (`Settings/SettingsView.swift`).
- [x] **S1** Performance ▸ Playback: Other Application Focused / Fullscreen / Playing Audio, Display asleep, Laptop on battery pickers; Application Rules Edit (disabled). Before: `Settings/PerformancePage.swift:21-66`. **Now:** Unchanged; Edit is glass prominent (still disabled).
- [x] **S2** Performance ▸ Quality: header note; Low/Medium/High/Ultra preset buttons; Anti-aliasing (red warning with help at ×8); Post-Processing (HDR option only with an HDR display, coerced on appear; yellow warning with help for Ultra); Texture Resolution, Scene Detail, Render Resolution, Volumetrics (help on each); FPS slider and field 10–120 (yellow warning over 30, red over 60, with help); Particle Budget (help); Reflections. Before: `Settings/PerformancePage.swift:67-203`. **Now:** Presets are a ControlGroup labelled "Preset" with the same four actions; the three warning triangles sit in the setting labels with the same colours and help (`Settings/PerformancePage.swift`).
- [x] **S3** General: Start with macOS; Language (disabled); Wallpaper Storage path, Choose… with the move/empty-folder confirmation, disconnected-volume warning, Use Default Location, error; Wallpaper Engine Assets path, Choose…, Use Built-in Assets; Remove original packages toggle, reclaimable size, Reclaim Now, result; Steam Web API key (masked key, Replace…, Remove, entry with Check & Save and Cancel, link); Adjust Menu Bar Color; Theme; Sync properties across displays; Audio Output; Reload when changing output device (disabled); Video Framework; Process Priority; Pause when VRAM is exhausted; Restart after crashing; Log Level; Reset Config. Before: `Settings/GeneralPage.swift`, `Workshop/SteamWebAPIKeyView.swift`. **Now:** Unchanged controls (`Settings/GeneralPage.swift`); Reset is glass prominent red, Check & Save glass prominent. **Intentionally removed at the user's request (2026-09-27):** the Wallpaper Engine Assets section (path, Choose…, Use Built-in Assets, the "Point it at the assets folder of a Wallpaper Engine installation" footer). The app always uses its bundled assets; a saved `WallpaperEngineAssetsDirectory` value is ignored and left in place. What only that setting enabled goes with it: the install's Steam Workshop content folder as a source of dependency items (dependencies come from the Wallpaper Storage folder). WE's labels are unaffected: its `locale/ui_*.json` ship in the bundled assets (`we-assets/locale`), read in the user's language over English.
- [x] **S4** Plugins: Animates toggle; Description expander (animated) with a GIF preview on a translucent tile and notes; Third-party "None"; footer. Before: `Settings/PluginsPage.swift`. **Now:** Unchanged; the GIF tile is glass on macOS 26, thin material before (`Settings/PluginsPage.swift`).
- [x] **S5** Permissions: permission row with status, Grant Access (disabled once granted), Open Privacy Settings, Recheck; refreshes on appear. Before: `Settings/PermissionsPage.swift`. **Now:** Unchanged.
- [x] **S6** Diagnostics: assets source and path, built-in compiler, fallback compiler paths, Re-detect, translated variant count, Refresh; values selectable. Before: `Settings/DiagnosticsPage.swift`. **Now:** Assets path, built-in compiler (in a section now titled "Shader Compiler") and the variant count with Refresh are unchanged. **Intentionally removed at the user's request (2026-09-27):** the Shader Toolchain section's "Fallback glslang" / "Fallback spirv-cross" (or "Fallback compiler: Not installed") rows, its Re-detect button and the `brew install glslang spirv-cross` footer hint, with the command-line fallback compiler itself; and the assets "Source" row, which only told the bundled copy from the removed assets setting.
- [x] **S7** About page inside Settings (same view as the About window). Before: `Settings/SettingsView.swift:60-61`. **Now:** Unchanged.

## SI. Scene Inspector

- [x] **SI1** Object list (300 pt): Versions section; Scene Objects with a per-object visibility switch (help Hide/Show object) and a kind icon; selection; initially the stored version or the first object. Before: `Scene/UI/SceneInspectorView.swift:877-907,845-849`. **Now:** The split view sidebar, 300 pt ideal and resizable 240–440, same sections, switches and help (`Scene/UI/SceneInspectorView.swift`).
- [x] **SI2** Search in the toolbar: capsule field that widens (240 → 300) and gains an accent ring while focused; clear button; ⌘K focuses it; filters by name, kind, paths, effects and parameters. Before: `Scene/UI/SceneInspectorView.swift:821-840,862-874,931-968`. **Now:** Native search field at the top of the sidebar with the same matching and a clear button; ⌘K focuses it (see K1). **Custom focus animation not carried over:** the widen-on-focus and accent ring are replaced by the system field's focus ring. Listed in the report.
- [x] **SI3** Copy Path toolbar button: copies the wallpaper folder, shows "Copied" for 1.5 s, help shows the path. Before: `Scene/UI/SceneInspectorView.swift:970-993`. **Now:** Native toolbar button "Copy Path" at the trailing end of the toolbar, with the same copy, "Copied" feedback and help. It is its own item, not grouped with the Move & Align toggle beside it.
- [x] **SI4** Titles: "Scene Inspector", then the selected object's name. Before: `Scene/UI/SceneInspectorView.swift:906,1022`. **Now:** "Scene Inspector" until an object is selected, then its name, which now also shows as the window title.
- [x] **SI5** Object detail: Type, Use This Version, Source, Material, Textures with decoded previews, Shaders, Effects (enable checkbox, info tip, disclosure with mask preview, combos with grouped options and requirements, colour pickers anchored beside the control, sliders with linked X/Y toggle, Sync to Music and Music Amount), Object Properties JSON editor with Save, Layer Details for video layers, Particle System and Material JSON editors with Save. Before: `Scene/UI/SceneInspectorView.swift:995-1176,1418-1528`. **Now:** Unchanged (`Scene/UI/SceneInspectorView.swift`); JSON editors and texture previews stay without glass.
- [x] **SI6** Empty states: "Scene Unavailable" with the error, "Select a Scene Object". Before: `Scene/UI/SceneInspectorView.swift:909-921`. **Now:** Unchanged.
- [x] **SI7** Movement column (300 pt): Move Element card with position readout and arrow buttons (help gives the steps), disabled without a selection; Size slider (0.05–5×), Reset to 1x, Blend mode picker for images; Align Element horizontal Left/Center/Right and vertical Top/Center/Bottom; step legend. Before: `Scene/UI/SceneInspectorView.swift:1178-1380`. **Now:** An inspector column (300 pt ideal, 260–400) with a toolbar toggle "Move & Align"; the column scrolls. The Move card is a GroupBox; arrow and alignment buttons are glass with their help; everything else unchanged.
- [x] **SI8** Arrow keys move the selected object while the detail or movement panel has focus (Shift 50 px, Control 1 px, otherwise 10 px). Before: `Scene/UI/SceneInspectorView.swift:925-928,1382-1403`. **Now:** Unchanged steps; works while the detail or the Move & Align column has focus, without a focus ring (`ArrowKeyMove`).
- [x] **SI9** Minimum size 1120 × 560. Before: `Scene/UI/SceneInspectorView.swift:844`. **Now:** Unchanged.

## WP. Workshop preview window

- [x] **WP1** Live wallpaper (Metal, AVKit or web). Before: `App/AppDelegate.swift:41-45`. **Now:** Unchanged.
- [x] **WP2** Bottom-right controls: Play/Pause (videos, with help), volume slider and field (videos), Set Wallpaper (prominent). Before: `App/AppDelegate.swift:47-69`. **Now:** Same controls in one GlassEffectContainer: play/pause and volume in a glass capsule, Set Wallpaper glass prominent; play/pause keeps its help and has an accessibility label (`App/AppDelegate.swift`).

## AB. About

- [x] **AB1** App icon, name, subtitle, version, contributors with GitHub links and roles. Before: `Settings/AboutUsView.swift:22-68`. **Now:** Unchanged (`Settings/AboutUsView.swift`); nothing there was custom chrome.

## FL. First Launch

- [x] **FL1** Sheet over the main window with four pages: header, feature rows, page dots, "Never show this again until next update", Back (disabled on the first page), Next/Finish (Return), selectable text, fade between pages. Help ▸ Debug ▸ Reset First Launch shows it again. Before: `UI/FirstLaunchView.swift`, `UI/ContentView.swift:184-187`. **Now:** Unchanged; Next/Finish is glass prominent (`UI/FirstLaunchView.swift`).

## SR. Safe-restart notice and unsafe wallpaper warning

- [x] **SR1** Notice: warning icon, message, Dismiss, Retry (prominent). Before: `App/SafeRestartNotice.swift:46-70`. **Now:** Same message and buttons; the panel is glass on macOS 26 and the buttons stay bordered to avoid glass on glass (`App/SafeRestartNotice.swift`).
- [x] **SR2** Unsafe wallpaper sheet: 5 s countdown, Proceed (red, disabled until the countdown ends), Cancel, "Don't ask again for this wallpaper", file path. Before: `UI/Explorer/Alerts/UnsafeWallpaper.swift`, `UI/ContentView.swift:188-191`. **Now:** Unchanged; Proceed is glass prominent red (`UI/Explorer/Alerts/UnsafeWallpaper.swift`).

## MN. Main menu

- [x] **MN1** App menu: About, Settings… (⌘,), Quit (⌘Q), Hide (⌘H), Hide Others (⌥⌘H). Before: `App/Menus/MainMenu.swift:13-29`. **Now:** Unchanged.
- [x] **MN2** File: Import ▸ Wallpaper from Folder (⌘I), Wallpapers in Folders; Close Window (⌘W). Before: `App/Menus/MainMenu.swift:32-47`. **Now:** Unchanged.
- [x] **MN3** Edit: Undo, Redo, Cut, Copy, Paste, Delete All, Select All. Before: `App/Menus/MainMenu.swift:50-62`. **Now:** Unchanged.
- [x] **MN4** View: Show Filter Results (⌃⌘S), Enter Full Screen (⌃⌘F). Before: `App/Menus/MainMenu.swift:65-79`. **Now:** Unchanged; Show Filter Results now animates the sidebar.
- [x] **MN5** Window: Wallpaper Explorer (⇧⌘1). Before: `App/Menus/MainMenu.swift:82-90`. **Now:** Unchanged.
- [x] **MN6** Help ▸ Debug: Reset First Launch, Toggle Desktop Wallpaper Window, Reset All Trusted Wallpapers. Before: `App/Menus/MainMenu.swift:93-106`. **Now:** Unchanged.

## SB. Status bar and Dock menu

- [x] **SB1** Status item (app icon, or a symbol fallback) with: Show Open Wallpaper Engine, Recent Wallpapers ▸ (rebuilt each time the menu opens), Browse Workshop, Settings, Support & FAQ, Mute, Pause, Quit. Before: `App/Menus/StatusBar.swift`. **Now:** Unchanged.
- [x] **DK1** Dock menu: the status menu without Quit. Before: `App/AppDelegate.swift:167-171`. **Now:** Unchanged.

## AL. Other alerts

- [x] **AL1** Audio permission alert: Grant Access, Open Permissions Page, Later, Don't Ask Again. Before: `App/AppDelegate.swift:260-283`. **Now:** Unchanged.

## K. Keyboard and accessibility

- [x] **K1** ⌘K focuses the Scene Inspector search. Before: `Scene/UI/SceneInspectorView.swift:870-874`. **Now:** Hidden ⌘K button (`Scene/UI/SceneInspectorView.swift`, `focusSearch`): `searchFocused` on macOS 15+, first-responder lookup of the window's search field on 14. Not keystroke-tested here (no Accessibility permission for synthetic keys).
- [x] **K2** Arrow keys nudge in the Scene Inspector (see SI8). **Now:** See SI8.
- [x] **K3** Return triggers Next/Finish in First Launch. Before: `UI/FirstLaunchView.swift:97`. **Now:** Unchanged; the new sheets also answer Return/Esc (Display Settings Done, Create Playlist, Add URL).
- [x] **K4** Help text on icon-only buttons: tile selection, safe-restart warning, delete wallpaper, favourite, author link, link rates, playlist create/delete, download retry, Workshop filters/author/clear selection/download state, Scene Inspector switches, arrows, alignment, link toggle, Copy Path, preview Play/Pause. **Now:** All kept; new icon-only toolbar and row buttons have help text and labels (sidebar, Details, Move & Align, Add Wallpaper, Refresh, playlist rows, copy snippet, retry).
