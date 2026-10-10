Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | **Italiano** | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine è un player gratuito e open source per macOS che riproduce gli sfondi di Wallpaper Engine: scena, video e web. Ha un renderer Metal nativo e supporta effetti, particelle, modelli 3D, illuminazione, SceneScript, elementi visivi reattivi all’audio e lo Steam Workshop. È nato come fork di [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) di Haren Chen e MrWindDog ed è stato poi in gran parte riscritto.

> **Nota:** questo progetto NON è affiliato al Wallpaper Engine commerciale venduto su Steam. È un’app open source per macOS in grado di mostrare le risorse degli sfondi dello Steam Workshop di Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Sito web:** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Wiki:** [guide e risoluzione dei problemi](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![La libreria](../../docs/images/library.png)

## In evidenza

- **Sfondi scena, video e web** — le scene vengono disegnate con gli shader di Wallpaper Engine propri di ciascuno sfondo, tradotti in Metal, con effetti, particelle, modelli 3D, luci, timeline, SceneScript ed elementi visivi reattivi all’audio. Gli sfondi web girano in WebKit o nel motore Chromium opzionale.
- **Steam Workshop** — sfoglia, filtra e scarica dal Workshop direttamente nell’app, oppure importa cartelle e file zip di sfondi.
- **Modifica/esporta scena** — modifica dal vivo sulla scrivania i livelli e gli effetti dello sfondo in esecuzione, rendilo il tuo salvaschermo o esportalo (scene e video) come schermata di blocco Live Photo per iPhone e iPad o come pacchetto per l’app Android di Wallpaper Engine.

  ![Modifica/esporta scena](../../docs/images/scene-editor-live.png)

- **Editor sfondi** — un editor sul modello di quello di Wallpaper Engine: livelli, effetti con anteprime, timeline, SceneScript, proprietà utente, particelle, Puppet Warp e maschere create da una mappa di profondità. Modifichi una bozza: **Salva** la applica allo sfondo, **Salva come nuovo sfondo** ne aggiunge una copia alla libreria, e i file dello sfondo stesso non vengono mai modificati.

  ![Editor sfondi](../../docs/images/wallpaper-editor.png)

- **Schermi** — uno sfondo per schermo, uno solo esteso su tutti o clonato su ciascuno, gruppi, suddivisioni e profili, come in Wallpaper Engine.

  ![Schermi](../../docs/images/displays.png)

- **Playlist** — cambia sfondo con un timer, all’accesso, in base all’ora del giorno o al giorno della settimana, con le transizioni di Wallpaper Engine.

  ![Impostazioni delle playlist](../../docs/images/playlists.png)

- **Esportazione** — schermate di blocco Live Photo per iPhone e iPad e pacchetti Android di Wallpaper Engine, inviati al telefono via Wi-Fi con un codice QR.

  ![Invia via Wi-Fi](../../docs/images/send-over-wifi.png)

- **Tema colore** — la barra dei menu, il colore di evidenziazione e le icone e le cartelle colorate seguono il colore dello sfondo; le finestre di Open Wallpaper Engine possono usare il colore esatto.

  ![Tema colore](../../docs/images/theming.png)

- **Plug-in Server MCP** — i client MCP possono impostare sfondi, playlist e impostazioni e modificare le scene tramite una connessione locale che solo il tuo account può aprire.

  ![Plug-in Server MCP](../../docs/images/mcp-plugin.png)

Tutto il resto, area per area: [docs/features.md](../../docs/features.md).

## Installazione

1. Scarica l’ultima versione da [openwallpaperengine.app](https://openwallpaperengine.app/) o da [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases). È firmata e autenticata da Apple, e si aggiorna da sola.
2. Apri il DMG e trascina **Open Wallpaper Engine** in Applicazioni.

Serve **macOS 14.0 (Sonoma) o successivo**. Alcune funzionalità richiedono una versione di macOS più recente, un permesso o un plug-in: vedi [Per iniziare](../../docs/getting-started.md#requirements).

## Avvio rapido

1. Apri l’app. L’assistente di configurazione imposta la lingua, SteamCMD, l’accesso a Steam e le risorse di Wallpaper Engine, e può importare i tuoi preferiti di Wallpaper Engine; ogni passaggio si può saltare.
2. Installa le risorse di Wallpaper Engine (*Impostazioni › Risorse*) se vuoi gli sfondi di tipo scena. Provengono dalla tua copia di Wallpaper Engine su Steam; gli sfondi video e web funzionano anche senza.
3. Trova sfondi nelle schede **Esplora** e **Workshop**, oppure importa una cartella o un file zip di uno sfondo (*File › Importa sfondo da cartella…*, ⌘I).
4. Fai clic su uno sfondo nella libreria, poi su **Imposta sfondo** nei suoi dettagli (oppure fai clic su di esso con il tasto destro e scegli **Imposta come sfondo**). Le sue proprietà sono elencate subito sotto.

Altro: [Per iniziare](../../docs/getting-started.md) e il [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Privacy

Tutto ciò che l’app salva resta sul tuo Mac, e non raccoglie dati né statistiche. Contatta Steam (per il Workshop e le risorse), openwallpaperengine.app (per cercare gli aggiornamenti) e GitHub (per scaricarli), e i plug-in vengono scaricati solo quando li installi. Dettagli: [a cosa si connette l’app](../../docs/getting-started.md#what-the-app-connects-to) e l’[informativa sulla privacy](../../docs/legal/privacy-policy.md).

## Documentazione

- [Per iniziare](../../docs/getting-started.md) — requisiti, risorse, il Workshop e l’importazione
- [Funzionalità](../../docs/features.md) — tutto ciò che l’app supporta e come usarlo
- Guide: [disposizioni degli schermi](../../docs/display-layouts.md) · [playlist](../../docs/playlists.md) · [salvaschermo](../../docs/screen-saver.md) · [esportazione per iPhone e iPad](../../docs/iphone-ipad-export.md) · [esportazione per Android](../../docs/android-export.md) · [mappe di profondità](../../docs/depth-maps.md) · [temi](../../docs/theming.md) · [Server MCP](../../docs/mcp.md) · [motore web Chromium](../../docs/chromium-engine.md)
- [Sviluppo](../../docs/development.md) — compilare dal codice sorgente e struttura del progetto; [CONTRIBUTING.md](../../CONTRIBUTING.md) e [architettura](../../docs/architecture.md)
- [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — guide, riferimento delle impostazioni e risoluzione dei problemi

## Progetti correlati

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — Un’interfaccia grafica PyQt6 per [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine), con integrazione dello Steam Workshop e design dell’interfaccia portato da questa versione per macOS.

## Riconoscimenti

Questo progetto si basa sul lavoro di:

- **[MrWindDog](https://github.com/MrWindDog)** — Manutentore del fork upstream [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac); ha aggiunto nuove funzionalità e perfezionamenti all’interfaccia
- **[Haren Chen](https://github.com/haren724)** — Creatore originale di [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac); ha realizzato l’architettura di base dell’app (SwiftUI, riproduzione degli sfondi video, sistema di importazione, interfaccia delle playlist)
- **1ris_W** — Traduzione in cinese
- **[Klaus Zhu](https://github.com/klauszhu1105)** — Design originale del logo
- **[Chen Chia Yang](https://github.com/Unayung)** — Rendering degli sfondi di tipo scena, correzioni per gli sfondi web, integrazione dello Steam Workshop, supporto per più schermi, importazione di file zip
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Renderer di scene Metal e pipeline degli effetti, traduzione e caching degli shader GLSL→MSL, runtime di SceneScript, rendering reattivo all’audio, revisione di Workshop e Download, impostazioni di posizionamento e prestazioni, riprogettazione del logo

Distribuito con licenza [GPL-3.0](../../LICENSE), come il progetto originale.

## Note legali

[Condizioni d’uso](../../docs/legal/terms-of-use.md) · [Informativa sulla privacy](../../docs/legal/privacy-policy.md) · [Politica di sicurezza](../../SECURITY.md)

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
