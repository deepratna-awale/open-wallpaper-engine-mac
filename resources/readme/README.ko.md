Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | **한국어** | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine은 Wallpaper Engine 배경화면(장면, 동영상, 웹)을 재생하는 무료 오픈 소스 macOS 플레이어입니다. 네이티브 Metal 렌더러를 갖추고 있으며 효과, 파티클, 3D 모델, 조명, SceneScript, 오디오 반응형 비주얼, Steam 창작마당을 지원합니다. Haren Chen과 MrWindDog의 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 포크로 시작했으며, 이후 대부분 새로 작성되었습니다.

> **참고:** 이 프로젝트는 Steam의 상용 Wallpaper Engine과 관련이 없습니다. Wallpaper Engine의 Steam 창작마당에 있는 배경화면 에셋을 표시할 수 있는 오픈 소스 macOS 앱입니다. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**웹사이트:** [openwallpaperengine.app](https://openwallpaperengine.app/) · **위키:** [가이드 및 문제 해결](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![보관함](../../docs/images/library.png)

## 주요 기능

- **장면, 동영상, 웹 배경화면** — 장면은 각 배경화면에 포함된 Wallpaper Engine 셰이더를 Metal로 변환해 그리며, 효과, 파티클, 3D 모델, 조명, 타임라인, SceneScript, 오디오 반응형 비주얼을 지원합니다. 웹 배경화면은 WebKit 또는 선택 사항인 Chromium 엔진에서 실행됩니다.
- **Steam 창작마당** — 앱 안에서 창작마당을 둘러보고, 필터링하고, 다운로드하거나 배경화면 폴더와 zip 파일을 가져올 수 있습니다.
- **장면 편집기(라이브)** — 실행 중인 배경화면의 레이어와 효과를 데스크탑에서 실시간으로 바꾸고, 이를 녹화해 나만의 화면 보호기를 만들거나, iPhone 및 iPad용 Live Photo 잠금 화면 또는 Wallpaper Engine Android 앱용 패키지로 내보낼 수 있습니다.

  ![장면 편집기(라이브)](../../docs/images/scene-editor-live.png)

- **배경화면 편집기** — Wallpaper Engine 편집기를 본뜬 편집기입니다. 레이어, 미리보기가 있는 효과, 타임라인, SceneScript, 사용자 속성, 파티클, Puppet Warp를 다룰 수 있습니다. 편집 내용은 배경화면 파일이 아니라 배경화면 옆에 따로 저장됩니다.

  ![배경화면 편집기](../../docs/images/wallpaper-editor.png)

- **디스플레이** — Wallpaper Engine처럼 디스플레이마다 다른 배경화면, 여러 디스플레이에 걸쳐 늘리거나 각 디스플레이에 복제한 배경화면, 그룹, 분할, 프로필을 지원합니다.

  ![디스플레이](../../docs/images/displays.png)

- **플레이리스트** — 타이머, 로그인 시, 시간대, 요일에 따라 Wallpaper Engine의 전환 효과와 함께 배경화면을 바꿉니다.

  ![플레이리스트 설정](../../docs/images/playlists.png)

- **내보내기** — iPhone 및 iPad용 Live Photo 잠금 화면과 Wallpaper Engine Android 패키지를 만들어 QR 코드로 Wi-Fi를 통해 휴대폰에 보낼 수 있습니다.

  ![Wi-Fi로 보내기](../../docs/images/send-over-wifi.png)

- **테마** — 메뉴 막대, 강조 색상, 색이 입혀진 폴더가 배경화면의 색상을 따라갑니다.

  ![테마](../../docs/images/theming.png)

- **MCP 서버 플러그인** — MCP 클라이언트가 배경화면, 플레이리스트, 설정을 지정하고 장면을 편집할 수 있습니다. 연결은 로컬에서만 이루어지며 사용자 본인의 계정만 열 수 있습니다.

  ![MCP 서버 플러그인](../../docs/images/mcp-plugin.png)

그 밖의 모든 기능은 영역별로 [docs/features.md](../../docs/features.md)에서 확인하세요.

## 설치

1. [openwallpaperengine.app](https://openwallpaperengine.app/) 또는 [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases)에서 최신 릴리스를 다운로드합니다. 서명 및 공증을 거쳤으며 자동으로 업데이트됩니다.
2. DMG를 열고 **Open Wallpaper Engine**을 응용 프로그램 폴더로 드래그합니다.

**macOS 14.0(Sonoma) 이상**이 필요합니다. 일부 기능에는 더 최신 macOS, 권한 또는 플러그인이 필요합니다. [시작하기](../../docs/getting-started.md#requirements)를 참고하세요.

## 빠른 시작

1. 앱을 엽니다. 설정 도우미에서 언어, SteamCMD, Steam 로그인, Wallpaper Engine 에셋을 설정합니다. 모든 단계는 건너뛸 수 있습니다.
2. 장면 배경화면을 사용하려면 Wallpaper Engine 에셋을 설치합니다(*설정 › 에셋*). 에셋은 사용자가 Steam에서 보유한 Wallpaper Engine에서 가져오며, 동영상 및 웹 배경화면은 에셋 없이도 작동합니다.
3. **창작마당** 탭에서 배경화면을 찾거나, 배경화면 폴더 또는 zip 파일을 가져옵니다(*파일 › 폴더에서 배경화면 가져오기…*, ⌘I).
4. 보관함에서 배경화면을 클릭한 다음, 세부사항에서 **배경화면 설정**을 클릭합니다. 그 아래에 배경화면의 속성이 표시됩니다.

자세한 내용: [시작하기](../../docs/getting-started.md) 및 [위키](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## 개인정보 보호

앱이 저장하는 모든 것은 사용자의 Mac에 남으며, 어떤 데이터나 분석 정보도 수집하지 않습니다. 앱은 Steam(창작마당 및 에셋용)과 GitHub(업데이트용)에 연결하며, 플러그인은 사용자가 설치할 때만 다운로드됩니다. 자세한 내용: [앱이 연결하는 대상](../../docs/getting-started.md#what-the-app-connects-to) 및 [개인정보 처리방침](../../docs/legal/privacy-policy.md).

## 문서

- [시작하기](../../docs/getting-started.md) — 요구 사항, 에셋, 창작마당, 가져오기
- [기능](../../docs/features.md) — 앱이 지원하는 모든 기능과 사용 방법
- 가이드: [디스플레이 레이아웃](../../docs/display-layouts.md) · [플레이리스트](../../docs/playlists.md) · [화면 보호기](../../docs/screen-saver.md) · [iPhone 및 iPad 내보내기](../../docs/iphone-ipad-export.md) · [Android 내보내기](../../docs/android-export.md) · [깊이 맵](../../docs/depth-maps.md) · [테마](../../docs/theming.md) · [MCP 서버](../../docs/mcp.md) · [Chromium 웹 엔진](../../docs/chromium-engine.md)
- [개발](../../docs/development.md) — 소스에서 빌드하기와 프로젝트 구조, [CONTRIBUTING.md](../../CONTRIBUTING.md) 및 [아키텍처](../../docs/architecture.md)
- [위키](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — 가이드, 설정 레퍼런스, 문제 해결

## 관련 프로젝트

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine)용 PyQt6 GUI로, Steam 창작마당 연동 기능과 UI 디자인을 이 macOS 버전에서 이식했습니다.

## 크레딧

이 프로젝트는 다음 기여자들의 작업을 기반으로 합니다.

- **[MrWindDog](https://github.com/MrWindDog)** — 업스트림 [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) 포크의 메인테이너로, 새로운 기능과 UI 개선 사항을 추가
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac)의 최초 제작자로, 앱의 핵심 아키텍처(SwiftUI, 비디오 배경화면 재생, 가져오기 시스템, 플레이리스트 UI)를 구축
- **1ris_W** — 중국어 i18n 번역
- **[Klaus Zhu](https://github.com/klauszhu1105)** — 원래 로고 디자인
- **[Chen Chia Yang](https://github.com/Unayung)** — 장면 배경화면 렌더링, 웹 배경화면 수정, Steam 창작마당 연동, 다중 디스플레이 지원, zip 가져오기
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal 장면 렌더러와 효과 파이프라인, GLSL→MSL 셰이더 변환 및 캐싱, SceneScript 런타임, 오디오 응답 렌더링, 창작마당/다운로드 전면 개편, 배치 및 성능 설정, 로고 리디자인

원본 프로젝트와 동일하게 [GPL-3.0](../../LICENSE) 라이선스가 적용됩니다.

## 법적 고지

[이용 약관](../../docs/legal/terms-of-use.md) · [개인정보 처리방침](../../docs/legal/privacy-policy.md) · [보안 정책](../../SECURITY.md)

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
