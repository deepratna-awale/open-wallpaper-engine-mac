Open Wallpaper Engine (gepatcht)
=========

[English](../../README.md) | **Deutsch** | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Ein gepatchter Fork von [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) für macOS, der das Rendern von Szenen-Hintergrundbildern und Korrekturen für Web-Hintergrundbilder hinzufügt.

> **Hinweis:** Dieses Projekt steht in KEINER Verbindung zum kommerziellen Wallpaper Engine auf Steam. Es handelt sich um eine Open-Source-App für macOS, die Hintergrundbild-Assets aus dem Steam Workshop von Wallpaper Engine anzeigen kann.

## Verwandte Projekte

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** – Eine PyQt6-Oberfläche für [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) mit Steam-Workshop-Integration und einem von dieser macOS-Version übernommenen UI-Design.

## Danksagungen

Dieses Projekt baut auf der Arbeit folgender Personen auf:

- **[MrWindDog](https://github.com/MrWindDog)** – Maintainer des Upstream-Forks [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac), hat neue Funktionen und Verbesserungen der Benutzeroberfläche hinzugefügt
- **[Haren Chen](https://github.com/haren724)** – Ursprünglicher Entwickler von [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac), hat die Kernarchitektur der App erstellt (SwiftUI, Wiedergabe von Video-Hintergrundbildern, Importsystem, Playlist-Oberfläche)
- **[1ris_W](https://github.com/Erica-Iris)** – Chinesische Übersetzung (i18n)
- **[Klaus Zhu](https://github.com/klauszhu1105)** – App-Symbole
- **[Chen Chia Yang](https://github.com/Unayung)** – Rendern von Szenen-Hintergrundbildern, Korrekturen für Web-Hintergrundbilder, Steam-Workshop-Integration, Unterstützung mehrerer Displays, Zip-Import
- **[Deepratna Awale](https://github.com/deepratna-awale)** – Metal-Szenenrenderer und Effekt-Pipeline, Übersetzung und Caching von GLSL→MSL-Shadern, SceneScript-Laufzeitumgebung, audioreaktives Rendern, Überarbeitung von Workshop und Downloads, Platzierungs- und Leistungseinstellungen

Lizenziert unter [GPL-3.0](../../LICENSE), wie das ursprüngliche Projekt.

## Funktionsumfang von 0.8.1

### Wiedergabe von Hintergrundbildern
- **Szenen-Hintergrundbilder** werden nativ mit Metal gerendert – Bildebenen, Transformationen, Keyframe-Zeitleisten, Tiefenreihenfolge sowie Kamera- und Projektionsdaten aus `scene.json`.
- **Video-Hintergrundbilder** (`.mp4`, `.webm`) mit Wiedergabegeschwindigkeit, Lautstärke, Kopplung der Audio- und Videogeschwindigkeit sowie optionalem, mit der Musik synchronisiertem Zoom, Neigen und Sättigung.
- **Web-Hintergrundbilder** (HTML/WebGL) mit aktiviertem Zugriff auf lokale Dateien, damit WebGL-Texturen und Assets korrekt geladen werden, sowie externe Einbettungen (YouTube/Vimeo).
- **Platzierungsmodi** – Bildschirmfüllend, An Bildschirm anpassen, Zentriert, Bildschirmfüllend vergrößern, Zoomen.
- **Mehrere Displays** – ein eigenes Hintergrundbild pro Monitor, Aktivieren und Deaktivieren pro Bildschirm, visuelle Monitoranordnung und automatische Erkennung neu angeschlossener Displays.
- **Mehrere Schreibtische (Spaces)** – durchgehende Wiedergabe auf allen Schreibtischen, einschließlich der Zuweisungsoption `Alle Schreibtische`.
- **Wiedergaberegeln** – weiterlaufen, Ton aus, Pause oder Stopp, wenn eine andere App im Vordergrund ist; korrektes Verhalten beim Ruhezustand, Aufwachen und Wechseln des Schreibtischs.

### Unterstützung des Szenenformats
- **PKG-Parser** für `PKGV`-Archive von Wallpaper Engine (scene.json, Materialien, Texturen, Shader).
- **TEX-Parser** für `TEXV0005`-Container: eingebettetes JPEG/PNG sowie DXT1/DXT3/DXT5 mit Mipmaps, auf der GPU per Metal-Compute-Shader decodiert.
- **TEXS-Sprite-Zeitleisten** (0001/0002/0003), einschließlich Frame-Rechtecken in einem einzelnen Atlas und Sequenzen aus mehreren Bildern.
- **Flexibles Decodieren von scene.json**, das die polymorphen Felder von Wallpaper Engine verarbeitet (einfache Werte oder `{"script":…,"value":…}`).
- **Vorschau als Fallback** auf `preview.jpg/png/gif`, wenn Texturen nicht extrahiert werden können.

### Effekte und Shader
- **~48 native Metal-Effekte**, darunter Verzerrung, Weichzeichnung (Standard/präzise/radial/Bewegung), Bloom, Godrays und Lichtstrahlen, Wasserwellen/Kräuselungen/Kaustiken/Strömung, Wolken und Nebel, Filmkorn, Glitch/VHS, chromatische Aberration, Farbschlüssel, Transformieren/Scheren/Drehen/Verwirbeln/Perspektive, Spiegelung, Brechung, Glanz/Schimmer/Glitzer, Kantenerkennung und mehr.
- **Audioreaktive Effekte** – Puls, Audiobalken, audiosynchrone Farbtonverschiebung und Hyperdrive, gesteuert durch Live-Spektrumdaten des Systemaudios.
- **Semantische Materialeffekte** – Helligkeit, Kontrast, Sättigung, Belichtung, Gamma, Farbton, Bloom-Schwellenwert, Bloom und Weichzeichnung, abgebildet auf native Metal-Durchläufe.
- **GLSL → SPIR-V → MSL-Übersetzung** beim Laden durch die in die App eingebundenen Bibliotheken glslang und SPIRV-Cross, mit COMBO-Defines, Auflösung von Includes und Neunummerierung der Metal-Buffer-Slots.
- **Vorkompilierter Shader-Cache** – übersetzte `.metal`-Dateien, kompilierte `.metallib`-Dateien und `.reflection.json`-Begleitdateien werden unter `.open-wallpaper-engine/shaders` zwischengespeichert, per Hash abgesichert, sodass nur geänderte Shader neu übersetzt werden, und im Hintergrund kompiliert, sodass das Rendern nie blockiert wird.
- **Dynamischer Effektkatalog**, gelesen aus den Manifesten `assets/effects/*/effect.json` von Wallpaper Engine, einschließlich Effekten mit mehreren Durchläufen und per Reflexion ermittelten Uniform-Bindungen.
- **Effektmasken** (bis zu 4 Maskentexturen pro Ebene), additives und Alpha-Blending sowie ein System mit gepoolten Render-Targets.

### Partikel
- Sprite-Emitter mit zufälliger Lebensdauer, Größe, Geschwindigkeit, Farbe, Rotation, Winkelgeschwindigkeit, Schwerkraft, Luftwiderstand und Alpha-Überblendung.
- Erweitertes Verhalten – Turbulenz, Attraktoren, Wirbel- und Boid-Bewegung, statische und an den Cursor gekoppelte Kontrollpunkte, verbundene Seilsegmente sowie Spuren mit Alpha- und Größenüberblendung.
- Frame-Animation aus Spritesheets über `.tex-json`-Sequenzen.
- Skriptgesteuerte Operatoren für Emissionsrate, Luftwiderstand und Zeitpunkt der Alpha-Überblendung.

### SceneScript-Laufzeitumgebung
- Dauerhafte Skriptkontexte pro Ebene, wobei `init()` einmal und `update(value)` in jedem Frame aufgerufen wird.
- Globale Objekte: `thisScene`, `thisLayer`, `engine`, `input`, `audio(low, high)`, echtes `fft(index)`, `setTimeout`/`setInterval` und dauerhafte globale Skriptvariablen.
- Vollständige Mathematikbibliothek für `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4` sowie die Hilfsfunktionen `WEMath`, `WEVector` und `WEColor`.
- JS-Laufzeitmodule von Wallpaper Engine, geladen aus `assets/scripts/jsmodules` und `jsclasses`.
- Cursor-Ereignisse (`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`) und `resizeScreen`.
- Skripte können Alpha, Ursprung, Größe, Skalierung, Winkel, Helligkeit/Farbe der Ebene, Materialkonstanten, Effekt-Schwellenwerte und Partikelraten steuern.
- Deduplizierte Protokollierung von Skriptausnahmen mit Wiederholungszählern.

### Audio
- Aufnahme des Systemaudios über ScreenCaptureKit, die ein geglättetes Spektrum mit 16 Bändern, eine Wellenform sowie Pegel für Bass, Mitten und Höhen liefert.
- **Musiksynchronisierung** pro Eigenschaft – jede Benutzereigenschaft kann mit einstellbarer Stärke durch den Audiopegel moduliert werden.

### Benutzereigenschaften & Inspektor
- Projekteinstellungen als Schieberegler, Markierungsfeld, Auswahlliste, Text und Farbe, angezeigt in der Seitenleiste der Szene, live angewendet und aus SceneScript lesbar.
- Mausverfolgung und Parallaxe für Ebenen mit festgelegtem `parallaxDepth`.

### Steam Workshop
- Durchsuchen, Suchen und Filtern nach Altersfreigabe, Typ und Genre-Tags, mit den Sortierungen Im Trend / Neueste / Beliebteste / Meiste Abonnements und nummerierter Seitennavigation.
- Vorschaufenster mit Steuerelementen zum Festlegen als Hintergrundbild, für die Wiedergabe und die Lautstärke, gestützt durch einen begrenzten Cache; angewendete Vorschauen werden ohne erneutes Laden in die Mediathek übernommen.
- SteamCMD-Integration mit automatischer Erkennung, Anmeldung per Passwort, Steam Guard oder zwischengespeicherter Sitzung, eigenem Tab „Downloads“, in Warteschlangen eingereihten und wiederholbaren Downloads sowie Live-Fortschritt.
- Mehrfachauswahl, Bereichsauswahl, Massen-Downloads und -Löschvorgänge mit Bestätigung, dauerhaft gespeicherte IDs geladener Objekte und Sortierung nach `Downloaddatum`.

### Mediathek & Einstellungen
- Import aus Ordnern, aus `.zip`-Paketen oder per Drag & Drop.
- Konfigurierbarer Speicherort für Hintergrundbilder mit Migration einer vorhandenen Mediathek.
- Menü mit zuletzt verwendeten Hintergrundbildern in der Menüleiste.
- Leistungseinstellungen – Qualität, Antialiasing, Post-Processing und Wiedergabeverhalten bei Fokusverlust.
- Diagnose – der Pfad der mitgelieferten Assets, die Bibliotheksversionen des integrierten Shader-Compilers und Statistiken zum Shader-Cache.

<details>
<summary>Bisher in 0.8.0</summary>

### Unterstützung mehrerer Displays
Weisen Sie jedem angeschlossenen Monitor ein anderes Hintergrundbild zu – mit Aktivieren und Deaktivieren pro Bildschirm.
- **Bereich „Displayeinstellungen“** – Visuelle Monitoranordnung mit allen angeschlossenen Bildschirmen; zum Auswählen klicken
- **Hintergrundbild pro Bildschirm** – Jedes Display kann unabhängig ein anderes Hintergrundbild anzeigen
- **Schalter zum Aktivieren/Deaktivieren** – Hintergrundbild pro Monitor ein- oder ausschalten
- **Automatische Erkennung** – Neue Monitore werden beim Anschließen automatisch erkannt und aktiviert

### Unterstützung mehrerer Schreibtische
Hintergrundbilder werden jetzt auf allen macOS-Schreibtischen (Spaces) mit durchgehender Wiedergabe angezeigt – ohne Unterbrechung beim Wechseln des Schreibtischs.

### Menü „Zuletzt verwendete Hintergrundbilder“
Wechseln Sie Hintergrundbilder schnell über das Menü in der Menüleiste. Die letzten 10 verwendeten Hintergrundbilder stehen dort mit einem Klick zur Verfügung.

### Wiedergabeeinstellungen – korrigiert
Die Wiedergabeeinstellungen unter „Leistung“ (Pause/Ton aus/Stopp, wenn andere Apps im Vordergrund sind) funktionieren jetzt für alle Hintergrundbildtypen korrekt.

### Steam-Workshop-Browser
Durchsuchen, suchen und laden Sie Hintergrundbilder direkt aus dem Steam Workshop, ohne die App zu verlassen.
- **Suchen & Filtern** – Suche nach Name, Filter nach Altersfreigabe (Jeder/Fragwürdig/Nicht jugendfrei), Typ (Szene/Video/Web) und Genre-Tags
- **Sortieroptionen** – Im Trend, Neueste, Beliebteste, Meiste Abonnements
- **steamcmd-Integration** – Erkennt steamcmd automatisch (Homebrew oder eigener Pfad) und zeigt Installationsanweisungen an, wenn es nicht gefunden wird
- **Steam-Anmeldung** – Unterstützt die Authentifizierung per Passwort, Steam Guard und zwischengespeicherter Sitzung
- **Download mit Fortschritt** – Statusaktualisierungen in Echtzeit während des Downloads (Authentifizierung, Download in %, Überprüfung, Kopieren)
- **Sichere Standardwerte** – Die Altersfreigabe ist standardmäßig auf „Jeder“ gesetzt, um nicht jugendfreie Inhalte herauszufiltern

### Zip-Import
Importieren Sie Hintergrundbildpakete direkt aus `.zip`-Dateien – ohne sie vorher manuell zu entpacken. Funktioniert über Ablage > Importieren und per Drag & Drop.

### Mehrfachauswahl & Abbestellen im Stapel
Klicken Sie mit gedrückter Befehlstaste (Cmd), um mehrere Hintergrundbilder auszuwählen, und klicken Sie dann mit der rechten Maustaste, um sie gesammelt abzubestellen.

### Isolierter Hintergrundbild-Speicher
Hintergrundbilder werden jetzt in `~/Documents/OpenWallpaperEngine/` statt direkt im Ordner „Dokumente“ gespeichert. Dadurch werden „error“-Hintergrundbilder vermieden, wenn das Repository auf einem neuen Rechner geklont wird.

</details>

<details>
<summary>Änderungen gegenüber Upstream</summary>

### Web-Hintergrundbilder – graue/leere Darstellung korrigiert
WebGL-basierte Hintergrundbilder wurden als graue Rechtecke dargestellt, weil `WKWebView` den Zugriff auf lokale Dateien für Texturen und Assets blockiert hat.

**Korrektur:** `allowFileAccessFromFileURLs` und `allowUniversalAccessFromFileURLs` wurden in der WKWebView-Konfiguration aktiviert, sodass WebGL-Shader lokale Texturdateien laden können.

### Szenen-Hintergrundbilder – von Grund auf implementiert
Szenen-Hintergrundbilder (der häufigste Typ im Steam Workshop) waren überhaupt nicht implementiert – es wurde nur „Hello, World!“ angezeigt.

**Die neue Implementierung umfasst:**
- **PKG-Parser** – Liest das PKGV-Archivformat von Wallpaper Engine, um scene.json, Modelle, Materialien und Texturen zu extrahieren
- **TEX-Parser** – Liest TEXV0005-Texturcontainer, extrahiert eingebettete JPEG/PNG-Bilddaten und liest DXT1/DXT3/DXT5-Mipmaps
- **Scene-JSON-Decoder** – Parst scene.json mit flexiblem Decodieren, das die polymorphen Felder von Wallpaper Engine verarbeitet (Werte können einfache Typen oder `{"script":..,"value":..}`-Objekte sein)
- **Metal-Renderer** – Rendert Bildebenen von Szenen mit GPU-Texturkomposition und einer Grundlage für künftige Shader-Effekte
- **DXT-Decodierung auf der GPU** – Entpackt DXT1- (TEXI 7), DXT3- (TEXI 6) und DXT5-Texturen (TEXI 4) beim Laden der Szene über einen Metal-Compute-Shader
- **Sprite-Partikel** – Rendert gängige `sphererandom`-Sprite-Emitter mit zufälliger Lebensdauer, Größe, Geschwindigkeit, Alpha, Farbe, Rotation, Winkelgeschwindigkeit, Schwerkraft, Luftwiderstand und Alpha-Überblendung
- **Erweiterte Partikel** – Unterstützt Rotation, Farbvariation, Turbulenz, statische und an den Cursor gekoppelte Kontrollpunkte, verbundene Seilsegmente, Spuren und Frame-Animation aus `.tex-json`-Spritesheets
- **TEXS-Animation** – Decodiert TEXS0001/0002/0003-Zeitleisten, einschließlich Frame-Rechtecken in einem einzelnen Atlas und Textursequenzen aus mehreren Bildern
- **Szenen-Zeitleisten** – Interpoliert Keyframes für Alpha, Ursprung, Skalierung und Winkel von Objekten mit 60 FPS
- **SceneScript-Laufzeitumgebung** – Wertet Ausdrücke und Eigenschaftsskripte mit `export function update(value)` anhand des Systemaudios aus ScreenCaptureKit aus. Das Timing von `thisScene`, `thisLayer.value`, `engine`, der Eingabecursor, `audio(low, high)`, echtes `fft(index)`, das Nachschlagen von Eigenschaften und dauerhafte globale Variablen steuern Bildtransformationen, Alpha und Partikel-Emissionsraten.
- **Dauerhafter SceneScript-Lebenszyklus** – Verwendet Skriptkontexte pro Ebene wieder, ruft `init()` einmal auf und ruft `update()` über alle Frames hinweg auf, mit gemeinsamem Zustand für `dt`, Frame, Maus, Taste, Sondertaste, Cursor, Audio, FFT, Eigenschaften und Ebenen.
- **Skriptgesteuerte Partikeloperatoren** – Unterstützt Skripte für Partikel-Emissionsrate, Luftwiderstand der Bewegung und Zeitpunkt der Alpha-Überblendung, mit flexiblen numerischen/String-Partikelfeldern.
- **Mausverfolgung und Parallaxe** – Wendet eine cursorbezogene Verschiebung und optional eine perspektivische Skalierung auf Ebenen mit festgelegten `parallaxDepth`-Metadaten an; an den Cursor gekoppelte Partikel verwenden denselben Cursor im Szenenraum.
- **Skriptgesteuerte visuelle Eigenschaften** – Unterstützt skriptgesteuerte Helligkeit/RGB-Farbe von Objekten, Konstanten von Materialeffekten, Skalar-/Vektortransformationen und das Überschreiben von Effekt-Schwellenwerten.
- **Benutzereigenschaften** – Zeigt dokumentierte Projekteinstellungen als Schieberegler, Markierungsfeld, Auswahlliste, Text und Farbe in der Seitenleiste der Szene an und stellt numerische und boolesche Werte für SceneScript bereit
- **Integrierte Szeneneffekte** – Führt festgelegte Einträge `pulse`, `shake`, `iris` und `waterwaves` des Effektgraphen im Metal-Renderer aus
- **Semantische Materialeffekte** – Bildet gängige Materialkonstanten und Skripte für Helligkeit, Kontrast, Sättigung, Belichtung, Gamma, Farbton, Bloom-Schwellenwert, Bloom und Weichzeichnung auf native Metal-Effekte ab
- **GLSL-Shader-Übersetzung** – Konvertiert die mitgelieferten GLSL-Shader von Wallpaper Engine beim Laden mit den in die App eingebundenen Bibliotheken glslang und SPIRV-Cross in SPIR-V und MSL; übersetzte Varianten werden unter `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants` zwischengespeichert
- **Vorschau als Fallback** – Greift auf preview.jpg/png/gif zurück, wenn Texturen nicht extrahiert werden können

### Import – Ordnerimport korrigiert
Das Importfenster verarbeitet jetzt sowohl einzelne Hintergrundbildordner als auch übergeordnete Verzeichnisse mit mehreren Hintergrundbildern korrekt.

</details>

## Aktuelle Einschränkungen

- **Anwendungs-Hintergrundbilder** – Hintergrundbilder mit `type: "application"` werden nicht unterstützt und laufen nicht.
- **3D-Modelle und Rigging** – Knochentransformationen, Blend Shapes, Anhänge und Puppet-Warp-Rigs (`.mdl`) sind nur als Platzhalter vorhanden; betroffene Ebenen werden als flache Atlanten gerendert.
- **Skriptfunktionen für Materialien** – `getMaterial()`, `getMaterialCount()`, `setMaterialProperty()` und `executeMaterialFunction()` sind Platzhalter, die nichts tun oder leere Werte zurückgeben.
- **Bindung eigener GLSL-Shader** – Konvertiertes MSL wird beim Import zwischengespeichert, aber Shader, die von Wallpaper-Engine-spezifischen Attributen, Texturketten oder nicht unterstützten Includes abhängen, werden nicht in die Metal-Pipeline zur Laufzeit eingebunden. Gängige Parameter für Bloom, Weichzeichnung, Farbkorrektur und Transformation greifen auf native Metal-Abbildungen zurück.
- **Metal-Buffer-Limit** – Shader, die mehr als die 31 Buffer-Slots von Metal benötigen, können nicht übersetzt werden und werden für die aktuelle Pipeline-Revision dauerhaft als nicht unterstützt markiert.
- **HLSL-Shader** – Reine Direct3D-Shader, die neben den GLSL-Quellen ausgeliefert werden, werden vollständig übersprungen.
- **Abdeckung von Effektschemata** – Unbekannte eigene Uniform-Namen und beliebige Parameterschemata von Effekten werden weiterhin nicht unterstützt.
- **SceneScript-Parität** – Nicht jeder proprietäre Ereignisname, jeder Eingabe-Callback, jeder Sonderfall im Lebenszyklus und jede exakte Timing-Semantik wird nachgebildet.
- **Abdeckung von Partikeloperatoren** – Gängige skriptgesteuerte Operatoren für Rate, Luftwiderstand und Alpha-Überblendung funktionieren; seltene Operatorskripte, eigene Partikelmodule und beliebige Operatorschemata werden nur teilweise unterstützt.
- **Wiederherstellung externer Assets** – Einige Workshop-Pakete verweisen auf gemeinsam genutzte TEX-Assets, die im geladenen Paket fehlen, und benötigen die ursprüngliche Wallpaper-Engine-Installation.
- **Einige JPEG-Miniaturen** – Einige wenige Dateien im Format TEXB 1 enthalten nicht standardkonforme JPEG-Daten, die macOS nicht decodieren kann.
- **Geltungsbereich der Leistungseinstellungen** – Die Optionen für Qualität, Antialiasing und Post-Processing sind für Szenen-Hintergrundbilder gedacht und wirken sich auf Video- und Web-Hintergrundbilder nur begrenzt aus.
- **Audiofunktionen erfordern eine Berechtigung** – Ohne die Berechtigung „Aufnahme von Bildschirm & Systemaudio“ erhalten Audio-Visualisierungen und audioreaktives SceneScript nur Stille.

## Unterstützte Hintergrundbildtypen

| Typ | Status |
|------|--------|
| Video (.mp4, .webm) | Funktioniert |
| Web (HTML/WebGL) | Funktioniert |
| Szene – Bildebenen & Zeitleisten | Funktioniert (Metal) |
| Szene – DXT1/DXT3/DXT5-Texturen | Funktioniert (Metal-GPU-Decodierung) |
| Szene – TEXS-Sprites / Alpha-Zeitleisten | Funktioniert |
| Szene – Sprite-Partikel | Funktioniert |
| Szene – erweiterte Partikel | Teilweise (skriptgesteuerte Rate/Luftwiderstand/Überblendung unterstützt) |
| Szene – native Metal-Effekte | Funktioniert (~48 Effekte) |
| Szene – übersetzte GLSL-Effekte aus dem Workshop | Teilweise (siehe Einschränkungen) |
| Szene – SceneScript | Teilweise (siehe Einschränkungen) |
| Szene – 3D-Modelle / Rigging / Puppet Warp | Nicht unterstützt |
| Anwendung | Nicht unterstützt |

## Voraussetzungen

### Erforderlich
- **macOS 13.0 oder neuer** (Ventura). Sowohl die Audioaufnahme über ScreenCaptureKit als auch das Rendern von Szenen mit Metal setzen dies voraus.

### Optional – für bestimmte Funktionen erforderlich

| Funktion | Voraussetzung | Installation |
|---------|-------------|---------|
| Durchsuchen / Laden aus dem Steam Workshop | `steamcmd` | `brew install steamcmd` |
| Audio-Visualisierungen & audioreaktives SceneScript | Berechtigung „Aufnahme von Bildschirm & Systemaudio“ | Einstellungen → Berechtigungen |

#### Shader

Wallpaper Engine liefert seine Effekte als GLSL aus. Sie werden von glslang und SPIRV-Cross, die in die App integriert sind (`Vendor/ShaderToolchain`), beim ersten Verwenden durch ein Hintergrundbild nach Metal übersetzt (GLSL → SPIR-V → MSL) und anschließend auf dem Datenträger zwischengespeichert. Es muss nichts installiert werden. Ein Shader, dessen Übersetzung die App hängen ließ oder zweimal zum Absturz brachte, wird bei späteren Starts übersprungen; alle anderen Shader werden weiterhin übersetzt.

#### Wallpaper-Engine-Assets

Die gemeinsam genutzten Effekte, Materialien, Shader und die SceneScript-Laufzeitumgebung, auf die Hintergrundbilder verweisen, sind in der App enthalten (`Vendor/we-assets`, aktualisiert aus einer Wallpaper-Engine-Installation mit `Scripts/vendor-we-assets.sh`). Es muss nichts konfiguriert werden.

## Aus dem Quellcode erstellen

### Voraussetzungen
- macOS >= 14.0
- Xcode >= 26.3 (macOS 26 SDK)
- Xcode Command Line Tools

### Schritte
```sh
git clone https://github.com/unayung/wallpaper-engine-mac
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

Ändern Sie in Xcode das Signaturzertifikat in Ihr eigenes oder wählen Sie „Sign to Run Locally“ und drücken Sie dann `Cmd + R`, um die App zu erstellen und auszuführen.

## Verwendung

### Aus dem Steam Workshop durchsuchen & laden

1. Installieren Sie steamcmd (`brew install steamcmd`) oder verweisen Sie die App auf eine vorhandene Binärdatei
2. Wechseln Sie zum Tab **Workshop** und melden Sie sich mit Ihrem Steam-Account an (Sie müssen Wallpaper Engine besitzen)
3. Geben Sie einen [Steam-Web-API-Schlüssel](https://steamcommunity.com/dev/apikey) ein, wenn Sie dazu aufgefordert werden, oder unter *Einstellungen → Allgemein*. Er wird bei Steam überprüft und in Ihrem Schlüsselbund gespeichert; Ihr Steam-Passwort wird nie gespeichert (steamcmd verwendet seine eigene zwischengespeicherte Sitzung erneut)
4. Suchen und filtern Sie und klicken Sie bei einem beliebigen Hintergrundbild auf **Laden**

### Aus lokalen Dateien importieren

- **Ordner:** Ablage > Importieren > Hintergrundbild aus Ordner – wählen Sie Hintergrundbildordner aus, die `project.json` enthalten
- **Zip:** Ablage > Importieren oder ziehen Sie eine `.zip`-Datei mit Hintergrundbildpaketen per Drag & Drop in die App
- **Manuell:** Kopieren Sie Hintergrundbildordner direkt nach `~/Documents/OpenWallpaperEngine/`

## Projektstruktur

- `OpenWallpaperEngine/Services/SceneParsers/` – Parser und Modelle für PKG, TEX/TEXS und scene.json
- `OpenWallpaperEngine/Services/SceneEffects/` – dynamischer Effektkatalog und festgelegte Wertebereiche für Effektparameter
- `OpenWallpaperEngine/Scene/Shaders/` – GLSL → SPIR-V → MSL-Übersetzung (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), Caching und das Pipeline-Archiv
- `Vendor/ShaderToolchain/` – Quellcode von glslang und SPIRV-Cross, als lokales Paket in die App eingebunden
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift` – SceneScript-Laufzeitumgebung und Audio-/FFT-Bindungen
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` – Aufnahme des Systemaudios über ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` – der Metal-Szenenrenderer und die Shader-Bibliothek
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` – Durchsuchen des Steam Workshop und Downloads
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` – Speicher der Mediathek, Import und Paketkonvertierung
- `Scripts/vendor-we-assets.sh` – übernimmt übersetzte Effekt-Shader und Manifeste nach `we-assets/`
- `Scripts/scene-api-coverage.py` – zeigt an, welche SceneScript-APIs installierte Hintergrundbilder verwenden und welche implementiert sind
