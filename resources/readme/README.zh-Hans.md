Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | **简体中文** | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine 是一款免费、开源的 macOS 播放器，可播放 Wallpaper Engine 的场景、视频和网页墙纸。它采用原生 Metal 渲染器，支持特效、粒子、3D 模型、光照、SceneScript、音频响应视觉效果以及 Steam 创意工坊。本项目最初是 Haren Chen 与 MrWindDog 的 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 的分支，此后已大部分重写。

> **注：** 本项目与 Steam 上的商业软件 Wallpaper Engine 没有任何关联。这是一款开源的 macOS App，可显示来自 Wallpaper Engine Steam 创意工坊的墙纸素材。 → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**网站：** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Wiki：** [指南与疑难解答](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![资源库](../../docs/images/library.png)

## 亮点

- **场景、视频和网页墙纸** — 场景使用每张墙纸自己的 Wallpaper Engine 着色器绘制（翻译为 Metal），支持特效、粒子、3D 模型、光源、时间线、SceneScript 和音频响应视觉效果。网页墙纸在 WebKit 或可选的 Chromium 引擎中运行。
- **Steam 创意工坊** — 在 App 内浏览、筛选和下载创意工坊内容，或导入墙纸文件夹和 zip 文件。
- **场景编辑器（实时）** — 直接在桌面上实时修改正在运行的墙纸的图层和效果，用它录制你自己的屏幕保护程序，或将其导出为 iPhone 和 iPad 的实况照片锁定屏幕，或 Android 版 Wallpaper Engine 的墙纸包。

  ![场景编辑器（实时）](../../docs/images/scene-editor-live.png)

- **墙纸编辑器** — 一款秉承 Wallpaper Engine 编辑器理念的编辑器：图层、带预览的效果、时间线、SceneScript、用户属性、粒子和 Puppet Warp。你的编辑保存在墙纸旁边，绝不会写入墙纸本身的文件。

  ![墙纸编辑器](../../docs/images/wallpaper-editor.png)

- **显示器** — 与 Wallpaper Engine 一样：每台显示器一张墙纸、一张墙纸横跨所有显示器或在每台显示器上克隆，并支持分组、分割和配置文件。

  ![显示器](../../docs/images/displays.png)

- **播放列表** — 按计时器、登录时、一天中的时段或星期几更换墙纸，并使用 Wallpaper Engine 的过渡效果。

  ![播放列表设置](../../docs/images/playlists.png)

- **导出** — iPhone 和 iPad 的实况照片锁定屏幕，以及 Android 版 Wallpaper Engine 的墙纸包，可通过二维码经 Wi-Fi 发送到手机。

  ![通过 Wi-Fi 发送](../../docs/images/send-over-wifi.png)

- **主题** — 菜单栏、强调色和着色文件夹会跟随墙纸的颜色变化。

  ![主题](../../docs/images/theming.png)

- **MCP 服务器插件** — MCP 客户端可以设定墙纸、播放列表和设置，并编辑场景；连接仅限本地，且只有你的账户可以打开。

  ![MCP 服务器插件](../../docs/images/mcp-plugin.png)

其他所有功能（按领域分类）：[docs/features.md](../../docs/features.md)。

## 安装

1. 从 [openwallpaperengine.app](https://openwallpaperengine.app/) 或 [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases) 下载最新版本。它经过签名和公证，并会自动更新。
2. 打开 DMG，将 **Open Wallpaper Engine** 拖到“应用程序”文件夹。

需要 **macOS 14.0（Sonoma）或更高版本**。部分功能需要更新的 macOS、某项权限或某个插件：请参阅[入门指南](../../docs/getting-started.md#requirements)。

## 快速入门

1. 打开 App。设置助理会设置语言、SteamCMD、你的 Steam 登录和 Wallpaper Engine 素材；每一步都可以跳过。
2. 如果想使用场景墙纸，请安装 Wallpaper Engine 素材（*设置 › 资源*）。这些素材来自你在 Steam 上自己的 Wallpaper Engine 副本；视频和网页墙纸无需它们即可使用。
3. 在 **创意工坊** 标签页中查找墙纸，或导入墙纸文件夹或 zip 文件（*文件 › 从文件夹导入墙纸…*，⌘I）。
4. 在资源库中点按一张墙纸，然后在其详细信息中点按 **设定墙纸**。它的属性列在下方。

更多内容：[入门指南](../../docs/getting-started.md)和 [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)。

## 隐私

App 保存的所有内容都留在你的 Mac 上，它不收集任何数据或分析信息。它会连接 Steam（用于创意工坊和素材）和 GitHub（用于更新），插件只会在你安装时下载。详情：[App 会连接哪些服务](../../docs/getting-started.md#what-the-app-connects-to)以及[隐私政策](../../docs/legal/privacy-policy.md)。

## 文档

- [入门指南](../../docs/getting-started.md) — 系统要求、素材、创意工坊和导入
- [功能](../../docs/features.md) — App 支持的所有功能及其使用方法
- 指南：[显示器布局](../../docs/display-layouts.md) · [播放列表](../../docs/playlists.md) · [屏幕保护程序](../../docs/screen-saver.md) · [iPhone 与 iPad 导出](../../docs/iphone-ipad-export.md) · [Android 导出](../../docs/android-export.md) · [深度图](../../docs/depth-maps.md) · [主题](../../docs/theming.md) · [MCP 服务器](../../docs/mcp.md) · [Chromium 网页引擎](../../docs/chromium-engine.md)
- [开发](../../docs/development.md) — 从源代码构建和项目结构；另见 [CONTRIBUTING.md](../../CONTRIBUTING.md) 和[架构](../../docs/architecture.md)
- [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — 指南、设置参考和疑难解答

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

## 法律信息

[使用条款](../../docs/legal/terms-of-use.md) · [隐私政策](../../docs/legal/privacy-policy.md) · [安全政策](../../SECURITY.md)

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
