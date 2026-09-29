Open Wallpaper Engine
=========

[English](../../README.md) | **Deutsch** | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine ist ein kostenloser Open-Source-Player für macOS, der Wallpaper-Engine-Hintergrundbilder abspielt: Szenen, Videos und Web. Er bringt einen nativen Metal-Renderer mit und unterstützt Effekte, Partikel, 3D-Modelle, Beleuchtung, SceneScript, audioreaktive Visuals und den Steam Workshop. Das Projekt begann als Fork von [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) von Haren Chen und MrWindDog und wurde seitdem weitgehend neu geschrieben.

> **Hinweis:** Dieses Projekt steht in KEINER Verbindung zum kommerziellen Wallpaper Engine auf Steam. Es handelt sich um eine Open-Source-App für macOS, die Hintergrundbild-Assets aus dem Steam Workshop von Wallpaper Engine anzeigen kann. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** Anleitungen und Dokumentation findest du im [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Voraussetzungen

### Erforderlich
- **macOS 14.0 oder neuer** (Sonoma). Sowohl die Audioaufnahme über ScreenCaptureKit als auch das Rendern von Szenen mit Metal setzen dies voraus.

### Optional – für bestimmte Funktionen erforderlich

| Funktion | Voraussetzung | Installation |
|---------|-------------|---------|
| Durchsuchen / Laden aus dem Steam Workshop | `steamcmd` | Automatisch (optional: `brew install steamcmd`) |
| Audio-Visualisierungen & audioreaktives SceneScript | Berechtigung „Aufnahme von Systemaudio“ (vor macOS 14.2: „Aufnahme von Bildschirm & Systemaudio“) | Einstellungen → Berechtigungen |

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
cd open-wallpaper-engine-mac
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

## Aktuelle Einschränkungen

- **SceneScript-Platzhalter** – `getVideoTexture()` tut noch nichts.
- **SceneScript-Parität** – Nicht jeder proprietäre Ereignisname, jeder Eingabe-Callback, jeder Sonderfall im Lebenszyklus und jede exakte Timing-Semantik wird nachgebildet.
- **WebM-Videos** – WebM (VP8/VP9) läuft über WebKit, daher wirken Musiksynchronisations-Effekte darauf nicht.

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

## Datenschutz

Alles, was Open Wallpaper Engine speichert, bleibt auf deinem Mac: deine Einstellungen, Mediathek, der Cache und die Anmeldung von SteamCMD. Open Wallpaper Engine hat keinen Server und sammelt keine Daten oder Analysen. Es kontaktiert Valve (Steam, wenn du den Workshop verwendest oder Assets installierst, und Valves Server, um SteamCMD zu laden) und GitHub, um nach App-Updates zu suchen (den Appcast auf GitHub Pages) und sie von GitHub Releases zu laden, ohne persönliche Daten zu senden. Die Update-Suche lässt sich unter Einstellungen › Allgemein abschalten. Web-Hintergrundbilder können eigene Online-Inhalte laden. Dein Steam-Passwort und dein Steam-Guard-Code gehen direkt an SteamCMD und werden nie gespeichert, protokolliert oder anderswohin gesendet; nur dein Accountname wird gemerkt, um die gespeicherte Anmeldung von SteamCMD wiederzuverwenden.

## Projektstruktur

- `OpenWallpaperEngine/Scene/Format/` – Parser und Modelle für PKG, TEX/TEXS und scene.json
- `OpenWallpaperEngine/Scene/Shaders/` – GLSL → SPIR-V → MSL-Übersetzung (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), Caching und das Pipeline-Archiv
- `Vendor/ShaderToolchain/` – Quellcode von glslang und SPIRV-Cross, als lokales Paket in die App eingebunden
- `OpenWallpaperEngine/Scene/Scripting/` – SceneScript-Laufzeitumgebung und Audio-/FFT-Bindungen
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` – Aufnahme des Systemaudios über ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` – der Metal-Szenenrenderer und die Shader-Bibliothek
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` – Durchsuchen des Steam Workshop und Downloads
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` – Speicher der Mediathek, Import und Paketkonvertierung
- `Scripts/fill-assets-cache.sh` – Hilfsskript für die Entwicklung: kopiert die Assets einer Wallpaper-Engine-Installation in einen lokalen Ordner oder den Cache im Hintergrundbild-Speicher
- `Scripts/scene-api-coverage.py` – zeigt an, welche SceneScript-APIs installierte Hintergrundbilder verwenden und welche implementiert sind

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
