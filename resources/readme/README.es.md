Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | **Español** | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine es un reproductor gratuito y de código abierto para macOS de fondos de pantalla de Wallpaper Engine: de escena, de vídeo y web. Cuenta con un renderizador nativo en Metal y admite efectos, partículas, modelos 3D, iluminación, SceneScript, visuales que reaccionan al audio y Steam Workshop. Nació como un fork de [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) de Haren Chen y MrWindDog, y desde entonces se ha reescrito en gran parte.

> **Nota:** Este proyecto NO está afiliado al Wallpaper Engine comercial de Steam. Es una app de código abierto para macOS que puede mostrar recursos de fondos de pantalla del Steam Workshop de Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** las guías y la documentación están en la [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Requisitos

### Obligatorios
- **macOS 14.0 o posterior** (Sonoma). Tanto la captura de audio con ScreenCaptureKit como el renderizado de escenas con Metal dependen de ello.

### Opcionales: necesarios para funciones concretas

| Función | Requisito | Instalación |
|---------|-------------|---------|
| Explorar y descargar desde el Steam Workshop | `steamcmd` | Automático (opcional: `brew install steamcmd`) |
| Visualizadores de audio y SceneScript que reacciona al audio | Permiso de Grabación de pantalla y del audio del sistema | Ajustes → Permisos |

#### Sombreadores

Wallpaper Engine incluye sus efectos en GLSL. glslang y SPIRV-Cross, integrados en la app (`Vendor/ShaderToolchain`), los traducen a Metal (GLSL → SPIR-V → MSL) la primera vez que un fondo de pantalla los usa y después los almacenan en caché en el disco. No hace falta instalar nada. Un sombreador cuya traducción bloqueó la app, o la hizo fallar dos veces, se omite en los siguientes arranques, y todos los demás sombreadores se siguen traduciendo.

#### Recursos de Wallpaper Engine

Las escenas usan los efectos, materiales, sombreadores, tipos de letra y el entorno de ejecución de SceneScript compartidos de tu propia copia de Wallpaper Engine en Steam; la app no los incluye. Instálalos en *Ajustes → Recursos*: la app descarga tu copia con steamcmd (la cuenta debe tener Wallpaper Engine), conserva solo los recursos y los fondos de pantalla predeterminados, y elimina el resto. También puedes elegir una carpeta de Wallpaper Engine existente. Los fondos de pantalla de vídeo y web funcionan sin ellos.

## Compilar desde el código fuente

### Requisitos previos
- macOS >= 14.0
- Xcode >= 26.3 (SDK de macOS 26)
- Herramientas de línea de comandos de Xcode

### Pasos
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

En Xcode, cambia el certificado de firma por el tuyo o selecciona «Sign to Run Locally» y, después, pulsa `Cmd + R` para compilar y ejecutar.

Al compilar desde el código fuente, la primera compilación descarga el paquete Swift Sparkle. Las compilaciones desde el código fuente no buscan actualizaciones.

## Uso

### Explorar y descargar desde el Steam Workshop

1. No hay que instalar nada: la app descarga SteamCMD de Valve en segundo plano la primera vez que se necesita (desde Valve, no viene incluido). Homebrew (`brew install steamcmd`) es opcional; si encuentra un steamcmd existente (Homebrew, Steam o el que elijas), lo usa
2. Cambia a la pestaña **Workshop** e inicia sesión con tu cuenta de Steam (debes tener Wallpaper Engine)
3. Introduce una [clave de la API web de Steam](https://steamcommunity.com/dev/apikey) cuando se te pida, o en *Ajustes → General*. Se comprueba con Steam y se guarda en tu llavero; tu contraseña de Steam nunca se almacena (steamcmd reutiliza su propia sesión en caché)
4. Busca, filtra y haz clic en **Descargar** en cualquier fondo de pantalla

### Importar desde archivos locales

- **Carpeta:** Archivo > Importar > Fondo de pantalla desde carpeta: selecciona carpetas de fondos de pantalla que contengan `project.json`
- **Zip:** Archivo > Importar, o arrastra y suelta un archivo `.zip` que contenga paquetes de fondos de pantalla
- **Manual:** copia las carpetas de fondos de pantalla directamente en `~/Documents/Open Wallpaper Engine/`

## Funciones compatibles de la versión 1.0.0

### Configuración, biblioteca y actualizaciones
- **Asistente de configuración**: en el primer inicio, unos pocos pasos que se pueden omitir eligen el idioma, muestran las notas de privacidad, configuran SteamCMD, el inicio de sesión de Steam y una clave opcional de la Web API de Steam, instalan los recursos de Wallpaper Engine y traen tus fondos de pantalla.
- **SteamCMD se configura solo**: si no encuentra ninguno, la app descarga SteamCMD de Valve; si existe uno de Homebrew o de Steam, lo usa.
- **Recursos de Wallpaper Engine desde tu propia copia de Steam**: se instalan con SteamCMD tras iniciar sesión, opcionalmente con los fondos predeterminados de Wallpaper Engine.
- **Importaciones**: tus colecciones y suscripciones del Workshop (desde la Web API de Steam), los elementos del Workshop de una biblioteca de Steam existente y carpetas de fondos de pantalla.
- **La [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)**: guías, referencia de ajustes y solución de problemas; «Soporte y preguntas frecuentes» en la app la abre.
- **Actualizaciones automáticas**: las actualizaciones firmadas se instalan solas (al salir, tras 10 minutos de ausencia o en un día como máximo, y un reinicio rápido restaura tus fondos). En Ajustes › General › Actualizaciones puedes solo buscarlas, desactivar la búsqueda y recibir versiones beta. «Buscar actualizaciones…» está en el menú de la app y en el menú de la barra de menús.

### Renderizado de escenas
- **Los sombreadores propios de Wallpaper Engine**: las capas, los efectos y los materiales se dibujan ahora con los sombreadores originales de cada fondo de pantalla, traducidos a Metal, incluidos los efectos creados por los autores del Workshop.
- Capas de composición, de pantalla completa y de color sólido, capas que muestrean otras capas, los 33 modos de fusión y más máscaras de efecto.
- **Maquetación fiel del texto**: el texto se dimensiona, alinea y coloca como en Wallpaper Engine, con efectos de fuente de contorno, desenfoque y sombra paralela.
- **Líneas de tiempo**: las animaciones de fotogramas clave y de texturas siguen las reglas de Wallpaper Engine para reproducción única, en bucle y en espejo.
- Tablas de consulta de color, la corrección de color de Wallpaper Engine y las opciones de filtro de imagen y de color en las propiedades de un fondo de pantalla.
- Imágenes con **Puppet Warp** animadas por sus animaciones, con física de huesos (muelles, gravedad, límites) y objetos sujetos a sus huesos.

### 3D e iluminación
- **Modelos 3D** con skinning, capas de animación, morph targets y root motion.
- Cámaras de escena en perspectiva con trayectorias, fundidos y vibración; las capas 2D se sitúan en profundidad.
- **Luces de escena** con cookies de luz, sombras, reflejos planos, niebla por distancia y por altura, y luces volumétricas.
- **HDR**: las escenas HDR se renderizan con el bloom HDR de Wallpaper Engine, y la calidad «Ultra (HDR de pantalla)» genera EDR en las pantallas que pueden mostrarlo.

### Partículas
- **Partículas en la GPU**: cada sistema de partículas se simula en la GPU, en 3D, con puntos de control 3D.
- Sistemas hijos, incluidos los que activan las partículas de su padre; ráfagas de emisión, retardos y emisión periódica; emisión desde la imagen de una capa.
- Colisiones, también con los huesos de un modelo, respuesta al audio y rotación en todos los ejes.
- Ajustes de partículas vinculados a las propiedades de usuario de un fondo de pantalla.

### SceneScript y multimedia
- Un **entorno de ejecución de SceneScript** completo: módulos, el modelo de objetos de escena/capa/efecto/material, eventos de animación, `localStorage` y detección del cursor, con los scripts de cada fondo de pantalla en su propio hilo.
- Los scripts pueden crear capas, sistemas de partículas y sonidos, mover la niebla, controlar el bloom y posar marionetas y modelos.
- **Ahora suena**: los fondos de pantalla de escena y web reciben la pista actual y el estado de reproducción (macOS 15.4 o posterior).
- Los fondos de pantalla web reciben sus propiedades de usuario y el audio en directo.

### Audio
- El espectro de audio se calcula como lo calcula Wallpaper Engine, en estéreo.
- Las **capas de sonido** se reproducen al ritmo del reloj de la escena, con **sonido espacial** situado como en Wallpaper Engine.

### Pantallas y reproducción
- **Pausar por pantalla** o **Pausar todas**, con las reglas de reproducción evaluadas para cada pantalla, incluida la regla de Wallpaper Engine para ventanas maximizadas.
- Propiedades de usuario por pantalla, con «Sincronizar propiedades entre pantallas».
- Un fondo de pantalla que se muestra en varias pantallas se renderiza una sola vez y se presenta en cada una.
- Nuevos ajustes de calidad: Resolución de renderizado, Resolución de texturas, nivel de detalle de escena ajustado a la pantalla, reflejos, sombras y volumétricos.
- **Reinicio seguro**: un fondo de pantalla que bloqueó la app o la hizo fallar se omite en el siguiente arranque y se marca en la biblioteca.

### Workshop y biblioteca
- Los filtros del Workshop de Wallpaper Engine: Mostrar solo, un filtro de resolución, géneros combinados con Y/O y etiquetas en cada tarjeta.
- Los fondos de pantalla instalados muestran sus etiquetas del Workshop y se pueden filtrar por ellas; los elementos que solo son recursos o dependencias no aparecen en Instalados.
- Las dependencias del Workshop que faltan se descargan automáticamente, y las que ya no se usan se eliminan tras un borrado. Cada descarga va a la carpeta Almacenamiento de fondos de pantalla.
- **Restablecer** en Detalles devuelve las propiedades de un fondo de pantalla, y sus cambios en el Inspector de escenas, a los valores por defecto que fijó su autor.
- Se respetan las condiciones de propiedades, las filas de texto y los formatos de los reguladores definidos en los ajustes del fondo de pantalla.
- Las contraseñas de Steam nunca se guardan, y la clave de la API web de Steam se guarda en el llavero.

### Interfaz e idiomas
- **Liquid Glass** en macOS 26: una vista dividida nativa con barra de herramientas, inspector y controles de cristal. Las versiones anteriores de macOS mantienen el aspecto de siempre.
- **15 idiomas nuevos**: alemán, francés, español, portugués de Brasil, italiano, japonés, coreano, chino simplificado y tradicional, ruso, polaco, turco, ucraniano, árabe e hindi, que se eligen en el selector de idioma de los ajustes.
- Un nuevo icono de la app y un icono de la barra de menús que sigue el aspecto de la barra de menús.

## Limitaciones actuales

- **Funciones de SceneScript sin implementar**: `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()` todavía no hacen nada.
- **Paridad con SceneScript**: no se reproducen todos los nombres de eventos propietarios, callbacks de entrada, casos límite del ciclo de vida ni la semántica exacta de temporización.
- **Funciones de partículas poco comunes**: no se admiten formas de emisor distintas de esfera, caja e imagen de capa, ni los renderizadores posteriores al primero de un sistema.
- **Vídeos WebM**: el formato WebM (VP8/VP9) se reproduce a través de WebKit, por lo que los efectos de sincronización con la música no se aplican.
- **Algunas miniaturas JPEG**: un pequeño número de archivos TEXB de formato 1 contienen datos JPEG no estándar que macOS no puede descodificar.
- **Alcance de los ajustes de rendimiento**: las opciones de calidad, suavizado de contorno y posprocesado están pensadas para los fondos de pantalla de escena y tienen un efecto limitado en los fondos de pantalla de vídeo y web.
- **Las funciones de audio requieren permiso**: sin el permiso de Grabación de pantalla y del audio del sistema, los visualizadores de audio y los scripts de SceneScript que reaccionan al audio solo reciben silencio.
- **Sin comparar lado a lado con Wallpaper Engine** – Wallpaper Engine no funciona en macOS, así que el comportamiento sigue los propios archivos y shaders de Wallpaper Engine; algunos casos límite (líneas de tiempo, iluminación, salida HDR) no están confirmados.

## Tipos de fondos de pantalla compatibles

| Tipo | Estado |
|------|--------|
| Vídeo (.mp4, .webm) | Funciona |
| Web (HTML/WebGL) | Funciona |
| Escena: capas de imagen y líneas de tiempo | Funciona (Metal) |
| Escena: texturas DXT1/DXT3/DXT5 | Funciona (descodificación en la GPU con Metal) |
| Escena: sprites TEXS / líneas de tiempo de alfa | Funciona |
| Escena: partículas de sprites | Funciona |
| Escena: partículas avanzadas | Parcial (consulta Limitaciones) |
| Escena: efectos de Wallpaper Engine y del Workshop (los propios sombreadores de WE) | Funciona |
| Escena: SceneScript | Parcial (consulta Limitaciones) |
| Escena: modelos 3D / rigging / deformación de marioneta | Funciona |
| Aplicación | No compatible |

## Privacidad

Todo lo que guarda Open Wallpaper Engine se queda en tu Mac: tus ajustes, tu biblioteca, la caché y el inicio de sesión de SteamCMD. Open Wallpaper Engine no tiene servidor y no recopila datos ni analíticas. Se comunica con Valve (con Steam cuando usas el Workshop o instalas los recursos, y con el servidor de Valve para descargar SteamCMD) y con GitHub, para buscar actualizaciones de la app (el appcast en GitHub Pages) y descargarlas de GitHub Releases, sin enviar ningún dato personal. La búsqueda de actualizaciones se puede desactivar en Ajustes › General. Los fondos de pantalla web pueden cargar su propio contenido en línea. Tu contraseña de Steam y tu código de Steam Guard van directamente a SteamCMD y nunca se guardan, se registran ni se envían a ningún otro sitio; solo se recuerda tu nombre de cuenta, para reutilizar el inicio de sesión guardado de SteamCMD.

## Estructura del proyecto

- `OpenWallpaperEngine/Scene/Format/`: analizadores y modelos de PKG, TEX/TEXS y scene.json
- `OpenWallpaperEngine/Scene/Shaders/`: traducción GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), almacenamiento en caché y el archivo de pipelines
- `Vendor/ShaderToolchain/`: código fuente de glslang y SPIRV-Cross, integrado en la app como paquete local
- `OpenWallpaperEngine/Scene/Scripting/`: entorno de ejecución de SceneScript y vinculaciones de audio/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift`: captura del audio del sistema con ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal`: el renderizador de escenas Metal y la biblioteca de sombreadores
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift`: exploración del Steam Workshop y descargas
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift`: almacenamiento de la biblioteca, importación y conversión de paquetes
- `Scripts/fill-assets-cache.sh`: utilidad de desarrollo que copia los recursos de una instalación de Wallpaper Engine en una carpeta local o en la caché del almacenamiento de fondos de pantalla
- `Scripts/scene-api-coverage.py`: indica qué API de SceneScript usan los fondos de pantalla instalados en comparación con las que están implementadas

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
