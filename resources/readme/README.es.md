Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | **Español** | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine es un reproductor gratuito y de código abierto para macOS de fondos de pantalla de Wallpaper Engine: de escena, de vídeo y web. Cuenta con un renderizador nativo en Metal y admite efectos, partículas, modelos 3D, iluminación, SceneScript, visuales que reaccionan al audio y Steam Workshop. Nació como un fork de [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) de Haren Chen y MrWindDog, y desde entonces se ha reescrito en gran parte.

> **Nota:** Este proyecto NO está afiliado al Wallpaper Engine comercial de Steam. Es una app de código abierto para macOS que puede mostrar recursos de fondos de pantalla del Steam Workshop de Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Sitio web:** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Wiki:** [guías y solución de problemas](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![La biblioteca](../../docs/images/library.png)

## Lo más destacado

- **Fondos de pantalla de escena, de vídeo y web**: las escenas se dibujan con los propios sombreadores de Wallpaper Engine de cada fondo, traducidos a Metal, con efectos, partículas, modelos 3D, luces, líneas de tiempo, SceneScript y visuales que reaccionan al audio. Los fondos web se ejecutan en WebKit o en el motor Chromium opcional.
- **Steam Workshop**: explora, filtra y descarga fondos del Workshop sin salir de la app, o importa carpetas y archivos zip de fondos de pantalla.
- **Editar/exportar escena**: cambia en vivo en el escritorio las capas y los efectos del fondo que se está reproduciendo, graba con él tu propio salvapantallas o expórtalo como pantalla de bloqueo Live Photo para iPhone y iPad o como paquete para la app de Android de Wallpaper Engine.

  ![Editar/exportar escena](../../docs/images/scene-editor-live.png)

- **Editor de fondos de pantalla**: un editor al estilo del de Wallpaper Engine, con capas, efectos con vista previa, línea de tiempo, SceneScript, propiedades de usuario, partículas y Puppet Warp. Tus cambios se guardan junto al fondo de pantalla, nunca en sus archivos.

  ![Editor de fondos de pantalla](../../docs/images/wallpaper-editor.png)

- **Pantallas**: un fondo por pantalla, uno estirado a lo largo de todas o clonado en cada una, grupos, divisiones y perfiles, como en Wallpaper Engine.

  ![Pantallas](../../docs/images/displays.png)

- **Playlists**: cambia de fondo con un temporizador, al iniciar sesión, según la hora del día o el día de la semana, con las transiciones de Wallpaper Engine.

  ![Ajustes de playlists](../../docs/images/playlists.png)

- **Exportación**: pantallas de bloqueo Live Photo para iPhone y iPad y paquetes de Android de Wallpaper Engine, enviados al teléfono por Wi-Fi con un código QR.

  ![Enviar por Wi-Fi](../../docs/images/send-over-wifi.png)

- **Temas**: la barra de menús, el color de acento y las carpetas teñidas siguen los colores del fondo de pantalla.

  ![Temas](../../docs/images/theming.png)

- **Plugin Servidor MCP**: los clientes MCP pueden establecer fondos de pantalla, playlists y ajustes, y editar escenas, a través de una conexión local que solo tu cuenta puede abrir.

  ![Plugin Servidor MCP](../../docs/images/mcp-plugin.png)

Todo lo demás, área por área: [docs/features.md](../../docs/features.md).

## Instalación

1. Descarga la última versión desde [openwallpaperengine.app](https://openwallpaperengine.app/) o [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases). Está firmada y notarizada, y se actualiza sola.
2. Abre el DMG y arrastra **Open Wallpaper Engine** a Aplicaciones.

Necesitas **macOS 14.0 (Sonoma) o posterior**. Algunas funciones requieren una versión más reciente de macOS, un permiso o un plugin: consulta [Primeros pasos](../../docs/getting-started.md#requirements).

## Inicio rápido

1. Abre la app. El asistente de configuración establece el idioma, SteamCMD, tu inicio de sesión de Steam y los recursos de Wallpaper Engine; todos los pasos se pueden omitir.
2. Instala los recursos de Wallpaper Engine (*Ajustes › Recursos*) si quieres fondos de pantalla de escena. Proceden de tu propia copia de Wallpaper Engine en Steam; los fondos de vídeo y web funcionan sin ellos.
3. Busca fondos de pantalla en la pestaña **Workshop**, o importa una carpeta o un archivo zip de fondo de pantalla (*Archivo › Importar fondo de pantalla desde carpeta…*, ⌘I).
4. Haz clic en un fondo de pantalla de la biblioteca y luego en **Establecer fondo de pantalla** en sus detalles. Sus propiedades aparecen debajo.

Más información: [Primeros pasos](../../docs/getting-started.md) y la [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Privacidad

Todo lo que guarda la app se queda en tu Mac, y no recopila datos ni analíticas. Se conecta a Steam (para el Workshop y los recursos) y a GitHub (para las actualizaciones), y los plugins solo se descargan cuando los instalas. Detalles: [a qué se conecta la app](../../docs/getting-started.md#what-the-app-connects-to) y la [política de privacidad](../../docs/legal/privacy-policy.md).

## Documentación

- [Primeros pasos](../../docs/getting-started.md): requisitos, recursos, el Workshop y la importación
- [Funciones](../../docs/features.md): todo lo que admite la app y cómo usarlo
- Guías: [disposiciones de pantallas](../../docs/display-layouts.md) · [playlists](../../docs/playlists.md) · [salvapantallas](../../docs/screen-saver.md) · [exportación a iPhone y iPad](../../docs/iphone-ipad-export.md) · [exportación a Android](../../docs/android-export.md) · [mapas de profundidad](../../docs/depth-maps.md) · [temas](../../docs/theming.md) · [Servidor MCP](../../docs/mcp.md) · [motor web Chromium](../../docs/chromium-engine.md)
- [Desarrollo](../../docs/development.md): compilar desde el código fuente y la estructura del proyecto; [CONTRIBUTING.md](../../CONTRIBUTING.md) y [arquitectura](../../docs/architecture.md)
- [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki): guías, referencia de ajustes y solución de problemas

## Proyectos relacionados

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)**: una interfaz gráfica PyQt6 para [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine), con integración del Steam Workshop y un diseño de interfaz adaptado de esta versión para macOS.

## Créditos

Este proyecto se basa en el trabajo de:

- **[MrWindDog](https://github.com/MrWindDog)**: responsable del fork original [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac); añadió nuevas funciones y mejoras de la interfaz
- **[Haren Chen](https://github.com/haren724)**: creador original de [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac); desarrolló la arquitectura base de la app (SwiftUI, reproducción de fondos de pantalla de vídeo, sistema de importación, interfaz de playlists)
- **1ris_W**: traducción al chino (i18n)
- **[Klaus Zhu](https://github.com/klauszhu1105)**: diseño original del logotipo
- **[Chen Chia Yang](https://github.com/Unayung)**: renderizado de fondos de pantalla de escena, correcciones de fondos de pantalla web, integración del Steam Workshop, compatibilidad con varias pantallas, importación de archivos zip
- **[Deepratna Awale](https://github.com/deepratna-awale)**: renderizador de escenas Metal y pipeline de efectos, traducción y almacenamiento en caché de sombreadores GLSL→MSL, entorno de ejecución de SceneScript, renderizado que reacciona al audio, renovación del Workshop y las descargas, ajustes de colocación y rendimiento, rediseño del logotipo

Con licencia [GPL-3.0](../../LICENSE), igual que el proyecto original.

## Aviso legal

[Condiciones de uso](../../docs/legal/terms-of-use.md) · [Política de privacidad](../../docs/legal/privacy-policy.md) · [Política de seguridad](../../SECURITY.md)

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
