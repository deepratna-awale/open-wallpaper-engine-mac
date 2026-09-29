Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | **日本語** | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine は、Wallpaper Engine の壁紙（シーン・動画・Web）を再生できる、無料でオープンソースの macOS 向けプレーヤーです。ネイティブの Metal レンダラーを搭載し、エフェクト、パーティクル、3D モデル、ライティング、SceneScript、オーディオ連動ビジュアル、Steam ワークショップに対応しています。Haren Chen 氏と MrWindDog 氏の [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) のフォークとして始まり、現在ではその大部分が書き直されています。

> **注意：** 本プロジェクトは Steam の商用版 Wallpaper Engine とは一切関係ありません。Wallpaper Engine の Steam ワークショップにある壁紙アセットを表示できる、オープンソースの macOS アプリです。 → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki：** ガイドとドキュメントは [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) にあります。

## 必要条件

### 必須
- **macOS 14.0 以降**（Sonoma）。ScreenCaptureKit によるオーディオキャプチャと Metal によるシーンのレンダリングは、いずれもこれに依存しています。

### オプション — 特定の機能に必要

| 機能 | 必要条件 | インストール |
|---------|-------------|---------|
| Steam ワークショップのブラウズ／ダウンロード | `steamcmd` | 自動（任意：`brew install steamcmd`） |
| オーディオビジュアライザとオーディオに反応する SceneScript | 画面収録の許可 | 設定 → アクセス権 |

#### シェーダー

Wallpaper Engine のエフェクトは GLSL で提供されています。これらは、壁紙で初めて使用されるときに、アプリに組み込まれた glslang と SPIRV-Cross（`Vendor/ShaderToolchain`）によって Metal に変換され（GLSL → SPIR-V → MSL）、その後ディスクにキャッシュされます。追加でインストールするものはありません。変換中にアプリが応答しなくなったシェーダーや、アプリが 2 回クラッシュしたシェーダーは以降の起動時にスキップされ、それ以外のシェーダーは引き続き変換されます。

#### Wallpaper Engine のアセット

シーンは、お持ちの Steam 版 Wallpaper Engine に含まれる共有のエフェクト、マテリアル、シェーダー、フォント、SceneScript ランタイムを使います。アプリにはこれらは同梱されていません。「設定 → アセット」でインストールしてください。アプリは steamcmd でお持ちのコピーをダウンロードし（アカウントが Wallpaper Engine を所有している必要があります）、アセットとデフォルトの壁紙だけを残して残りを削除します。既存の Wallpaper Engine フォルダを選択することもできます。ビデオと Web の壁紙はアセットなしで動作します。

## ソースからビルド

### 前提条件
- macOS >= 14.0
- Xcode >= 26.3（macOS 26 SDK）
- Xcode Command Line Tools

### 手順
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

Xcode で署名証明書を自分のものに変更するか「Sign to Run Locally」を選択し、`Cmd + R` を押してビルドおよび実行します。

ソースからの初回ビルドでは Swift パッケージの Sparkle を取得します。ソースからビルドしたアプリはアップデートを確認しません。

## 使い方

### Steam ワークショップからブラウズ／ダウンロードする

1. インストールは不要です。初めて必要になったときに、アプリが Valve の SteamCMD をバックグラウンドでダウンロードします（Valve から取得、同梱はしていません）。Homebrew（`brew install steamcmd`）は任意で、既存の steamcmd（Homebrew、Steam、または自分で選んだもの）が見つかればそれを使います
2. **ワークショップ**タブに切り替え、Steam アカウントでログインします（Wallpaper Engine を所有している必要があります）
3. 求められたら、または *設定 → 一般* で [Steam Web API キー](https://steamcommunity.com/dev/apikey)を入力します。キーは Steam で確認されたうえでキーチェーンに保管されます。Steam のパスワードが保存されることはありません（steamcmd は独自のキャッシュ済みセッションを再利用します）
4. 検索やフィルタを行い、任意の壁紙で **ダウンロード** をクリックします

### ローカルファイルから読み込む

- **フォルダ：** ファイル > 読み込む > フォルダから壁紙を読み込む — `project.json` を含む壁紙フォルダを選択します
- **zip：** ファイル > 読み込む、または壁紙パッケージを含む `.zip` ファイルをドラッグ＆ドロップします
- **手動：** 壁紙フォルダを `~/Documents/Open Wallpaper Engine/` に直接コピーします

## 1.0.0 の対応機能

### セットアップ・ライブラリ・アップデート
- **セットアップアシスタント** — 初回起動時に、スキップ可能な数ステップで言語の選択、プライバシーの説明、SteamCMD・Steam ログイン・任意の Steam Web API キーの設定、Wallpaper Engine アセットのインストール、壁紙の取り込みを行います。
- **SteamCMD の自動セットアップ** — 見つからない場合は Valve の SteamCMD をダウンロードします。Homebrew や Steam のものがあればそれを使います。
- **自分の Steam コピーからの Wallpaper Engine アセット** — サインイン後に SteamCMD でインストールします。Wallpaper Engine のデフォルト壁紙も任意で追加できます。
- **インポート** — ワークショップのコレクションとサブスクリプション（Steam の Web API から）、既存の Steam ライブラリのワークショップアイテム、壁紙フォルダ。
- **[wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)** — ガイド、設定リファレンス、トラブルシューティング。アプリの「サポートと FAQ」から開けます。
- **自動アップデート** — 署名済みのアップデートが自動でインストールされます（終了時、Mac から 10 分離れたとき、または 1 日以内。その後の短い再起動で壁紙が復元されます）。設定 › 一般 › アップデート で確認のみ・確認オフ・ベータ版の受け取りを選べます。「アップデートを確認…」はアプリメニューとメニューバーのメニューにあります。

### シーンのレンダリング
- **Wallpaper Engine 本来のシェーダー** — レイヤー、エフェクト、マテリアルを、各壁紙のオリジナルのシェーダーを Metal に変換して描画するようになりました。ワークショップの作者が独自に作ったエフェクトにも対応しています。
- コンポジション、フルスクリーン、単色の各レイヤー、ほかのレイヤーをサンプリングするレイヤー、33 種類すべての描画モード、さらに多くのエフェクトマスク。
- **忠実なテキストレイアウト** — テキストのサイズ、揃え、位置を Wallpaper Engine と同じように決定し、アウトライン、ぼかし、ドロップシャドウのフォントエフェクトにも対応しています。
- **タイムライン** — キーフレームとテクスチャのアニメーションが、Wallpaper Engine の 1 回再生、ループ、ミラーの規則に従います。
- カラールックアップテーブル、Wallpaper Engine の色補正、壁紙のプロパティにある画像フィルタとカラーのオプション。
- アニメーションで動く **Puppet Warp** 画像。ボーンの物理（スプリング、重力、制限）と、ボーンに取り付けられたオブジェクトに対応しています。

### 3D とライティング
- スキニング、アニメーションレイヤー、モーフターゲット、ルートモーションに対応した **3D モデル**。
- カメラパス、フェード、シェイクに対応した透視投影のシーンカメラ。2D レイヤーも奥行きの中に配置されます。
- ライトクッキー、影、平面反射、距離フォグと高さフォグ、ボリューメトリックライトに対応した **シーンのライト**。
- **HDR** — HDR シーンを Wallpaper Engine の HDR ブルームでレンダリングし、「ウルトラ（ディスプレイHDR）」の品質では、表示できるディスプレイに EDR で出力します。

### パーティクル
- **GPU パーティクル** — すべてのパーティクルシステムを GPU 上で 3D シミュレーションし、3D のコントロールポイントに対応しています。
- 親のパーティクルをきっかけに発生するものを含む子システム、エミッタのバースト、遅延、周期的な放出、レイヤーの画像からの放出。
- モデルのボーンとの衝突を含む衝突判定、オーディオへの反応、すべての軸を中心とした回転。
- 壁紙のユーザプロパティに連動するパーティクルの設定。

### SceneScript とメディア
- 完全な **SceneScript ランタイム** — モジュール、シーン／レイヤー／エフェクト／マテリアルのオブジェクトモデル、アニメーションイベント、`localStorage`、カーソルのヒットテストに対応し、各壁紙のスクリプトは専用のスレッドで動作します。
- スクリプトからレイヤー、パーティクルシステム、サウンドの作成、フォグの移動、ブルームの制御、パペットやモデルのポーズ付けができます。
- **再生中の情報** — シーン壁紙と Web 壁紙が、再生中の曲と再生状態を受け取ります（macOS 15.4 以降）。
- Web 壁紙が、ユーザプロパティとライブオーディオを受け取ります。

### オーディオ
- オーディオスペクトルを Wallpaper Engine と同じ方法で、ステレオで算出します。
- **サウンドレイヤー**をシーンの時計に合わせて再生し、Wallpaper Engine と同じように配置される**空間オーディオ**に対応しています。

### ディスプレイと再生
- **ディスプレイごとに一時停止**または**すべて一時停止**。再生の規則はディスプレイごとに判定され、Wallpaper Engine の最大化ウインドウの規則にも対応しています。
- ディスプレイごとのユーザプロパティと、「ディスプレイ間でプロパティを同期」。
- 複数のディスプレイに表示する壁紙は 1 回だけレンダリングされ、それぞれに表示されます。
- 新しい品質設定：レンダリング解像度、テクスチャ解像度、「ディスプレイに合わせる」シーンの詳細度、反射、影、ボリューメトリック。
- **セーフリスタート** — アプリを停止させたりクラッシュさせたりした壁紙は、次回の起動時にスキップされ、ライブラリで印が付きます。

### ワークショップとライブラリ
- Wallpaper Engine のワークショップフィルタ：表示する項目、解像度フィルタ、AND／OR で組み合わせるジャンル、各カードのタグ。
- インストール済みの壁紙はワークショップのタグを表示し、タグで絞り込めます。アセットや依存関係だけの項目は「インストール済み」に表示されません。
- 不足しているワークショップの依存関係は自動的にダウンロードされ、使われなくなったものは削除時に取り除かれます。すべてのダウンロードは「壁紙の保存場所」フォルダに保存されます。
- 「詳細」の**リセット**で、壁紙のプロパティとシーンインスペクタでの編集を作者が設定したデフォルトに戻せます。
- 壁紙の設定にあるプロパティの条件、テキスト行、スライダの書式に従います。
- Steam のパスワードは保存されず、Steam Web API キーはキーチェーンに保管されます。

### インターフェイスと言語
- macOS 26 の **Liquid Glass** — ツールバー、インスペクタ、ガラスのコントロールを備えたネイティブの分割表示。それ以前の macOS では従来の外観のままです。
- **15 の新しい言語**：ドイツ語、フランス語、スペイン語、ポルトガル語（ブラジル）、イタリア語、日本語、韓国語、中国語（簡体字・繁体字）、ロシア語、ポーランド語、トルコ語、ウクライナ語、アラビア語、ヒンディー語。設定の言語ピッカーで選べます。
- 新しいアプリアイコンと、メニューバーの外観に合わせて変わるメニューバーアイコン。

## 現在の制限事項

- **SceneScript の未実装関数** — `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()` はまだ何もしません。
- **SceneScript の互換性** — 独自のイベント名、入力コールバック、ライフサイクルのエッジケース、正確なタイミングのセマンティクスのすべてが再現されているわけではありません。
- **まれなパーティクル機能** — 球・ボックス・レイヤー画像以外のエミッター形状と、システムの 2 番目以降のレンダラーには対応していません。
- **一部の JPEG サムネール** — 少数の TEXB 形式 1 のファイルには、macOS でデコードできない非標準の JPEG データが含まれています。
- **オーディオ機能には許可が必要** — 画面収録の許可がない場合、オーディオビジュアライザとオーディオに反応する SceneScript は無音を受け取ります。

## 対応している壁紙の種類

| 種類 | 状態 |
|------|--------|
| ビデオ（.mp4、.webm） | 動作 |
| Web（HTML/WebGL） | 動作 |
| シーン — 画像レイヤーとタイムライン | 動作（Metal） |
| シーン — DXT1/DXT3/DXT5 テクスチャ | 動作（Metal による GPU デコード） |
| シーン — TEXS スプライト／アルファのタイムライン | 動作 |
| シーン — スプライトパーティクル | 動作 |
| シーン — 高度なパーティクル | 一部対応（「制限事項」を参照） |
| シーン — Wallpaper Engine とワークショップのエフェクト（WE 自身のシェーダー） | 動作 |
| シーン — SceneScript | 一部対応（「制限事項」を参照） |
| シーン — 3D モデル／リギング／パペットワープ | 動作 |
| アプリケーション | 非対応 |

## プライバシー

Open Wallpaper Engine が保存するものはすべてお使いの Mac に残ります：設定、ライブラリ、キャッシュ、SteamCMD のログイン情報。Open Wallpaper Engine はサーバを持たず、データや分析情報を一切収集しません。通信する相手は Valve（ワークショップを使うときやアセットをインストールするときは Steam、SteamCMD をダウンロードするときは Valve のサーバ）と GitHub です。GitHub にはアプリのアップデートの確認（GitHub Pages 上の appcast）と、GitHub Releases からのダウンロードのためにアクセスし、個人データは送信しません。アップデートの確認は 設定 › 一般 でオフにできます。Web 壁紙は独自のオンラインコンテンツを読み込むことがあります。Steam のパスワードと Steam Guard コードは SteamCMD に直接渡され、保存・記録されることも、ほかの場所に送信されることもありません。SteamCMD の保存済みログインを再利用するため、アカウント名だけが記憶されます。

## プロジェクトの構成

- `OpenWallpaperEngine/Scene/Format/` — PKG、TEX/TEXS、scene.json のパーサーとモデル
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL の変換（`ShaderVariant.swift`、`InProcessShaderCompiler.swift`）、キャッシュ、パイプラインアーカイブ
- `Vendor/ShaderToolchain/` — glslang と SPIRV-Cross のソース。ローカルパッケージとしてアプリに組み込まれます
- `OpenWallpaperEngine/Scene/Scripting/` — SceneScript ランタイムとオーディオ／FFT のバインディング
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit によるシステムオーディオのキャプチャ
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`、`SceneShaders.metal` — Metal シーンレンダラーとシェーダーライブラリ
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`、`WorkshopAPIService.swift`、`WorkshopViewModel.swift` — Steam ワークショップのブラウズとダウンロード
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`、`ZipImporter.swift`、`WallpaperPackageConverter.swift` — ライブラリの保存、読み込み、パッケージの変換
- `Scripts/fill-assets-cache.sh` — 開発用ツール: Wallpaper Engine のインストールからアセットをローカルフォルダまたは壁紙の保存場所のキャッシュにコピーします
- `Scripts/scene-api-coverage.py` — インストール済みの壁紙が使用している SceneScript API と、実装済みの API を比較して報告します

## 関連プロジェクト

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) 向けの PyQt6 GUI です。Steam ワークショップとの連携と UI デザインは、この macOS 版から移植されています。

## クレジット

本プロジェクトは、以下の方々の成果の上に構築されています：

- **[MrWindDog](https://github.com/MrWindDog)** — 上流の [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) フォークのメンテナー。新機能と UI の改良を追加
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac) のオリジナル作者。アプリのコアアーキテクチャ（SwiftUI、ビデオ壁紙の再生、読み込みシステム、プレイリスト UI）を構築
- **1ris_W** — 中国語 i18n 翻訳
- **[Klaus Zhu](https://github.com/klauszhu1105)** — オリジナルのロゴデザイン
- **[Chen Chia Yang](https://github.com/Unayung)** — シーン壁紙のレンダリング、Web 壁紙の修正、Steam ワークショップとの連携、マルチディスプレイ対応、zip の読み込み
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal シーンレンダラーとエフェクトパイプライン、GLSL→MSL シェーダー変換とキャッシュ、SceneScript ランタイム、オーディオレスポンスのレンダリング、ワークショップ／ダウンロードの全面改良、配置とパフォーマンスの設定、ロゴのリデザイン

オリジナルのプロジェクトと同じく、[GPL-3.0](../../LICENSE) のもとでライセンスされています。
