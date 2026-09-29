Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | **Français** | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine est un lecteur macOS gratuit et open source pour les fonds d’écran Wallpaper Engine : scène, vidéo et web. Doté d’un moteur de rendu Metal natif, il prend en charge les effets, les particules, les modèles 3D, l’éclairage, SceneScript, les visuels réactifs à l’audio et le Steam Workshop. Il est né d’un fork d’[Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) de Haren Chen et MrWindDog, et a depuis été en grande partie réécrit.

> **Remarque :** ce projet n’est PAS affilié au logiciel commercial Wallpaper Engine vendu sur Steam. Il s’agit d’une app open source pour macOS capable d’afficher les ressources de fonds d’écran du Steam Workshop de Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki :** les guides et la documentation se trouvent dans le [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Configuration requise

### Obligatoire
- **macOS 14.0 ou version ultérieure** (Sonoma). La capture audio ScreenCaptureKit et le rendu de scène Metal en dépendent tous deux.

### Facultatif — nécessaire pour certaines fonctionnalités

| Fonctionnalité | Prérequis | Installation |
|---------|-------------|---------|
| Navigation et téléchargement depuis le Steam Workshop | `steamcmd` | Automatique (facultatif : `brew install steamcmd`) |
| Visualiseurs audio et SceneScript réactif au son | Autorisation Enregistrement de l’écran et des sons du système | Réglages → Autorisations |

#### Nuanceurs

Wallpaper Engine fournit ses effets en GLSL. Ils sont traduits pour Metal (GLSL → SPIR-V → MSL) par glslang et SPIRV-Cross, intégrés à l’app (`Vendor/ShaderToolchain`), la première fois qu’un fond d’écran les utilise, puis mis en cache sur le disque. Rien n’est à installer. Un nuanceur dont la traduction a bloqué l’app, ou l’a fait planter deux fois, est ignoré lors des lancements suivants, et tous les autres nuanceurs continuent d’être traduits.

#### Ressources de Wallpaper Engine

Les scènes utilisent les effets, matériaux, nuanceurs, polices et l’environnement d’exécution SceneScript partagés de votre propre copie de Wallpaper Engine sur Steam ; l’app ne les fournit pas. Installez-les dans *Réglages → Ressources* : l’app télécharge votre copie avec steamcmd (le compte doit posséder Wallpaper Engine), ne garde que les ressources et les fonds d’écran par défaut, et supprime le reste. Vous pouvez aussi choisir un dossier Wallpaper Engine existant. Les fonds d’écran vidéo et web fonctionnent sans elles.

## Compilation à partir des sources

### Prérequis
- macOS >= 14.0
- Xcode >= 26.3 (SDK macOS 26)
- Outils de ligne de commande Xcode

### Étapes
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

Dans Xcode, remplacez le certificat de signature par le vôtre ou sélectionnez « Sign to Run Locally », puis appuyez sur `Cmd + R` pour compiler et exécuter l’app.

La première compilation depuis les sources télécharge le paquet Swift Sparkle. Les versions compilées depuis les sources ne recherchent pas de mises à jour.

## Utilisation

### Parcourir et télécharger depuis le Steam Workshop

1. Rien à installer : l’app télécharge SteamCMD de Valve en arrière-plan la première fois qu’il est nécessaire (depuis Valve, non inclus). Homebrew (`brew install steamcmd`) est facultatif ; un steamcmd existant (Homebrew, Steam ou celui que vous choisissez) est utilisé s’il est trouvé
2. Passez à l’onglet **Workshop** et connectez-vous avec votre compte Steam (vous devez posséder Wallpaper Engine)
3. Saisissez une [clé d’API Web Steam](https://steamcommunity.com/dev/apikey) lorsque vous y êtes invité, ou dans *Réglages → Général*. Elle est vérifiée auprès de Steam et conservée dans votre trousseau ; votre mot de passe Steam n’est jamais enregistré (steamcmd réutilise sa propre session en cache)
4. Recherchez, filtrez, puis cliquez sur **Télécharger** pour n’importe quel fond d’écran

### Importer depuis des fichiers locaux

- **Dossier :** Fichier > Importer > Fond d’écran depuis un dossier — sélectionnez des dossiers de fond d’écran contenant `project.json`
- **Zip :** Fichier > Importer, ou glissez-déposez un fichier `.zip` contenant des paquets de fonds d’écran
- **Manuellement :** copiez les dossiers de fond d’écran directement dans `~/Documents/Open Wallpaper Engine/`

## Fonctionnalités prises en charge par la version 1.0.0

### Configuration, bibliothèque et mises à jour
- **Assistant de configuration** — au premier lancement, quelques étapes facultatives choisissent la langue, présentent les notes de confidentialité, configurent SteamCMD, la connexion Steam et une clé Steam Web API facultative, installent les ressources de Wallpaper Engine et importent vos fonds d’écran.
- **SteamCMD s’installe tout seul** — s’il n’en trouve aucun, l’app télécharge SteamCMD de Valve ; celui de Homebrew ou de Steam est utilisé s’il existe.
- **Ressources de Wallpaper Engine depuis votre propre copie Steam** — installées par SteamCMD après la connexion, avec en option les fonds d’écran par défaut de Wallpaper Engine.
- **Imports** — vos collections et abonnements du Workshop (via la Web API de Steam), les éléments du Workshop d’une bibliothèque Steam existante et des dossiers de fonds d’écran.
- **Le [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)** — guides, référence des réglages et dépannage ; « Assistance et FAQ » dans l’app l’ouvre.
- **Mises à jour automatiques** — les mises à jour signées s’installent d’elles-mêmes (à la fermeture, après 10 minutes d’absence ou dans la journée, puis un relancement rapide restaure vos fonds d’écran). Réglages › Général › Mises à jour permet de seulement rechercher, de désactiver la recherche et de recevoir les versions bêta. « Rechercher les mises à jour… » se trouve dans le menu de l’app et dans le menu de la barre des menus.

### Rendu des scènes
- **Les nuanceurs d’origine de Wallpaper Engine** — les calques, effets et matériaux sont désormais dessinés avec les nuanceurs d’origine de chaque fond d’écran, traduits en Metal, y compris les effets créés par les auteurs du Workshop.
- Calques de composition, plein écran et de couleur unie, calques qui échantillonnent d’autres calques, les 33 modes de fusion et davantage de masques d’effet.
- **Mise en page fidèle du texte** — le texte est dimensionné, aligné et positionné comme dans Wallpaper Engine, avec les effets de police contour, flou et ombre portée.
- **Chronologies** — les animations par images clés et de textures suivent les règles de Wallpaper Engine pour la lecture unique, en boucle et en miroir.
- Tables de correspondance des couleurs, correction colorimétrique de Wallpaper Engine, et options de filtre d’image et de couleur dans les propriétés d’un fond d’écran.
- Images **Puppet Warp** animées par leurs animations, avec une physique des os (ressorts, gravité, limites) et des objets attachés à leurs os.

### 3D et éclairage
- **Modèles 3D** avec skinning, calques d’animation, cibles de morphing et root motion.
- Caméras de scène en perspective avec trajectoires, fondus et tremblements ; les calques 2D sont placés en profondeur.
- **Lumières de scène** avec cookies de lumière, ombres, réflexions planes, brouillard de distance et de hauteur, et lumières volumétriques.
- **HDR** — les scènes HDR sont rendues avec le bloom HDR de Wallpaper Engine, et la qualité « Ultra (HDR du moniteur) » produit de l’EDR sur les moniteurs capables de l’afficher.

### Particules
- **Particules sur le GPU** — chaque système de particules est simulé sur le GPU, en 3D, avec des points de contrôle 3D.
- Systèmes enfants, y compris ceux déclenchés par les particules de leur parent ; salves d’émission, délais et émission périodique ; émission depuis l’image d’un calque.
- Collisions, y compris avec les os d’un modèle, réaction au son et rotation sur tous les axes.
- Réglages de particules liés aux propriétés utilisateur d’un fond d’écran.

### SceneScript et médias
- Un **environnement d’exécution SceneScript** complet — modules, modèle objet scène/calque/effet/matériau, événements d’animation, `localStorage` et détection du curseur, les scripts de chaque fond d’écran s’exécutant sur leur propre fil.
- Les scripts peuvent créer des calques, des systèmes de particules et des sons, déplacer le brouillard, piloter le bloom et poser des marionnettes et des modèles.
- **À l’écoute** — les fonds d’écran de scène et web reçoivent le morceau en cours et l’état de lecture (macOS 15.4 ou ultérieur).
- Les fonds d’écran web reçoivent leurs propriétés utilisateur et l’audio en direct.

### Audio
- Le spectre audio est calculé comme le calcule Wallpaper Engine, en stéréo.
- Les **calques sonores** sont lus au rythme de l’horloge de la scène, avec un **son spatial** placé comme dans Wallpaper Engine.

### Moniteurs et lecture
- **Pause par moniteur** ou **Tout mettre en pause**, les règles de lecture étant évaluées pour chaque moniteur, y compris la règle de Wallpaper Engine pour les fenêtres agrandies.
- Propriétés utilisateur par moniteur, avec « Synchroniser les propriétés entre les moniteurs ».
- Un fond d’écran affiché sur plusieurs moniteurs est rendu une seule fois et présenté sur chacun.
- Nouveaux réglages de qualité : Résolution de rendu, Résolution des textures, niveau de détail de scène adapté au moniteur, réflexions, ombres et effets volumétriques.
- **Redémarrage sécurisé** — un fond d’écran qui a bloqué ou fait planter l’app est ignoré au lancement suivant et signalé dans la bibliothèque.

### Workshop et bibliothèque
- Les filtres Workshop de Wallpaper Engine : Afficher uniquement, un filtre de résolution, des genres combinés en ET/OU et des tags sur chaque carte.
- Les fonds d’écran installés affichent leurs tags Workshop et peuvent être filtrés par ces tags ; les éléments qui ne sont que des ressources ou des dépendances restent hors de Installés.
- Les dépendances Workshop manquantes sont téléchargées automatiquement, et celles devenues inutiles sont supprimées après une suppression. Chaque téléchargement arrive dans le dossier Stockage des fonds d’écran.
- **Réinitialiser** dans Détails rétablit les propriétés d’un fond d’écran, ainsi que ses modifications dans l’inspecteur de scène, aux valeurs par défaut choisies par son auteur.
- Les conditions de propriétés, les lignes de texte et les formats de curseur définis dans les réglages du fond d’écran sont respectés.
- Les mots de passe Steam ne sont jamais enregistrés, et la clé de l’API Web Steam est conservée dans le trousseau.

### Interface et langues
- **Liquid Glass** sous macOS 26 — une présentation divisée native avec barre d’outils, inspecteur et commandes en verre. Les versions antérieures de macOS conservent l’apparence habituelle.
- **15 nouvelles langues** : allemand, français, espagnol, portugais du Brésil, italien, japonais, coréen, chinois simplifié et traditionnel, russe, polonais, turc, ukrainien, arabe et hindi, à choisir dans le sélecteur de langue des réglages.
- Une nouvelle icône d’app, et une icône de barre des menus qui suit l’apparence de la barre des menus.

## Limitations actuelles

- **Fonctions SceneScript non implémentées** — `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()` ne font encore rien.
- **Parité SceneScript** — Les noms d’événements propriétaires, les rappels d’entrée, les cas limites du cycle de vie et la sémantique exacte du minutage ne sont pas tous reproduits.
- **Vidéos WebM** — Le WebM (VP8/VP9) est lu par WebKit ; les effets de synchronisation musicale ne s’y appliquent donc pas.
- **Certaines vignettes JPEG** — Un petit nombre de fichiers TEXB au format 1 contiennent des données JPEG non standard que macOS ne peut pas décoder.
- **Les fonctionnalités audio nécessitent une autorisation** — Sans l’autorisation Enregistrement de l’écran et des sons du système, les visualiseurs audio et les scripts SceneScript réactifs au son ne reçoivent que du silence.

## Types de fonds d’écran pris en charge

| Type | État |
|------|--------|
| Vidéo (.mp4, .webm) | Fonctionnel |
| Web (HTML/WebGL) | Fonctionnel |
| Scène — calques d’image et chronologies | Fonctionnel (Metal) |
| Scène — textures DXT1/DXT3/DXT5 | Fonctionnel (décodage GPU Metal) |
| Scène — sprites TEXS / chronologies alpha | Fonctionnel |
| Scène — particules de sprites | Fonctionnel |
| Scène — particules avancées | Partiel (voir Limitations) |
| Scène — effets de Wallpaper Engine et du Workshop (les nuanceurs de WE) | Fonctionnel |
| Scène — SceneScript | Partiel (voir Limitations) |
| Scène — modèles 3D / rigging / déformation de marionnette | Fonctionnel |
| Application | Non pris en charge |

## Confidentialité

Tout ce qu’Open Wallpaper Engine enregistre reste sur votre Mac : vos réglages, votre bibliothèque, le cache et la connexion de SteamCMD. Open Wallpaper Engine n’a pas de serveur et ne collecte aucune donnée ni statistique d’utilisation. Il contacte Valve (Steam lorsque vous utilisez le Workshop ou installez les ressources, et le serveur de Valve pour télécharger SteamCMD) et GitHub, pour rechercher les mises à jour de l’app (l’appcast sur GitHub Pages) et les télécharger depuis GitHub Releases, sans envoyer aucune donnée personnelle. La recherche de mises à jour peut être désactivée dans Réglages › Général. Les fonds d’écran web peuvent charger leur propre contenu en ligne. Votre mot de passe Steam et votre code Steam Guard sont transmis directement à SteamCMD et ne sont jamais enregistrés, journalisés ni envoyés ailleurs ; seul votre nom de compte est mémorisé, pour réutiliser la connexion enregistrée de SteamCMD.

## Organisation du projet

- `OpenWallpaperEngine/Scene/Format/` — analyseurs et modèles PKG, TEX/TEXS et scene.json
- `OpenWallpaperEngine/Scene/Shaders/` — traduction GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), mise en cache et archive de pipelines
- `Vendor/ShaderToolchain/` — sources de glslang et de SPIRV-Cross, intégrées à l’app sous forme de paquet local
- `OpenWallpaperEngine/Scene/Scripting/` — environnement d’exécution SceneScript et liaisons audio/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — capture de l’audio du système via ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — le moteur de rendu de scène Metal et la bibliothèque de nuanceurs
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — navigation dans le Steam Workshop et téléchargements
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — stockage de la bibliothèque, importation et conversion des paquets
- `Scripts/fill-assets-cache.sh` — outil de développement : copie les ressources d’une installation de Wallpaper Engine dans un dossier local ou dans le cache du stockage des fonds d’écran
- `Scripts/scene-api-coverage.py` — indique quelles API SceneScript les fonds d’écran installés utilisent par rapport à celles qui sont implémentées

## Projets associés

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — Une interface PyQt6 pour [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine), avec intégration du Steam Workshop et un design d’interface repris de cette version macOS.

## Remerciements

Ce projet s’appuie sur le travail de :

- **[MrWindDog](https://github.com/MrWindDog)** — Mainteneur du fork en amont [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac), a ajouté de nouvelles fonctionnalités et des améliorations de l’interface
- **[Haren Chen](https://github.com/haren724)** — Créateur d’origine d’[open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac), a conçu l’architecture de base de l’app (SwiftUI, lecture des fonds d’écran vidéo, système d’importation, interface des playlists)
- **1ris_W** — Traduction chinoise (i18n)
- **[Klaus Zhu](https://github.com/klauszhu1105)** — Conception du logo d’origine
- **[Chen Chia Yang](https://github.com/Unayung)** — Rendu des fonds d’écran de scène, corrections des fonds d’écran web, intégration du Steam Workshop, prise en charge de plusieurs moniteurs, importation de fichiers zip
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Moteur de rendu de scène Metal et pipeline d’effets, traduction et mise en cache des nuanceurs GLSL→MSL, environnement d’exécution SceneScript, rendu réactif au son, refonte du Workshop et des téléchargements, réglages de placement et de performances, refonte du logo

Distribué sous licence [GPL-3.0](../../LICENSE), comme le projet d’origine.
