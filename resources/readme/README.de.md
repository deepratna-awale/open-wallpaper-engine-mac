Open Wallpaper Engine
=========

[English](../../README.md) | **Deutsch** | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine ist ein kostenloser Open-Source-Player für macOS, der Wallpaper-Engine-Hintergrundbilder abspielt: Szenen, Videos und Web. Er bringt einen nativen Metal-Renderer mit und unterstützt Effekte, Partikel, 3D-Modelle, Beleuchtung, SceneScript, audioreaktive Visuals und den Steam Workshop. Das Projekt begann als Fork von [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) von Haren Chen und MrWindDog und wurde seitdem weitgehend neu geschrieben.

> **Hinweis:** Dieses Projekt steht in KEINER Verbindung zum kommerziellen Wallpaper Engine auf Steam. Es handelt sich um eine Open-Source-App für macOS, die Hintergrundbild-Assets aus dem Steam Workshop von Wallpaper Engine anzeigen kann. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Website:** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Wiki:** [Anleitungen und Fehlerbehebung](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![Die Mediathek](../../docs/images/library.png)

## Highlights

- **Szenen-, Video- und Web-Hintergrundbilder** – Szenen werden mit den eigenen Wallpaper-Engine-Shadern des jeweiligen Hintergrundbilds gezeichnet, nach Metal übersetzt, mit Effekten, Partikeln, 3D-Modellen, Lichtern, Zeitleisten, SceneScript und audioreaktiven Visuals. Web-Hintergrundbilder laufen in WebKit oder in der optionalen Chromium-Engine.
- **Steam Workshop** – Hintergrundbilder direkt in der App im Workshop durchsuchen, filtern und laden oder Hintergrundbildordner und Zip-Dateien importieren.
- **Szene bearbeiten/exportieren** – Ebenen und Effekte des laufenden Hintergrundbilds live auf dem Schreibtisch ändern, daraus einen eigenen Bildschirmschoner aufnehmen oder es als Live-Photo-Sperrbildschirm für iPhone und iPad oder als Paket für die Android-App von Wallpaper Engine exportieren.

  ![Szene bearbeiten/exportieren](../../docs/images/scene-editor-live.png)

- **Hintergrundbild-Editor** – ein Editor nach dem Vorbild von Wallpaper Engine: Ebenen, Effekte mit Vorschauen, eine Zeitleiste, SceneScript, Benutzereigenschaften, Partikel und Puppet Warp. Deine Änderungen werden neben dem Hintergrundbild gespeichert, nie in seinen Dateien.

  ![Hintergrundbild-Editor](../../docs/images/wallpaper-editor.png)

- **Displays** – ein Hintergrundbild pro Display, eines über alle gestreckt oder auf jedes geklont, Gruppen, Teilungen und Profile, wie in Wallpaper Engine.

  ![Displays](../../docs/images/displays.png)

- **Playlists** – Hintergrundbilder per Timer, bei der Anmeldung, nach Tageszeit oder Wochentag wechseln, mit den Übergängen von Wallpaper Engine.

  ![Playlist-Einstellungen](../../docs/images/playlists.png)

- **Export** – Live-Photo-Sperrbildschirme für iPhone und iPad sowie Android-Pakete von Wallpaper Engine, per QR-Code über WLAN aufs Telefon gesendet.

  ![Über WLAN senden](../../docs/images/send-over-wifi.png)

- **Theming** – Menüleiste, Akzentfarbe und eingefärbte Ordner übernehmen die Farben des Hintergrundbilds.

  ![Theming](../../docs/images/theming.png)

- **Plug-in MCP-Server** – MCP-Clients können Hintergrundbilder, Playlists und Einstellungen festlegen und Szenen bearbeiten, über eine lokale Verbindung, die nur dein Benutzeraccount öffnen kann.

  ![Plug-in MCP-Server](../../docs/images/mcp-plugin.png)

Alles Weitere, Bereich für Bereich: [docs/features.md](../../docs/features.md).

## Installation

1. Lade die neueste Version von [openwallpaperengine.app](https://openwallpaperengine.app/) oder von [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases). Sie ist signiert und notarisiert und aktualisiert sich selbst.
2. Öffne das DMG und ziehe **Open Wallpaper Engine** in den Ordner „Programme“.

Du brauchst **macOS 14.0 (Sonoma) oder neuer**. Manche Funktionen setzen eine neuere macOS-Version, eine Berechtigung oder ein Plug-in voraus: siehe [Erste Schritte](../../docs/getting-started.md#requirements).

## Schnellstart

1. Öffne die App. Der Einrichtungsassistent legt die Sprache, SteamCMD, deine Steam-Anmeldung und die Wallpaper-Engine-Assets fest; jeder Schritt lässt sich überspringen.
2. Installiere die Wallpaper-Engine-Assets (*Einstellungen › Assets*), wenn du Szenen-Hintergrundbilder nutzen möchtest. Sie stammen aus deiner eigenen Wallpaper-Engine-Kopie auf Steam; Video- und Web-Hintergrundbilder funktionieren ohne sie.
3. Finde Hintergrundbilder im Tab **Workshop** oder importiere einen Hintergrundbildordner oder eine Zip-Datei (*Ablage › Hintergrundbild aus Ordner importieren …*, ⌘I).
4. Klicke in der Mediathek auf ein Hintergrundbild und dann in seinen Details auf **Hintergrundbild festlegen**. Seine Eigenschaften stehen darunter.

Mehr dazu: [Erste Schritte](../../docs/getting-started.md) und das [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Datenschutz

Alles, was die App speichert, bleibt auf deinem Mac, und sie sammelt keine Daten oder Analysen. Sie kontaktiert Steam (für den Workshop und die Assets) und GitHub (für Updates), und Plug-ins werden erst geladen, wenn du sie installierst. Details: [womit sich die App verbindet](../../docs/getting-started.md#what-the-app-connects-to) und die [Datenschutzrichtlinie](../../docs/legal/privacy-policy.md).

## Dokumentation

- [Erste Schritte](../../docs/getting-started.md) – Voraussetzungen, Assets, der Workshop und Importieren
- [Funktionen](../../docs/features.md) – alles, was die App unterstützt, und wie man es benutzt
- Anleitungen: [Display-Layouts](../../docs/display-layouts.md) · [Playlists](../../docs/playlists.md) · [Bildschirmschoner](../../docs/screen-saver.md) · [Export für iPhone & iPad](../../docs/iphone-ipad-export.md) · [Export für Android](../../docs/android-export.md) · [Tiefenkarten](../../docs/depth-maps.md) · [Theming](../../docs/theming.md) · [MCP-Server](../../docs/mcp.md) · [Chromium-Web-Engine](../../docs/chromium-engine.md)
- [Entwicklung](../../docs/development.md) – aus dem Quellcode erstellen und die Projektstruktur; [CONTRIBUTING.md](../../CONTRIBUTING.md) und [Architektur](../../docs/architecture.md)
- [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) – Anleitungen, Einstellungsreferenz und Fehlerbehebung

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

## Rechtliches

[Nutzungsbedingungen](../../docs/legal/terms-of-use.md) · [Datenschutzrichtlinie](../../docs/legal/privacy-policy.md) · [Sicherheitsrichtlinie](../../SECURITY.md)

- **English:** Please read the Terms of Use and the Privacy Policy.
- **Deutsch:** Bitte lesen Sie die Nutzungsbedingungen und die Datenschutzrichtlinie.
- **Français :** Veuillez lire les conditions d’utilisation et la politique de confidentialité.
- **Español:** Lee las condiciones de uso y la política de privacidad.
- **Português (Brasil):** Leia os Termos de Uso e a Política de Privacidade.
- **Italiano:** Leggi le condizioni d’uso e l’informativa sulla privacy.
- **日本語：** 利用規約とプライバシーポリシーをお読みください。
- **한국어:** 이용 약관과 개인정보 처리방침을 읽어 주십시오.
- **简体中文：** 请阅读使用条款和隐私政策。
- **繁體中文：** 請閱讀使用條款和隱私權政策。
- **Русский:** Прочитайте условия использования и политику конфиденциальности.
- **Polski:** Przeczytaj warunki korzystania i politykę prywatności.
- **Türkçe:** Lütfen Kullanım Koşulları’nı ve Gizlilik Politikası’nı okuyun.
- **Українська:** Прочитайте умови використання та політику приватності.
- **العربية:** يُرجى قراءة شروط الاستخدام وسياسة الخصوصية.
- **हिन्दी:** कृपया उपयोग की शर्तें और गोपनीयता नीति पढ़ें।
