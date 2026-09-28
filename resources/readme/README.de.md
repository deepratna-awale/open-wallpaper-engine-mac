Open Wallpaper Engine
=========

[English](../../README.md) | **Deutsch** | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine ist ein kostenloser Open-Source-Player für macOS, der Wallpaper-Engine-Hintergrundbilder abspielt: Szenen, Videos und Web. Er bringt einen nativen Metal-Renderer mit und unterstützt Effekte, Partikel, 3D-Modelle, Beleuchtung, SceneScript, audioreaktive Visuals und den Steam Workshop. Das Projekt begann als Fork von [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) von Haren Chen und MrWindDog und wurde seitdem weitgehend neu geschrieben.

> **Hinweis:** Dieses Projekt steht in KEINER Verbindung zum kommerziellen Wallpaper Engine auf Steam. Es handelt sich um eine Open-Source-App für macOS, die Hintergrundbild-Assets aus dem Steam Workshop von Wallpaper Engine anzeigen kann. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** Anleitungen und Dokumentation findest du im [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Verwandte Projekte

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** – Eine PyQt6-Oberfläche für [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) mit Steam-Workshop-Integration und einem von dieser macOS-Version übernommenen UI-Design.

## Danksagungen

Dieses Projekt baut auf der Arbeit folgender Personen auf:

- **[MrWindDog](https://github.com/MrWindDog)** – Maintainer des Upstream-Forks [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac), hat neue Funktionen und Verbesserungen der Benutzeroberfläche hinzugefügt
- **[Haren Chen](https://github.com/haren724)** – Ursprünglicher Entwickler von [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac), hat die Kernarchitektur der App erstellt (SwiftUI, Wiedergabe von Video-Hintergrundbildern, Importsystem, Playlist-Oberfläche)
- **1ris_W** – Chinesische Übersetzung (i18n)
- **[Klaus Zhu](https://github.com/klauszhu1105)** – Ursprüngliches Logodesign
- **[Chen Chia Yang](https://github.com/Unayung)** – Rendern von Szenen-Hintergrundbildern, Korrekturen für Web-Hintergrundbilder, Steam-Workshop-Integration, Unterstützung mehrerer Displays, Zip-Import
- **[Deepratna Awale](https://github.com/deepratna-awale)** – Metal-Szenenrenderer und Effekt-Pipeline, Übersetzung und Caching von GLSL→MSL-Shadern, SceneScript-Laufzeitumgebung, audioreaktives Rendern, Überarbeitung von Workshop und Downloads, Platzierungs- und Leistungseinstellungen, Neugestaltung des Logos

Lizenziert unter [GPL-3.0](../../LICENSE), wie das ursprüngliche Projekt.

## Von 0.8.1 zu 1.0.0

### Der Ausgangspunkt

Dieser Fork beginnt beim Upstream-Stand 0.8.1 (Commit `aa29a89e`, März 2026). 0.8.1 spielte Video- und Web-Hintergrundbilder ab, unterstützte mehrere Displays und Desktops, Wiedergabelisten, ein Menü zuletzt verwendeter Hintergrundbilder, Zip- und Ordnerimport sowie einen Steam-Workshop-Browser, der über das SteamCMD aus Homebrew herunterlud. Szenen wurden mit SpriteKit aus PKG- und TEX-Dateien gezeichnet: Bildebenen mit Position, Tönung und Mischmodi, bei DXT-Texturen mit dem Vorschaubild als Ersatz. Wallpaper-Engine-Shader und -Effekte, Partikel, Sprite- und Zeitleistenanimationen, Kamera-Parallaxe, audioreaktive Skripte, 3D-Modelle, Puppets, Beleuchtung und SceneScript wurden nicht unterstützt.

### Was hinzugekommen ist

Seitdem haben 1.118 Commits Folgendes hinzugefügt:

- **Rendering:** ein neuer Metal-Szenenrenderer, der die Shader von Wallpaper Engine im Prozess übersetzt und zwischenspeichert, Effekte, Bloom und HDR.
- **Szeneninhalte:** Partikel, die auf der GPU simuliert werden; 3D-Modelle, Puppets mit Skelettanimation und Beleuchtung.
- **Verhalten:** eine SceneScript-Laufzeit, Eigenschafts-Zeitleisten, audioreaktive Visuals und räumlicher Klang.
- **Displays und Workshop:** Regeln pro Display, ein überarbeiteter Workshop-Browser und Downloads sowie weitere Importwege. Die Assets von Wallpaper Engine stammen aus deiner eigenen Steam-Kopie; nichts davon wird mitgeliefert.
- **App:** ein Einrichtungsassistent, automatische SteamCMD-Installation, Sparkle-Updates, eine Liquid-Glass-Oberfläche und 15 Sprachen.
- **Qualität:** eine Testsuite mit rund 1.900 Tests, CI, die sie mit den Assets von Wallpaper Engine ausführt, sowie signierte und notarisierte Releases.
- **Dokumentation:** eine Projektwebsite und das Wiki.

Die vollständige Liste steht unter [Funktionsumfang von 1.0.0](#funktionsumfang-von-100); Anleitungen findest du im [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Funktionsumfang von 1.0.0

### Einrichtung, Mediathek & Updates
- **Einrichtungsassistent** — beim ersten Start legen einige überspringbare Schritte die Sprache fest, zeigen die Datenschutzhinweise, richten SteamCMD, die Steam-Anmeldung und einen optionalen Steam-Web-API-Schlüssel ein, installieren die Wallpaper-Engine-Assets und holen deine Hintergrundbilder.
- **SteamCMD richtet sich selbst ein** — wird keines gefunden, lädt die App Valves SteamCMD; ein vorhandenes von Homebrew oder Steam wird verwendet.
- **Wallpaper-Engine-Assets aus deiner eigenen Steam-Kopie** — nach der Anmeldung über SteamCMD installiert, auf Wunsch mit den Standard-Hintergrundbildern von Wallpaper Engine.
- **Importe** — deine Workshop-Kollektionen und Abonnements (über Steams Web API), die Workshop-Objekte einer vorhandenen Steam-Bibliothek und Ordner mit Hintergrundbildern.
- **Das [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)** — Anleitungen, Einstellungsreferenz und Fehlerbehebung; „Support & FAQ“ in der App öffnet es.
- **Automatische Updates** — signierte Updates installieren sich selbst (beim Beenden, nach 10 Minuten Abwesenheit oder innerhalb eines Tages, danach stellt ein kurzer Neustart deine Hintergrundbilder wieder her). Unter Einstellungen › Allgemein › Updates kannst du nur suchen lassen, die Suche abschalten und Beta-Updates erhalten. „Nach Updates suchen…“ steht im App-Menü und im Menüleistenmenü.

### Szenen-Rendering
- **Die eigenen Shader von Wallpaper Engine** – Ebenen, Effekte und Materialien werden jetzt mit den Original-Shadern des jeweiligen Hintergrundbilds gezeichnet, nach Metal übersetzt, auch Effekte, die Workshop-Autoren selbst erstellt haben.
- Kompositions-, Vollbild- und Farbflächenebenen, Ebenen, die andere Ebenen abtasten, alle 33 Füllmethoden und weitere Effektmasken.
- **Originalgetreues Textlayout** – Text wird wie in Wallpaper Engine skaliert, ausgerichtet und platziert, mit Kontur-, Weichzeichner- und Schlagschatten-Schrifteffekten.
- **Zeitleisten** – Keyframe- und Texturanimationen folgen den Regeln von Wallpaper Engine für einmalige, wiederholte und gespiegelte Wiedergabe.
- Farb-Lookup-Tabellen, die Farbkorrektur von Wallpaper Engine sowie die Bildfilter- und Farboptionen in den Eigenschaften eines Hintergrundbilds.
- **Puppet Warp**-Bilder, die ihren Animationen folgen, mit Knochenphysik (Federn, Schwerkraft, Grenzen) und an ihren Knochen befestigten Objekten.

### 3D & Beleuchtung
- **3D-Modelle** mit Skinning, Animationsebenen, Morph-Targets und Root Motion.
- Perspektivische Szenenkameras mit Kamerapfaden, Überblendungen und Wackeln; 2D-Ebenen liegen in der Tiefe.
- **Szenenlichter** mit Lichtmasken (Cookies), Schatten, planaren Reflexionen, Entfernungs- und Höhennebel sowie volumetrischen Lichtern.
- **HDR** – HDR-Szenen werden mit dem HDR-Bloom von Wallpaper Engine gerendert, und die Qualität „Ultra (Display-HDR)“ gibt auf Displays, die es darstellen können, EDR aus.

### Partikel
- **GPU-Partikel** – jedes Partikelsystem wird auf der GPU simuliert, in 3D und mit 3D-Kontrollpunkten.
- Untergeordnete Systeme, auch solche, die von den Partikeln ihres übergeordneten Systems ausgelöst werden; Emitter-Stöße, Verzögerungen und periodische Emission; Emission aus dem Bild einer Ebene.
- Kollision, auch mit den Knochen eines Modells, Audioreaktion und Rotation um jede Achse.
- Partikeleinstellungen, die an die Benutzereigenschaften eines Hintergrundbilds gebunden sind.

### SceneScript & Medien
- Eine vollständige **SceneScript-Laufzeitumgebung** – Module, das Objektmodell für Szene/Ebene/Effekt/Material, Animationsereignisse, `localStorage` und Treffertests für den Cursor, wobei die Skripte jedes Hintergrundbilds in einem eigenen Thread laufen.
- Skripte können Ebenen, Partikelsysteme und Sounds erstellen, den Nebel bewegen, Bloom steuern und Puppets und Modelle posieren.
- **Jetzt läuft** – Szenen- und Web-Hintergrundbilder erhalten den aktuellen Titel und den Wiedergabestatus (macOS 15.4 oder neuer).
- Web-Hintergrundbilder erhalten ihre Benutzereigenschaften und Live-Audio.

### Audio
- Das Audiospektrum wird so berechnet, wie Wallpaper Engine es berechnet, in Stereo.
- **Sound-Ebenen** werden im Takt der Szenenuhr abgespielt, mit **räumlichem Klang**, der wie in Wallpaper Engine platziert wird.

### Displays & Wiedergabe
- **Pro Display pausieren** oder **Alle pausieren**, wobei die Wiedergaberegeln für jedes Display geprüft werden, einschließlich der Regel von Wallpaper Engine für maximierte Fenster.
- Benutzereigenschaften pro Display, mit „Eigenschaften über Displays synchronisieren“.
- Ein Hintergrundbild, das auf mehreren Displays angezeigt wird, wird einmal gerendert und auf jedem dargestellt.
- Neue Qualitätseinstellungen: Renderauflösung, Texturauflösung, Szenendetail „Wie Display“, Reflexionen, Schatten und Volumetrie.
- **Sicherer Neustart** – ein Hintergrundbild, das die App blockiert oder zum Absturz gebracht hat, wird beim nächsten Start übersprungen und in der Mediathek markiert.

### Workshop & Mediathek
- Die Workshop-Filter von Wallpaper Engine: „Nur anzeigen“, ein Auflösungsfilter, mit UND/ODER kombinierte Genres und Tags auf jeder Karte.
- Installierte Hintergrundbilder zeigen ihre Workshop-Tags und lassen sich danach filtern; reine Asset- und Abhängigkeitselemente erscheinen nicht unter „Installiert“.
- Fehlende Workshop-Abhängigkeiten werden automatisch geladen, und nicht mehr benötigte werden nach dem Löschen entfernt. Jeder Download landet im Ordner „Hintergrundbild-Speicher“.
- **Zurücksetzen** unter „Details“ setzt die Eigenschaften eines Hintergrundbilds und seine Änderungen im Szeneninspektor auf die Standardwerte seines Autors zurück.
- Bedingungen für Eigenschaften, Textzeilen und Schiebereglerformate aus den Einstellungen des Hintergrundbilds werden berücksichtigt.
- Steam-Passwörter werden nie gespeichert, und der Steam-Web-API-Schlüssel liegt im Schlüsselbund.

### Oberfläche & Sprachen
- **Liquid Glass** unter macOS 26 – eine native geteilte Ansicht mit Symbolleiste, Inspektor und Glas-Bedienelementen. Ältere macOS-Versionen behalten das gewohnte Aussehen.
- **15 neue Sprachen**: Deutsch, Französisch, Spanisch, brasilianisches Portugiesisch, Italienisch, Japanisch, Koreanisch, vereinfachtes und traditionelles Chinesisch, Russisch, Polnisch, Türkisch, Ukrainisch, Arabisch und Hindi, auswählbar über die Sprachauswahl in den Einstellungen.
- Ein neues App-Symbol und ein Menüleistensymbol, das sich dem Erscheinungsbild der Menüleiste anpasst.

<details>
<summary>Bisher in 0.8.1</summary>

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

</details>

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
- **steamcmd-Integration** – Lädt Valves SteamCMD beim ersten Bedarf automatisch (nicht mitgeliefert); ein vorhandenes steamcmd (Homebrew, Steam oder eigener Pfad) wird verwendet, falls gefunden
- **Steam-Anmeldung** – Unterstützt die Authentifizierung per Passwort, Steam Guard und zwischengespeicherter Sitzung
- **Download mit Fortschritt** – Statusaktualisierungen in Echtzeit während des Downloads (Authentifizierung, Download in %, Überprüfung, Kopieren)
- **Sichere Standardwerte** – Die Altersfreigabe ist standardmäßig auf „Jeder“ gesetzt, um nicht jugendfreie Inhalte herauszufiltern

### Zip-Import
Importieren Sie Hintergrundbildpakete direkt aus `.zip`-Dateien – ohne sie vorher manuell zu entpacken. Funktioniert über Ablage > Importieren und per Drag & Drop.

### Mehrfachauswahl & Abbestellen im Stapel
Klicken Sie mit gedrückter Befehlstaste (Cmd), um mehrere Hintergrundbilder auszuwählen, und klicken Sie dann mit der rechten Maustaste, um sie gesammelt abzubestellen.

### Isolierter Hintergrundbild-Speicher
Hintergrundbilder werden jetzt in `~/Documents/Open Wallpaper Engine/` statt direkt im Ordner „Dokumente“ gespeichert. Dadurch werden „error“-Hintergrundbilder vermieden, wenn das Repository auf einem neuen Rechner geklont wird.

</details>

<details>
<summary>Frühe Änderungen gegenüber dem ursprünglichen Projekt</summary>

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
- **SceneScript-Platzhalter** – `effect.executeMaterialFunction()`, `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `getVideoTexture()`, `engine.openUserShortcut()` tun noch nichts.
- **SceneScript-Parität** – Nicht jeder proprietäre Ereignisname, jeder Eingabe-Callback, jeder Sonderfall im Lebenszyklus und jede exakte Timing-Semantik wird nachgebildet.
- **Seltene Partikelfunktionen** – Emitterformen außer Kugel, Box und Ebenenbild sowie weitere Renderer nach dem ersten eines Systems werden nicht unterstützt.
- **Wallpaper-Engine-Assets erforderlich** – Szenen brauchen die Assets aus deiner eigenen Wallpaper-Engine-Kopie (Einstellungen → Assets); ohne sie laufen nur Video- und Web-Hintergrundbilder.
- **WebM-Videos** – WebM (VP8/VP9) läuft über WebKit, daher wirken Musiksynchronisations-Effekte darauf nicht.
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
| Szene – erweiterte Partikel | Teilweise (siehe Einschränkungen) |
| Szene – Effekte von Wallpaper Engine und aus dem Workshop (WEs eigene Shader) | Funktioniert |
| Szene – SceneScript | Teilweise (siehe Einschränkungen) |
| Szene – 3D-Modelle / Rigging / Puppet Warp | Funktioniert |
| Anwendung | Nicht unterstützt |

## Voraussetzungen

### Erforderlich
- **macOS 14.0 oder neuer** (Sonoma). Sowohl die Audioaufnahme über ScreenCaptureKit als auch das Rendern von Szenen mit Metal setzen dies voraus.

### Optional – für bestimmte Funktionen erforderlich

| Funktion | Voraussetzung | Installation |
|---------|-------------|---------|
| Durchsuchen / Laden aus dem Steam Workshop | `steamcmd` | Automatisch (optional: `brew install steamcmd`) |
| Audio-Visualisierungen & audioreaktives SceneScript | Berechtigung „Aufnahme von Bildschirm & Systemaudio“ | Einstellungen → Berechtigungen |

#### Shader

Wallpaper Engine liefert seine Effekte als GLSL aus. Sie werden von glslang und SPIRV-Cross, die in die App integriert sind (`Vendor/ShaderToolchain`), beim ersten Verwenden durch ein Hintergrundbild nach Metal übersetzt (GLSL → SPIR-V → MSL) und anschließend auf dem Datenträger zwischengespeichert. Es muss nichts installiert werden. Ein Shader, dessen Übersetzung die App hängen ließ oder zweimal zum Absturz brachte, wird bei späteren Starts übersprungen; alle anderen Shader werden weiterhin übersetzt.

#### Wallpaper-Engine-Assets

Szenen verwenden die gemeinsamen Effekte, Materialien, Shader, Schriften und die SceneScript-Laufzeitumgebung aus deiner eigenen Wallpaper-Engine-Kopie auf Steam; die App liefert sie nicht mit. Installiere sie unter *Einstellungen → Assets*: Die App lädt deine Kopie mit steamcmd (der Account muss Wallpaper Engine besitzen), behält nur die Assets und die Standard-Hintergrundbilder und löscht den Rest. Du kannst auch einen vorhandenen Wallpaper-Engine-Ordner auswählen. Video- und Web-Hintergrundbilder funktionieren ohne sie.

## Aus dem Quellcode erstellen

### Voraussetzungen
- macOS >= 14.0
- Xcode >= 26.3 (macOS 26 SDK)
- Xcode Command Line Tools

### Schritte
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

Ändern Sie in Xcode das Signaturzertifikat in Ihr eigenes oder wählen Sie „Sign to Run Locally“ und drücken Sie dann `Cmd + R`, um die App zu erstellen und auszuführen.

Beim ersten Build aus dem Quellcode wird das Swift-Paket Sparkle geladen. Aus dem Quellcode gebaute Versionen suchen nicht nach Updates.

## Verwendung

### Aus dem Steam Workshop durchsuchen & laden

1. Keine Installation nötig: Die App lädt Valves SteamCMD beim ersten Bedarf im Hintergrund (von Valve, nicht mitgeliefert). Homebrew (`brew install steamcmd`) ist optional; ein vorhandenes steamcmd (Homebrew, Steam oder ein selbst gewähltes) wird verwendet, falls gefunden
2. Wechseln Sie zum Tab **Workshop** und melden Sie sich mit Ihrem Steam-Account an (Sie müssen Wallpaper Engine besitzen)
3. Geben Sie einen [Steam-Web-API-Schlüssel](https://steamcommunity.com/dev/apikey) ein, wenn Sie dazu aufgefordert werden, oder unter *Einstellungen → Allgemein*. Er wird bei Steam überprüft und in Ihrem Schlüsselbund gespeichert; Ihr Steam-Passwort wird nie gespeichert (steamcmd verwendet seine eigene zwischengespeicherte Sitzung erneut)
4. Suchen und filtern Sie und klicken Sie bei einem beliebigen Hintergrundbild auf **Laden**

### Aus lokalen Dateien importieren

- **Ordner:** Ablage > Importieren > Hintergrundbild aus Ordner – wählen Sie Hintergrundbildordner aus, die `project.json` enthalten
- **Zip:** Ablage > Importieren oder ziehen Sie eine `.zip`-Datei mit Hintergrundbildpaketen per Drag & Drop in die App
- **Manuell:** Kopieren Sie Hintergrundbildordner direkt nach `~/Documents/Open Wallpaper Engine/`

## Datenschutz

Alles, was Open Wallpaper Engine speichert, bleibt auf deinem Mac: deine Einstellungen, Mediathek, der Cache und die Anmeldung von SteamCMD. Open Wallpaper Engine hat keinen Server und sammelt keine Daten oder Analysen. Es kontaktiert Valve (Steam, wenn du den Workshop verwendest oder Assets installierst, und Valves Server, um SteamCMD zu laden) und GitHub, um nach App-Updates zu suchen (den Appcast auf GitHub Pages) und sie von GitHub Releases zu laden, ohne persönliche Daten zu senden. Die Update-Suche lässt sich unter Einstellungen › Allgemein abschalten. Web-Hintergrundbilder können eigene Online-Inhalte laden. Dein Steam-Passwort und dein Steam-Guard-Code gehen direkt an SteamCMD und werden nie gespeichert, protokolliert oder anderswohin gesendet; nur dein Accountname wird gemerkt, um die gespeicherte Anmeldung von SteamCMD wiederzuverwenden.

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
- `Scripts/fill-assets-cache.sh` – Hilfsskript für die Entwicklung: kopiert die Assets einer Wallpaper-Engine-Installation in einen lokalen Ordner oder den Cache im Hintergrundbild-Speicher
- `Scripts/scene-api-coverage.py` – zeigt an, welche SceneScript-APIs installierte Hintergrundbilder verwenden und welche implementiert sind
