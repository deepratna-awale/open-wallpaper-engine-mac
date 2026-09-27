Open Wallpaper Engine (version patchée)
=========

[English](../../README.md) | [Deutsch](README.de.md) | **Français** | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Un fork patché d’[Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) pour macOS, qui ajoute le rendu des fonds d’écran de scène et des corrections pour les fonds d’écran web.

> **Remarque :** ce projet n’est PAS affilié au logiciel commercial Wallpaper Engine vendu sur Steam. Il s’agit d’une app open source pour macOS capable d’afficher les ressources de fonds d’écran du Steam Workshop de Wallpaper Engine.

## Projets associés

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — Une interface PyQt6 pour [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine), avec intégration du Steam Workshop et un design d’interface repris de cette version macOS.

## Remerciements

Ce projet s’appuie sur le travail de :

- **[MrWindDog](https://github.com/MrWindDog)** — Mainteneur du fork en amont [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac), a ajouté de nouvelles fonctionnalités et des améliorations de l’interface
- **[Haren Chen](https://github.com/haren724)** — Créateur d’origine d’[open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac), a conçu l’architecture de base de l’app (SwiftUI, lecture des fonds d’écran vidéo, système d’importation, interface des playlists)
- **[1ris_W](https://github.com/Erica-Iris)** — Traduction chinoise (i18n)
- **[Klaus Zhu](https://github.com/klauszhu1105)** — Icônes de l’app
- **[Chen Chia Yang](https://github.com/Unayung)** — Rendu des fonds d’écran de scène, corrections des fonds d’écran web, intégration du Steam Workshop, prise en charge de plusieurs moniteurs, importation de fichiers zip
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Moteur de rendu de scène Metal et pipeline d’effets, traduction et mise en cache des nuanceurs GLSL→MSL, environnement d’exécution SceneScript, rendu réactif au son, refonte du Workshop et des téléchargements, réglages de placement et de performances

Distribué sous licence [GPL-3.0](../../LICENSE), comme le projet d’origine.

## Fonctionnalités prises en charge par la version 0.8.1

### Lecture des fonds d’écran
- **Fonds d’écran de scène** rendus nativement avec Metal — calques d’image, transformations, chronologies d’images clés, ordre de profondeur et données de caméra et de projection issues de `scene.json`.
- **Fonds d’écran vidéo** (`.mp4`, `.webm`) avec vitesse de lecture, volume, liaison des vitesses audio et vidéo, et zoom, inclinaison et saturation synchronisés sur la musique en option.
- **Fonds d’écran web** (HTML/WebGL) avec accès aux fichiers locaux activé pour que les textures et les ressources WebGL se chargent correctement, ainsi que les intégrations externes (YouTube/Vimeo).
- **Modes de placement** — Occuper tout l’écran, Adapter à l’écran, Centrer, Étirer pour remplir l’écran, Zoomer.
- **Plusieurs moniteurs** — un fond d’écran différent par moniteur, activation ou désactivation par écran, disposition visuelle des moniteurs et détection automatique des moniteurs nouvellement connectés.
- **Plusieurs bureaux (Spaces)** — lecture continue sur tous les bureaux, y compris une option d’attribution `Tous les bureaux`.
- **Règles de lecture** — continuer, couper le son, mettre en pause ou arrêter lorsqu’une autre app est au premier plan ; comportement correct lors de la suspension, de la réactivation et des changements de bureau.

### Prise en charge du format de scène
- **Analyseur PKG** pour les archives `PKGV` de Wallpaper Engine (scene.json, matériaux, textures, nuanceurs).
- **Analyseur TEX** pour les conteneurs `TEXV0005` : JPEG/PNG intégrés et DXT1/DXT3/DXT5 avec mipmaps décodés sur le GPU par un nuanceur de calcul Metal.
- **Chronologies de sprites TEXS** (0001/0002/0003), y compris les rectangles d’images d’un atlas unique et les séquences de plusieurs images.
- **Décodage souple de scene.json**, qui gère les champs polymorphes de Wallpaper Engine (valeurs simples ou `{"script":…,"value":…}`).
- **Aperçu de secours** avec `preview.jpg/png/gif` lorsque les textures ne peuvent pas être extraites.

### Effets et nuanceurs
- **~48 effets Metal natifs** : distorsion, flou (standard/précis/radial/de mouvement), flou lumineux, rayons crépusculaires et faisceaux lumineux, vagues/ondulations/caustiques/écoulement de l’eau, nuages et brouillard, grain de film, glitch/VHS, aberration chromatique, incrustation de couleur, transformation/inclinaison/rotation/tourbillon/perspective, réflexion, réfraction, brillance/miroitement/paillettes, détection des contours, et bien plus.
- **Effets réactifs au son** — pulsation, barres audio, décalage de teinte synchronisé sur le son et hyperdrive, pilotés par les données de spectre en direct de l’audio du système.
- **Effets de matériau sémantiques** — luminosité, contraste, saturation, exposition, gamma, teinte, seuil du flou lumineux, flou lumineux et flou, associés à des passes Metal natives.
- **Traduction GLSL → SPIR-V → MSL** au chargement par glslang et SPIRV-Cross, liés à l’app, avec les définitions COMBO, la résolution des inclusions et la renumérotation des emplacements de tampon Metal.
- **Cache de nuanceurs précompilés** — les fichiers `.metal` traduits, les fichiers `.metallib` compilés et les fichiers annexes `.reflection.json` sont mis en cache dans `.open-wallpaper-engine/shaders`, contrôlés par hachage afin que seuls les nuanceurs modifiés soient retraduits, et compilés en arrière-plan afin que le rendu ne soit jamais bloqué.
- **Catalogue d’effets dynamique** lu à partir des manifestes `assets/effects/*/effect.json` de Wallpaper Engine, y compris les effets à plusieurs passes et les liaisons d’uniformes obtenues par réflexion.
- **Masquage des effets** (jusqu’à 4 textures de masque par calque), fusion additive et alpha, et système de cibles de rendu mutualisées.

### Particules
- Émetteurs de sprites avec durée de vie, taille, vitesse, couleur, rotation, vitesse angulaire, gravité, traînée et fondus alpha aléatoires.
- Comportements avancés — turbulence, attracteurs, mouvement en vortex et de type boids, points de contrôle statiques et liés au curseur, segments de corde reliés et traînées avec fondu d’alpha et de taille.
- Animation d’images de planches de sprites via des séquences `.tex-json`.
- Opérateurs scriptés pour le taux d’émission, la traînée et le minutage du fondu alpha.

### Environnement d’exécution SceneScript
- Contextes de script persistants par calque, avec `init()` appelée une fois et `update(value)` appelée à chaque image.
- Globales : `thisScene`, `thisLayer`, `engine`, `input`, `audio(low, high)`, une véritable `fft(index)`, `setTimeout`/`setInterval` et des globales de script persistantes.
- Bibliothèque mathématique complète `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4`, ainsi que les utilitaires `WEMath`, `WEVector` et `WEColor`.
- Modules JS de l’environnement d’exécution de Wallpaper Engine chargés depuis `assets/scripts/jsmodules` et `jsclasses`.
- Événements de curseur (`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`) et `resizeScreen`.
- Les scripts peuvent piloter l’alpha, l’origine, la taille, l’échelle, les angles, la luminosité et la couleur des calques, les constantes de matériau, les seuils d’effet et les taux de particules.
- Journalisation dédupliquée des exceptions de script avec nombre de répétitions.

### Audio
- Capture de l’audio du système via ScreenCaptureKit, qui alimente un spectre lissé à 16 bandes, une forme d’onde et des niveaux de graves, médiums et aigus.
- **Synchronisation sur la musique** par propriété — toute propriété utilisateur peut être modulée par le niveau audio, avec une intensité réglable.

### Propriétés utilisateur et inspecteur
- Réglages de projet de type curseur, case à cocher, liste déroulante, texte et couleur, affichés dans la barre latérale de la scène, appliqués en direct et lisibles depuis SceneScript.
- Suivi de la souris et parallaxe pour les calques dotés d’une valeur `parallaxDepth`.

### Steam Workshop
- Navigation, recherche et filtrage par classification, type et étiquettes de genre, avec les tris Tendances / Les plus récents / Les plus populaires / Les plus suivis et une pagination numérotée.
- Fenêtres d’aperçu avec des commandes pour définir le fond d’écran, gérer la lecture et régler le volume, adossées à un cache de taille limitée ; les aperçus appliqués sont intégrés à la bibliothèque sans nouveau téléchargement.
- Intégration de SteamCMD avec détection automatique, connexion par mot de passe, Steam Guard ou session en cache, onglet Téléchargements dédié, téléchargements en file d’attente pouvant être relancés et progression en direct.
- Sélection multiple, sélection d’une plage, téléchargements et suppressions groupés soumis à confirmation, identifiants téléchargés conservés et tri par `Date de téléchargement`.

### Bibliothèque et réglages
- Importation depuis des dossiers, depuis des paquets `.zip` ou par glisser-déposer.
- Emplacement de stockage des fonds d’écran configurable, avec migration d’une bibliothèque existante.
- Menu des fonds d’écran récents dans la barre des menus.
- Réglages de performances — qualité, anticrénelage, post-traitement et comportement de lecture en cas de perte du premier plan.
- Diagnostic — le chemin des ressources intégrées, les versions des bibliothèques du compilateur de nuanceurs intégré et les statistiques du cache des nuanceurs.

<details>
<summary>Précédemment dans la version 0.8.0</summary>

### Prise en charge de plusieurs moniteurs
Attribuez un fond d’écran différent à chaque moniteur connecté, avec activation ou désactivation par écran.
- **Panneau Réglages des moniteurs** — Disposition visuelle de tous les écrans connectés ; cliquez pour en sélectionner un
- **Fond d’écran par écran** — Chaque moniteur peut afficher indépendamment un fond d’écran différent
- **Bouton d’activation** — Activez ou désactivez le fond d’écran pour chaque moniteur
- **Détection automatique** — Les nouveaux moniteurs sont automatiquement détectés et activés lors de leur connexion

### Prise en charge de plusieurs bureaux
Les fonds d’écran s’affichent désormais sur tous les bureaux macOS (Spaces) avec une lecture continue, sans interruption lors du changement de bureau.

### Menu Fonds d’écran récents
Changez rapidement de fond d’écran depuis le menu de la barre des menus. Les 10 derniers fonds d’écran utilisés y sont accessibles en un clic.

### Réglages de lecture — corrigés
Les réglages de lecture de la section Performances (pause, son coupé ou arrêt lorsque d’autres apps sont au premier plan) fonctionnent désormais correctement pour tous les types de fonds d’écran.

### Navigateur du Steam Workshop
Parcourez, recherchez et téléchargez des fonds d’écran directement depuis le Steam Workshop, sans quitter l’app.
- **Recherche et filtres** — Recherche par nom, filtrage par classification (Tout public/Discutable/Adulte), type (Scène/Vidéo/Web) et étiquettes de genre
- **Options de tri** — Tendances, Les plus récents, Les plus populaires, Les plus suivis
- **Intégration de steamcmd** — Détecte automatiquement steamcmd (Homebrew ou chemin personnalisé) et affiche les instructions d’installation s’il est introuvable
- **Connexion à Steam** — Prend en charge l’authentification par mot de passe, par Steam Guard et par session en cache
- **Téléchargement avec progression** — Mises à jour de l’état en temps réel pendant le téléchargement (authentification, pourcentage téléchargé, validation, copie)
- **Valeurs par défaut sûres** — La classification est définie par défaut sur « Tout public » afin de filtrer les contenus pour adultes

### Importation de fichiers zip
Importez des paquets de fonds d’écran directement depuis des fichiers `.zip`, sans avoir à les extraire manuellement au préalable. Fonctionne via Fichier > Importer et par glisser-déposer.

### Sélection multiple et désabonnement groupé
Cliquez tout en maintenant la touche Cmd enfoncée pour sélectionner plusieurs fonds d’écran, puis cliquez avec le bouton droit pour vous désabonner de tous en une fois.

### Isolation du stockage des fonds d’écran
Les fonds d’écran sont désormais stockés dans `~/Documents/OpenWallpaperEngine/` plutôt qu’à la racine du dossier Documents, ce qui évite les fonds d’écran « error » lors du clonage du dépôt sur une nouvelle machine.

</details>

<details>
<summary>Modifications par rapport au projet en amont</summary>

### Fonds d’écran web — rendu gris ou vide corrigé
Les fonds d’écran basés sur WebGL s’affichaient sous forme de rectangles gris, car `WKWebView` bloquait l’accès aux fichiers locaux pour les textures et les ressources.

**Correction :** activation de `allowFileAccessFromFileURLs` et `allowUniversalAccessFromFileURLs` dans la configuration de WKWebView, ce qui permet aux nuanceurs WebGL de charger les fichiers de texture locaux.

### Fonds d’écran de scène — implémentés de zéro
Les fonds d’écran de scène (le type le plus courant sur le Steam Workshop) n’étaient pas du tout implémentés et affichaient simplement « Hello, World! ».

**La nouvelle implémentation comprend :**
- **Analyseur PKG** — Lit le format d’archive PKGV de Wallpaper Engine pour extraire scene.json, les modèles, les matériaux et les textures
- **Analyseur TEX** — Lit les conteneurs de textures TEXV0005, extrait les données d’image JPEG/PNG intégrées et lit les mipmaps DXT1/DXT3/DXT5
- **Décodeur JSON de scène** — Analyse scene.json avec un décodage souple qui gère les champs polymorphes de Wallpaper Engine (les valeurs peuvent être des types simples ou des objets `{"script":..,"value":..}`)
- **Moteur de rendu Metal** — Effectue le rendu des calques d’image des scènes avec composition des textures sur le GPU et pose les bases de futurs effets de nuanceur
- **Décodage DXT sur le GPU** — Décompresse les textures DXT1 (TEXI 7), DXT3 (TEXI 6) et DXT5 (TEXI 4) à l’aide d’un nuanceur de calcul Metal lors du chargement de la scène
- **Particules de sprites** — Effectue le rendu des émetteurs de sprites `sphererandom` courants avec durée de vie, taille, vitesse, alpha, couleur, rotation, vitesse angulaire, gravité, traînée et fondus alpha aléatoires
- **Particules avancées** — Prend en charge la rotation, la variation de couleur, la turbulence, les points de contrôle statiques et liés au curseur, les segments de corde reliés, les traînées et l’animation d’images de planches de sprites `.tex-json`
- **Animation TEXS** — Décode les chronologies TEXS0001/0002/0003, y compris les rectangles d’images d’un atlas unique et les séquences de textures à plusieurs images
- **Chronologies de scène** — Interpole les images clés d’alpha, d’origine, d’échelle et d’angles des objets à 60 FPS
- **Environnement d’exécution SceneScript** — Évalue les expressions et les scripts de propriété `export function update(value)` à partir de l’audio du système capturé par ScreenCaptureKit. Le minutage de `thisScene`, `thisLayer.value`, `engine`, le curseur d’entrée, `audio(low, high)`, une véritable `fft(index)`, la consultation des propriétés et les globales persistantes pilotent les transformations d’image, l’alpha et les taux d’émission des particules.
- **Cycle de vie SceneScript persistant** — Réutilise les contextes de script par calque, appelle `init()` une fois et appelle `update()` d’une image à l’autre avec un état partagé pour `dt`, l’image, la souris, les boutons, les touches de modification, le curseur, l’audio, la FFT, les propriétés et les calques.
- **Opérateurs de particules scriptés** — Prend en charge les scripts pour le taux d’émission des particules, la traînée du mouvement et le minutage du fondu alpha, avec des champs de particules numériques ou textuels souples.
- **Suivi de la souris et parallaxe** — Applique une translation relative au curseur et, en option, une mise à l’échelle en perspective aux calques dotés de métadonnées `parallaxDepth` ; les particules liées au curseur utilisent le même curseur dans l’espace de la scène.
- **Propriétés visuelles scriptées** — Prend en charge la luminosité et la couleur RVB des objets, les constantes d’effet de matériau, les transformations scalaires et vectorielles et le remplacement des seuils d’effet, pilotés par script.
- **Propriétés utilisateur** — Affiche dans la barre latérale de la scène les réglages de projet documentés de type curseur, case à cocher, liste déroulante, texte et couleur, et rend les valeurs numériques et booléennes accessibles à SceneScript
- **Effets de scène intégrés** — Exécute dans le moteur de rendu Metal les entrées `pulse`, `shake`, `iris` et `waterwaves` du graphe d’effets
- **Effets de matériau sémantiques** — Associe les constantes de matériau et les scripts courants de luminosité, contraste, saturation, exposition, gamma, teinte, seuil du flou lumineux, flou lumineux et flou à des effets Metal natifs
- **Traduction des nuanceurs GLSL** — Convertit au chargement les nuanceurs GLSL fournis avec Wallpaper Engine en SPIR-V et MSL avec glslang et SPIRV-Cross, liés à l’app ; les variantes traduites sont mises en cache dans `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants`
- **Aperçu de secours** — Utilise preview.jpg/png/gif lorsque les textures ne peuvent pas être extraites

### Importation — importation de dossiers corrigée
Le panneau d’importation gère désormais correctement aussi bien les dossiers de fond d’écran individuels que les dossiers parents contenant plusieurs fonds d’écran.

</details>

## Limitations actuelles

- **Fonds d’écran de type application** — Les fonds d’écran `type: "application"` ne sont pas pris en charge et ne s’exécutent pas.
- **Modèles 3D et rigging** — Les transformations d’os, les blend shapes, les attachements et les rigs de déformation de marionnette (`.mdl`) ne sont que des ébauches ; les calques concernés sont rendus sous forme d’atlas plats.
- **Fonctions de script de matériau** — `getMaterial()`, `getMaterialCount()`, `setMaterialProperty()` et `executeMaterialFunction()` sont des ébauches qui ne font rien ou renvoient des valeurs vides.
- **Liaison des nuanceurs GLSL personnalisés** — Le MSL converti est mis en cache lors de l’importation, mais les nuanceurs qui dépendent d’attributs propres à Wallpaper Engine, de chaînes de textures ou d’inclusions non prises en charge ne sont pas liés au pipeline Metal à l’exécution. Les paramètres courants de flou lumineux, de flou, de correction colorimétrique et de transformation se rabattent sur des équivalents Metal natifs.
- **Limite de tampons Metal** — Les nuanceurs nécessitant plus que les 31 emplacements de tampon de Metal ne peuvent pas être traduits et sont définitivement marqués comme non pris en charge pour la révision actuelle du pipeline.
- **Nuanceurs HLSL** — Les nuanceurs réservés à Direct3D, fournis avec les sources GLSL, sont entièrement ignorés.
- **Couverture des schémas d’effets** — Les noms d’uniformes personnalisés inconnus et les schémas de paramètres d’effet arbitraires restent non pris en charge.
- **Parité SceneScript** — Les noms d’événements propriétaires, les rappels d’entrée, les cas limites du cycle de vie et la sémantique exacte du minutage ne sont pas tous reproduits.
- **Couverture des opérateurs de particules** — Les opérateurs scriptés courants de taux, de traînée et de fondu alpha fonctionnent ; les scripts d’opérateurs peu courants, les modules de particules personnalisés et les schémas d’opérateurs arbitraires ne sont que partiellement pris en charge.
- **Récupération des ressources externes** — Certains paquets du Workshop font référence à des ressources TEX partagées absentes du paquet téléchargé et nécessitent l’installation d’origine de Wallpaper Engine.
- **Certaines vignettes JPEG** — Un petit nombre de fichiers TEXB au format 1 contiennent des données JPEG non standard que macOS ne peut pas décoder.
- **Portée des réglages de performances** — Les options de qualité, d’anticrénelage et de post-traitement sont conçues pour les fonds d’écran de scène et n’ont qu’un effet limité sur les fonds d’écran vidéo et web.
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
| Scène — particules avancées | Partiel (taux, traînée et fondu scriptés pris en charge) |
| Scène — effets Metal natifs | Fonctionnel (~48 effets) |
| Scène — effets GLSL du Workshop traduits | Partiel (voir Limitations) |
| Scène — SceneScript | Partiel (voir Limitations) |
| Scène — modèles 3D / rigging / déformation de marionnette | Non pris en charge |
| Application | Non pris en charge |

## Configuration requise

### Obligatoire
- **macOS 13.0 ou version ultérieure** (Ventura). La capture audio ScreenCaptureKit et le rendu de scène Metal en dépendent tous deux.

### Facultatif — nécessaire pour certaines fonctionnalités

| Fonctionnalité | Prérequis | Installation |
|---------|-------------|---------|
| Navigation et téléchargement depuis le Steam Workshop | `steamcmd` | `brew install steamcmd` |
| Visualiseurs audio et SceneScript réactif au son | Autorisation Enregistrement de l’écran et des sons du système | Réglages → Autorisations |

#### Nuanceurs

Wallpaper Engine fournit ses effets en GLSL. Ils sont traduits pour Metal (GLSL → SPIR-V → MSL) par glslang et SPIRV-Cross, intégrés à l’app (`Vendor/ShaderToolchain`), la première fois qu’un fond d’écran les utilise, puis mis en cache sur le disque. Rien n’est à installer. Un nuanceur dont la traduction a bloqué l’app, ou l’a fait planter deux fois, est ignoré lors des lancements suivants, et tous les autres nuanceurs continuent d’être traduits.

#### Ressources de Wallpaper Engine

Les effets, matériaux, nuanceurs et l’environnement d’exécution SceneScript partagés auxquels les fonds d’écran font référence sont fournis avec l’app (`Vendor/we-assets`, actualisé à partir d’une installation de Wallpaper Engine avec `Scripts/vendor-we-assets.sh`). Il n’y a rien à configurer.

## Compilation à partir des sources

### Prérequis
- macOS >= 14.0
- Xcode >= 26.3 (SDK macOS 26)
- Outils de ligne de commande Xcode

### Étapes
```sh
git clone https://github.com/unayung/wallpaper-engine-mac
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

Dans Xcode, remplacez le certificat de signature par le vôtre ou sélectionnez « Sign to Run Locally », puis appuyez sur `Cmd + R` pour compiler et exécuter l’app.

## Utilisation

### Parcourir et télécharger depuis le Steam Workshop

1. Installez steamcmd (`brew install steamcmd`) ou indiquez à l’app un exécutable existant
2. Passez à l’onglet **Workshop** et connectez-vous avec votre compte Steam (vous devez posséder Wallpaper Engine)
3. Saisissez une [clé d’API Web Steam](https://steamcommunity.com/dev/apikey) lorsque vous y êtes invité, ou dans *Réglages → Général*. Elle est vérifiée auprès de Steam et conservée dans votre trousseau ; votre mot de passe Steam n’est jamais enregistré (steamcmd réutilise sa propre session en cache)
4. Recherchez, filtrez, puis cliquez sur **Télécharger** pour n’importe quel fond d’écran

### Importer depuis des fichiers locaux

- **Dossier :** Fichier > Importer > Fond d’écran depuis un dossier — sélectionnez des dossiers de fond d’écran contenant `project.json`
- **Zip :** Fichier > Importer, ou glissez-déposez un fichier `.zip` contenant des paquets de fonds d’écran
- **Manuellement :** copiez les dossiers de fond d’écran directement dans `~/Documents/OpenWallpaperEngine/`

## Organisation du projet

- `OpenWallpaperEngine/Services/SceneParsers/` — analyseurs et modèles PKG, TEX/TEXS et scene.json
- `OpenWallpaperEngine/Services/SceneEffects/` — catalogue d’effets dynamique et plages des paramètres d’effet définies par les auteurs
- `OpenWallpaperEngine/Scene/Shaders/` — traduction GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), mise en cache et archive de pipelines
- `Vendor/ShaderToolchain/` — sources de glslang et de SPIRV-Cross, intégrées à l’app sous forme de paquet local
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift` — environnement d’exécution SceneScript et liaisons audio/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — capture de l’audio du système via ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — le moteur de rendu de scène Metal et la bibliothèque de nuanceurs
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — navigation dans le Steam Workshop et téléchargements
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — stockage de la bibliothèque, importation et conversion des paquets
- `Scripts/vendor-we-assets.sh` — intègre les nuanceurs d’effets traduits et les manifestes dans `we-assets/`
- `Scripts/scene-api-coverage.py` — indique quelles API SceneScript les fonds d’écran installés utilisent par rapport à celles qui sont implémentées
