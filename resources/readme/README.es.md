Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | **Español** | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine es un reproductor gratuito y de código abierto para macOS de fondos de pantalla de Wallpaper Engine: de escena, de vídeo y web. Cuenta con un renderizador nativo en Metal y admite efectos, partículas, modelos 3D, iluminación, SceneScript, visuales que reaccionan al audio y Steam Workshop. Nació como un fork de [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) de Haren Chen y MrWindDog, y desde entonces se ha reescrito en gran parte.

> **Nota:** Este proyecto NO está afiliado al Wallpaper Engine comercial de Steam. Es una app de código abierto para macOS que puede mostrar recursos de fondos de pantalla del Steam Workshop de Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** las guías y la documentación están en la [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

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

## Funciones compatibles de la versión 0.9.0

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

<details>
<summary>Novedades anteriores de la versión 0.8.1</summary>

### Reproducción de fondos de pantalla
- **Fondos de pantalla de escena** renderizados de forma nativa con Metal: capas de imagen, transformaciones, líneas de tiempo con fotogramas clave, orden de profundidad y datos de cámara y proyección de `scene.json`.
- **Fondos de pantalla de vídeo** (`.mp4`, `.webm`) con velocidad de reproducción, volumen, vinculación de la velocidad de audio y vídeo, y zoom, inclinación y saturación sincronizados con la música de forma opcional.
- **Fondos de pantalla web** (HTML/WebGL) con acceso a archivos locales activado para que las texturas y los recursos WebGL se carguen correctamente, además de contenido externo incrustado (YouTube/Vimeo).
- **Modos de colocación**: Llenar pantalla, Ajustar a pantalla, Centrar, Ampliar para rellenar, Acercar.
- **Varias pantallas**: un fondo de pantalla distinto para cada monitor, activación y desactivación por pantalla, disposición visual de los monitores y detección automática de las pantallas recién conectadas.
- **Varios escritorios (Spaces)**: reproducción continua en todos los escritorios, incluida la opción de asignación `Todos los escritorios`.
- **Reglas de reproducción**: seguir reproduciendo, silenciar, pausar o detener cuando otra app está activa; comportamiento correcto al entrar en reposo, al reactivarse y al cambiar de escritorio.

### Compatibilidad con el formato de escena
- **Analizador PKG** para los archivos `PKGV` de Wallpaper Engine (scene.json, materiales, texturas, sombreadores).
- **Analizador TEX** para los contenedores `TEXV0005`: JPEG/PNG incrustados y DXT1/DXT3/DXT5 con mipmaps descodificados en la GPU mediante un sombreador de cálculo de Metal.
- **Líneas de tiempo de sprites TEXS** (0001/0002/0003), incluidos los rectángulos de fotograma en un único atlas y las secuencias de varias imágenes.
- **Descodificación flexible de scene.json**, que gestiona los campos polimórficos de Wallpaper Engine (valores simples o `{"script":…,"value":…}`).
- **Previsualización de reserva** con `preview.jpg/png/gif` cuando no se pueden extraer las texturas.

### Efectos y sombreadores
- **Unos 48 efectos nativos de Metal** que abarcan distorsión, desenfoque (estándar/preciso/radial/de movimiento), resplandor, rayos de luz y haces de luz, olas/ondas/cáusticas/flujo de agua, nubes y niebla, grano de película, glitch/VHS, aberración cromática, clave de color, transformación/sesgo/giro/remolino/perspectiva, reflejo, refracción, brillo/destello/purpurina, detección de bordes y mucho más.
- **Efectos que reaccionan al audio**: pulso, barras de audio, cambio de tono sincronizado con el audio e hyperdrive, controlados por datos del espectro del audio del sistema en tiempo real.
- **Efectos de material semánticos**: brillo, contraste, saturación, exposición, gamma, tono, umbral de resplandor, resplandor y desenfoque, asignados a pasadas nativas de Metal.
- **Traducción GLSL → SPIR-V → MSL** durante la carga mediante glslang y SPIRV-Cross, enlazados en la app, con definiciones COMBO, resolución de inclusiones y renumeración de las ranuras de búfer de Metal.
- **Caché de sombreadores precompilados**: los archivos `.metal` traducidos, los `.metallib` compilados y los archivos complementarios `.reflection.json` se almacenan en caché en `.open-wallpaper-engine/shaders`, protegidos por hash para que solo se vuelvan a traducir los sombreadores modificados, y se compilan en segundo plano para que el renderizado nunca se bloquee.
- **Catálogo dinámico de efectos** leído de los manifiestos `assets/effects/*/effect.json` de Wallpaper Engine, incluidos los efectos de varias pasadas y las vinculaciones de uniforms obtenidas por reflexión.
- **Enmascaramiento de efectos** (hasta 4 texturas de máscara por capa), fusión aditiva y alfa, y un sistema de destinos de renderizado agrupados.

### Partículas
- Emisores de sprites con duración, tamaño, velocidad, color, rotación, velocidad angular, gravedad, resistencia y fundidos alfa aleatorios.
- Comportamiento avanzado: turbulencia, atractores, movimiento de vórtice y de tipo boid, puntos de control estáticos y vinculados al cursor, segmentos de cuerda conectados y estelas con fundido de alfa y tamaño.
- Animación de fotogramas de hojas de sprites mediante secuencias `.tex-json`.
- Operadores con script para la tasa de emisión, la resistencia y el momento del fundido alfa.

### Entorno de ejecución de SceneScript
- Contextos de script persistentes por capa, con `init()` llamada una vez y `update(value)` llamada en cada fotograma.
- Globales: `thisScene`, `thisLayer`, `engine`, `input`, `audio(low, high)`, una `fft(index)` real, `setTimeout`/`setInterval` y globales de script persistentes.
- Biblioteca matemática completa `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4`, además de las utilidades `WEMath`, `WEVector` y `WEColor`.
- Módulos JS del entorno de ejecución de Wallpaper Engine cargados desde `assets/scripts/jsmodules` y `jsclasses`.
- Eventos del cursor (`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`) y `resizeScreen`.
- Los scripts pueden controlar el alfa, el origen, el tamaño, la escala, los ángulos y el brillo o color de las capas, las constantes de material, los umbrales de efecto y las tasas de partículas.
- Registro sin duplicados de las excepciones de script, con recuento de repeticiones.

### Audio
- Captura del audio del sistema mediante ScreenCaptureKit, que proporciona un espectro suavizado de 16 bandas, una forma de onda y niveles de graves, medios y agudos.
- **Sincronización con la música** por propiedad: cualquier propiedad de usuario puede modularse según el nivel de audio con una intensidad configurable.

### Propiedades de usuario e inspector
- Ajustes del proyecto de tipo regulador, casilla, menú desplegable, texto y color, que se muestran en la barra lateral de la escena, se aplican en tiempo real y pueden leerse desde SceneScript.
- Seguimiento del ratón y paralaje para las capas que definen `parallaxDepth`.

### Steam Workshop
- Explora, busca y filtra por clasificación de contenido, tipo y etiquetas de género, con ordenación por Tendencias / Más recientes / Más populares / Más suscritos y paginación numerada.
- Ventanas de previsualización con controles para establecer el fondo de pantalla, la reproducción y el volumen, respaldadas por una caché limitada; las previsualizaciones aplicadas pasan a la biblioteca sin volver a descargarse.
- Integración con SteamCMD con detección automática, inicio de sesión con contraseña, Steam Guard o sesión en caché, una pestaña Descargas dedicada, descargas en cola que pueden reintentarse y progreso en tiempo real.
- Selección múltiple, selección de intervalos, descargas y eliminaciones en bloque con confirmación, identificadores descargados persistentes y ordenación por `Fecha de descarga`.

### Biblioteca y ajustes
- Importación desde carpetas, desde paquetes `.zip` o arrastrando y soltando.
- Ubicación configurable del almacenamiento de fondos de pantalla, con migración de una biblioteca existente.
- Menú de fondos de pantalla recientes en la barra de menús.
- Ajustes de rendimiento: calidad, suavizado de contorno, posprocesado y comportamiento de la reproducción al perder el foco.
- Diagnóstico: la ruta de los recursos incluidos, las versiones de las bibliotecas del compilador de sombreadores integrado y las estadísticas de la caché de sombreadores.

</details>

<details>
<summary>Novedades anteriores de la versión 0.8.0</summary>

### Compatibilidad con varias pantallas
Asigna un fondo de pantalla distinto a cada monitor conectado, con activación y desactivación por pantalla.
- **Panel Ajustes de pantalla**: disposición visual de todas las pantallas conectadas; haz clic para seleccionar una
- **Fondo de pantalla por pantalla**: cada pantalla puede mostrar un fondo de pantalla distinto de forma independiente
- **Interruptor de activación**: activa o desactiva el fondo de pantalla en cada monitor
- **Detección automática**: los monitores nuevos se detectan y activan automáticamente al conectarlos

### Compatibilidad con varios escritorios
Los fondos de pantalla se muestran ahora en todos los escritorios de macOS (Spaces) con reproducción continua, sin interrupciones al cambiar de escritorio.

### Menú Fondos de pantalla recientes
Cambia rápidamente de fondo de pantalla desde el menú de la barra de menús. Los últimos 10 fondos de pantalla que has usado aparecen en la lista para acceder a ellos con un clic.

### Ajustes de reproducción: corregidos
Los ajustes de reproducción de Rendimiento (pausar, silenciar o detener cuando otras apps están activas) ahora funcionan correctamente con todos los tipos de fondos de pantalla.

### Navegador del Steam Workshop
Explora, busca y descarga fondos de pantalla directamente desde el Steam Workshop sin salir de la app.
- **Búsqueda y filtros**: busca por nombre y filtra por clasificación de contenido (Todos/Dudoso/Adulto), tipo (Escena/Vídeo/Web) y etiquetas de género
- **Opciones de ordenación**: Tendencias, Más recientes, Más populares, Más suscritos
- **Integración con steamcmd**: descarga automáticamente SteamCMD de Valve la primera vez que se necesita (no viene incluido); si encuentra un steamcmd existente (Homebrew, Steam o ruta personalizada), lo usa
- **Inicio de sesión en Steam**: admite la autenticación con contraseña, Steam Guard y sesión en caché
- **Descarga con progreso**: actualizaciones de estado en tiempo real durante la descarga (autenticando, porcentaje descargado, validando, copiando)
- **Valores predeterminados seguros**: la clasificación de contenido es «Todos» por omisión para filtrar el contenido para adultos

### Importación de archivos zip
Importa paquetes de fondos de pantalla directamente desde archivos `.zip`, sin tener que extraerlos antes a mano. Funciona mediante Archivo > Importar y arrastrando y soltando.

### Selección múltiple y anulación de suscripciones en bloque
Haz Cmd + clic para seleccionar varios fondos de pantalla y, después, haz clic con el botón derecho para anular todas las suscripciones a la vez.

### Aislamiento del almacenamiento de fondos de pantalla
Los fondos de pantalla se guardan ahora en `~/Documents/Open Wallpaper Engine/` en lugar de directamente en la carpeta Documentos, lo que evita fondos de pantalla con «error» al clonar el repositorio en un ordenador nuevo.

</details>

<details>
<summary>Primeros cambios respecto al proyecto original</summary>

### Fondos de pantalla web: corregida la visualización gris o en blanco
Los fondos de pantalla basados en WebGL se mostraban como rectángulos grises porque `WKWebView` bloqueaba el acceso a los archivos locales de texturas y recursos.

**Solución:** se han activado `allowFileAccessFromFileURLs` y `allowUniversalAccessFromFileURLs` en la configuración de WKWebView, lo que permite que los sombreadores WebGL carguen archivos de textura locales.

### Fondos de pantalla de escena: implementados desde cero
Los fondos de pantalla de escena (el tipo más habitual en el Steam Workshop) no estaban implementados en absoluto; solo mostraban «Hello, World!».

**La nueva implementación incluye:**
- **Analizador PKG**: lee el formato de archivo PKGV de Wallpaper Engine para extraer scene.json, modelos, materiales y texturas
- **Analizador TEX**: lee los contenedores de texturas TEXV0005, extrae los datos de imagen JPEG/PNG incrustados y lee los mipmaps DXT1/DXT3/DXT5
- **Descodificador del JSON de escena**: analiza scene.json con una descodificación flexible que gestiona los campos polimórficos de Wallpaper Engine (los valores pueden ser tipos simples u objetos `{"script":..,"value":..}`)
- **Renderizador Metal**: renderiza las capas de imagen de la escena con composición de texturas en la GPU y sienta las bases para futuros efectos de sombreador
- **Descodificación DXT en la GPU**: expande las texturas DXT1 (TEXI 7), DXT3 (TEXI 6) y DXT5 (TEXI 4) mediante un sombreador de cálculo de Metal al cargar la escena
- **Partículas de sprites**: renderiza los emisores de sprites `sphererandom` habituales con duración, tamaño, velocidad, alfa, color, rotación, velocidad angular, gravedad, resistencia y fundidos alfa aleatorios
- **Partículas avanzadas**: admite rotación, variación de color, turbulencia, puntos de control estáticos y vinculados al cursor, segmentos de cuerda conectados, estelas y animación de fotogramas de hojas de sprites `.tex-json`
- **Animación TEXS**: descodifica las líneas de tiempo TEXS0001/0002/0003, incluidos los rectángulos de fotograma en un único atlas y las secuencias de texturas de varias imágenes
- **Líneas de tiempo de escena**: interpola los fotogramas clave de alfa, origen, escala y ángulos de los objetos a 60 FPS
- **Entorno de ejecución de SceneScript**: evalúa expresiones y scripts de propiedad `export function update(value)` a partir del audio del sistema capturado con ScreenCaptureKit. La temporización de `thisScene`, `thisLayer.value`, `engine`, el cursor de entrada, `audio(low, high)`, una `fft(index)` real, la consulta de propiedades y las globales persistentes controlan las transformaciones de imagen, el alfa y las tasas de emisión de partículas.
- **Ciclo de vida persistente de SceneScript**: reutiliza los contextos de script por capa, llama a `init()` una vez y llama a `update()` en cada fotograma con un estado compartido de `dt`, fotograma, ratón, botones, teclas modificadoras, cursor, audio, FFT, propiedades y capas.
- **Operadores de partículas con script**: admite scripts para la tasa de emisión de partículas, la resistencia al movimiento y el momento del fundido alfa, con campos de partículas numéricos o de texto flexibles.
- **Seguimiento del ratón y paralaje**: aplica una traslación relativa al cursor y, opcionalmente, un escalado en perspectiva a las capas con metadatos `parallaxDepth` definidos; las partículas vinculadas al cursor usan el mismo cursor en el espacio de la escena.
- **Propiedades visuales con script**: admite brillo y color RGB de objetos, constantes de efectos de material, transformaciones escalares y vectoriales, y la sustitución de umbrales de efecto mediante scripts.
- **Propiedades de usuario**: muestra en la barra lateral de la escena los ajustes del proyecto documentados de tipo regulador, casilla, menú desplegable, texto y color, y pone los valores numéricos y booleanos a disposición de SceneScript
- **Efectos de escena integrados**: ejecuta en el renderizador Metal las entradas `pulse`, `shake`, `iris` y `waterwaves` del grafo de efectos
- **Efectos de material semánticos**: asigna a efectos nativos de Metal las constantes de material y los scripts habituales de brillo, contraste, saturación, exposición, gamma, tono, umbral de resplandor, resplandor y desenfoque
- **Traducción de sombreadores GLSL**: convierte durante la carga los sombreadores GLSL incluidos en los paquetes de Wallpaper Engine a SPIR-V y MSL con glslang y SPIRV-Cross, enlazados en la app; las variantes traducidas se almacenan en caché en `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants`
- **Previsualización de reserva**: recurre a preview.jpg/png/gif cuando no se pueden extraer las texturas

### Importación: corregida la importación de carpetas
El panel de importación ahora gestiona correctamente tanto las carpetas de fondos de pantalla individuales como los directorios superiores que contienen varios fondos de pantalla.

</details>

## Limitaciones actuales

- **Fondos de pantalla de aplicación**: los fondos de pantalla con `type: "application"` no son compatibles y no se ejecutan.
- **Funciones de SceneScript sin implementar**: `effect.executeMaterialFunction()`, `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `getVideoTexture()`, `engine.openUserShortcut()` todavía no hacen nada.
- **Paridad con SceneScript**: no se reproducen todos los nombres de eventos propietarios, callbacks de entrada, casos límite del ciclo de vida ni la semántica exacta de temporización.
- **Funciones de partículas poco comunes**: no se admiten formas de emisor distintas de esfera, caja e imagen de capa, ni los renderizadores posteriores al primero de un sistema.
- **Se necesitan los recursos de Wallpaper Engine**: las escenas necesitan los recursos de tu propia copia de Wallpaper Engine (Ajustes → Recursos); sin ellos solo se reproducen los fondos de vídeo y web.
- **Vídeos WebM**: el formato WebM (VP8/VP9) se reproduce a través de WebKit, por lo que los efectos de sincronización con la música no se aplican.
- **Algunas miniaturas JPEG**: un pequeño número de archivos TEXB de formato 1 contienen datos JPEG no estándar que macOS no puede descodificar.
- **Alcance de los ajustes de rendimiento**: las opciones de calidad, suavizado de contorno y posprocesado están pensadas para los fondos de pantalla de escena y tienen un efecto limitado en los fondos de pantalla de vídeo y web.
- **Las funciones de audio requieren permiso**: sin el permiso de Grabación de pantalla y del audio del sistema, los visualizadores de audio y los scripts de SceneScript que reaccionan al audio solo reciben silencio.

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
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

En Xcode, cambia el certificado de firma por el tuyo o selecciona «Sign to Run Locally» y, después, pulsa `Cmd + R` para compilar y ejecutar.

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

## Privacidad

Todo lo que guarda Open Wallpaper Engine se queda en tu Mac: tus ajustes, tu biblioteca, la caché y el inicio de sesión de SteamCMD. Open Wallpaper Engine no tiene servidor y no recopila datos ni analíticas. Solo se comunica con Valve: con Steam cuando usas el Workshop o instalas los recursos, y con el servidor de Valve para descargar SteamCMD. Los fondos de pantalla web pueden cargar su propio contenido en línea. Tu contraseña de Steam y tu código de Steam Guard van directamente a SteamCMD y nunca se guardan, se registran ni se envían a ningún otro sitio; solo se recuerda tu nombre de cuenta, para reutilizar el inicio de sesión guardado de SteamCMD.

## Estructura del proyecto

- `OpenWallpaperEngine/Services/SceneParsers/`: analizadores y modelos de PKG, TEX/TEXS y scene.json
- `OpenWallpaperEngine/Services/SceneEffects/`: catálogo dinámico de efectos e intervalos de los parámetros de efecto definidos por los autores
- `OpenWallpaperEngine/Scene/Shaders/`: traducción GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), almacenamiento en caché y el archivo de pipelines
- `Vendor/ShaderToolchain/`: código fuente de glslang y SPIRV-Cross, integrado en la app como paquete local
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift`: entorno de ejecución de SceneScript y vinculaciones de audio/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift`: captura del audio del sistema con ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal`: el renderizador de escenas Metal y la biblioteca de sombreadores
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift`: exploración del Steam Workshop y descargas
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift`: almacenamiento de la biblioteca, importación y conversión de paquetes
- `Scripts/fill-assets-cache.sh`: utilidad de desarrollo que copia los recursos de una instalación de Wallpaper Engine en una carpeta local o en la caché del almacenamiento de fondos de pantalla
- `Scripts/scene-api-coverage.py`: indica qué API de SceneScript usan los fondos de pantalla instalados en comparación con las que están implementadas
