Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | **繁體中文** | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine 是一款免費、開源的 macOS 播放器，可播放 Wallpaper Engine 的場景、影片與網頁背景圖片。它採用原生 Metal 渲染器，支援特效、粒子、3D 模型、光照、SceneScript、音訊響應視覺效果以及 Steam 工作坊。本專案最初是 Haren Chen 與 MrWindDog 的 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 的分支，此後已大部分重寫。

> **注意：** 本專案與 Steam 上的商業軟體 Wallpaper Engine 無關。這是一款開源的 macOS App，可顯示來自 Wallpaper Engine Steam 工作坊的背景圖片素材。 → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki：** 指南與文件請見 [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)。

## 系統需求

### 必要
- **macOS 14.0 或以上版本**（Sonoma）。ScreenCaptureKit 音訊擷取與 Metal 場景渲染皆仰賴此版本。

### 選用 — 特定功能所需

| 功能 | 需求 | 安裝 |
|---------|-------------|---------|
| 瀏覽／下載 Steam 工作坊內容 | `steamcmd` | 自動（選用：`brew install steamcmd`） |
| 音訊視覺化與音訊回應式 SceneScript | 「系統錄音」權限（macOS 14.2 之前為「螢幕與系統錄音」） | 設定 → 權限 |

#### 著色器

Wallpaper Engine 以 GLSL 形式提供其效果。當背景圖片首次使用這些效果時，會由內建於 App 的 glslang 與 SPIRV-Cross（`Vendor/ShaderToolchain`）轉換為 Metal（GLSL → SPIR-V → MSL），接著快取到磁碟上。無需安裝任何項目。若某個著色器在轉換時造成 App 停止回應，或兩度導致 App 當機，之後啟動時便會略過它，其他著色器仍會照常轉換。

#### Wallpaper Engine 素材

場景使用你在 Steam 上的 Wallpaper Engine 副本中的共用效果、材質、著色器、字體與 SceneScript 執行環境；App 不隨附這些資源。請在「設定 → 資源」中安裝：App 會用 steamcmd 下載你的副本（該帳號必須擁有 Wallpaper Engine），只保留資源與預設背景圖片，其餘部分會被刪除。你也可以選擇現有的 Wallpaper Engine 檔案夾。影片與網頁背景圖片不需要這些資源即可使用。

## 從原始碼建置

### 前置需求
- macOS >= 14.0
- Xcode >= 26.3（macOS 26 SDK）
- Xcode Command Line Tools

### 步驟
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

在 Xcode 中，將簽署憑證更改為你自己的憑證，或選擇「Sign to Run Locally」，然後按下 `Cmd + R` 建置並執行。

從原始碼首次建置時會取得 Sparkle Swift 套件。從原始碼建置的版本不會檢查更新。

## 使用方式

### 從 Steam 工作坊瀏覽與下載

1. 無需安裝：首次需要時，App 會在背景自動下載 Valve 的 SteamCMD（從 Valve 下載，不隨 App 附帶）。Homebrew（`brew install steamcmd`）為選用；若找到現有的 steamcmd（Homebrew、Steam 或你指定的）則直接使用
2. 切換到 **工作坊** 標籤頁，並使用 Steam 帳號登入（必須擁有 Wallpaper Engine）
3. 出現提示時，或在 *設定 → 一般* 中輸入 [Steam Web API 密鑰](https://steamcommunity.com/dev/apikey)。密鑰會經過 Steam 驗證並保存在你的鑰匙圈中；你的 Steam 密碼絕不會被儲存（steamcmd 會重複使用其自身的快取工作階段）
4. 搜尋、篩選，然後在任一背景圖片上按一下 **下載**

### 從本機檔案輸入

- **檔案夾：** 檔案 > 輸入 > 從檔案夾輸入背景圖片 — 選擇包含 `project.json` 的背景圖片檔案夾
- **zip：** 檔案 > 輸入，或拖放包含背景圖片套件的 `.zip` 檔案
- **手動：** 將背景圖片檔案夾直接拷貝至 `~/Documents/Open Wallpaper Engine/`

## 1.0.0 支援的功能

### 設定、資料庫與更新
- **設定輔助程式**——首次啟動時，幾個可略過的步驟會選擇語言、說明隱私、設定 SteamCMD、Steam 登入和選用的 Steam Web API 金鑰、安裝 Wallpaper Engine 素材並匯入你的桌布。
- **SteamCMD 自動設定**——找不到時，App 會下載 Valve 的 SteamCMD；若已有 Homebrew 或 Steam 的版本則直接使用。
- **來自你自己 Steam 副本的 Wallpaper Engine 素材**——登入後透過 SteamCMD 安裝，可選擇一併加入 Wallpaper Engine 的預設桌布。
- **匯入**——你的工作坊收藏集和訂閱（透過 Steam Web API）、現有 Steam 資料庫中的工作坊項目，以及桌布檔案夾。
- **[wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)**——指南、設定參考和疑難排解；App 中的「支援與常見問題」會打開它。
- **自動更新**——已簽署的更新會自動安裝（結束時、離開 Mac 10 分鐘後或一天之內，隨後快速重新啟動並還原你的桌布）。在「設定 › 一般 › 更新」中可以只檢查、關閉檢查或接收測試版更新。「檢查更新⋯」位於 App 選單和選單列選單中。

### 場景渲染
- **Wallpaper Engine 本身的著色器** — 圖層、效果和材質現在以每張背景圖片的原始著色器繪製，並轉譯為 Metal，包含工作坊作者自行製作的效果。
- 合成、全螢幕和純色圖層，取樣其他圖層的圖層，全部 33 種混合模式，以及更多效果遮罩。
- **忠實的文字排版** — 文字的大小、對齊和位置與 Wallpaper Engine 一致，並支援外框、模糊和陰影字體效果。
- **時間軸** — 關鍵影格和紋理動畫遵循 Wallpaper Engine 的單次、循環和鏡像播放規則。
- 色彩查詢表、Wallpaper Engine 的色彩校正，以及背景圖片屬性中的影像濾鏡和色彩選項。
- 由自身動畫驅動的 **Puppet Warp** 影像，支援骨骼物理（彈簧、重力、限制）以及掛在骨骼上的物件。

### 3D 與光照
- 支援蒙皮、動畫圖層、變形目標和根運動的 **3D 模型**。
- 支援相機路徑、淡入淡出和晃動的透視場景相機；2D 圖層也位於景深之中。
- 支援光照 Cookie、陰影、平面反射、距離霧和高度霧以及體積光的**場景光源**。
- **HDR** — HDR 場景以 Wallpaper Engine 的 HDR 光暈渲染，「超高（顯示器 HDR）」畫質會在能顯示 EDR 的顯示器上輸出 EDR。

### 粒子
- **GPU 粒子** — 所有粒子系統都在 GPU 上以 3D 模擬，並支援 3D 控制點。
- 子系統（包含由父系統粒子觸發的子系統）、發射器爆發、延遲和週期性發射，以及從圖層影像發射。
- 碰撞（包含與模型骨骼的碰撞）、音訊反應，以及繞任意軸的旋轉。
- 與背景圖片使用者屬性綁定的粒子設定。

### SceneScript 與媒體
- 完整的 **SceneScript 執行環境** — 模組、場景／圖層／效果／材質物件模型、動畫事件、`localStorage` 和游標點擊測試，每張背景圖片的指令碼在各自的執行緒上執行。
- 指令碼可以建立圖層、粒子系統和聲音，移動霧，控制光暈，並為木偶和模型擺姿勢。
- **正在播放** — 場景和網頁背景圖片會收到目前的曲目和播放狀態（macOS 15.4 或以上版本）。
- 網頁背景圖片會收到自己的使用者屬性和即時音訊。

### 音訊
- 音訊頻譜依 Wallpaper Engine 的方式以立體聲計算。
- **聲音圖層**依場景時鐘播放，並支援與 Wallpaper Engine 一致定位的**空間音訊**。

### 顯示器與播放
- **依顯示器暫停**或**全部暫停**，播放規則會依每台顯示器分別判斷，包含 Wallpaper Engine 的視窗最大化規則。
- 依顯示器設定的使用者屬性，以及「在所有顯示器間同步屬性」。
- 在多台顯示器上顯示的同一張背景圖片只渲染一次，再呈現到每台顯示器上。
- 新的畫質設定：渲染解析度、紋理解析度、依顯示器調整的場景細節、反射、陰影和體積光。
- **安全重新啟動** — 導致 App 停止回應或當機的背景圖片會在下次啟動時略過，並在資料庫中標示。

### 工作坊與資料庫
- Wallpaper Engine 的工作坊篩選：僅顯示、解析度篩選、以「且／或」組合的類型，以及每張卡片上的標籤。
- 已安裝的背景圖片會顯示其工作坊標籤並可依標籤篩選；僅含素材或相依項目的項目不會出現在「已安裝」中。
- 缺少的工作坊相依項目會自動下載，不再使用的相依項目會在刪除後移除。所有下載都會存放到「背景圖片儲存位置」檔案夾。
- 「詳細資訊」中的**重置**會將背景圖片的屬性及其在場景檢閱器中的編輯還原為作者設定的預設值。
- 遵循背景圖片設定中的屬性條件、文字列和滑桿格式。
- 絕不儲存 Steam 密碼，Steam Web API 金鑰保存在鑰匙圈中。

### 介面與語言
- macOS 26 上的 **Liquid Glass** — 具備工具列、檢閱器和玻璃控制項的原生分割顯示方式。較早的 macOS 版本維持原本的外觀。
- **15 種新語言**：德文、法文、西班牙文、巴西葡萄牙文、義大利文、日文、韓文、簡體中文和繁體中文、俄文、波蘭文、土耳其文、烏克蘭文、阿拉伯文和印地文，可在設定的語言選擇器中選擇。
- 全新的 App 圖像，以及隨選單列外觀變化的選單列圖像。

## 目前的限制

- **尚未實作的 SceneScript 函式** — `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()` 目前不執行任何動作。
- **SceneScript 一致性** — 並未完整重現所有專有事件名稱、輸入回呼、生命週期的邊界情況或精確的計時語意。
- **少見的粒子功能** — 不支援球體、盒體與圖層影像以外的發射器形狀，也不支援系統中第一個之後的渲染器。
- **WebM 影片** — WebM（VP8/VP9）透過 WebKit 播放，因此音樂同步效果不適用。
- **部分 JPEG 縮覽圖** — 少數 TEXB 格式 1 檔案含有 macOS 無法解碼的非標準 JPEG 資料。

## 支援的背景圖片類型

| 類型 | 狀態 |
|------|--------|
| 影片（.mp4、.webm） | 可運作 |
| 網頁（HTML/WebGL） | 可運作 |
| 場景 — 影像圖層與時間軸 | 可運作（Metal） |
| 場景 — DXT1/DXT3/DXT5 紋理 | 可運作（Metal GPU 解碼） |
| 場景 — TEXS 精靈／Alpha 時間軸 | 可運作 |
| 場景 — 精靈粒子 | 可運作 |
| 場景 — 進階粒子 | 部分支援（請參閱「目前的限制」） |
| 場景 — Wallpaper Engine 與工作坊效果（WE 本身的著色器） | 可運作 |
| 場景 — SceneScript | 部分支援（請參閱「目前的限制」） |
| 場景 — 3D 模型／骨架綁定／人偶彎曲 | 可運作 |
| 應用程式 | 不支援 |

## 隱私權

Open Wallpaper Engine 儲存的所有內容都留在你的 Mac 上：你的設定、資料庫、快取以及 SteamCMD 的登入資訊。Open Wallpaper Engine 沒有伺服器，不收集任何資料或分析資訊。它會與 Valve 連線（使用工作坊或安裝素材時連線到 Steam，下載 SteamCMD 時連線到 Valve 的伺服器），並連線到 GitHub 檢查 App 更新（GitHub Pages 上的 appcast）以及從 GitHub Releases 下載更新，不傳送任何個人資料。可在「設定 › 一般」中關閉更新檢查。網頁桌布可能會載入自己的線上內容。你的 Steam 密碼和 Steam Guard 驗證碼會直接交給 SteamCMD，絕不會被儲存、記錄或傳送到其他任何地方；只會記住你的帳號名稱，以便重複使用 SteamCMD 已儲存的登入。

## 專案結構

- `OpenWallpaperEngine/Scene/Format/` — PKG、TEX/TEXS 與 scene.json 的解析器與模型
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL 轉換（`ShaderVariant.swift`、`InProcessShaderCompiler.swift`）、快取與管線封存
- `Vendor/ShaderToolchain/` — glslang 與 SPIRV-Cross 原始碼，以本機套件形式建置到 App 中
- `OpenWallpaperEngine/Scene/Scripting/` — SceneScript 執行環境與音訊／FFT 繫結
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit 系統音訊擷取
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`、`SceneShaders.metal` — Metal 場景渲染器與著色器函式庫
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`、`WorkshopAPIService.swift`、`WorkshopViewModel.swift` — Steam 工作坊瀏覽與下載
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`、`ZipImporter.swift`、`WallpaperPackageConverter.swift` — 資料庫儲存、輸入與套件轉換
- `Scripts/fill-assets-cache.sh` — 開發輔助工具：將 Wallpaper Engine 安裝中的資源拷貝到本機檔案夾或背景圖片儲存位置的快取
- `Scripts/scene-api-coverage.py` — 報告已安裝的背景圖片使用了哪些 SceneScript API，並與已實作的 API 進行比較

## 相關專案

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — 適用於 [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) 的 PyQt6 圖形介面，其 Steam 工作坊整合與 UI 設計移植自本 macOS 版本。

## 致謝

本專案建立於以下貢獻者的成果之上：

- **[MrWindDog](https://github.com/MrWindDog)** — 上游 [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) 分支的維護者，新增了功能並改善了 UI
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac) 的原作者，建構了 App 的核心架構（SwiftUI、影片背景圖片播放、輸入系統、播放列表 UI）
- **1ris_W** — 中文 i18n 翻譯
- **[Klaus Zhu](https://github.com/klauszhu1105)** — 原始標誌設計
- **[Chen Chia Yang](https://github.com/Unayung)** — 場景背景圖片渲染、網頁背景圖片修正、Steam 工作坊整合、多顯示器支援、zip 輸入
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal 場景渲染器與效果管線、GLSL→MSL 著色器轉換與快取、SceneScript 執行環境、音訊回應式渲染、工作坊／下載功能全面翻新、擺放與效能設定、標誌重新設計

與原始專案相同，本專案採用 [GPL-3.0](../../LICENSE) 授權。
