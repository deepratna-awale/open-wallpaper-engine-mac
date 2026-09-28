Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | **Italiano** | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine è un player gratuito e open source per macOS che riproduce gli sfondi di Wallpaper Engine: scena, video e web. Ha un renderer Metal nativo e supporta effetti, particelle, modelli 3D, illuminazione, SceneScript, elementi visivi reattivi all’audio e lo Steam Workshop. È nato come fork di [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) di Haren Chen e MrWindDog ed è stato poi in gran parte riscritto.

> **Nota:** questo progetto NON è affiliato al Wallpaper Engine commerciale venduto su Steam. È un’app open source per macOS in grado di mostrare le risorse degli sfondi dello Steam Workshop di Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** guide e documentazione sono nella [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

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

## Cosa supporta la versione 0.9.0

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

<details>
<summary>In precedenza nella versione 0.8.1</summary>

### Riproduzione degli sfondi
- **Sfondi di tipo scena** renderizzati in modo nativo con Metal: livelli di immagine, trasformazioni, timeline con keyframe, ordinamento per profondità e dati di videocamera/proiezione da `scene.json`.
- **Sfondi video** (`.mp4`, `.webm`) con velocità di riproduzione, volume, collegamento della velocità audio/video e, facoltativamente, zoom/inclinazione/saturazione sincronizzati con la musica.
- **Sfondi web** (HTML/WebGL) con accesso ai file locali abilitato, in modo che texture e risorse WebGL vengano caricate correttamente, oltre ai contenuti esterni incorporati (YouTube/Vimeo).
- **Modalità di posizionamento**: A schermo pieno, Adatta allo schermo, Centro, Amplia per riempire lo schermo, Zoom.
- **Più schermi**: uno sfondo diverso per ciascun monitor, attivazione/disattivazione per schermo, layout visivo dei monitor e rilevamento automatico degli schermi appena collegati.
- **Più scrivanie (Spaces)**: riproduzione continua su tutte le scrivanie, inclusa l’opzione di assegnazione `Tutte le scrivanie`.
- **Regole di riproduzione**: continua, disattiva l’audio, metti in pausa o interrompi quando un’altra app è in primo piano; comportamento corretto durante stop/riattivazione e al cambio di scrivania.

### Supporto del formato scena
- **Parser PKG** per gli archivi `PKGV` di Wallpaper Engine (scene.json, materiali, texture, shader).
- **Parser TEX** per i contenitori `TEXV0005`: JPEG/PNG incorporati e DXT1/DXT3/DXT5 con mipmap decodificati sulla GPU tramite un compute shader Metal.
- **Timeline degli sprite TEXS** (0001/0002/0003), inclusi i rettangoli dei fotogrammi in un singolo atlas e le sequenze di più immagini.
- **Decodifica flessibile di scene.json**, che gestisce i campi polimorfici di Wallpaper Engine (valori semplici oppure `{"script":…,"value":…}`).
- **Ripiego sull’anteprima**: usa `preview.jpg/png/gif` quando non è possibile estrarre le texture.

### Effetti e shader
- **~48 effetti Metal nativi** che coprono distorsione, sfocatura (standard/precisa/radiale/di movimento), bloom, raggi crepuscolari e fasci di luce, onde/increspature/caustiche/flusso dell’acqua, nuvole e nebbia, grana della pellicola, glitch/VHS, aberrazione cromatica, chiave colore, trasformazione/inclinazione/rotazione/vortice/prospettiva, riflessione, rifrazione, lucentezza/luccichio/brillantini, rilevamento dei bordi e altro ancora.
- **Effetti reattivi all’audio**: pulsazione, barre audio, variazione di tonalità sincronizzata con l’audio e hyperdrive, guidati dai dati dello spettro dell’audio di sistema in tempo reale.
- **Effetti semantici dei materiali**: luminosità, contrasto, saturazione, esposizione, gamma, tonalità, soglia del bloom, bloom e sfocatura mappati su passaggi Metal nativi.
- **Traduzione GLSL → SPIR-V → MSL** al caricamento tramite glslang e SPIRV-Cross collegati all’app, con define COMBO, risoluzione degli include e rinumerazione degli slot dei buffer Metal.
- **Cache degli shader precompilati**: i file `.metal` tradotti, i `.metallib` compilati e i file ausiliari `.reflection.json` vengono memorizzati nella cache in `.open-wallpaper-engine/shaders`, con controllo tramite hash in modo che vengano ritradotti solo gli shader modificati, e compilati in background in modo che il rendering non venga mai bloccato.
- **Catalogo dinamico degli effetti** letto dai manifest `assets/effects/*/effect.json` di Wallpaper Engine, inclusi gli effetti a più passaggi e i binding delle uniform ottenuti per reflection.
- **Mascheratura degli effetti** (fino a 4 texture maschera per livello), fusione additiva e alfa e un sistema di render target in pool.

### Particelle
- Emettitori di sprite con durata, dimensione, velocità, colore, rotazione, velocità angolare, gravità, attrito e dissolvenze alfa casuali.
- Comportamento avanzato: turbolenza, attrattori, movimento a vortice e boid, punti di controllo statici e collegati al cursore, segmenti di corda collegati e scie con dissolvenza di alfa/dimensione.
- Animazione dei fotogrammi degli spritesheet tramite sequenze `.tex-json`.
- Operatori tramite script per frequenza di emissione, attrito e tempistica della dissolvenza alfa.

### Runtime di SceneScript
- Contesti di script persistenti per livello, con `init()` chiamato una sola volta e `update(value)` chiamato a ogni fotogramma.
- Globali: `thisScene`, `thisLayer`, `engine`, `input`, `audio(low, high)`, `fft(index)` reale, `setTimeout`/`setInterval` e globali di script persistenti.
- Libreria matematica completa `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4` più gli helper `WEMath`, `WEVector` e `WEColor`.
- Moduli JS del runtime di Wallpaper Engine caricati da `assets/scripts/jsmodules` e `jsclasses`.
- Eventi del cursore (`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`) e `resizeScreen`.
- Gli script possono controllare alfa, origine, dimensione, scala, angoli, luminosità/colore del livello, costanti dei materiali, soglie degli effetti e frequenze delle particelle.
- Registrazione delle eccezioni degli script senza duplicati, con il conteggio delle ripetizioni.

### Audio
- Acquisizione dell’audio di sistema tramite ScreenCaptureKit, che alimenta uno spettro smussato a 16 bande, la forma d’onda e i livelli di bassi/medi/alti.
- **Sincronizzazione con la musica** per proprietà: qualsiasi proprietà utente può essere modulata dal livello audio con un’intensità configurabile.

### Proprietà utente e Inspector
- Impostazioni di progetto di tipo cursore, casella di controllo, combo, testo e colore mostrate nella barra laterale della scena, applicate in tempo reale e leggibili da SceneScript.
- Tracciamento del mouse e parallasse per i livelli con `parallaxDepth` definito dall’autore.

### Steam Workshop
- Sfoglia, cerca e filtra per classificazione dei contenuti, tipo e tag di genere, con ordinamento Di tendenza / Più recenti / Più popolari / Più sottoscritti e paginazione numerata.
- Finestre di anteprima con controlli per impostare lo sfondo, la riproduzione e il volume, supportate da una cache limitata; le anteprime applicate vengono promosse nella libreria senza scaricarle di nuovo.
- Integrazione di SteamCMD con rilevamento automatico, accesso con password / Steam Guard / sessione salvata, un pannello Download dedicato, download in coda che puoi riprovare e avanzamento in tempo reale.
- Selezione multipla, selezione di intervalli, download ed eliminazioni in blocco previa conferma, ID scaricati persistenti e ordinamento per `Data di download`.

### Libreria e impostazioni
- Importazione da cartelle, da pacchetti `.zip` o tramite trascinamento.
- Posizione di archiviazione degli sfondi configurabile, con migrazione di una libreria esistente.
- Menu degli sfondi recenti nella barra di stato.
- Impostazioni delle prestazioni: qualità, anti-aliasing, post-elaborazione e comportamento di riproduzione quando l’app perde il focus.
- Diagnosi: il percorso delle risorse incluse, le versioni delle librerie del compilatore di shader integrato e le statistiche della cache degli shader.

</details>

<details>
<summary>In precedenza nella versione 0.8.0</summary>

### Supporto per più schermi
Assegna sfondi diversi a ciascun monitor collegato, con controllo di attivazione/disattivazione per schermo.
- **Pannello Impostazioni schermo**: layout visivo che mostra tutti gli schermi collegati; fai clic per selezionarne uno
- **Sfondo per schermo**: ogni schermo può mostrare uno sfondo diverso in modo indipendente
- **Interruttore di attivazione/disattivazione**: attiva o disattiva lo sfondo su ciascun monitor
- **Rilevamento automatico**: i nuovi monitor vengono rilevati e attivati automaticamente quando li colleghi

### Supporto per più scrivanie
Ora gli sfondi vengono mostrati su tutte le scrivanie di macOS (Spaces) con riproduzione continua, senza interruzioni quando cambi scrivania.

### Menu Sfondi recenti
Cambia rapidamente sfondo dal menu nella barra di stato. Gli ultimi 10 sfondi che hai usato sono elencati per accedervi con un clic.

### Impostazioni di riproduzione: corrette
Le impostazioni di riproduzione relative alle prestazioni (pausa/disattivazione audio/interruzione quando altre app sono in primo piano) ora funzionano correttamente per tutti i tipi di sfondo.

### Browser dello Steam Workshop
Sfoglia, cerca e scarica sfondi direttamente dallo Steam Workshop senza uscire dall’app.
- **Ricerca e filtri**: cerca per nome e filtra per classificazione dei contenuti (Per tutti/Discutibile/Per adulti), tipo (Scena/Video/Web) e tag di genere
- **Opzioni di ordinamento**: Di tendenza, Più recenti, Più popolari, Più sottoscritti
- **Integrazione di steamcmd**: scarica automaticamente SteamCMD di Valve la prima volta che serve (non incluso); se trova uno steamcmd esistente (Homebrew, Steam o percorso personalizzato), usa quello
- **Accesso a Steam**: supporta l’autenticazione con password, Steam Guard e sessione salvata
- **Download con avanzamento**: aggiornamenti di stato in tempo reale durante il download (autenticazione, percentuale scaricata, convalida, copia)
- **Impostazioni predefinite sicure**: la classificazione dei contenuti è impostata su "Per tutti" per escludere i contenuti per adulti

### Importazione di file zip
Importa i pacchetti di sfondi direttamente dai file `.zip`, senza doverli prima estrarre manualmente. Funziona tramite File > Importa e con il trascinamento.

### Selezione multipla e annullamento della sottoscrizione in blocco
Fai Cmd-clic per selezionare più sfondi, quindi fai clic con il tasto destro per annullare la sottoscrizione in blocco.

### Isolamento dell’archivio sfondi
Ora gli sfondi vengono archiviati in `~/Documents/Open Wallpaper Engine/` invece che direttamente nella directory Documenti, evitando gli sfondi in "errore" quando cloni il repository su un computer nuovo.

</details>

<details>
<summary>Prime modifiche rispetto al progetto originale</summary>

### Sfondi web: corretto il rendering grigio/vuoto
Gli sfondi basati su WebGL venivano renderizzati come rettangoli grigi perché `WKWebView` bloccava l’accesso ai file locali per texture e risorse.

**Correzione:** sono stati abilitati `allowFileAccessFromFileURLs` e `allowUniversalAccessFromFileURLs` nella configurazione di WKWebView, consentendo agli shader WebGL di caricare i file di texture locali.

### Sfondi di tipo scena: implementati da zero
Gli sfondi di tipo scena (il tipo più diffuso sullo Steam Workshop) non erano implementati affatto: mostravano solo "Hello, World!".

**La nuova implementazione include:**
- **Parser PKG**: legge il formato di archivio PKGV di Wallpaper Engine per estrarre scene.json, modelli, materiali e texture
- **Parser TEX**: legge i contenitori di texture TEXV0005, estrae i dati delle immagini JPEG/PNG incorporate e legge le mipmap DXT1/DXT3/DXT5
- **Decodificatore JSON della scena**: analizza scene.json con una decodifica flessibile che gestisce i campi polimorfici di Wallpaper Engine (i valori possono essere tipi semplici oppure oggetti `{"script":..,"value":..}`)
- **Renderer Metal**: renderizza i livelli di immagine della scena con la composizione delle texture sulla GPU e una base per futuri effetti shader
- **Decodifica DXT sulla GPU**: espande le texture DXT1 (TEXI 7), DXT3 (TEXI 6) e DXT5 (TEXI 4) tramite un compute shader Metal al caricamento della scena
- **Particelle sprite**: renderizza gli emettitori di sprite `sphererandom` più comuni con durata, dimensione, velocità, alfa, colore, rotazione, velocità angolare, gravità, attrito e dissolvenze alfa casuali
- **Particelle avanzate**: supporta rotazione, variazione di colore, turbolenza, punti di controllo statici e collegati al cursore, segmenti di corda collegati, scie e animazione dei fotogrammi degli spritesheet `.tex-json`
- **Animazione TEXS**: decodifica le timeline TEXS0001/0002/0003, inclusi i rettangoli dei fotogrammi in un singolo atlas e le sequenze di texture con più immagini
- **Timeline della scena**: interpola i keyframe di alfa, origine, scala e angoli degli oggetti a 60 FPS
- **Runtime di SceneScript**: valuta gli script di proprietà di tipo espressione e `export function update(value)` in base all’audio di sistema acquisito con ScreenCaptureKit. La temporizzazione di `thisScene`, `thisLayer.value`, `engine`, il cursore di input, `audio(low, high)`, `fft(index)` reale, la ricerca delle proprietà e le globali persistenti controllano le trasformazioni delle immagini, l’alfa e le frequenze di emissione delle particelle.
- **Ciclo di vita persistente di SceneScript**: riutilizza i contesti di script per livello, chiama `init()` una sola volta e chiama `update()` fotogramma dopo fotogramma con lo stato condiviso di `dt`, fotogramma, mouse, pulsanti, tasti modificatori, cursore, audio, FFT, proprietà e livello.
- **Operatori delle particelle tramite script**: supporta gli script per la frequenza di emissione delle particelle, l’attrito del movimento e la tempistica della dissolvenza alfa, con campi delle particelle numerici/stringa flessibili.
- **Tracciamento del mouse e parallasse**: applica una traslazione relativa al cursore e un ridimensionamento prospettico facoltativo ai livelli con metadati `parallaxDepth` definiti dall’autore; le particelle collegate al cursore usano lo stesso cursore nello spazio della scena.
- **Proprietà visive tramite script**: supporta luminosità/colore RGB degli oggetti, costanti degli effetti dei materiali, trasformazioni scalari/vettoriali e sostituzioni delle soglie degli effetti definite tramite script.
- **Proprietà utente**: mostra le impostazioni di progetto documentate di tipo cursore, casella di controllo, combo, testo e colore nella barra laterale della scena e rende disponibili a SceneScript i valori numerici e booleani
- **Effetti di scena integrati**: esegue nel renderer Metal le voci del grafo degli effetti `pulse`, `shake`, `iris` e `waterwaves` definite dall’autore
- **Effetti semantici dei materiali**: mappa le costanti dei materiali e gli script più comuni per luminosità, contrasto, saturazione, esposizione, gamma, tonalità, soglia del bloom, bloom e sfocatura su effetti Metal nativi
- **Traduzione degli shader GLSL**: converte gli shader GLSL inclusi nei pacchetti di Wallpaper Engine in SPIR-V e MSL al caricamento, con glslang e SPIRV-Cross collegati all’app; le varianti tradotte vengono memorizzate nella cache in `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants`
- **Ripiego sull’anteprima**: usa preview.jpg/png/gif quando non è possibile estrarre le texture

### Importazione: corretta l’importazione delle cartelle
Il pannello di importazione ora gestisce correttamente sia le singole cartelle degli sfondi sia le directory superiori che contengono più sfondi.

</details>

## Limitazioni attuali

- **Sfondi di tipo applicazione**: gli sfondi `type: "application"` non sono supportati e non vengono eseguiti.
- **Funzioni SceneScript non implementate**: `effect.executeMaterialFunction()`, `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `getVideoTexture()`, `engine.openUserShortcut()` non fanno ancora nulla.
- **Parità di SceneScript**: non vengono riprodotti tutti i nomi di eventi proprietari, i callback di input, i casi limite del ciclo di vita o l’esatta semantica delle tempistiche.
- **Funzioni particellari rare**: le forme di emettitore diverse da sfera, box e immagine del livello e i renderer successivi al primo di un sistema non sono supportati.
- **Risorse di Wallpaper Engine necessarie**: le scene richiedono le risorse della tua copia di Wallpaper Engine (Impostazioni → Risorse); senza di esse funzionano solo gli sfondi video e web.
- **Video WebM**: i WebM (VP8/VP9) vengono riprodotti tramite WebKit, quindi gli effetti di sincronizzazione musicale non si applicano.
- **Alcune miniature JPEG**: un piccolo numero di file TEXB di formato 1 contiene dati JPEG non standard che macOS non riesce a decodificare.
- **Ambito delle impostazioni delle prestazioni**: le opzioni di qualità, anti-aliasing e post-elaborazione sono pensate per gli sfondi di tipo scena e hanno un effetto limitato sugli sfondi video e web.
- **Le funzionalità audio richiedono un’autorizzazione**: senza l’autorizzazione Registrazione schermo e audio di sistema, i visualizzatori audio e SceneScript reattivo all’audio ricevono solo silenzio.

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
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

In Xcode, sostituisci il certificato di firma con il tuo oppure seleziona "Sign to Run Locally", quindi premi `Cmd + R` per compilare ed eseguire.

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

## Privacy

Tutto ciò che Open Wallpaper Engine salva resta sul tuo Mac: impostazioni, libreria, cache e login di SteamCMD. Open Wallpaper Engine non ha un server e non raccoglie dati né statistiche. Contatta solo Valve: Steam quando usi il Workshop o installi gli asset, e il server di Valve per scaricare SteamCMD. Gli sfondi web possono caricare propri contenuti online. La password di Steam e il codice Steam Guard vanno direttamente a SteamCMD e non vengono mai salvati, registrati o inviati altrove; viene ricordato solo il nome dell’account, per riutilizzare il login salvato di SteamCMD.

## Struttura del progetto

- `OpenWallpaperEngine/Services/SceneParsers/`: parser e modelli per PKG, TEX/TEXS e scene.json
- `OpenWallpaperEngine/Services/SceneEffects/`: catalogo dinamico degli effetti e intervalli dei parametri degli effetti definiti dall’autore
- `OpenWallpaperEngine/Scene/Shaders/`: traduzione GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), caching e archivio delle pipeline
- `Vendor/ShaderToolchain/`: sorgenti di glslang e SPIRV-Cross, integrati nell’app come pacchetto locale
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift`: runtime di SceneScript e binding audio/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift`: acquisizione dell’audio di sistema con ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal`: il renderer di scene Metal e la libreria degli shader
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift`: navigazione e download dello Steam Workshop
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift`: archiviazione della libreria, importazione e conversione dei pacchetti
- `Scripts/fill-assets-cache.sh`: strumento di sviluppo che copia le risorse di un’installazione di Wallpaper Engine in una cartella locale o nella cache dell’archivio sfondi
- `Scripts/scene-api-coverage.py`: indica quali API di SceneScript usano gli sfondi installati rispetto a quelle implementate
