Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | **简体中文** | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine 是一款免费、开源的 macOS 播放器，可播放 Wallpaper Engine 的场景、视频和网页墙纸。它采用原生 Metal 渲染器，支持特效、粒子、3D 模型、光照、SceneScript、音频响应视觉效果以及 Steam 创意工坊。本项目最初是 Haren Chen 与 MrWindDog 的 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 的分支，此后已大部分重写。

> **注：** 本项目与 Steam 上的商业软件 Wallpaper Engine 没有任何关联。这是一款开源的 macOS App，可显示来自 Wallpaper Engine Steam 创意工坊的墙纸素材。 → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki：** 指南和文档见 [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)。

## 系统要求

### 必需
- **macOS 14.0 或更高版本**（Sonoma）。ScreenCaptureKit 音频捕获和 Metal 场景渲染都依赖于此。

### 可选 — 特定功能所需

| 功能 | 要求 | 安装 |
|---------|-------------|---------|
| 浏览／下载 Steam 创意工坊内容 | `steamcmd` | 自动（可选：`brew install steamcmd`） |
| 音频可视化与音频响应的 SceneScript | 录屏权限 | 设置 → 权限 |

#### 着色器

Wallpaper Engine 以 GLSL 形式提供其效果。当墙纸首次使用这些效果时，它们会由内置于 App 中的 glslang 和 SPIRV-Cross（`Vendor/ShaderToolchain`）转换为 Metal（GLSL → SPIR-V → MSL），随后缓存到磁盘上。无需安装任何内容。如果某个着色器在转换时导致 App 挂起或两次崩溃，之后启动时会跳过它，其他着色器仍会照常转换。

#### Wallpaper Engine 素材

场景使用你在 Steam 上的 Wallpaper Engine 副本中的共享效果、材质、着色器、字体和 SceneScript 运行时；App 不附带这些资源。请在“设置 → 资源”中安装：App 会用 steamcmd 下载你的副本（该账户必须拥有 Wallpaper Engine），仅保留资源和默认墙纸，其余部分会被删除。你也可以选择现有的 Wallpaper Engine 文件夹。视频和网页墙纸无需这些资源即可使用。

## 从源代码构建

### 前提条件
- macOS >= 14.0
- Xcode >= 26.3（macOS 26 SDK）
- Xcode Command Line Tools

### 步骤
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

在 Xcode 中，将签名证书更改为你自己的证书或选择“Sign to Run Locally”，然后按下 `Cmd + R` 进行构建并运行。

从源代码首次构建时会获取 Sparkle Swift 包。从源代码构建的版本不会检查更新。

## 使用方法

### 从 Steam 创意工坊浏览与下载

1. 无需安装：首次需要时，App 会在后台自动下载 Valve 的 SteamCMD（从 Valve 下载，不随 App 附带）。Homebrew（`brew install steamcmd`）为可选；如找到已有的 steamcmd（Homebrew、Steam 或你指定的）则直接使用
2. 切换到 **创意工坊** 标签页，并使用 Steam 账户登录（必须拥有 Wallpaper Engine）
3. 在出现提示时，或在 *设置 → 通用* 中输入 [Steam Web API 密钥](https://steamcommunity.com/dev/apikey)。密钥会经过 Steam 验证并保存在你的钥匙串中；你的 Steam 密码永远不会被存储（steamcmd 会复用它自己的缓存会话）
4. 搜索、筛选，然后在任意墙纸上点按 **下载**

### 从本地文件导入

- **文件夹：** 文件 > 导入 > 来自文件夹的墙纸 — 选择包含 `project.json` 的墙纸文件夹
- **zip：** 文件 > 导入，或拖放包含墙纸包的 `.zip` 文件
- **手动：** 将墙纸文件夹直接拷贝到 `~/Documents/Open Wallpaper Engine/`

## 1.0.0 支持的功能

### 设置、资源库与更新
- **设置助理**——首次启动时，几个可跳过的步骤会选择语言、说明隐私、设置 SteamCMD、Steam 登录和可选的 Steam Web API 密钥、安装 Wallpaper Engine 素材并导入你的壁纸。
- **SteamCMD 自动设置**——找不到时，App 会下载 Valve 的 SteamCMD；若已有 Homebrew 或 Steam 的版本则直接使用。
- **来自你自己 Steam 副本的 Wallpaper Engine 素材**——登录后通过 SteamCMD 安装，可选同时加入 Wallpaper Engine 的默认壁纸。
- **导入**——你的创意工坊合集和订阅（通过 Steam Web API）、现有 Steam 库中的创意工坊项目，以及壁纸文件夹。
- **[wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)**——指南、设置参考和疑难解答；App 中的“支持与常见问题”会打开它。
- **自动更新**——已签名的更新会自动安装（退出时、离开 Mac 10 分钟后或一天之内，随后快速重新启动并恢复你的壁纸）。在“设置 › 通用 › 更新”中可以只检查、关闭检查或接收测试版更新。“检查更新…”位于 App 菜单和菜单栏菜单中。

### 场景渲染
- **Wallpaper Engine 自己的着色器** — 图层、效果和材质现在用每张墙纸的原始着色器绘制，并翻译为 Metal，包括创意工坊作者自己制作的效果。
- 合成、全屏和纯色图层，采样其他图层的图层，全部 33 种混合模式，以及更多效果遮罩。
- **忠实的文本排版** — 文本的大小、对齐和位置与 Wallpaper Engine 一致，并支持描边、模糊和投影字体效果。
- **时间线** — 关键帧和纹理动画遵循 Wallpaper Engine 的单次、循环和镜像播放规则。
- 颜色查找表、Wallpaper Engine 的色彩校正，以及墙纸属性中的图像滤镜和颜色选项。
- 由自身动画驱动的 **Puppet Warp** 图像，支持骨骼物理（弹簧、重力、限制）以及挂在骨骼上的对象。

### 3D 与光照
- 支持蒙皮、动画图层、变形目标和根运动的 **3D 模型**。
- 支持相机路径、淡入淡出和抖动的透视场景相机；2D 图层也位于深度之中。
- 支持光照 Cookie、阴影、平面反射、距离雾和高度雾以及体积光的**场景光源**。
- **HDR** — HDR 场景使用 Wallpaper Engine 的 HDR 泛光渲染，“超高（显示器 HDR）”画质会在能够显示 EDR 的显示器上输出 EDR。

### 粒子
- **GPU 粒子** — 所有粒子系统都在 GPU 上以 3D 模拟，并支持 3D 控制点。
- 子系统（包括由父系统粒子触发的子系统）、发射器爆发、延迟和周期性发射，以及从图层图像发射。
- 碰撞（包括与模型骨骼的碰撞）、音频响应，以及绕任意轴的旋转。
- 与墙纸用户属性绑定的粒子设置。

### SceneScript 与媒体
- 完整的 **SceneScript 运行时** — 模块、场景／图层／效果／材质对象模型、动画事件、`localStorage` 和光标命中测试，每张墙纸的脚本在各自的线程上运行。
- 脚本可以创建图层、粒子系统和声音，移动雾，控制泛光，并为木偶和模型摆姿势。
- **正在播放** — 场景墙纸和网页墙纸会收到当前曲目和播放状态（macOS 15.4 或更高版本）。
- 网页墙纸会收到自己的用户属性和实时音频。

### 音频
- 音频频谱按 Wallpaper Engine 的方式以立体声计算。
- **声音图层**按场景时钟播放，并支持与 Wallpaper Engine 一致定位的**空间音频**。

### 显示器与播放
- **按显示器暂停**或**全部暂停**，播放规则按每台显示器分别判断，包括 Wallpaper Engine 的窗口最大化规则。
- 按显示器设置的用户属性，以及“在显示器之间同步属性”。
- 在多台显示器上显示的同一张墙纸只渲染一次，再呈现到每台显示器上。
- 新的画质设置：渲染分辨率、纹理分辨率、按显示器匹配的场景细节、反射、阴影和体积光。
- **安全重启** — 导致 App 卡住或崩溃的墙纸会在下次启动时跳过，并在资源库中标记。

### 创意工坊与资源库
- Wallpaper Engine 的创意工坊筛选：仅显示、分辨率筛选、按“与／或”组合的类型，以及每张卡片上的标签。
- 已安装的墙纸会显示其创意工坊标签并可按标签筛选；仅包含素材或依赖项的项目不会出现在“已安装”中。
- 缺少的创意工坊依赖项会自动下载，不再使用的依赖项会在删除后移除。所有下载都保存到“墙纸存储位置”文件夹。
- “详细信息”中的**重置**会将墙纸的属性及其在场景检查器中的编辑恢复为作者设置的默认值。
- 遵循墙纸设置中的属性条件、文本行和滑块格式。
- 从不存储 Steam 密码，Steam Web API 密钥保存在钥匙串中。

### 界面与语言
- macOS 26 上的 **Liquid Glass** — 带有工具栏、检查器和玻璃控件的原生分栏视图。较早的 macOS 版本保持原有外观。
- **15 种新语言**：德语、法语、西班牙语、巴西葡萄牙语、意大利语、日语、韩语、简体中文和繁体中文、俄语、波兰语、土耳其语、乌克兰语、阿拉伯语和印地语，可在设置的语言选择器中选择。
- 全新的 App 图标，以及跟随菜单栏外观变化的菜单栏图标。

## 当前限制

- **尚未实现的 SceneScript 函数** — `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()` 目前不执行任何操作。
- **SceneScript 一致性** — 并未完全重现所有专有事件名称、输入回调、生命周期边界情况或精确的计时语义。
- **少见的粒子功能** — 不支持球体、盒体和图层图像以外的发射器形状，也不支持系统中第一个之后的渲染器。
- **WebM 视频** — WebM（VP8/VP9）通过 WebKit 播放，因此音乐同步效果不适用于它。
- **部分 JPEG 缩略图** — 少量 TEXB 格式 1 文件包含 macOS 无法解码的非标准 JPEG 数据。
- **音频功能需要权限** — 未授予录屏权限时，音频可视化和音频响应的 SceneScript 只会收到静音。

## 支持的墙纸类型

| 类型 | 状态 |
|------|--------|
| 视频（.mp4、.webm） | 可用 |
| 网页（HTML/WebGL） | 可用 |
| 场景 — 图像图层与时间线 | 可用（Metal） |
| 场景 — DXT1/DXT3/DXT5 纹理 | 可用（Metal GPU 解码） |
| 场景 — TEXS 精灵／Alpha 时间线 | 可用 |
| 场景 — 精灵粒子 | 可用 |
| 场景 — 高级粒子 | 部分支持（请参阅“当前限制”） |
| 场景 — Wallpaper Engine 与创意工坊效果（WE 自身的着色器） | 可用 |
| 场景 — SceneScript | 部分支持（请参阅“当前限制”） |
| 场景 — 3D 模型／骨骼绑定／木偶变形 | 可用 |
| 应用程序 | 不支持 |

## 隐私

Open Wallpaper Engine 保存的所有内容都留在你的 Mac 上：你的设置、资源库、缓存以及 SteamCMD 的登录信息。Open Wallpaper Engine 没有服务器，不收集任何数据或分析信息。它会与 Valve 通信（使用创意工坊或安装素材时连接 Steam，下载 SteamCMD 时连接 Valve 的服务器），并连接 GitHub 检查 App 更新（GitHub Pages 上的 appcast）以及从 GitHub Releases 下载更新，不发送任何个人数据。可在“设置 › 通用”中关闭更新检查。网页壁纸可能会加载自己的在线内容。你的 Steam 密码和 Steam Guard 验证码直接交给 SteamCMD，绝不会被存储、记录或发送到其他任何地方；只会记住你的账户名，以便重用 SteamCMD 已保存的登录。

## 项目结构

- `OpenWallpaperEngine/Scene/Format/` — PKG、TEX/TEXS 和 scene.json 的解析器与模型
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL 转换（`ShaderVariant.swift`、`InProcessShaderCompiler.swift`）、缓存和管线归档
- `Vendor/ShaderToolchain/` — glslang 和 SPIRV-Cross 源代码，作为本地包构建到 App 中
- `OpenWallpaperEngine/Scene/Scripting/` — SceneScript 运行时以及音频／FFT 绑定
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit 系统音频捕获
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`、`SceneShaders.metal` — Metal 场景渲染器与着色器库
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`、`WorkshopAPIService.swift`、`WorkshopViewModel.swift` — Steam 创意工坊浏览与下载
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`、`ZipImporter.swift`、`WallpaperPackageConverter.swift` — 资源库存储、导入和包转换
- `Scripts/fill-assets-cache.sh` — 开发辅助工具：将 Wallpaper Engine 安装中的资源拷贝到本地文件夹或墙纸存储位置的缓存
- `Scripts/scene-api-coverage.py` — 报告已安装的墙纸使用了哪些 SceneScript API，并与已实现的 API 进行对比

## 相关项目

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — 适用于 [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) 的 PyQt6 图形界面，其 Steam 创意工坊集成与 UI 设计移植自本 macOS 版本。

## 致谢

本项目建立在以下贡献者的工作之上：

- **[MrWindDog](https://github.com/MrWindDog)** — 上游 [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) 分支的维护者，添加了新功能并改进了 UI
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac) 的原作者，构建了 App 的核心架构（SwiftUI、视频墙纸播放、导入系统、播放列表 UI）
- **1ris_W** — 中文 i18n 翻译
- **[Klaus Zhu](https://github.com/klauszhu1105)** — 原始标志设计
- **[Chen Chia Yang](https://github.com/Unayung)** — 场景墙纸渲染、网页墙纸修复、Steam 创意工坊集成、多显示器支持、zip 导入
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal 场景渲染器与效果管线、GLSL→MSL 着色器转换与缓存、SceneScript 运行时、音频响应渲染、创意工坊／下载功能全面改进、摆放与性能设置、标志重新设计

与原项目相同，本项目采用 [GPL-3.0](../../LICENSE) 许可证。
