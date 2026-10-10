Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | **Français** | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine est un lecteur macOS gratuit et open source pour les fonds d’écran Wallpaper Engine : scène, vidéo et web. Doté d’un moteur de rendu Metal natif, il prend en charge les effets, les particules, les modèles 3D, l’éclairage, SceneScript, les visuels réactifs à l’audio et le Steam Workshop. Il est né d’un fork d’[Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) de Haren Chen et MrWindDog, et a depuis été en grande partie réécrit.

> **Remarque :** ce projet n’est PAS affilié au logiciel commercial Wallpaper Engine vendu sur Steam. Il s’agit d’une app open source pour macOS capable d’afficher les ressources de fonds d’écran du Steam Workshop de Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Site web :** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Wiki :** [guides et dépannage](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![La bibliothèque](../../docs/images/library.jpg)

## Points forts

- **Fonds d’écran de scène, vidéo et web** — les scènes sont dessinées avec les propres nuanceurs Wallpaper Engine de chaque fond d’écran, traduits en Metal, avec effets, particules, modèles 3D, lumières, chronologies, SceneScript et visuels réactifs à l’audio. Les fonds d’écran web s’exécutent dans WebKit ou dans le moteur Chromium facultatif.
- **Steam Workshop** — parcourez, filtrez et téléchargez des fonds d’écran du Workshop directement dans l’app, ou importez des dossiers et des fichiers zip de fonds d’écran.
- **Modifier/exporter la scène** — modifiez en direct sur le bureau les calques et les effets du fond d’écran en cours, faites-en votre économiseur d’écran, ou exportez-le (scènes et vidéos) en écran verrouillé Live Photo pour iPhone et iPad ou en paquet pour l’app Android de Wallpaper Engine.

  ![Modifier/exporter la scène](../../docs/images/scene-editor-live.jpg)

- **Éditeur de fond d’écran** — un éditeur dans l’esprit de celui de Wallpaper Engine : calques, effets avec aperçus, chronologie, SceneScript, propriétés utilisateur, particules, Puppet Warp et masques créés à partir d’une carte de profondeur. Vous modifiez un brouillon : **Enregistrer** l’applique au fond d’écran, **Enregistrer comme nouveau fond d’écran** en ajoute une copie à la bibliothèque, et les fichiers du fond d’écran lui-même ne sont jamais modifiés.

  ![Éditeur de fond d’écran](../../docs/images/wallpaper-editor.jpg)

- **Moniteurs** — un fond d’écran par moniteur, un seul étiré sur tous ou cloné sur chacun, des groupes, des divisions et des profils, comme dans Wallpaper Engine.

  ![Moniteurs](../../docs/images/displays.png)

- **Playlists** — changez de fond d’écran selon une minuterie, à l’ouverture de session, selon l’heure ou le jour de la semaine, avec les transitions de Wallpaper Engine.

  ![Réglages des playlists](../../docs/images/playlists.png)

- **Exportation** — écrans verrouillés Live Photo pour iPhone et iPad et paquets Android de Wallpaper Engine, envoyés au téléphone par Wi-Fi grâce à un code QR.

  ![Envoyer par Wi-Fi](../../docs/images/send-over-wifi.png)

- **Thème de couleur** — la barre des menus, la couleur d’accentuation ainsi que les icônes et les dossiers teintés suivent la couleur du fond d’écran ; les fenêtres d’Open Wallpaper Engine peuvent utiliser la couleur exacte.

  ![Thème de couleur](../../docs/images/theming.png)

- **Plug-in Serveur MCP** — les clients MCP peuvent définir les fonds d’écran, les playlists et les réglages, et modifier les scènes, via une connexion locale que seul votre compte peut ouvrir.

  ![Plug-in Serveur MCP](../../docs/images/mcp-plugin.png)

Tout le reste, domaine par domaine : [docs/features.md](../../docs/features.md).

## Installation

1. Téléchargez la dernière version sur [openwallpaperengine.app](https://openwallpaperengine.app/) ou sur [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases). Elle est signée et notariée, et se met à jour toute seule.
2. Ouvrez le DMG et faites glisser **Open Wallpaper Engine** dans Applications.

Il vous faut **macOS 14.0 (Sonoma) ou version ultérieure**. Certaines fonctionnalités nécessitent une version plus récente de macOS, une autorisation ou un plug-in : voir [Prise en main](../../docs/getting-started.md#requirements).

## Démarrage rapide

1. Ouvrez l’app. L’assistant de configuration règle la langue, SteamCMD, votre connexion Steam et les ressources de Wallpaper Engine, et peut importer vos favoris Wallpaper Engine ; chaque étape peut être ignorée.
2. Installez les ressources de Wallpaper Engine (*Réglages › Ressources*) si vous voulez des fonds d’écran de scène. Elles proviennent de votre propre exemplaire de Wallpaper Engine sur Steam ; les fonds d’écran vidéo et web fonctionnent sans elles.
3. Trouvez des fonds d’écran dans les onglets **Découvrir** et **Workshop**, ou importez un dossier ou un fichier zip de fond d’écran (*Fichier › Importer un fond d’écran depuis un dossier…*, ⌘I).
4. Cliquez sur un fond d’écran dans la bibliothèque, puis sur **Définir le fond d’écran** dans ses détails (ou cliquez dessus avec le bouton droit et choisissez **Définir comme fond d’écran**). Ses propriétés sont listées en dessous.

Pour aller plus loin : [Prise en main](../../docs/getting-started.md) et le [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Confidentialité

Tout ce que l’app enregistre reste sur votre Mac, et elle ne collecte aucune donnée ni statistique d’utilisation. Elle contacte Steam (pour le Workshop et les ressources), openwallpaperengine.app (pour rechercher les mises à jour) et GitHub (pour les télécharger), et les plug-ins ne sont téléchargés que lorsque vous les installez. Détails : [ce à quoi l’app se connecte](../../docs/getting-started.md#what-the-app-connects-to) et la [politique de confidentialité](../../docs/legal/privacy-policy.md).

## Documentation

- [Prise en main](../../docs/getting-started.md) — configuration requise, ressources, le Workshop et l’importation
- [Fonctionnalités](../../docs/features.md) — tout ce que l’app prend en charge, et comment l’utiliser
- Guides : [dispositions des moniteurs](../../docs/display-layouts.md) · [playlists](../../docs/playlists.md) · [économiseur d’écran](../../docs/screen-saver.md) · [exportation pour iPhone et iPad](../../docs/iphone-ipad-export.md) · [exportation pour Android](../../docs/android-export.md) · [cartes de profondeur](../../docs/depth-maps.md) · [thèmes](../../docs/theming.md) · [Serveur MCP](../../docs/mcp.md) · [moteur web Chromium](../../docs/chromium-engine.md)
- [Développement](../../docs/development.md) — compilation à partir des sources et organisation du projet ; [CONTRIBUTING.md](../../CONTRIBUTING.md) et [architecture](../../docs/architecture.md)
- [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — guides, référence des réglages et dépannage

## Projets associés

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — Une interface PyQt6 pour [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine), avec intégration du Steam Workshop et un design d’interface repris de cette version macOS.

## Remerciements

Ce projet s’appuie sur le travail de :

- **[MrWindDog](https://github.com/MrWindDog)** — Mainteneur du fork en amont [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac), a ajouté de nouvelles fonctionnalités et des améliorations de l’interface
- **[Haren Chen](https://github.com/haren724)** — Créateur d’origine d’[open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac), a conçu l’architecture de base de l’app (SwiftUI, lecture des fonds d’écran vidéo, système d’importation, interface des playlists)
- **1ris_W** — Traduction chinoise (i18n)
- **[Klaus Zhu](https://github.com/klauszhu1105)** — Conception du logo d’origine
- **[Chen Chia Yang](https://github.com/Unayung)** — Rendu des fonds d’écran de scène, corrections des fonds d’écran web, intégration du Steam Workshop, prise en charge de plusieurs moniteurs, importation de fichiers zip
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Moteur de rendu de scène Metal et pipeline d’effets, traduction et mise en cache des nuanceurs GLSL→MSL, environnement d’exécution SceneScript, rendu réactif au son, refonte du Workshop et des téléchargements, réglages de placement et de performances, refonte du logo

Distribué sous licence [GPL-3.0](../../LICENSE), comme le projet d’origine.

## Mentions légales

[Conditions d’utilisation](../../docs/legal/terms-of-use.md) · [Politique de confidentialité](../../docs/legal/privacy-policy.md) · [Politique de sécurité](../../SECURITY.md)

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
