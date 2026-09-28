Open Wallpaper Engine (com patches)
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | **Português (Brasil)** | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Um fork com patches do [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) para macOS, que adiciona a renderização de imagens de fundo de cena e correções para imagens de fundo web.

> **Observação:** este projeto NÃO tem nenhuma relação com o Wallpaper Engine comercial vendido no Steam. É um app de código aberto para macOS capaz de exibir os recursos de imagens de fundo da Oficina Steam do Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** guias e documentação estão na [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Projetos Relacionados

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — Uma interface gráfica em PyQt6 para o [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine), com integração à Oficina Steam e design de interface portado desta versão para macOS.

## Créditos

Este projeto foi construído sobre o trabalho de:

- **[MrWindDog](https://github.com/MrWindDog)** — Mantenedor do fork upstream [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac); adicionou novos recursos e refinamentos de interface
- **[Haren Chen](https://github.com/haren724)** — Criador original do [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac); construiu a arquitetura central do app (SwiftUI, reprodução de imagens de fundo de vídeo, sistema de importação, interface de playlist)
- **1ris_W** — Tradução para o chinês
- **[Klaus Zhu](https://github.com/klauszhu1105)** — Design original do logotipo
- **[Chen Chia Yang](https://github.com/Unayung)** — Renderização de imagens de fundo de cena, correções para imagens de fundo web, integração à Oficina Steam, suporte a várias telas, importação de zip
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Renderizador de cenas em Metal e pipeline de efeitos, tradução e cache de shaders GLSL→MSL, runtime do SceneScript, renderização sensível a áudio, reformulação da Oficina e dos Downloads, ajustes de posicionamento e de desempenho, redesenho do logotipo

Licenciado sob a [GPL-3.0](../../LICENSE), assim como o projeto original.

## O que a versão 0.9.0 suporta

### Renderização de cenas
- **Os próprios shaders do Wallpaper Engine** — camadas, efeitos e materiais agora são desenhados com os shaders originais de cada imagem de fundo, traduzidos para Metal, incluindo efeitos criados pelos próprios autores da Oficina.
- Camadas de composição, de tela cheia e de cor sólida, camadas que amostram outras camadas, todos os 33 modos de mesclagem e mais máscaras de efeito.
- **Layout de texto fiel** — o texto é dimensionado, alinhado e posicionado como no Wallpaper Engine, com efeitos de fonte de contorno, desfoque e sombra projetada.
- **Linhas do tempo** — animações de quadros-chave e de texturas seguem as regras do Wallpaper Engine para reprodução única, em loop e espelhada.
- Tabelas de consulta de cores, a correção de cor do Wallpaper Engine e as opções de filtro de imagem e de cor nas propriedades de uma imagem de fundo.
- Imagens com **Puppet Warp** animadas pelas suas animações, com física de ossos (molas, gravidade, limites) e objetos presos aos seus ossos.

### 3D e iluminação
- **Modelos 3D** com skinning, camadas de animação, morph targets e root motion.
- Câmeras de cena em perspectiva com trajetórias, transições e tremor; camadas 2D ficam em profundidade.
- **Luzes de cena** com cookies de luz, sombras, reflexos planares, névoa por distância e por altura, e luzes volumétricas.
- **HDR** — cenas HDR são renderizadas com o bloom HDR do Wallpaper Engine, e a qualidade "Ultra (HDR da Tela)" gera EDR nas telas capazes de exibi-lo.

### Partículas
- **Partículas na GPU** — todo sistema de partículas é simulado na GPU, em 3D, com pontos de controle 3D.
- Sistemas filhos, incluindo os disparados pelas partículas do sistema pai; rajadas de emissão, atrasos e emissão periódica; emissão a partir da imagem de uma camada.
- Colisão, inclusive com os ossos de um modelo, resposta ao áudio e rotação em todos os eixos.
- Ajustes de partículas vinculados às propriedades do usuário de uma imagem de fundo.

### SceneScript e mídia
- Um **runtime do SceneScript** completo — módulos, o modelo de objetos de cena/camada/efeito/material, eventos de animação, `localStorage` e detecção do cursor, com os scripts de cada imagem de fundo em sua própria thread.
- Scripts podem criar camadas, sistemas de partículas e sons, mover a névoa, controlar o bloom e posicionar marionetes e modelos.
- **Tocando Agora** — imagens de fundo de cena e web recebem a faixa atual e o estado de reprodução (macOS 15.4 ou posterior).
- Imagens de fundo web recebem suas propriedades do usuário e o áudio ao vivo.

### Áudio
- O espectro de áudio é calculado da mesma forma que o Wallpaper Engine o calcula, em estéreo.
- **Camadas de som** tocam no relógio da cena, com **som espacial** posicionado como no Wallpaper Engine.

### Telas e reprodução
- **Pausar por Tela** ou **Pausar Todas**, com as regras de reprodução avaliadas para cada tela, incluindo a regra do Wallpaper Engine para janelas maximizadas.
- Propriedades do usuário por tela, com "Sincronizar propriedades entre as telas".
- Uma imagem de fundo exibida em várias telas é renderizada uma única vez e apresentada em cada uma.
- Novos ajustes de qualidade: Resolução de Renderização, Resolução das Texturas, detalhe de cena conforme a tela, reflexos, sombras e volumétricos.
- **Reinício seguro** — uma imagem de fundo que travou ou fez o app falhar é ignorada na próxima abertura e marcada na biblioteca.

### Oficina e biblioteca
- Os filtros da Oficina do Wallpaper Engine: Mostrar Apenas, um filtro de resolução, gêneros combinados com E/OU e tags em cada cartão.
- Imagens de fundo instaladas mostram suas tags da Oficina e podem ser filtradas por elas; itens que são apenas recursos ou dependências ficam fora de Instaladas.
- Dependências da Oficina que faltam são baixadas automaticamente, e as que não são mais usadas são removidas após uma exclusão. Todo download vai para a pasta Armazenamento de Imagens de Fundo.
- **Redefinir** em Detalhes devolve as propriedades de uma imagem de fundo, e suas edições no Inspetor de Cena, aos padrões definidos pelo autor.
- Condições de propriedades, linhas de texto e formatos de controles deslizantes definidos nos ajustes da imagem de fundo são respeitados.
- Senhas da Steam nunca são armazenadas, e a chave da API Web da Steam fica nas Chaves.

### Interface e idiomas
- **Liquid Glass** no macOS 26 — uma visualização dividida nativa com barra de ferramentas, inspetor e controles de vidro. Versões anteriores do macOS mantêm a aparência de sempre.
- **15 novos idiomas**: alemão, francês, espanhol, português do Brasil, italiano, japonês, coreano, chinês simplificado e tradicional, russo, polonês, turco, ucraniano, árabe e hindi, escolhidos no seletor de idioma dos ajustes.
- Um novo ícone do app e um ícone da barra de menus que acompanha a aparência da barra de menus.

<details>
<summary>Anteriormente na versão 0.8.1</summary>

### Reprodução de imagens de fundo
- **Imagens de fundo de cena** renderizadas nativamente com Metal — camadas de imagem, transformações, linhas do tempo com quadros-chave, ordenação por profundidade e dados de câmera/projeção do `scene.json`.
- **Imagens de fundo de vídeo** (`.mp4`, `.webm`) com taxa de reprodução, volume, vinculação da velocidade de áudio/vídeo e, opcionalmente, zoom/inclinação/saturação sincronizados com a música.
- **Imagens de fundo web** (HTML/WebGL) com acesso a arquivos locais ativado, para que texturas e recursos WebGL sejam carregados corretamente, além de conteúdo externo incorporado (YouTube/Vimeo).
- **Modos de posicionamento** — Preencher Tela, Ajustar à Tela, Centralizar, Estender e Preencher Tela, Zoom.
- **Várias telas** — uma imagem de fundo diferente por monitor, ativação/desativação por tela, layout visual dos monitores e detecção automática de telas recém-conectadas.
- **Várias mesas (Spaces)** — reprodução contínua em todas as mesas, incluindo a opção de atribuição `Todas as Mesas`.
- **Regras de reprodução** — continuar executando, silenciar, pausar ou parar quando outro app estiver em primeiro plano; comportamento correto ao repousar/despertar e ao alternar entre mesas.

### Suporte ao formato de cena
- **Parser de PKG** para arquivos `PKGV` do Wallpaper Engine (scene.json, materiais, texturas, shaders).
- **Parser de TEX** para contêineres `TEXV0005`: JPEG/PNG incorporados e DXT1/DXT3/DXT5 com mipmaps decodificados na GPU por meio de um shader de computação Metal.
- **Linhas do tempo de sprites TEXS** (0001/0002/0003), incluindo retângulos de quadros em um único atlas e sequências de várias imagens.
- **Decodificação flexível do scene.json**, que lida com os campos polimórficos do Wallpaper Engine (valores simples ou `{"script":…,"value":…}`).
- **Recurso de pré-visualização** que usa `preview.jpg/png/gif` quando não é possível extrair as texturas.

### Efeitos e shaders
- **~48 efeitos nativos em Metal**, abrangendo distorção, desfoque (padrão/preciso/radial/de movimento), bloom, raios crepusculares e feixes de luz, ondas/ondulações/cáusticas/fluxo de água, nuvens e neblina, granulação de filme, glitch/VHS, aberração cromática, chave de cor, transformação/inclinação/giro/torção/perspectiva, reflexo, refração, brilho/cintilação/purpurina, detecção de bordas e muito mais.
- **Efeitos sensíveis a áudio** — pulso, barras de áudio, mudança de matiz sincronizada com o áudio e hyperdrive, controlados por dados de espectro do áudio do sistema em tempo real.
- **Efeitos semânticos de material** — brilho, contraste, saturação, exposição, gama, matiz, limiar de bloom, bloom e desfoque mapeados para passes nativos em Metal.
- **Tradução GLSL → SPIR-V → MSL** no momento do carregamento pelo glslang e pelo SPIRV-Cross, vinculados ao app, com defines COMBO, resolução de includes e renumeração dos slots de buffer do Metal.
- **Cache de shaders pré-compilados** — os arquivos `.metal` traduzidos, os `.metallib` compilados e os arquivos auxiliares `.reflection.json` ficam em cache em `.open-wallpaper-engine/shaders`, controlados por hash para que apenas os shaders alterados sejam traduzidos novamente, e são compilados em segundo plano para que a renderização nunca seja bloqueada.
- **Catálogo dinâmico de efeitos** lido dos manifestos `assets/effects/*/effect.json` do Wallpaper Engine, incluindo efeitos de vários passes e vinculações de uniforms obtidas por reflexão.
- **Máscaras de efeito** (até 4 texturas de máscara por camada), mesclagem aditiva e alfa e um sistema de destinos de renderização em pool.

### Partículas
- Emissores de sprites com tempo de vida, tamanho, velocidade, cor, rotação, velocidade angular, gravidade, arrasto e desvanecimento alfa aleatórios.
- Comportamento avançado — turbulência, atratores, movimento de vórtice e de boids, pontos de controle estáticos e vinculados ao cursor, segmentos de corda conectados e rastros com desvanecimento de alfa/tamanho.
- Animação de quadros de spritesheet por meio de sequências `.tex-json`.
- Operadores com script para taxa de emissão, arrasto e tempo de desvanecimento alfa.

### Runtime do SceneScript
- Contextos de script persistentes por camada, com `init()` chamado uma vez e `update(value)` chamado a cada quadro.
- Globais: `thisScene`, `thisLayer`, `engine`, `input`, `audio(low, high)`, `fft(index)` real, `setTimeout`/`setInterval` e globais de script persistentes.
- Biblioteca matemática completa `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4`, além dos auxiliares `WEMath`, `WEVector` e `WEColor`.
- Módulos JS do runtime do Wallpaper Engine carregados de `assets/scripts/jsmodules` e `jsclasses`.
- Eventos do cursor (`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`) e `resizeScreen`.
- Os scripts podem controlar alfa, origem, tamanho, escala, ângulos, brilho/cor da camada, constantes de material, limiares de efeitos e taxas de partículas.
- Registro de exceções de script sem duplicatas, com contagem de repetições.

### Áudio
- Captura do áudio do sistema via ScreenCaptureKit, que alimenta um espectro suavizado de 16 bandas, a forma de onda e os níveis de graves/médios/agudos.
- **Sincronização com a música** por propriedade — qualquer propriedade do usuário pode ser modulada pelo nível do áudio, com intensidade configurável.

### Propriedades do usuário e Inspetor
- Ajustes de projeto de controle deslizante, caixa de seleção, combo, texto e cor expostos na barra lateral da cena, aplicados em tempo real e legíveis pelo SceneScript.
- Rastreamento do mouse e paralaxe para camadas com `parallaxDepth` definido pelo autor.

### Oficina Steam
- Explore, busque e filtre por classificação de conteúdo, tipo e tags de gênero, com ordenação Em Alta / Mais Recentes / Mais Populares / Mais Inscritos e paginação numerada.
- Janelas de pré-visualização com controles para definir a imagem de fundo, reprodução e volume, apoiadas por um cache limitado; as pré-visualizações aplicadas são promovidas à biblioteca sem baixar novamente.
- Integração com o SteamCMD com detecção automática, início de sessão com senha / Steam Guard / sessão em cache, uma aba Downloads dedicada, downloads em fila que podem ser repetidos e progresso em tempo real.
- Seleção múltipla, seleção de intervalo, downloads e remoções em lote mediante confirmação, IDs baixados persistentes e ordenação por `Data do Download`.

### Biblioteca e ajustes
- Importação de pastas, de pacotes `.zip` ou por arrastar e soltar.
- Local de armazenamento das imagens de fundo configurável, com migração de uma biblioteca existente.
- Menu de imagens de fundo recentes na barra de status.
- Ajustes de desempenho — qualidade, suavização, pós-processamento e comportamento de reprodução ao perder o foco.
- Diagnóstico — o caminho dos recursos incluídos, as versões das bibliotecas do compilador de shaders integrado e as estatísticas do cache de shaders.

</details>

<details>
<summary>Anteriormente na versão 0.8.0</summary>

### Suporte a Várias Telas
Atribua imagens de fundo diferentes a cada monitor conectado, com controle de ativação/desativação por tela.
- **Painel Ajustes de Tela** — Layout visual que mostra todas as telas conectadas; clique para selecionar
- **Imagem de fundo por tela** — Cada tela pode exibir uma imagem de fundo diferente, de forma independente
- **Botão de ativar/desativar** — Ative ou desative a imagem de fundo em cada monitor
- **Detecção automática** — Novos monitores são detectados e ativados automaticamente ao serem conectados

### Suporte a Várias Mesas
As imagens de fundo agora são exibidas em todas as mesas do macOS (Spaces) com reprodução contínua — sem interrupção ao alternar entre mesas.

### Menu de Imagens de Fundo Recentes
Troque rapidamente de imagem de fundo pelo menu da barra de status. As 10 últimas imagens de fundo usadas são listadas para acesso com um clique.

### Ajustes de Reprodução — Corrigidos
Os ajustes de reprodução de desempenho (pausar/silenciar/parar quando outros apps estão em primeiro plano) agora funcionam corretamente para todos os tipos de imagem de fundo.

### Navegador da Oficina Steam
Explore, busque e baixe imagens de fundo diretamente da Oficina Steam sem sair do app.
- **Busca e filtros** — Busque pelo nome e filtre por classificação de conteúdo (Livre/Questionável/Adulto), tipo (Cena/Vídeo/Web) e tags de gênero
- **Opções de ordenação** — Em Alta, Mais Recentes, Mais Populares, Mais Inscritos
- **Integração com o steamcmd** — Baixa automaticamente o SteamCMD da Valve na primeira vez que ele é necessário (não vem incluído); um steamcmd existente (Homebrew, Steam ou caminho personalizado) é usado se for encontrado
- **Início de sessão no Steam** — Suporta autenticação por senha, Steam Guard e sessão em cache
- **Download com progresso** — Atualizações de status em tempo real durante o download (autenticando, % baixado, validando, copiando)
- **Padrões seguros** — A classificação de conteúdo é "Livre" por padrão, para filtrar conteúdo adulto

### Importação de Zip
Importe pacotes de imagens de fundo diretamente de arquivos `.zip` — não é preciso extraí-los manualmente antes. Funciona por meio de Arquivo > Importar e de arrastar e soltar.

### Seleção Múltipla e Cancelamento de Inscrição em Lote
Pressione Cmd e clique para selecionar várias imagens de fundo e, em seguida, clique com o botão direito para cancelar a inscrição em lote.

### Isolamento do Armazenamento de Imagens de Fundo
As imagens de fundo agora são armazenadas em `~/Documents/Open Wallpaper Engine/` em vez de diretamente no diretório Documentos, o que evita imagens de fundo com "erro" ao clonar o repositório em uma máquina nova.

</details>

<details>
<summary>O que foi corrigido em relação ao upstream</summary>

### Imagens de Fundo Web — Corrigida a renderização cinza/em branco
Imagens de fundo baseadas em WebGL eram renderizadas como retângulos cinza porque o `WKWebView` bloqueava o acesso a arquivos locais para texturas e recursos.

**Correção:** `allowFileAccessFromFileURLs` e `allowUniversalAccessFromFileURLs` foram ativados na configuração do WKWebView, permitindo que os shaders WebGL carreguem arquivos de textura locais.

### Imagens de Fundo de Cena — Implementadas do zero
As imagens de fundo de cena (o tipo mais comum na Oficina Steam) não estavam implementadas — exibiam apenas "Hello, World!".

**A nova implementação inclui:**
- **Parser de PKG** — Lê o formato de arquivo PKGV do Wallpaper Engine para extrair scene.json, modelos, materiais e texturas
- **Parser de TEX** — Lê contêineres de textura TEXV0005, extrai dados de imagem JPEG/PNG incorporados e lê mipmaps DXT1/DXT3/DXT5
- **Decodificador do JSON de cena** — Analisa o scene.json com decodificação flexível que lida com os campos polimórficos do Wallpaper Engine (os valores podem ser tipos simples ou objetos `{"script":..,"value":..}`)
- **Renderizador Metal** — Renderiza as camadas de imagem da cena com composição de texturas na GPU e uma base para futuros efeitos de shader
- **Decodificação DXT na GPU** — Expande texturas DXT1 (TEXI 7), DXT3 (TEXI 6) e DXT5 (TEXI 4) por meio de um shader de computação Metal quando a cena é carregada
- **Partículas de sprite** — Renderiza emissores de sprites `sphererandom` comuns com tempo de vida, tamanho, velocidade, alfa, cor, rotação, velocidade angular, gravidade, arrasto e desvanecimento alfa aleatórios
- **Partículas avançadas** — Suporta rotação, variação de cor, turbulência, pontos de controle estáticos e vinculados ao cursor, segmentos de corda conectados, rastros e animação de quadros de spritesheet `.tex-json`
- **Animação TEXS** — Decodifica linhas do tempo TEXS0001/0002/0003, incluindo retângulos de quadros em um único atlas e sequências de texturas de várias imagens
- **Linhas do tempo da cena** — Interpola quadros-chave de alfa, origem, escala e ângulos dos objetos a 60 FPS
- **Runtime do SceneScript** — Avalia scripts de propriedade de expressão e `export function update(value)` com base no áudio do sistema obtido pelo ScreenCaptureKit. A temporização de `thisScene`, `thisLayer.value`, `engine`, o cursor de entrada, `audio(low, high)`, `fft(index)` real, a consulta de propriedades e as globais persistentes controlam as transformações de imagem, o alfa e as taxas de emissão de partículas.
- **Ciclo de vida persistente do SceneScript** — Reutiliza contextos de script por camada, chama `init()` uma vez e chama `update()` ao longo dos quadros com estado compartilhado de `dt`, quadro, mouse, botão, modificador, cursor, áudio, FFT, propriedades e camada.
- **Operadores de partículas com script** — Suporta scripts para a taxa de emissão de partículas, o arrasto do movimento e o tempo de desvanecimento alfa, com campos de partícula numéricos/de string flexíveis.
- **Rastreamento do mouse e paralaxe** — Aplica translação relativa ao cursor e escala de perspectiva opcional às camadas com metadados `parallaxDepth` definidos pelo autor; as partículas vinculadas ao cursor usam o mesmo cursor no espaço da cena.
- **Propriedades visuais com script** — Suporta brilho/cor RGB de objetos, constantes de efeitos de material, transformações escalares/vetoriais e substituições de limiar de efeitos definidos por script.
- **Propriedades do usuário** — Expõe os ajustes de projeto documentados de controle deslizante, caixa de seleção, combo, texto e cor na barra lateral da cena e disponibiliza os valores numéricos e booleanos para o SceneScript
- **Efeitos de cena integrados** — Executa as entradas de grafo de efeitos `pulse`, `shake`, `iris` e `waterwaves` definidas pelo autor no renderizador Metal
- **Efeitos semânticos de material** — Mapeia constantes de material e scripts comuns de brilho, contraste, saturação, exposição, gama, matiz, limiar de bloom, bloom e desfoque para efeitos nativos em Metal
- **Tradução de shaders GLSL** — Converte os shaders GLSL empacotados do Wallpaper Engine em SPIR-V e MSL no momento do carregamento com o glslang e o SPIRV-Cross vinculados ao app; as variantes traduzidas ficam em cache em `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants`
- **Recurso de pré-visualização** — Usa preview.jpg/png/gif quando não é possível extrair as texturas

### Importação — Corrigida a importação de pastas
O painel de importação agora lida corretamente tanto com pastas individuais de imagens de fundo quanto com diretórios pai que contêm várias imagens de fundo.

</details>

## Limitações Atuais

- **Imagens de fundo de aplicativo** — As imagens de fundo `type: "application"` não são suportadas e não serão executadas.
- **Funções do SceneScript não implementadas** — `effect.executeMaterialFunction()`, `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `getVideoTexture()`, `engine.openUserShortcut()` ainda não fazem nada.
- **Paridade do SceneScript** — Nem todos os nomes de eventos proprietários, callbacks de entrada, casos extremos do ciclo de vida ou semânticas exatas de temporização são reproduzidos.
- **Recursos de partículas raros** — Formatos de emissor além de esfera, caixa e imagem de camada, e renderizadores após o primeiro de um sistema, não são suportados.
- **Recursos do Wallpaper Engine necessários** — As cenas precisam dos recursos da sua própria cópia do Wallpaper Engine (Ajustes → Recursos); sem eles, só as imagens de fundo de vídeo e web funcionam.
- **Vídeos WebM** — WebM (VP8/VP9) é reproduzido pelo WebKit, então os efeitos de sincronização com a música não se aplicam.
- **Algumas miniaturas JPEG** — Um pequeno número de arquivos TEXB de formato 1 contém dados JPEG fora do padrão que o macOS não consegue decodificar.
- **Escopo dos ajustes de desempenho** — As opções de qualidade, suavização e pós-processamento foram projetadas para imagens de fundo de cena e têm efeito limitado em imagens de fundo de vídeo e web.
- **Os recursos de áudio exigem permissão** — Sem a permissão de Gravação do Áudio do Sistema e da Tela, os visualizadores de áudio e o SceneScript sensível a áudio recebem silêncio.

## Tipos de Imagem de Fundo Suportados

| Tipo | Status |
|------|--------|
| Vídeo (.mp4, .webm) | Funciona |
| Web (HTML/WebGL) | Funciona |
| Cena — camadas de imagem e linhas do tempo | Funciona (Metal) |
| Cena — texturas DXT1/DXT3/DXT5 | Funciona (decodificação na GPU com Metal) |
| Cena — sprites TEXS / linhas do tempo de alfa | Funciona |
| Cena — partículas de sprite | Funciona |
| Cena — partículas avançadas | Parcial (consulte Limitações) |
| Cena — efeitos do Wallpaper Engine e do Workshop (os próprios shaders do WE) | Funciona |
| Cena — SceneScript | Parcial (consulte Limitações) |
| Cena — modelos 3D / rigging / puppet warp | Funciona |
| Aplicativo | Não suportado |

## Requisitos

### Obrigatório
- **macOS 14.0 ou posterior** (Sonoma). A captura de áudio do ScreenCaptureKit e a renderização de cenas em Metal dependem dele.

### Opcional — necessário para recursos específicos

| Recurso | Requisito | Instalação |
|---------|-------------|---------|
| Explorar / baixar da Oficina Steam | `steamcmd` | Automático (opcional: `brew install steamcmd`) |
| Visualizadores de áudio e SceneScript sensível a áudio | Permissão de Gravação do Áudio do Sistema e da Tela | Ajustes → Permissões |

#### Shaders

O Wallpaper Engine fornece seus efeitos em GLSL. Eles são traduzidos para Metal (GLSL → SPIR-V → MSL) pelo glslang e pelo SPIRV-Cross, integrados ao app (`Vendor/ShaderToolchain`), na primeira vez que uma imagem de fundo os usa, e depois ficam em cache no disco. Não é preciso instalar nada. Um shader cuja tradução travou o app, ou o fez encerrar inesperadamente duas vezes, é ignorado nas aberturas seguintes, e todos os outros shaders continuam sendo traduzidos.

#### Recursos do Wallpaper Engine

As cenas usam os efeitos, materiais, shaders, fontes e o runtime do SceneScript compartilhados da sua própria cópia do Wallpaper Engine no Steam; o app não os inclui. Instale-os em *Ajustes → Recursos*: o app baixa sua cópia com o steamcmd (a conta precisa ter o Wallpaper Engine), mantém apenas os recursos e as imagens de fundo padrão e apaga o resto. Você também pode escolher uma pasta existente do Wallpaper Engine. Imagens de fundo de vídeo e web funcionam sem eles.

## Compilar a partir do Código-Fonte

### Pré-requisitos
- macOS >= 14.0
- Xcode >= 26.3 (SDK do macOS 26)
- Ferramentas de Linha de Comando do Xcode

### Etapas
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

No Xcode, altere o certificado de assinatura para o seu ou selecione "Sign to Run Locally" e pressione `Cmd + R` para compilar e executar.

## Uso

### Explorar e Baixar da Oficina Steam

1. Nada para instalar: o app baixa o SteamCMD da Valve em segundo plano na primeira vez que ele é necessário (da Valve, não vem incluído). O Homebrew (`brew install steamcmd`) é opcional; um steamcmd existente (Homebrew, Steam ou um que você escolher) é usado se for encontrado
2. Vá para a aba **Oficina** e inicie sessão com a sua conta Steam (é preciso ter o Wallpaper Engine)
3. Digite uma [Chave de API Web do Steam](https://steamcommunity.com/dev/apikey) quando solicitado, ou em *Ajustes → Geral*. Ela é verificada com o Steam e guardada nas suas Chaves; a sua senha do Steam nunca é armazenada (o steamcmd reutiliza a própria sessão em cache)
4. Busque, filtre e clique em **Baixar** em qualquer imagem de fundo

### Importar de Arquivos Locais

- **Pasta:** Arquivo > Importar > Imagem de Fundo de uma Pasta — selecione pastas de imagens de fundo que contenham `project.json`
- **Zip:** Arquivo > Importar ou arraste e solte um arquivo `.zip` que contenha pacotes de imagens de fundo
- **Manual:** Copie as pastas de imagens de fundo diretamente para `~/Documents/Open Wallpaper Engine/`

## Privacidade

Tudo o que o Open Wallpaper Engine salva fica no seu Mac: seus ajustes, sua biblioteca, o cache e o login do SteamCMD. O Open Wallpaper Engine não tem servidor e não coleta dados nem análises. Ele só se comunica com a Valve: com a Steam quando você usa a Oficina ou instala os recursos, e com o servidor da Valve para baixar o SteamCMD. Papéis de parede web podem carregar seu próprio conteúdo online. Sua senha da Steam e seu código do Steam Guard vão direto para o SteamCMD e nunca são salvos, registrados ou enviados para nenhum outro lugar; só o nome da sua conta é lembrado, para reutilizar o login salvo do SteamCMD.

## Estrutura do Projeto

- `OpenWallpaperEngine/Services/SceneParsers/` — parsers e modelos de PKG, TEX/TEXS e scene.json
- `OpenWallpaperEngine/Services/SceneEffects/` — catálogo dinâmico de efeitos e intervalos dos parâmetros de efeitos definidos pelo autor
- `OpenWallpaperEngine/Scene/Shaders/` — tradução GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), cache e o arquivo de pipelines
- `Vendor/ShaderToolchain/` — fontes do glslang e do SPIRV-Cross, integradas ao app como um pacote local
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift` — runtime do SceneScript e vinculações de áudio/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — captura do áudio do sistema com o ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — o renderizador de cenas em Metal e a biblioteca de shaders
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — navegação e downloads da Oficina Steam
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — armazenamento da biblioteca, importação e conversão de pacotes
- `Scripts/fill-assets-cache.sh` — ferramenta de desenvolvimento: copia os recursos de uma instalação do Wallpaper Engine para uma pasta local ou para o cache do armazenamento de imagens de fundo
- `Scripts/scene-api-coverage.py` — informa quais APIs do SceneScript as imagens de fundo instaladas usam em comparação com o que está implementado
