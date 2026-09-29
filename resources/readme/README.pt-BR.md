Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | **Português (Brasil)** | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

O Open Wallpaper Engine é um player gratuito e de código aberto para macOS de imagens de fundo do Wallpaper Engine: cena, vídeo e web. Ele tem um renderizador nativo em Metal e suporta efeitos, partículas, modelos 3D, iluminação, SceneScript, visuais reativos ao áudio e o Steam Workshop. Começou como um fork do [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) de Haren Chen e MrWindDog e, desde então, foi em grande parte reescrito.

> **Observação:** este projeto NÃO tem nenhuma relação com o Wallpaper Engine comercial vendido no Steam. É um app de código aberto para macOS capaz de exibir os recursos de imagens de fundo da Oficina Steam do Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** guias e documentação estão na [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

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
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

No Xcode, altere o certificado de assinatura para o seu ou selecione "Sign to Run Locally" e pressione `Cmd + R` para compilar e executar.

A primeira compilação a partir do código-fonte baixa o pacote Swift Sparkle. Compilações a partir do código-fonte não procuram atualizações.

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

## O que a versão 1.0.0 suporta

### Configuração, biblioteca e atualizações
- **Assistente de configuração** — na primeira abertura, algumas etapas opcionais escolhem o idioma, mostram as notas de privacidade, configuram o SteamCMD, o login da Steam e uma chave opcional da Steam Web API, instalam os recursos do Wallpaper Engine e trazem seus papéis de parede.
- **O SteamCMD se configura sozinho** — se nenhum for encontrado, o app baixa o SteamCMD da Valve; o do Homebrew ou da Steam é usado se existir.
- **Recursos do Wallpaper Engine da sua própria cópia na Steam** — instalados pelo SteamCMD após o login, opcionalmente com os papéis de parede padrão do Wallpaper Engine.
- **Importações** — suas coleções e inscrições da Oficina (pela Web API da Steam), os itens da Oficina de uma biblioteca Steam existente e pastas de papéis de parede.
- **A [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)** — guias, referência dos ajustes e solução de problemas; "Suporte e FAQ" no app a abre.
- **Atualizações automáticas** — atualizações assinadas se instalam sozinhas (ao sair, após 10 minutos longe do Mac ou em até um dia, e uma reabertura rápida restaura seus papéis de parede). Em Ajustes › Geral › Atualizações você pode só procurar, desativar a busca e receber versões beta. "Procurar Atualizações…" fica no menu do app e no menu da barra de menus.

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

## Limitações Atuais

- **Funções do SceneScript não implementadas** — `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()` ainda não fazem nada.
- **Paridade do SceneScript** — Nem todos os nomes de eventos proprietários, callbacks de entrada, casos extremos do ciclo de vida ou semânticas exatas de temporização são reproduzidos.
- **Recursos de partículas raros** — Formatos de emissor além de esfera, caixa e imagem de camada, e renderizadores após o primeiro de um sistema, não são suportados.
- **Vídeos WebM** — WebM (VP8/VP9) é reproduzido pelo WebKit, então os efeitos de sincronização com a música não se aplicam.
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

## Privacidade

Tudo o que o Open Wallpaper Engine salva fica no seu Mac: seus ajustes, sua biblioteca, o cache e o login do SteamCMD. O Open Wallpaper Engine não tem servidor e não coleta dados nem análises. Ele se comunica com a Valve (com a Steam quando você usa a Oficina ou instala os recursos, e com o servidor da Valve para baixar o SteamCMD) e com o GitHub, para procurar atualizações do app (o appcast no GitHub Pages) e baixá-las do GitHub Releases, sem enviar nenhum dado pessoal. A busca por atualizações pode ser desativada em Ajustes › Geral. Papéis de parede web podem carregar seu próprio conteúdo online. Sua senha da Steam e seu código do Steam Guard vão direto para o SteamCMD e nunca são salvos, registrados ou enviados para nenhum outro lugar; só o nome da sua conta é lembrado, para reutilizar o login salvo do SteamCMD.

## Estrutura do Projeto

- `OpenWallpaperEngine/Scene/Format/` — parsers e modelos de PKG, TEX/TEXS e scene.json
- `OpenWallpaperEngine/Scene/Shaders/` — tradução GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), cache e o arquivo de pipelines
- `Vendor/ShaderToolchain/` — fontes do glslang e do SPIRV-Cross, integradas ao app como um pacote local
- `OpenWallpaperEngine/Scene/Scripting/` — runtime do SceneScript e vinculações de áudio/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — captura do áudio do sistema com o ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — o renderizador de cenas em Metal e a biblioteca de shaders
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — navegação e downloads da Oficina Steam
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — armazenamento da biblioteca, importação e conversão de pacotes
- `Scripts/fill-assets-cache.sh` — ferramenta de desenvolvimento: copia os recursos de uma instalação do Wallpaper Engine para uma pasta local ou para o cache do armazenamento de imagens de fundo
- `Scripts/scene-api-coverage.py` — informa quais APIs do SceneScript as imagens de fundo instaladas usam em comparação com o que está implementado

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
