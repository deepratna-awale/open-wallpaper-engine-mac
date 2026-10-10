Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | **繁體中文** | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine 是一款免費、開源的 macOS 播放器，可播放 Wallpaper Engine 的場景、影片與網頁背景圖片。它採用原生 Metal 渲染器，支援特效、粒子、3D 模型、光照、SceneScript、音訊響應視覺效果以及 Steam 工作坊。本專案最初是 Haren Chen 與 MrWindDog 的 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 的分支，此後已大部分重寫。

> **注意：** 本專案與 Steam 上的商業軟體 Wallpaper Engine 無關。這是一款開源的 macOS App，可顯示來自 Wallpaper Engine Steam 工作坊的背景圖片素材。 → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**網站：** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Wiki：** [指南與疑難排解](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![資料庫](../../docs/images/library.png)

## 特色

- **場景、影片與網頁背景圖片** — 場景會使用每張背景圖片自己的 Wallpaper Engine 著色器繪製（轉換為 Metal），支援特效、粒子、3D 模型、光源、時間軸、SceneScript 與音訊響應視覺效果。網頁背景圖片在 WebKit 或選用的 Chromium 引擎中執行。
- **Steam 工作坊** — 在 App 內瀏覽、篩選並下載工作坊內容，或輸入背景圖片檔案夾與 zip 檔。
- **場景編輯/輸出** — 直接在桌面上即時修改正在執行的背景圖片的圖層與效果，將它設為你的螢幕保護程式，或將其（場景與影片）輸出為 iPhone 與 iPad 的原況照片鎖定畫面，或 Android 版 Wallpaper Engine 的背景圖片套件。

  ![場景編輯/輸出](../../docs/images/scene-editor-live.png)

- **背景圖片編輯器** — 一款延續 Wallpaper Engine 編輯器精神的編輯器：圖層、附預覽的效果、時間軸、SceneScript、使用者屬性、粒子、Puppet Warp 以及由深度圖產生的遮罩。你編輯的是一份草稿：**儲存** 會將其套用到背景圖片，**儲存為新背景圖片** 會在資料庫中加入一份拷貝，背景圖片本身的檔案絕不會被更改。

  ![背景圖片編輯器](../../docs/images/wallpaper-editor.png)

- **顯示器** — 與 Wallpaper Engine 相同：每台顯示器一張背景圖片、一張背景圖片橫跨所有顯示器或在每台顯示器上複製，並支援群組、分割與設定檔。

  ![顯示器](../../docs/images/displays.png)

- **播放列表** — 依計時器、登入時、一天中的時段或星期幾更換背景圖片，並使用 Wallpaper Engine 的轉場效果。

  ![播放列表設定](../../docs/images/playlists.png)

- **輸出** — iPhone 與 iPad 的原況照片鎖定畫面，以及 Android 版 Wallpaper Engine 的背景圖片套件，可透過 QR 碼經由 Wi-Fi 傳送到手機。

  ![透過 Wi-Fi 傳送](../../docs/images/send-over-wifi.png)

- **主題顏色** — 選單列、強調色以及著色的圖像與檔案夾會跟隨背景圖片的顏色變化；Open Wallpaper Engine 自己的視窗可以使用背景圖片的準確顏色。

  ![主題顏色](../../docs/images/theming.png)

- **MCP 伺服器外掛** — MCP 用戶端可以設定背景圖片、播放列表與設定，並編輯場景；連線僅限本機，且只有你的帳號可以開啟。

  ![MCP 伺服器外掛](../../docs/images/mcp-plugin.png)

其他所有功能（依領域分類）：[docs/features.md](../../docs/features.md)。

## 安裝

1. 從 [openwallpaperengine.app](https://openwallpaperengine.app/) 或 [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases) 下載最新版本。它已經過簽署與公證，並會自動更新。
2. 打開 DMG，將 **Open Wallpaper Engine** 拖到「應用程式」檔案夾。

需要 **macOS 14.0（Sonoma）或以上版本**。部分功能需要較新的 macOS、某項權限或某個外掛：請參閱[入門指南](../../docs/getting-started.md#requirements)。

## 快速入門

1. 打開 App。設定輔助程式會設定語言、SteamCMD、你的 Steam 登入與 Wallpaper Engine 素材，也可以輸入你的 Wallpaper Engine 喜好項目；每個步驟都可以略過。
2. 如果想使用場景背景圖片，請安裝 Wallpaper Engine 素材（*設定 › 資源*）。這些素材來自你在 Steam 上自己的 Wallpaper Engine 副本；影片與網頁背景圖片不需要它們也能使用。
3. 在 **探索** 與 **工作坊** 標籤頁中尋找背景圖片，或輸入背景圖片檔案夾或 zip 檔（*檔案 › 從檔案夾輸入背景圖片…*，⌘I）。
4. 在資料庫中按一下背景圖片，然後在其詳細資訊中按一下 **設定背景圖片**（或按一下右鍵並選擇 **設為背景圖片**）。它的屬性會列在下方。

更多內容：[入門指南](../../docs/getting-started.md)與 [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)。

## 隱私權

App 儲存的所有內容都留在你的 Mac 上，它不收集任何資料或分析資訊。它會連線到 Steam（用於工作坊與素材）、openwallpaperengine.app（用於檢查更新）和 GitHub（用於下載更新），外掛只會在你安裝時下載。詳細資訊：[App 會連線到哪些服務](../../docs/getting-started.md#what-the-app-connects-to)以及[隱私權政策](../../docs/legal/privacy-policy.md)。

## 文件

- [入門指南](../../docs/getting-started.md) — 系統需求、素材、工作坊與輸入
- [功能](../../docs/features.md) — App 支援的所有功能及其使用方式
- 指南：[顯示器佈局](../../docs/display-layouts.md) · [播放列表](../../docs/playlists.md) · [螢幕保護程式](../../docs/screen-saver.md) · [iPhone 與 iPad 輸出](../../docs/iphone-ipad-export.md) · [Android 輸出](../../docs/android-export.md) · [深度圖](../../docs/depth-maps.md) · [主題](../../docs/theming.md) · [MCP 伺服器](../../docs/mcp.md) · [Chromium 網頁引擎](../../docs/chromium-engine.md)
- [開發](../../docs/development.md) — 從原始碼建置與專案結構；另請參閱 [CONTRIBUTING.md](../../CONTRIBUTING.md) 與[架構](../../docs/architecture.md)
- [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — 指南、設定參考與疑難排解

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

## 法律資訊

[使用條款](../../docs/legal/terms-of-use.md) · [隱私權政策](../../docs/legal/privacy-policy.md) · [安全性政策](../../SECURITY.md)

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
