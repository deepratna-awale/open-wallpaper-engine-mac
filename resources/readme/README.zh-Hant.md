Open Wallpaper Engine（修補版）
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | **繁體中文** | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

這是 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 針對 macOS 的修補分支，加入了場景背景圖片渲染，並修正了網頁背景圖片的問題。

> **注意：** 本專案與 Steam 上的商業軟體 Wallpaper Engine 無關。這是一款開源的 macOS App，可顯示來自 Wallpaper Engine Steam 工作坊的背景圖片素材。 → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki：** 指南與文件請見 [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)。

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

## 0.9.0 支援的功能

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

<details>
<summary>0.8.1 版支援的功能</summary>

### 背景圖片播放
- **場景背景圖片**以 Metal 原生渲染，支援影像圖層、變形、關鍵影格時間軸、深度排序，以及 `scene.json` 中的相機／投影資料。
- **影片背景圖片**（`.mp4`、`.webm`）支援播放速率、音量、音訊與影片速度連動，以及可選的隨音樂同步縮放／傾斜／飽和度。
- **網頁背景圖片**（HTML/WebGL）已啟用本機檔案存取，讓 WebGL 紋理與素材能正確載入，並支援外部嵌入內容（YouTube/Vimeo）。
- **擺放模式** — 填滿螢幕、符合螢幕大小、置中、擴展至填滿螢幕、縮放。
- **多顯示器** — 每台顯示器使用不同的背景圖片、依螢幕啟用／停用、視覺化的顯示器配置，以及自動偵測新連接的顯示器。
- **多桌面（Spaces）** — 在所有桌面上連續播放，並提供 `所有桌面` 指定選項。
- **播放規則** — 其他 App 為使用中時可持續執行、靜音、暫停或停止；在睡眠／喚醒與切換桌面時皆能正確運作。

### 場景格式支援
- **PKG 解析器**，用於 Wallpaper Engine `PKGV` 封存檔（scene.json、材質、紋理、著色器）。
- **TEX 解析器**，用於 `TEXV0005` 容器：內嵌的 JPEG/PNG，以及含 mipmap 的 DXT1/DXT3/DXT5，後者透過 Metal 運算著色器在 GPU 上解碼。
- **TEXS 精靈時間軸**（0001/0002/0003），包含單一圖集的影格矩形與多影像序列。
- **彈性的 scene.json 解碼**，可處理 Wallpaper Engine 的多型欄位（一般值或 `{"script":…,"value":…}`）。
- 無法擷取紋理時**改用預覽圖** `preview.jpg/png/gif`。

### 效果與著色器
- **約 48 種原生 Metal 效果**，涵蓋扭曲、模糊（標準／精確／放射狀／動態）、光暈、耶穌光與光束、水波／漣漪／焦散／流動、雲與霧、底片顆粒、故障／VHS、色差、色鍵、變形／傾斜／旋轉／漩渦／透視、反射、折射、光澤／微光／亮粉、邊緣偵測等。
- **音訊回應式效果** — 脈衝、音訊長條、隨音訊同步的色相偏移，以及由即時系統音訊頻譜資料驅動的超空間跳躍效果。
- **語意材質效果** — 將亮度、對比、飽和度、曝光、Gamma、色相、光暈臨界值、光暈與模糊對應至原生 Metal 渲染階段。
- **GLSL → SPIR-V → MSL 轉換**在載入時由連結至 App 的 glslang 與 SPIRV-Cross 執行，支援 COMBO 巨集定義、include 解析，以及 Metal 緩衝區槽位重新編號。
- **預先編譯的著色器快取** — 轉換後的 `.metal`、編譯後的 `.metallib` 以及 `.reflection.json` 附屬檔案會快取於 `.open-wallpaper-engine/shaders` 下；以雜湊值判斷，只有變更過的著色器才會重新轉換，且在背景編譯，因此絕不會阻塞渲染。
- **動態效果目錄**，讀取自 Wallpaper Engine 的 `assets/effects/*/effect.json` 清單，包含多階段效果以及透過反射取得的 uniform 繫結。
- **效果遮罩**（每個圖層最多 4 張遮罩紋理）、加法混合與 Alpha 混合，以及集區化的渲染目標系統。

### 粒子
- 精靈發射器，可隨機設定壽命、大小、速度、顏色、旋轉、角速度、重力、阻力與 Alpha 淡化。
- 進階行為 — 亂流、吸引子、渦流與 boid 群體運動、靜態控制點與跟隨游標的控制點、相連的繩索區段，以及帶有 Alpha／大小淡化的拖尾。
- 透過 `.tex-json` 序列製作精靈圖表影格動畫。
- 用於發射速率、阻力與 Alpha 淡化時機的腳本化運算子。

### SceneScript 執行環境
- 每個圖層持續保留的腳本環境，`init()` 只呼叫一次，`update(value)` 則每個影格呼叫。
- 全域物件：`thisScene`、`thisLayer`、`engine`、`input`、`audio(low, high)`、使用真實資料的 `fft(index)`、`setTimeout`/`setInterval`，以及持續保留的腳本全域變數。
- 完整的 `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4` 數學函式庫，以及 `WEMath`、`WEVector` 與 `WEColor` 輔助工具。
- 從 `assets/scripts/jsmodules` 與 `jsclasses` 載入的 Wallpaper Engine 執行環境 JS 模組。
- 游標事件（`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`）與 `resizeScreen`。
- 腳本可控制圖層的 Alpha、原點、大小、縮放、角度、亮度／顏色、材質常數、效果臨界值與粒子速率。
- 去除重複的腳本例外記錄，並附上重複次數。

### 音訊
- 透過 ScreenCaptureKit 擷取系統音訊，提供平滑處理的 16 頻段頻譜、波形，以及低音／中音／高音電平。
- 依屬性設定的**音樂同步** — 任何使用者屬性都可依音訊電平調變，調變幅度可自行設定。

### 使用者屬性與檢閱器
- 滑桿、核取方塊、組合方塊、文字與顏色等專案設定會顯示在場景側邊欄中，即時套用，且可從 SceneScript 讀取。
- 對設有 `parallaxDepth` 的圖層提供滑鼠追蹤與視差。

### Steam 工作坊
- 可依內容分級、類型與風格標籤瀏覽、搜尋與篩選，支援熱門／最新／最受歡迎／最多訂閱排序，以及附頁碼的分頁。
- 預覽視窗提供設為背景圖片、播放與音量控制，並使用有容量上限的快取；已套用的預覽會直接移入資料庫，無需重新下載。
- SteamCMD 整合：自動偵測、密碼／Steam Guard／快取工作階段登入、專用的「下載項目」標籤頁、可排入佇列並可重試的下載，以及即時進度。
- 多重選取、範圍選取、經確認後才執行的批次下載與刪除、保留已下載的 ID，以及依 `下載日期` 排序。

### 資料庫與設定
- 可從檔案夾、`.zip` 套件或透過拖放輸入。
- 可設定背景圖片儲存位置，並可遷移現有的資料庫。
- 狀態列中的「最近使用的背景圖片」選單。
- 效能設定 — 品質、消除鋸齒、後處理，以及失去焦點時的播放行為。
- 診斷 — 隨附素材的路徑、內建著色器編譯器的函式庫版本，以及著色器快取統計資料。

</details>

<details>
<summary>0.8.0 及更早版本</summary>

### 多顯示器支援
可為每台已連接的顯示器指定不同的背景圖片，並可依螢幕個別啟用或停用。
- **「顯示器設定」面板** — 以視覺化配置顯示所有已連接的螢幕，按一下即可選取
- **個別螢幕背景圖片** — 每台顯示器可獨立顯示不同的背景圖片
- **啟用／停用切換** — 可依顯示器開啟或關閉背景圖片
- **自動偵測** — 連接新顯示器時會自動偵測並啟用

### 多桌面支援
背景圖片現在會顯示於所有 macOS 桌面（Spaces）並連續播放，切換桌面時不會中斷。

### 「最近使用的背景圖片」選單
可從狀態列選單快速切換背景圖片。最近使用的 10 張背景圖片會列於其中，按一下即可切換。

### 播放設定 — 已修正
效能播放設定（其他 App 為使用中時暫停／靜音／停止）現在對所有類型的背景圖片皆能正常運作。

### Steam 工作坊瀏覽器
無需離開 App，即可直接瀏覽、搜尋及下載 Steam 工作坊中的背景圖片。
- **搜尋與篩選** — 依名稱搜尋，並依內容分級（全年齡／爭議性／成人）、類型（場景／影片／網頁）及風格標籤篩選
- **排序選項** — 熱門、最新、最受歡迎、最多訂閱
- **steamcmd 整合** — 首次需要時自動下載 Valve 的 SteamCMD（不隨 App 附帶）；若找到現有的 steamcmd（Homebrew、Steam 或自訂路徑）則直接使用
- **Steam 登入** — 支援密碼、Steam Guard 及快取工作階段驗證
- **顯示下載進度** — 下載期間即時更新狀態（驗證身分中、下載百分比、檢查中、拷貝中）
- **安全的預設值** — 內容分級預設為「全年齡」，以過濾成人內容

### zip 輸入
可直接從 `.zip` 檔案輸入背景圖片套件，無需先手動解壓縮。支援透過「檔案」>「輸入」及拖放操作使用。

### 多重選取與批次取消訂閱
按住 Cmd 鍵並按一下以選取多張背景圖片，接著按一下右鍵即可批次取消訂閱。

### 背景圖片儲存隔離
背景圖片現在儲存於 `~/Documents/Open Wallpaper Engine/`，而非直接存放於「文件」目錄下，可避免在新電腦上複製儲存庫時出現「error」背景圖片。

</details>

<details>
<summary>相對於上游的修補內容</summary>

### 網頁背景圖片 — 修正灰色／空白渲染
以 WebGL 為基礎的背景圖片會渲染成灰色矩形，原因是 `WKWebView` 封鎖了對紋理與素材的本機檔案存取。

**修正：** 在 WKWebView 設定中啟用 `allowFileAccessFromFileURLs` 與 `allowUniversalAccessFromFileURLs`，讓 WebGL 著色器能載入本機紋理檔案。

### 場景背景圖片 — 從零開始實作
場景背景圖片（Steam 工作坊中最常見的類型）先前完全沒有實作，只會顯示「Hello, World!」。

**新實作包含：**
- **PKG 解析器** — 讀取 Wallpaper Engine 的 PKGV 封存格式，擷取 scene.json、模型、材質與紋理
- **TEX 解析器** — 讀取 TEXV0005 紋理容器，擷取內嵌的 JPEG/PNG 影像資料，並讀取 DXT1/DXT3/DXT5 mipmap
- **Scene JSON 解碼器** — 以彈性的解碼方式解析 scene.json，可處理 Wallpaper Engine 的多型欄位（值可以是一般型別，也可以是 `{"script":..,"value":..}` 物件）
- **Metal 渲染器** — 透過 GPU 紋理合成渲染場景影像圖層，並為日後的著色器效果奠定基礎
- **GPU DXT 解碼** — 在場景載入時透過 Metal 運算著色器展開 DXT1（TEXI 7）、DXT3（TEXI 6）與 DXT5（TEXI 4）紋理
- **精靈粒子** — 渲染常見的 `sphererandom` 精靈發射器，可隨機設定壽命、大小、速度、Alpha、顏色、旋轉、角速度、重力、阻力與 Alpha 淡化
- **進階粒子** — 支援旋轉、顏色變化、亂流、靜態控制點與跟隨游標的控制點、相連的繩索區段、拖尾，以及 `.tex-json` 精靈圖表影格動畫
- **TEXS 動畫** — 解碼 TEXS0001/0002/0003 時間軸，包含單一圖集的影格矩形與多影像紋理序列
- **場景時間軸** — 以 60 FPS 對物件的 Alpha、原點、縮放與角度關鍵影格進行內插
- **SceneScript 執行環境** — 依據 ScreenCaptureKit 系統音訊，對運算式與 `export function update(value)` 屬性腳本求值。`thisScene` 計時、`thisLayer.value`、`engine`、輸入游標、`audio(low, high)`、使用真實資料的 `fft(index)`、屬性查詢與持續保留的全域變數，共同驅動影像變形、Alpha 與粒子發射速率。
- **持續保留的 SceneScript 生命週期** — 重複使用每個圖層的腳本環境，只呼叫一次 `init()`，並在各影格呼叫 `update()`，同時共用 `dt`、影格、滑鼠、按鈕、輔助鍵、游標、音訊、FFT、屬性與圖層狀態。
- **腳本化粒子運算子** — 支援用於粒子發射速率、移動阻力與 Alpha 淡化時機的腳本，並能彈性處理數值／字串型別的粒子欄位。
- **滑鼠追蹤與視差** — 對含有 `parallaxDepth` 詮釋資料的圖層套用相對於游標的平移與可選的透視縮放；跟隨游標的粒子使用同一個場景空間游標。
- **腳本化視覺屬性** — 支援以腳本設定物件亮度／RGB 顏色、材質效果常數、純量／向量變形，以及覆寫效果臨界值。
- **使用者屬性** — 在場景側邊欄中顯示文件所述的滑桿、核取方塊、組合方塊、文字與顏色專案設定，並讓數值與布林值可供 SceneScript 使用
- **內建場景效果** — 在 Metal 渲染器中執行作者設定的 `pulse`、`shake`、`iris` 與 `waterwaves` 效果圖項目
- **語意材質效果** — 將亮度、對比、飽和度、曝光、Gamma、色相、光暈臨界值、光暈與模糊的常見材質常數與腳本，對應至原生 Metal 效果
- **GLSL 著色器轉換** — 在載入時透過連結至 App 的 glslang 與 SPIRV-Cross，將封裝的 Wallpaper Engine GLSL 著色器轉換為 SPIR-V 與 MSL；轉換後的變體會快取於 `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants` 下
- **改用預覽圖** — 無法擷取紋理時改用 preview.jpg/png/gif

### 輸入 — 修正檔案夾輸入
輸入面板現在能正確處理單一背景圖片檔案夾，以及包含多張背景圖片的上層目錄。

</details>

## 目前的限制

- **應用程式背景圖片** — 不支援 `type: "application"` 背景圖片，此類背景圖片將無法執行。
- **尚未實作的 SceneScript 函式** — `effect.executeMaterialFunction()`, `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `getVideoTexture()`, `engine.openUserShortcut()` 目前不執行任何動作。
- **SceneScript 一致性** — 並未完整重現所有專有事件名稱、輸入回呼、生命週期的邊界情況或精確的計時語意。
- **少見的粒子功能** — 不支援球體、盒體與圖層影像以外的發射器形狀，也不支援系統中第一個之後的渲染器。
- **需要 Wallpaper Engine 資源** — 場景需要你自己的 Wallpaper Engine 副本中的資源（「設定 → 資源」）；沒有這些資源時只能播放影片與網頁背景圖片。
- **WebM 影片** — WebM（VP8/VP9）透過 WebKit 播放，因此音樂同步效果不適用。
- **部分 JPEG 縮覽圖** — 少數 TEXB 格式 1 檔案含有 macOS 無法解碼的非標準 JPEG 資料。
- **效能設定的適用範圍** — 品質、消除鋸齒與後處理選項是為場景背景圖片而設計，對影片與網頁背景圖片的效果有限。
- **音訊功能需要權限** — 若未授予「螢幕錄製」權限，音訊視覺化與音訊回應式 SceneScript 只會收到無聲訊號。

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

## 系統需求

### 必要
- **macOS 14.0 或以上版本**（Sonoma）。ScreenCaptureKit 音訊擷取與 Metal 場景渲染皆仰賴此版本。

### 選用 — 特定功能所需

| 功能 | 需求 | 安裝 |
|---------|-------------|---------|
| 瀏覽／下載 Steam 工作坊內容 | `steamcmd` | 自動（選用：`brew install steamcmd`） |
| 音訊視覺化與音訊回應式 SceneScript | 「螢幕錄製」權限 | 設定 → 權限 |

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
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

在 Xcode 中，將簽署憑證更改為你自己的憑證，或選擇「Sign to Run Locally」，然後按下 `Cmd + R` 建置並執行。

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

## 隱私權

Open Wallpaper Engine 儲存的所有內容都留在你的 Mac 上：你的設定、資料庫、快取以及 SteamCMD 的登入資訊。Open Wallpaper Engine 沒有伺服器，不收集任何資料或分析資訊。它只與 Valve 連線：使用工作坊或安裝素材時連線到 Steam，下載 SteamCMD 時連線到 Valve 的伺服器。網頁桌布可能會載入自己的線上內容。你的 Steam 密碼和 Steam Guard 驗證碼會直接交給 SteamCMD，絕不會被儲存、記錄或傳送到其他任何地方；只會記住你的帳號名稱，以便重複使用 SteamCMD 已儲存的登入。

## 專案結構

- `OpenWallpaperEngine/Services/SceneParsers/` — PKG、TEX/TEXS 與 scene.json 的解析器與模型
- `OpenWallpaperEngine/Services/SceneEffects/` — 動態效果目錄，以及作者設定的效果參數範圍
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL 轉換（`ShaderVariant.swift`、`InProcessShaderCompiler.swift`）、快取與管線封存
- `Vendor/ShaderToolchain/` — glslang 與 SPIRV-Cross 原始碼，以本機套件形式建置到 App 中
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift` — SceneScript 執行環境與音訊／FFT 繫結
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit 系統音訊擷取
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`、`SceneShaders.metal` — Metal 場景渲染器與著色器函式庫
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`、`WorkshopAPIService.swift`、`WorkshopViewModel.swift` — Steam 工作坊瀏覽與下載
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`、`ZipImporter.swift`、`WallpaperPackageConverter.swift` — 資料庫儲存、輸入與套件轉換
- `Scripts/fill-assets-cache.sh` — 開發輔助工具：將 Wallpaper Engine 安裝中的資源拷貝到本機檔案夾或背景圖片儲存位置的快取
- `Scripts/scene-api-coverage.py` — 報告已安裝的背景圖片使用了哪些 SceneScript API，並與已實作的 API 進行比較
