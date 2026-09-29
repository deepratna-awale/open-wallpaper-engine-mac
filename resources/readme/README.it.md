Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | **Italiano** | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine è un player gratuito e open source per macOS che riproduce gli sfondi di Wallpaper Engine: scena, video e web. Ha un renderer Metal nativo e supporta effetti, particelle, modelli 3D, illuminazione, SceneScript, elementi visivi reattivi all’audio e lo Steam Workshop. È nato come fork di [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) di Haren Chen e MrWindDog ed è stato poi in gran parte riscritto.

> **Nota:** questo progetto NON è affiliato al Wallpaper Engine commerciale venduto su Steam. È un’app open source per macOS in grado di mostrare le risorse degli sfondi dello Steam Workshop di Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** guide e documentazione sono nella [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Requisiti

### Obbligatori
- **macOS 14.0 o versioni successive** (Sonoma). Sia l’acquisizione audio con ScreenCaptureKit sia il rendering delle scene con Metal dipendono da questa versione.

### Facoltativi: necessari per funzionalità specifiche

| Funzionalità | Requisito | Installazione |
|---------|-------------|---------|
| Sfogliare / scaricare dallo Steam Workshop | `steamcmd` | Automatico (facoltativo: `brew install steamcmd`) |
| Visualizzatori audio e SceneScript reattivo all’audio | Autorizzazione Registrazione schermo e audio di sistema | Impostazioni → Autorizzazioni |

#### Shader

Wallpaper Engine distribuisce i propri effetti in GLSL. Vengono tradotti in Metal (GLSL → SPIR-V → MSL) da glslang e SPIRV-Cross, integrati nell’app (`Vendor/ShaderToolchain`), la prima volta che uno sfondo li usa, e poi memorizzati nella cache su disco. Non è necessario installare nulla. Uno shader la cui traduzione ha bloccato l’app, o l’ha fatta chiudere inaspettatamente due volte, viene ignorato agli avvii successivi, mentre tutti gli altri shader continuano a essere tradotti.

#### Risorse di Wallpaper Engine

Le scene usano gli effetti, i materiali, gli shader, i font e il runtime di SceneScript condivisi della tua copia di Wallpaper Engine su Steam; l’app non li include. Installali in *Impostazioni → Risorse*: l’app scarica la tua copia con steamcmd (l’account deve possedere Wallpaper Engine), conserva solo le risorse e gli sfondi predefiniti ed elimina il resto. Puoi anche scegliere una cartella di Wallpaper Engine esistente. Gli sfondi video e web funzionano senza.

## Compilare dal codice sorgente

### Prerequisiti
- macOS >= 14.0
- Xcode >= 26.3 (SDK di macOS 26)
- Strumenti da riga di comando di Xcode

### Passaggi
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

In Xcode, sostituisci il certificato di firma con il tuo oppure seleziona "Sign to Run Locally", quindi premi `Cmd + R` per compilare ed eseguire.

La prima compilazione dal codice sorgente scarica il pacchetto Swift Sparkle. Le build compilate dal sorgente non cercano aggiornamenti.

## Utilizzo

### Sfogliare e scaricare dallo Steam Workshop

1. Non serve installare nulla: l’app scarica SteamCMD di Valve in background la prima volta che serve (da Valve, non incluso). Homebrew (`brew install steamcmd`) è facoltativo; se trova uno steamcmd esistente (Homebrew, Steam o uno scelto da te), usa quello
2. Passa al pannello **Workshop** e accedi con il tuo account Steam (devi possedere Wallpaper Engine)
3. Inserisci una [Chiave Steam Web API](https://steamcommunity.com/dev/apikey) quando richiesto, oppure in *Impostazioni → Generali*. Viene verificata con Steam e conservata nel tuo portachiavi; la tua password di Steam non viene mai memorizzata (steamcmd riutilizza la propria sessione salvata)
4. Cerca, filtra e fai clic su **Scarica** su qualsiasi sfondo

### Importare da file locali

- **Cartella:** File > Importa > Sfondo da cartella: seleziona le cartelle degli sfondi che contengono `project.json`
- **Zip:** File > Importa oppure trascina un file `.zip` che contiene pacchetti di sfondi
- **Manuale:** copia le cartelle degli sfondi direttamente in `~/Documents/Open Wallpaper Engine/`

## Cosa supporta la versione 1.0.0

### Configurazione, libreria e aggiornamenti
- **Assistente di configurazione**: al primo avvio, pochi passaggi facoltativi scelgono la lingua, mostrano le note sulla privacy, configurano SteamCMD, il login di Steam e una chiave Steam Web API facoltativa, installano gli asset di Wallpaper Engine e importano i tuoi sfondi.
- **SteamCMD si configura da solo**: se non ne trova uno, l’app scarica SteamCMD di Valve; se c’è quello di Homebrew o di Steam, usa quello.
- **Asset di Wallpaper Engine dalla tua copia Steam**: installati tramite SteamCMD dopo il login, facoltativamente con gli sfondi predefiniti di Wallpaper Engine.
- **Importazioni**: le tue raccolte e iscrizioni del Workshop (dalla Web API di Steam), gli elementi del Workshop di una libreria Steam esistente e cartelle di sfondi.
- **La [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)**: guide, riferimento delle impostazioni e risoluzione dei problemi; «Supporto e FAQ» nell’app la apre.
- **Aggiornamenti automatici**: gli aggiornamenti firmati si installano da soli (all’uscita, dopo 10 minuti di assenza o entro un giorno, poi un rapido riavvio ripristina gli sfondi). In Impostazioni › Generali › Aggiornamenti puoi solo cercarli, disattivare la ricerca e ricevere le beta. «Cerca aggiornamenti…» è nel menu dell’app e nel menu della barra dei menu.

### Rendering delle scene
- **Gli shader originali di Wallpaper Engine**: livelli, effetti e materiali ora vengono disegnati con gli shader originali di ogni sfondo, tradotti in Metal, compresi gli effetti creati dagli autori del Workshop.
- Livelli di composizione, a schermo intero e a tinta unita, livelli che campionano altri livelli, tutte le 33 modalità di fusione e altre maschere degli effetti.
- **Impaginazione fedele del testo**: il testo viene dimensionato, allineato e posizionato come in Wallpaper Engine, con effetti di contorno, sfocatura e ombra esterna per i font.
- **Timeline**: le animazioni con keyframe e delle texture seguono le regole di Wallpaper Engine per la riproduzione singola, in loop e a specchio.
- Tabelle di ricerca dei colori, la correzione colore di Wallpaper Engine e le opzioni di filtro immagine e colore nelle proprietà di uno sfondo.
- Immagini con **Puppet Warp** mosse dalle proprie animazioni, con fisica delle ossa (molle, gravità, limiti) e oggetti agganciati alle ossa.

### 3D e illuminazione
- **Modelli 3D** con skinning, livelli di animazione, morph target e root motion.
- Videocamere di scena in prospettiva con percorsi, dissolvenze e vibrazione; i livelli 2D si collocano in profondità.
- **Luci di scena** con cookie di luce, ombre, riflessi planari, nebbia per distanza e altezza e luci volumetriche.
- **HDR**: le scene HDR vengono renderizzate con il bloom HDR di Wallpaper Engine, e la qualità "Ultra (Display HDR)" produce EDR sugli schermi in grado di mostrarlo.

### Particelle
- **Particelle sulla GPU**: ogni sistema di particelle è simulato sulla GPU, in 3D, con punti di controllo 3D.
- Sistemi figli, compresi quelli attivati dalle particelle del sistema padre; raffiche di emissione, ritardi ed emissione periodica; emissione dall’immagine di un livello.
- Collisioni, anche con le ossa di un modello, risposta all’audio e rotazione su tutti gli assi.
- Impostazioni delle particelle collegate alle proprietà utente di uno sfondo.

### SceneScript e contenuti multimediali
- Un **runtime di SceneScript** completo: moduli, il modello a oggetti scena/livello/effetto/materiale, eventi di animazione, `localStorage` e rilevamento del cursore, con gli script di ogni sfondo in un thread dedicato.
- Gli script possono creare livelli, sistemi di particelle e suoni, spostare la nebbia, controllare il bloom e mettere in posa marionette e modelli.
- **In riproduzione**: gli sfondi di tipo scena e web ricevono il brano corrente e lo stato di riproduzione (macOS 15.4 o versioni successive).
- Gli sfondi web ricevono le proprie proprietà utente e l’audio in tempo reale.

### Audio
- Lo spettro audio viene calcolato come lo calcola Wallpaper Engine, in stereo.
- I **livelli audio** vengono riprodotti sull’orologio della scena, con **audio spaziale** posizionato come in Wallpaper Engine.

### Schermi e riproduzione
- **Pausa per schermo** o **Pausa su tutti**, con le regole di riproduzione valutate per ogni schermo, compresa la regola di Wallpaper Engine per le finestre ingrandite.
- Proprietà utente per schermo, con "Sincronizza le proprietà tra gli schermi".
- Uno sfondo mostrato su più schermi viene renderizzato una sola volta e presentato su ciascuno.
- Nuove impostazioni di qualità: Risoluzione di rendering, Risoluzione texture, dettaglio della scena adattato allo schermo, riflessi, ombre ed effetti volumetrici.
- **Riavvio sicuro**: uno sfondo che ha bloccato o fatto chiudere inaspettatamente l’app viene saltato all’avvio successivo e segnalato nella libreria.

### Workshop e libreria
- I filtri del Workshop di Wallpaper Engine: Mostra solo, un filtro per risoluzione, generi combinati con E/O e tag su ogni scheda.
- Gli sfondi installati mostrano i propri tag del Workshop e si possono filtrare in base a essi; gli elementi che sono solo risorse o dipendenze restano fuori da Installati.
- Le dipendenze del Workshop mancanti vengono scaricate automaticamente e quelle non più usate vengono rimosse dopo un’eliminazione. Ogni download finisce nella cartella Archivio sfondi.
- **Ripristina** in Dettagli riporta le proprietà di uno sfondo, e le sue modifiche nell’Inspector scena, ai valori predefiniti scelti dall’autore.
- Le condizioni delle proprietà, le righe di testo e i formati dei cursori definiti nelle impostazioni dello sfondo vengono rispettati.
- Le password di Steam non vengono mai memorizzate e la chiave dell’API Web di Steam è conservata nel portachiavi.

### Interfaccia e lingue
- **Liquid Glass** su macOS 26: una vista divisa nativa con barra degli strumenti, Inspector e controlli in vetro. Le versioni precedenti di macOS mantengono l’aspetto consueto.
- **15 nuove lingue**: tedesco, francese, spagnolo, portoghese brasiliano, italiano, giapponese, coreano, cinese semplificato e tradizionale, russo, polacco, turco, ucraino, arabo e hindi, da scegliere nel selettore della lingua delle impostazioni.
- Una nuova icona dell’app e un’icona della barra dei menu che segue l’aspetto della barra dei menu.

## Limitazioni attuali

- **Funzioni SceneScript non implementate**: `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()` non fanno ancora nulla.
- **Parità di SceneScript**: non vengono riprodotti tutti i nomi di eventi proprietari, i callback di input, i casi limite del ciclo di vita o l’esatta semantica delle tempistiche.
- **Funzioni particellari rare**: le forme di emettitore diverse da sfera, box e immagine del livello e i renderer successivi al primo di un sistema non sono supportati.
- **Risorse di Wallpaper Engine necessarie**: le scene richiedono le risorse della tua copia di Wallpaper Engine (Impostazioni → Risorse); senza di esse funzionano solo gli sfondi video e web.
- **Video WebM**: i WebM (VP8/VP9) vengono riprodotti tramite WebKit, quindi gli effetti di sincronizzazione musicale non si applicano.
- **Alcune miniature JPEG**: un piccolo numero di file TEXB di formato 1 contiene dati JPEG non standard che macOS non riesce a decodificare.
- **Ambito delle impostazioni delle prestazioni**: le opzioni di qualità, anti-aliasing e post-elaborazione sono pensate per gli sfondi di tipo scena e hanno un effetto limitato sugli sfondi video e web.
- **Le funzionalità audio richiedono un’autorizzazione**: senza l’autorizzazione Registrazione schermo e audio di sistema, i visualizzatori audio e SceneScript reattivo all’audio ricevono solo silenzio.
- **Non confrontato fianco a fianco con Wallpaper Engine** – Wallpaper Engine non funziona su macOS, quindi il comportamento segue i file e gli shader di Wallpaper Engine; alcuni casi limite (timeline, illuminazione, uscita HDR) non sono confermati.

## Tipi di sfondo supportati

| Tipo | Stato |
|------|--------|
| Video (.mp4, .webm) | Funzionante |
| Web (HTML/WebGL) | Funzionante |
| Scena: livelli di immagine e timeline | Funzionante (Metal) |
| Scena: texture DXT1/DXT3/DXT5 | Funzionante (decodifica GPU con Metal) |
| Scena: sprite TEXS / timeline alfa | Funzionante |
| Scena: particelle sprite | Funzionante |
| Scena: particelle avanzate | Parziale (vedi Limitazioni) |
| Scena: effetti di Wallpaper Engine e del Workshop (gli shader di WE) | Funzionante |
| Scena: SceneScript | Parziale (vedi Limitazioni) |
| Scena: modelli 3D / rigging / puppet warp | Funzionante |
| Applicazione | Non supportato |

## Privacy

Tutto ciò che Open Wallpaper Engine salva resta sul tuo Mac: impostazioni, libreria, cache e login di SteamCMD. Open Wallpaper Engine non ha un server e non raccoglie dati né statistiche. Contatta Valve (Steam quando usi il Workshop o installi gli asset, e il server di Valve per scaricare SteamCMD) e GitHub, per cercare gli aggiornamenti dell’app (l’appcast su GitHub Pages) e scaricarli da GitHub Releases, senza inviare dati personali. La ricerca degli aggiornamenti si può disattivare in Impostazioni › Generali. Gli sfondi web possono caricare propri contenuti online. La password di Steam e il codice Steam Guard vanno direttamente a SteamCMD e non vengono mai salvati, registrati o inviati altrove; viene ricordato solo il nome dell’account, per riutilizzare il login salvato di SteamCMD.

## Struttura del progetto

- `OpenWallpaperEngine/Scene/Format/`: parser e modelli per PKG, TEX/TEXS e scene.json
- `OpenWallpaperEngine/Scene/Shaders/`: traduzione GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), caching e archivio delle pipeline
- `Vendor/ShaderToolchain/`: sorgenti di glslang e SPIRV-Cross, integrati nell’app come pacchetto locale
- `OpenWallpaperEngine/Scene/Scripting/`: runtime di SceneScript e binding audio/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift`: acquisizione dell’audio di sistema con ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal`: il renderer di scene Metal e la libreria degli shader
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift`: navigazione e download dello Steam Workshop
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift`: archiviazione della libreria, importazione e conversione dei pacchetti
- `Scripts/fill-assets-cache.sh`: strumento di sviluppo che copia le risorse di un’installazione di Wallpaper Engine in una cartella locale o nella cache dell’archivio sfondi
- `Scripts/scene-api-coverage.py`: indica quali API di SceneScript usano gli sfondi installati rispetto a quelle implementate

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
