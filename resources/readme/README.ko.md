Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | **한국어** | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine은 Wallpaper Engine 배경화면(장면, 동영상, 웹)을 재생하는 무료 오픈 소스 macOS 플레이어입니다. 네이티브 Metal 렌더러를 갖추고 있으며 효과, 파티클, 3D 모델, 조명, SceneScript, 오디오 반응형 비주얼, Steam 창작마당을 지원합니다. Haren Chen과 MrWindDog의 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 포크로 시작했으며, 이후 대부분 새로 작성되었습니다.

> **참고:** 이 프로젝트는 Steam의 상용 Wallpaper Engine과 관련이 없습니다. Wallpaper Engine의 Steam 창작마당에 있는 배경화면 에셋을 표시할 수 있는 오픈 소스 macOS 앱입니다. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**위키:** 가이드와 문서는 [위키](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)에 있습니다.

## 요구 사항

### 필수
- **macOS 14.0 이상**(Sonoma). ScreenCaptureKit 오디오 캡처와 Metal 장면 렌더링 모두 이 버전에 의존합니다.

### 선택 사항 — 특정 기능에 필요

| 기능 | 요구 사항 | 설치 |
|---------|-------------|---------|
| Steam 창작마당 탐색 / 다운로드 | `steamcmd` | 자동(선택 사항: `brew install steamcmd`) |
| 오디오 시각화 및 오디오 반응형 SceneScript | 시스템 오디오 녹음 권한(macOS 14.2 이전: 화면 및 시스템 오디오 녹음) | 설정 → 권한 |

#### 셰이더

Wallpaper Engine은 효과를 GLSL로 제공합니다. 이 효과는 배경화면에서 처음 사용될 때 앱에 내장된 glslang과 SPIRV-Cross(`Vendor/ShaderToolchain`)에 의해 Metal로 변환(GLSL → SPIR-V → MSL)된 다음 디스크에 캐시됩니다. 따로 설치할 것은 없습니다. 변환 중에 앱을 멈추게 했거나 앱을 두 번 충돌시킨 셰이더는 이후 실행 시 건너뛰며, 나머지 셰이더는 모두 계속 변환됩니다.

#### Wallpaper Engine 에셋

장면은 Steam에 있는 사용자의 Wallpaper Engine 사본에서 공유 효과, 머티리얼, 셰이더, 서체, SceneScript 런타임을 가져와 사용하며, 앱에는 포함되어 있지 않습니다. *설정 → 에셋*에서 설치하십시오. 앱이 steamcmd로 사본을 다운로드하고(계정이 Wallpaper Engine을 소유해야 함) 에셋과 기본 배경화면만 남긴 후 나머지는 삭제합니다. 기존 Wallpaper Engine 폴더를 선택할 수도 있습니다. 비디오 및 웹 배경화면은 에셋 없이 작동합니다.

## 소스에서 빌드

### 사전 요구 사항
- macOS >= 14.0
- Xcode >= 26.3(macOS 26 SDK)
- Xcode Command Line Tools

### 단계
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

Xcode에서 서명 인증서를 본인의 인증서로 변경하거나 'Sign to Run Locally'를 선택한 다음, `Cmd + R`을 눌러 빌드하고 실행합니다.

소스에서 처음 빌드할 때 Sparkle Swift 패키지를 가져옵니다. 소스에서 빌드한 앱은 업데이트를 확인하지 않습니다.

## 사용법

### Steam 창작마당에서 탐색 및 다운로드

1. 설치할 필요가 없습니다. 처음 필요할 때 앱이 Valve의 SteamCMD를 백그라운드에서 다운로드합니다(Valve에서 받으며 번들로 포함하지 않음). Homebrew(`brew install steamcmd`)는 선택 사항이며, 기존 steamcmd(Homebrew, Steam 또는 직접 선택한 것)가 있으면 그것을 사용합니다
2. **창작마당** 탭으로 전환하고 Steam 계정으로 로그인합니다(Wallpaper Engine을 보유하고 있어야 함)
3. 요청이 표시되면 또는 *설정 → 일반*에서 [Steam Web API 키](https://steamcommunity.com/dev/apikey)를 입력합니다. 키는 Steam에서 확인된 후 키체인에 보관되며, Steam 비밀번호는 저장되지 않습니다(steamcmd는 자체 캐시된 세션을 재사용함)
4. 검색하고 필터링한 다음, 원하는 배경화면에서 **다운로드**를 클릭합니다

### 로컬 파일에서 가져오기

- **폴더:** 파일 > 가져오기 > 폴더에서 배경화면 가져오기 — `project.json`이 포함된 배경화면 폴더를 선택합니다
- **zip:** 파일 > 가져오기를 사용하거나, 배경화면 패키지가 포함된 `.zip` 파일을 드래그 앤 드롭합니다
- **수동:** 배경화면 폴더를 `~/Documents/Open Wallpaper Engine/`에 직접 복사합니다

## 1.0.0에서 지원하는 기능

### 설정, 보관함 및 업데이트
- **설정 도우미** — 처음 실행하면 건너뛸 수 있는 몇 단계로 언어를 고르고, 개인정보 안내를 보여 주고, SteamCMD·Steam 로그인·선택 사항인 Steam Web API 키를 설정하고, Wallpaper Engine 에셋을 설치하고, 배경화면을 가져옵니다.
- **SteamCMD 자동 설정** — 찾지 못하면 Valve의 SteamCMD를 다운로드하며, Homebrew나 Steam의 것이 있으면 그것을 사용합니다.
- **내 Steam 사본의 Wallpaper Engine 에셋** — 로그인 후 SteamCMD로 설치하며, 원하면 Wallpaper Engine 기본 배경화면도 함께 추가합니다.
- **가져오기** — 창작마당 컬렉션과 구독(Steam Web API에서), 기존 Steam 라이브러리의 창작마당 항목, 배경화면 폴더.
- **[wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)** — 가이드, 설정 참조, 문제 해결. 앱의 '지원 및 FAQ'에서 열립니다.
- **자동 업데이트** — 서명된 업데이트가 알아서 설치됩니다(종료할 때, Mac을 10분 동안 사용하지 않을 때, 또는 하루 이내. 이후 빠른 재실행으로 배경화면이 복원됩니다). 설정 › 일반 › 업데이트에서 확인만 하거나, 확인을 끄거나, 베타 업데이트를 받을 수 있습니다. '업데이트 확인…'은 앱 메뉴와 메뉴 막대 메뉴에 있습니다.

### 장면 렌더링
- **Wallpaper Engine 고유의 셰이더** — 레이어, 효과, 재질을 이제 각 배경화면의 원본 셰이더를 Metal로 변환해 그립니다. 창작마당 제작자가 직접 만든 효과도 포함됩니다.
- 컴포지션, 전체 화면, 단색 레이어, 다른 레이어를 샘플링하는 레이어, 33가지 혼합 모드 전체, 더 많은 효과 마스크.
- **원본에 충실한 텍스트 레이아웃** — 텍스트의 크기, 정렬, 위치를 Wallpaper Engine과 같이 정하며, 외곽선, 흐림, 그림자 글꼴 효과를 지원합니다.
- **타임라인** — 키프레임 및 텍스처 애니메이션이 Wallpaper Engine의 1회, 반복, 미러 재생 규칙을 따릅니다.
- 색상 룩업 테이블, Wallpaper Engine의 색 보정, 배경화면 속성의 이미지 필터 및 색상 옵션.
- 애니메이션으로 움직이는 **Puppet Warp** 이미지. 본 물리(스프링, 중력, 제한)와 본에 부착된 오브젝트를 지원합니다.

### 3D 및 조명
- 스키닝, 애니메이션 레이어, 모프 타깃, 루트 모션을 지원하는 **3D 모델**.
- 카메라 경로, 페이드, 흔들림을 지원하는 원근 장면 카메라. 2D 레이어도 깊이 안에 배치됩니다.
- 라이트 쿠키, 그림자, 평면 반사, 거리 및 높이 안개, 볼류메트릭 조명을 지원하는 **장면 조명**.
- **HDR** — HDR 장면을 Wallpaper Engine의 HDR 블룸으로 렌더링하며, '울트라(디스플레이 HDR)' 품질에서는 표시할 수 있는 디스플레이에 EDR로 출력합니다.

### 파티클
- **GPU 파티클** — 모든 파티클 시스템을 GPU에서 3D로 시뮬레이션하며, 3D 컨트롤 포인트를 지원합니다.
- 부모 파티클에 의해 발생하는 것을 포함한 자식 시스템, 이미터 버스트, 지연 및 주기적 방출, 레이어 이미지에서의 방출.
- 모델의 본과의 충돌을 포함한 충돌, 오디오 반응, 모든 축을 중심으로 한 회전.
- 배경화면의 사용자 속성에 연결된 파티클 설정.

### SceneScript 및 미디어
- 완전한 **SceneScript 런타임** — 모듈, 장면/레이어/효과/재질 객체 모델, 애니메이션 이벤트, `localStorage`, 커서 히트 테스트를 지원하며, 각 배경화면의 스크립트는 자체 스레드에서 실행됩니다.
- 스크립트로 레이어, 파티클 시스템, 사운드를 만들고, 안개를 움직이고, 블룸을 제어하고, 퍼펫과 모델의 포즈를 잡을 수 있습니다.
- **지금 재생 중** — 장면 및 웹 배경화면이 현재 트랙과 재생 상태를 받습니다(macOS 15.4 이상).
- 웹 배경화면이 사용자 속성과 실시간 오디오를 받습니다.

### 오디오
- 오디오 스펙트럼을 Wallpaper Engine과 같은 방식으로, 스테레오로 계산합니다.
- **사운드 레이어**가 장면 시계에 맞춰 재생되며, Wallpaper Engine과 같이 배치되는 **공간 음향**을 지원합니다.

### 디스플레이 및 재생
- **디스플레이별 일시 정지** 또는 **모두 일시 정지**. 재생 규칙은 디스플레이마다 판단하며, Wallpaper Engine의 최대화 창 규칙도 지원합니다.
- 디스플레이별 사용자 속성과 '디스플레이 간 속성 동기화'.
- 여러 디스플레이에 표시되는 배경화면은 한 번만 렌더링되어 각 디스플레이에 표시됩니다.
- 새 품질 설정: 렌더링 해상도, 텍스처 해상도, 디스플레이에 맞춘 장면 세부 수준, 반사, 그림자, 볼류메트릭.
- **안전한 재시작** — 앱을 멈추게 하거나 충돌시킨 배경화면은 다음 실행 시 건너뛰고 라이브러리에 표시됩니다.

### 창작마당 및 라이브러리
- Wallpaper Engine의 창작마당 필터: 다음만 표시, 해상도 필터, AND/OR로 조합하는 장르, 모든 카드의 태그.
- 설치된 배경화면에 창작마당 태그가 표시되며 태그로 필터링할 수 있습니다. 에셋이나 종속 항목뿐인 항목은 '설치됨'에 나타나지 않습니다.
- 누락된 창작마당 종속 항목은 자동으로 다운로드되며, 더 이상 쓰이지 않는 항목은 삭제 후 제거됩니다. 모든 다운로드는 배경화면 저장 공간 폴더에 저장됩니다.
- 세부사항의 **재설정**으로 배경화면의 속성과 장면 인스펙터 편집 내용을 제작자가 정한 기본값으로 되돌릴 수 있습니다.
- 배경화면 설정의 속성 조건, 텍스트 행, 슬라이더 형식을 따릅니다.
- Steam 암호는 저장하지 않으며, Steam 웹 API 키는 키체인에 보관합니다.

### 인터페이스 및 언어
- macOS 26의 **Liquid Glass** — 도구 막대, 인스펙터, 글래스 컨트롤을 갖춘 기본 분할 보기. 이전 macOS 버전에서는 기존 모습을 유지합니다.
- **15개의 새 언어**: 독일어, 프랑스어, 스페인어, 포르투갈어(브라질), 이탈리아어, 일본어, 한국어, 중국어(간체, 번체), 러시아어, 폴란드어, 터키어, 우크라이나어, 아랍어, 힌디어. 설정의 언어 선택기에서 고를 수 있습니다.
- 새 앱 아이콘과 메뉴 막대 모양에 맞춰 바뀌는 메뉴 막대 아이콘.

## 현재 제한 사항

- **구현되지 않은 SceneScript 함수** — `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()`는 아직 아무 작업도 하지 않습니다.
- **SceneScript 호환성** — 모든 독점 이벤트 이름, 입력 콜백, 수명 주기의 예외 상황, 정확한 타이밍 의미가 재현되지는 않습니다.
- **드문 파티클 기능** — 구, 상자, 레이어 이미지 외의 이미터 모양과 시스템의 첫 번째 이후 렌더러는 지원되지 않습니다.
- **WebM 비디오** — WebM(VP8/VP9)은 WebKit으로 재생되므로 음악 동기화 효과가 적용되지 않습니다.
- **일부 JPEG 썸네일** — 소수의 TEXB 형식 1 파일에는 macOS가 디코딩할 수 없는 비표준 JPEG 데이터가 포함되어 있습니다.

## 지원되는 배경화면 유형

| 유형 | 상태 |
|------|--------|
| 비디오(.mp4, .webm) | 동작 |
| 웹(HTML/WebGL) | 동작 |
| 장면 — 이미지 레이어 및 타임라인 | 동작(Metal) |
| 장면 — DXT1/DXT3/DXT5 텍스처 | 동작(Metal GPU 디코딩) |
| 장면 — TEXS 스프라이트 / 알파 타임라인 | 동작 |
| 장면 — 스프라이트 파티클 | 동작 |
| 장면 — 고급 파티클 | 부분 지원(제한 사항 참고) |
| 장면 — Wallpaper Engine 및 창작마당 효과(WE 자체 셰이더) | 동작 |
| 장면 — SceneScript | 부분 지원(제한 사항 참고) |
| 장면 — 3D 모델 / 리깅 / 퍼핏 워프 | 동작 |
| 응용 프로그램 | 지원되지 않음 |

## 개인정보 보호

Open Wallpaper Engine이 저장하는 모든 것은 사용자의 Mac에 남습니다. 설정, 보관함, 캐시, SteamCMD 로그인 정보가 여기에 해당합니다. Open Wallpaper Engine에는 서버가 없으며 어떤 데이터나 분석 정보도 수집하지 않습니다. Valve(창작마당을 사용하거나 에셋을 설치할 때는 Steam, SteamCMD를 다운로드할 때는 Valve 서버)와 GitHub에 연결합니다. GitHub에는 앱 업데이트를 확인(GitHub Pages의 appcast)하고 GitHub Releases에서 다운로드하기 위해 연결하며, 개인 데이터는 보내지 않습니다. 업데이트 확인은 설정 › 일반에서 끌 수 있습니다. 웹 배경화면은 자체 온라인 콘텐츠를 불러올 수 있습니다. Steam 비밀번호와 Steam Guard 코드는 SteamCMD로 바로 전달되며 저장되거나 기록되거나 다른 곳으로 전송되지 않습니다. SteamCMD에 저장된 로그인을 다시 사용하기 위해 계정 이름만 기억합니다.

## 프로젝트 구조

- `OpenWallpaperEngine/Scene/Format/` — PKG, TEX/TEXS, scene.json 파서 및 모델
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL 변환(`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), 캐싱, 파이프라인 아카이브
- `Vendor/ShaderToolchain/` — 로컬 패키지로 앱에 내장되는 glslang 및 SPIRV-Cross 소스
- `OpenWallpaperEngine/Scene/Scripting/` — SceneScript 런타임과 오디오/FFT 바인딩
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit 시스템 오디오 캡처
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — Metal 장면 렌더러와 셰이더 라이브러리
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — Steam 창작마당 탐색 및 다운로드
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — 라이브러리 저장, 가져오기, 패키지 변환
- `Scripts/fill-assets-cache.sh` — 개발용 도구: Wallpaper Engine 설치본의 에셋을 로컬 폴더 또는 배경화면 저장 공간의 캐시로 복사합니다
- `Scripts/scene-api-coverage.py` — 설치된 배경화면이 사용하는 SceneScript API와 구현된 API를 비교하여 보고합니다

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
