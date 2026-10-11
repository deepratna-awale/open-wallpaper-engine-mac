# WE 2.8.42 Installed-tab folders: ground truth

Sources: `ui/dist/scripts/scripts.js` (byte offsets below), `ui/dist/**/*.css`, `locale/ui_en-us.json`, `config.json`.

## Colours (picker order, 5-column grid, preceded by a "Default" button)

Locale: `ui_browse_context_menu_change_color` = "Change Color", `ui_browse_context_menu_default` = "Default".

| # | CSS class (stored value) | Hex (from CSS) |
|---|---|---|
| - | Default (key deleted) | none |
| 1 | browseFolderColorBrightBlue | #00f5ff |
| 2 | browseFolderColorBlue | #2973f3 |
| 3 | browseFolderColorPurple | #780cff |
| 4 | browseFolderColorMagenta | #cc1a7a |
| 5 | browseFolderColorRed | #cc1a00 |
| 6 | browseFolderColorYellow | #cc7a00 |
| 7 | browseFolderColorBrightYellow | #efda00 |
| 8 | browseFolderColorGreen | #7acc00 |
| 9 | browseFolderColorDarkGreen | #2f6744 |

OWE's list matches exactly, same order. Note WE stores the class name, not the hex.

Evidence (scripts.js ~57000):
```
P.button("ui_browse_context_menu_default","",M=function(e){e?o.folderColor=e:delete o.folderColor},...),P.grid(5),
P.gridItem("","fas fa-square browseFolderColorBrightBlue",M,"browseFolderColorBrightBlue"), ...
```
CSS: `.browseFolderColorBrightBlue{color:#00f5ff}` etc.

## Icons (picker order, 5-column grid; `ui_browse_context_menu_change_icon` = "Change Icon")

Stored value is either a string (closed=open) or `{close, open}`; first item sets nothing (default).

1. fas fa-folder (default: deletes folderIcon/folderIconOpen; renders fa-folder / fa-folder-open)
2. fas fa-star
3. fas fa-heart
4. fas fa-gem
5. fas fa-car (open: fas fa-car-burst)
6. fas fa-rocket (open: fas fa-rocket-launch)
7. fas fa-snowflake (picker shows far fa-snowflake)
8. fas fa-thumbs-up
9. fas fa-gamepad-modern
10. fas fa-gift
11. fas fa-music
12. fas fa-trash
13. fas fa-bug
14. fas fa-magic (open: fas fa-wand-magic-sparkles)
15. fas fa-banana
16. fas fa-alien
17. fas fa-alien-8bit
18. fas fa-bat
19. fas fa-bomb (open: fas fa-explosion)
20. fas fa-boombox
21. fas fa-candle-holder
22. fas fa-dragon
23. fas fa-fire
24. fas fa-meteor
25. fas fa-tree-palm
26. fas fa-skull-crossbones
27. fas fa-tree-christmas
28. fas fa-tv-retro
29. fas fa-balloons (open: far fa-burst)
30. fas fa-bone

Many are Font Awesome Pro (alien, banana, bat, boombox, tree-palm, tv-retro, balloons, gamepad-modern...).

Evidence (scripts.js 54433):
```
I=function(e){e?angular.isObject(e)?(o.folderIconOpen=e.open,o.folderIcon=e.close):(delete o.folderIconOpen,o.folderIcon=e):(delete o.folderIconOpen,delete o.folderIcon)},
(E=B.builder()).grid(5),E.gridItem("","fas fa-folder browseFolderIconEnlarge",I),
E.gridItem("","fas fa-star browseFolderIconEnlarge",I,"fas fa-star"), ...
E.gridItem("","fas fa-car browseFolderIconEnlarge",I,{close:"fas fa-car",open:"fas fa-car-burst"}), ...
```
Rendering (scripts.js ~490250): `folderIcon.replace("fa ","fas ")`; if `folderIconOpen` set, closed/open spans get `folderClosed`/`folderOpened`; `folderColor` class appended to both.

## config.json storage

Path: `<account>.general.browser.folders`. On this machine it is empty (`[]`), so format is inferred from scripts.js.

Folder object (fields used by the code, offsets 19005, 36608-37131, 31431, 54433, 57108):
```json
{
  "type": "folder",
  "title": "My Folder",
  "items": { "<workshopid or file path>": 1 },
  "subfolders": [ /* nested folder objects */ ],
  "folderColor": "browseFolderColorRed",
  "folderIcon": "fas fa-rocket",
  "folderIconOpen": "fas fa-rocket-launch"
}
```
- `folderColor`: CSS class name string; absent = default.
- `folderIcon`: FA class string; absent = default folder. `folderIconOpen`: only present for icons with a distinct open variant.
- `items`: map keyed by workshop id (or local file for non-workshop) with value 1.
