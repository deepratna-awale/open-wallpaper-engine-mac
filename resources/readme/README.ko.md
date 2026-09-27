Open Wallpaper Engine (패치 버전)
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | **한국어** | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

macOS용 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac)의 패치 포크로, 장면 배경화면 렌더링과 웹 배경화면 수정 사항을 추가합니다.

> **참고:** 이 프로젝트는 Steam의 상용 Wallpaper Engine과 관련이 없습니다. Wallpaper Engine의 Steam 창작마당에 있는 배경화면 에셋을 표시할 수 있는 오픈 소스 macOS 앱입니다.

## 관련 프로젝트

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine)용 PyQt6 GUI로, Steam 창작마당 연동 기능과 UI 디자인을 이 macOS 버전에서 이식했습니다.

## 크레딧

이 프로젝트는 다음 기여자들의 작업을 기반으로 합니다.

- **[MrWindDog](https://github.com/MrWindDog)** — 업스트림 [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) 포크의 메인테이너로, 새로운 기능과 UI 개선 사항을 추가
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac)의 최초 제작자로, 앱의 핵심 아키텍처(SwiftUI, 비디오 배경화면 재생, 가져오기 시스템, 플레이리스트 UI)를 구축
- **[1ris_W](https://github.com/Erica-Iris)** — 중국어 i18n 번역
- **[Klaus Zhu](https://github.com/klauszhu1105)** — 앱 로고 아이콘
- **[Chen Chia Yang](https://github.com/Unayung)** — 장면 배경화면 렌더링, 웹 배경화면 수정, Steam 창작마당 연동, 다중 디스플레이 지원, zip 가져오기
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal 장면 렌더러와 효과 파이프라인, GLSL→MSL 셰이더 변환 및 캐싱, SceneScript 런타임, 오디오 응답 렌더링, 창작마당/다운로드 전면 개편, 배치 및 성능 설정

원본 프로젝트와 동일하게 [GPL-3.0](../../LICENSE) 라이선스가 적용됩니다.

## 0.8.1에서 지원하는 기능

### 배경화면 재생
- **장면 배경화면**을 Metal로 네이티브 렌더링합니다. 이미지 레이어, 변형, 키프레임 타임라인, 깊이 순서, `scene.json`의 카메라/투영 데이터를 지원합니다.
- **비디오 배경화면**(`.mp4`, `.webm`)은 재생 속도, 음량, 오디오/비디오 속도 연동, 그리고 음악에 동기화된 확대/기울기/채도(선택 사항)를 지원합니다.
- **웹 배경화면**(HTML/WebGL)은 WebGL 텍스처와 에셋이 올바르게 로드되도록 로컬 파일 접근을 활성화하며, 외부 임베드(YouTube/Vimeo)도 지원합니다.
- **배치 모드** — 화면 채우기, 화면에 맞추기, 중앙 정렬, 전체 화면으로 펼치기, 확대.
- **다중 디스플레이** — 모니터별로 다른 배경화면, 화면별 활성화/비활성화, 시각적인 모니터 배치, 새로 연결된 디스플레이 자동 감지.
- **다중 데스크탑(Spaces)** — 모든 데스크탑에서 끊김 없이 재생하며, `모든 데스크탑` 할당 옵션도 제공합니다.
- **재생 규칙** — 다른 앱이 활성화되면 계속 실행, 소리 끔, 일시 정지 또는 중지합니다. 잠자기/깨우기 및 데스크탑 전환 시에도 올바르게 동작합니다.

### 장면 형식 지원
- Wallpaper Engine `PKGV` 아카이브(scene.json, 머티리얼, 텍스처, 셰이더)를 위한 **PKG 파서**.
- `TEXV0005` 컨테이너를 위한 **TEX 파서**: 내장된 JPEG/PNG, 그리고 밉맵이 있는 DXT1/DXT3/DXT5를 Metal 컴퓨트 셰이더로 GPU에서 디코딩합니다.
- **TEXS 스프라이트 타임라인**(0001/0002/0003). 단일 아틀라스 프레임 사각형과 다중 이미지 시퀀스를 포함합니다.
- Wallpaper Engine의 다형성 필드(일반 값 또는 `{"script":…,"value":…}`)를 처리하는 **유연한 scene.json 디코딩**.
- 텍스처를 추출할 수 없을 때 `preview.jpg/png/gif`로 대체하는 **미리보기 대체**.

### 효과 및 셰이더
- **약 48개의 네이티브 Metal 효과**: 왜곡, 흐림(표준/정밀/방사형/모션), 블룸, 갓레이와 빛줄기, 물결/잔물결/커스틱/흐름, 구름과 안개, 필름 그레인, 글리치/VHS, 색수차, 컬러 키, 변형/기울이기/회전/소용돌이/원근, 반사, 굴절, 광택/일렁임/반짝이, 가장자리 검출 등.
- **오디오 응답 효과** — 펄스, 오디오 막대, 오디오에 동기화된 색조 변화, 하이퍼드라이브를 실시간 시스템 오디오 스펙트럼 데이터로 구동합니다.
- **의미 기반 머티리얼 효과** — 밝기, 대비, 채도, 노출, 감마, 색조, 블룸 임계값, 블룸, 흐림을 네이티브 Metal 패스에 매핑합니다.
- **GLSL → SPIR-V → MSL 변환**을 앱에 링크된 glslang과 SPIRV-Cross로 로드 시점에 수행하며, COMBO define, include 해석, Metal 버퍼 슬롯 번호 재지정을 지원합니다.
- **미리 컴파일된 셰이더 캐시** — 변환된 `.metal`, 컴파일된 `.metallib`, `.reflection.json` 사이드카 파일을 `.open-wallpaper-engine/shaders` 아래에 캐시합니다. 해시로 판별하므로 변경된 셰이더만 다시 변환하며, 백그라운드에서 컴파일하므로 렌더링이 차단되지 않습니다.
- Wallpaper Engine `assets/effects/*/effect.json` 매니페스트에서 읽어 오는 **동적 효과 카탈로그**. 다중 패스 효과와 리플렉션으로 얻은 uniform 바인딩을 포함합니다.
- **효과 마스킹**(레이어당 최대 4개의 마스크 텍스처), 가산 블렌딩과 알파 블렌딩, 풀링된 렌더 타깃 시스템.

### 파티클
- 수명, 크기, 속도, 색상, 회전, 각속도, 중력, 저항, 알파 페이드를 무작위로 지정할 수 있는 스프라이트 이미터.
- 고급 동작 — 난류, 끌개, 소용돌이 및 보이드 움직임, 정적 제어점과 커서 연동 제어점, 연결된 로프 세그먼트, 알파/크기 페이드가 적용되는 트레일.
- `.tex-json` 시퀀스를 통한 스프라이트 시트 프레임 애니메이션.
- 방출 속도, 저항, 알파 페이드 타이밍을 위한 스크립트 연산자.

### SceneScript 런타임
- 레이어별로 유지되는 스크립트 컨텍스트로, `init()`은 한 번, `update(value)`는 매 프레임 호출됩니다.
- 전역 객체: `thisScene`, `thisLayer`, `engine`, `input`, `audio(low, high)`, 실제 데이터 기반 `fft(index)`, `setTimeout`/`setInterval`, 유지되는 스크립트 전역 변수.
- 완전한 `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4` 수학 라이브러리와 `WEMath`, `WEVector`, `WEColor` 헬퍼.
- `assets/scripts/jsmodules` 및 `jsclasses`에서 로드되는 Wallpaper Engine 런타임 JS 모듈.
- 커서 이벤트(`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`)와 `resizeScreen`.
- 스크립트로 레이어의 알파, 원점, 크기, 배율, 각도, 밝기/색상, 머티리얼 상수, 효과 임계값, 파티클 속도를 제어할 수 있습니다.
- 반복 횟수를 포함하여 중복을 제거한 스크립트 예외 로깅.

### 오디오
- ScreenCaptureKit을 통한 시스템 오디오 캡처로, 평활화된 16밴드 스펙트럼, 파형, 저음/중음/고음 레벨을 제공합니다.
- 속성별 **음악 동기화** — 모든 사용자 속성을 설정 가능한 양만큼 오디오 레벨로 변조할 수 있습니다.

### 사용자 속성 및 인스펙터
- 슬라이더, 체크박스, 콤보, 텍스트, 색상 프로젝트 설정을 장면 사이드바에 표시하며, 변경 사항은 즉시 적용되고 SceneScript에서 읽을 수 있습니다.
- `parallaxDepth`가 지정된 레이어의 마우스 추적 및 시차.

### Steam 창작마당
- 콘텐츠 연령 등급, 유형, 장르 태그로 탐색, 검색, 필터링하며, 인기 급상승 / 최신순 / 인기순 / 구독자순 정렬과 번호가 매겨진 페이지 이동을 지원합니다.
- 배경화면 설정, 재생, 음량 제어가 포함된 미리보기 윈도우로, 크기가 제한된 캐시를 사용합니다. 적용한 미리보기는 다시 다운로드하지 않고 라이브러리로 옮겨집니다.
- SteamCMD 연동: 자동 감지, 비밀번호 / Steam Guard / 캐시된 세션 로그인, 전용 다운로드 탭, 대기열에 추가되고 재시도 가능한 다운로드, 실시간 진행률.
- 다중 선택, 범위 선택, 확인 후 진행되는 일괄 다운로드 및 삭제, 다운로드한 ID 유지, `다운로드한 날짜` 정렬.

### 라이브러리 및 설정
- 폴더, `.zip` 패키지 또는 드래그 앤 드롭으로 가져오기.
- 배경화면 저장 공간 위치를 설정할 수 있으며, 기존 라이브러리를 이전할 수 있습니다.
- 상태 막대의 최근 사용한 배경화면 메뉴.
- 성능 설정 — 품질, 앤티앨리어싱, 포스트 프로세싱, 포커스를 잃었을 때의 재생 동작.
- 진단 — 번들로 제공되는 에셋 경로, 내장 셰이더 컴파일러의 라이브러리 버전, 셰이더 캐시 통계.

<details>
<summary>0.8.0까지의 변경 사항</summary>

### 다중 디스플레이 지원
연결된 각 모니터에 서로 다른 배경화면을 지정하고 화면별로 활성화/비활성화를 제어할 수 있습니다.
- **디스플레이 설정 패널** — 연결된 모든 화면을 시각적인 모니터 배치로 표시하며, 클릭하여 선택할 수 있습니다
- **화면별 배경화면** — 각 디스플레이에 서로 다른 배경화면을 독립적으로 표시할 수 있습니다
- **활성화/비활성화 토글** — 모니터별로 배경화면을 켜거나 끌 수 있습니다
- **자동 감지** — 새 모니터를 연결하면 자동으로 감지되어 활성화됩니다

### 다중 데스크탑 지원
이제 배경화면이 모든 macOS 데스크탑(Spaces)에 표시되며 끊김 없이 재생됩니다. 데스크탑을 전환해도 중단되지 않습니다.

### 최근 사용한 배경화면 메뉴
상태 막대 메뉴에서 배경화면을 빠르게 전환할 수 있습니다. 최근 사용한 배경화면 10개가 나열되어 한 번의 클릭으로 선택할 수 있습니다.

### 재생 설정 — 수정됨
성능 재생 설정(다른 앱이 활성화되었을 때 일시 정지/소리 끔/중지)이 이제 모든 유형의 배경화면에서 올바르게 동작합니다.

### Steam 창작마당 브라우저
앱을 벗어나지 않고 Steam 창작마당에서 배경화면을 바로 탐색, 검색, 다운로드할 수 있습니다.
- **검색 및 필터** — 이름으로 검색하고, 연령 등급(전체 이용가/선정적/성인), 유형(장면/비디오/웹), 장르 태그로 필터링합니다
- **정렬 옵션** — 인기 급상승, 최신순, 인기순, 구독자순
- **steamcmd 연동** — steamcmd를 자동으로 감지하며(Homebrew 또는 사용자 지정 경로), 찾을 수 없으면 설치 방법을 안내합니다
- **Steam 로그인** — 비밀번호, Steam Guard, 캐시된 세션 인증을 지원합니다
- **진행률이 표시되는 다운로드** — 다운로드 중 상태(인증 중, 다운로드 %, 검증 중, 복사 중)를 실시간으로 업데이트합니다
- **안전한 기본값** — 성인 콘텐츠를 걸러내기 위해 연령 등급의 기본값은 '전체 이용가'입니다

### zip 가져오기
`.zip` 파일에서 배경화면 패키지를 바로 가져올 수 있으므로 먼저 수동으로 압축을 풀 필요가 없습니다. 파일 > 가져오기와 드래그 앤 드롭으로 사용할 수 있습니다.

### 다중 선택 및 일괄 구독 취소
Cmd+클릭으로 여러 배경화면을 선택한 다음, 오른쪽 클릭으로 일괄 구독 취소할 수 있습니다.

### 배경화면 저장 공간 분리
이제 배경화면은 Documents 디렉토리 바로 아래가 아닌 `~/Documents/OpenWallpaperEngine/`에 저장되므로, 새 컴퓨터에서 저장소를 복제할 때 'error' 배경화면이 나타나는 문제를 방지합니다.

</details>

<details>
<summary>업스트림 대비 패치 내용</summary>

### 웹 배경화면 — 회색/빈 화면 렌더링 수정
WebGL 기반 배경화면은 `WKWebView`가 텍스처와 에셋에 대한 로컬 파일 접근을 차단했기 때문에 회색 사각형으로 렌더링되었습니다.

**수정:** WKWebView 구성에서 `allowFileAccessFromFileURLs`와 `allowUniversalAccessFromFileURLs`를 활성화하여 WebGL 셰이더가 로컬 텍스처 파일을 로드할 수 있도록 했습니다.

### 장면 배경화면 — 처음부터 구현
장면 배경화면(Steam 창작마당에서 가장 흔한 유형)은 전혀 구현되어 있지 않았으며, 'Hello, World!'만 표시되었습니다.

**새 구현에 포함된 내용:**
- **PKG 파서** — Wallpaper Engine의 PKGV 아카이브 형식을 읽어 scene.json, 모델, 머티리얼, 텍스처를 추출합니다
- **TEX 파서** — TEXV0005 텍스처 컨테이너를 읽어 내장된 JPEG/PNG 이미지 데이터를 추출하고, DXT1/DXT3/DXT5 밉맵을 읽습니다
- **Scene JSON 디코더** — Wallpaper Engine의 다형성 필드(값이 일반 유형이거나 `{"script":..,"value":..}` 객체일 수 있음)를 처리하는 유연한 디코딩으로 scene.json을 파싱합니다
- **Metal 렌더러** — GPU 텍스처 합성으로 장면 이미지 레이어를 렌더링하며, 향후 셰이더 효과를 위한 기반을 제공합니다
- **GPU DXT 디코딩** — 장면을 로드할 때 DXT1(TEXI 7), DXT3(TEXI 6), DXT5(TEXI 4) 텍스처를 Metal 컴퓨트 셰이더로 확장합니다
- **스프라이트 파티클** — 일반적인 `sphererandom` 스프라이트 이미터를 수명, 크기, 속도, 알파, 색상, 회전, 각속도, 중력, 저항, 알파 페이드를 무작위로 지정하여 렌더링합니다
- **고급 파티클** — 회전, 색상 변화, 난류, 정적 제어점과 커서 연동 제어점, 연결된 로프 세그먼트, 트레일, `.tex-json` 스프라이트 시트 프레임 애니메이션을 지원합니다
- **TEXS 애니메이션** — 단일 아틀라스 프레임 사각형과 다중 이미지 텍스처 시퀀스를 포함하여 TEXS0001/0002/0003 타임라인을 디코딩합니다
- **장면 타임라인** — 객체의 알파, 원점, 배율, 각도 키프레임을 60 FPS로 보간합니다
- **SceneScript 런타임** — 표현식과 `export function update(value)` 속성 스크립트를 ScreenCaptureKit 시스템 오디오를 기준으로 평가합니다. `thisScene` 타이밍, `thisLayer.value`, `engine`, 입력 커서, `audio(low, high)`, 실제 데이터 기반 `fft(index)`, 속성 조회, 유지되는 전역 변수가 이미지 변형, 알파, 파티클 방출 속도를 제어합니다.
- **유지되는 SceneScript 수명 주기** — 레이어별 스크립트 컨텍스트를 재사용하고, `init()`을 한 번 호출하며, 공유된 `dt`, 프레임, 마우스, 버튼, 보조 키, 커서, 오디오, FFT, 속성, 레이어 상태와 함께 프레임마다 `update()`를 호출합니다.
- **스크립트 파티클 연산자** — 파티클 방출 속도, 이동 저항, 알파 페이드 타이밍을 위한 스크립트를 지원하며, 숫자/문자열 파티클 필드를 유연하게 처리합니다.
- **마우스 추적 및 시차** — `parallaxDepth` 메타데이터가 지정된 레이어에 커서 기준 이동과 선택적인 원근 배율을 적용합니다. 커서 연동 파티클도 동일한 장면 공간 커서를 사용합니다.
- **스크립트 시각 속성** — 스크립트로 제어하는 객체 밝기/RGB 색상, 머티리얼 효과 상수, 스칼라/벡터 변형, 효과 임계값 재정의를 지원합니다.
- **사용자 속성** — 문서화된 슬라이더, 체크박스, 콤보, 텍스트, 색상 프로젝트 설정을 장면 사이드바에 표시하고, 숫자 및 부울 값을 SceneScript에서 사용할 수 있게 합니다
- **내장 장면 효과** — 제작자가 작성한 `pulse`, `shake`, `iris`, `waterwaves` 효과 그래프 항목을 Metal 렌더러에서 실행합니다
- **의미 기반 머티리얼 효과** — 밝기, 대비, 채도, 노출, 감마, 색조, 블룸 임계값, 블룸, 흐림에 대한 일반적인 머티리얼 상수와 스크립트를 네이티브 Metal 효과에 매핑합니다
- **GLSL 셰이더 변환** — 패키지에 포함된 Wallpaper Engine GLSL 셰이더를 앱에 링크된 glslang과 SPIRV-Cross로 로드 시점에 SPIR-V와 MSL로 변환합니다. 변환된 변형은 `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants` 아래에 캐시됩니다
- **미리보기 대체** — 텍스처를 추출할 수 없으면 preview.jpg/png/gif로 대체합니다

### 가져오기 — 폴더 가져오기 수정
가져오기 패널이 이제 개별 배경화면 폴더와 여러 배경화면을 포함하는 상위 디렉토리를 모두 올바르게 처리합니다.

</details>

## 현재 제한 사항

- **응용 프로그램 배경화면** — `type: "application"` 배경화면은 지원되지 않으며 실행되지 않습니다.
- **3D 모델 및 리깅** — 본 변형, 블렌드 셰이프, 부착물, 퍼핏 워프 리그(`.mdl`)는 스텁으로 구현되어 있어, 해당 레이어는 평면 아틀라스로 렌더링됩니다.
- **머티리얼 스크립트 함수** — `getMaterial()`, `getMaterialCount()`, `setMaterialProperty()`, `executeMaterialFunction()`은 아무 작업도 하지 않거나 빈 값을 반환하는 스텁입니다.
- **사용자 정의 GLSL 셰이더 바인딩** — 변환된 MSL은 가져오기 시점에 캐시되지만, Wallpaper Engine 고유의 속성, 텍스처 체인 또는 지원되지 않는 include에 의존하는 셰이더는 런타임 Metal 파이프라인에 바인딩되지 않습니다. 일반적인 블룸, 흐림, 색 보정, 변형 매개변수는 네이티브 Metal 매핑으로 대체됩니다.
- **Metal 버퍼 제한** — Metal의 31개 버퍼 슬롯보다 많은 슬롯이 필요한 셰이더는 변환할 수 없으며, 현재 파이프라인 리비전에서 영구적으로 지원되지 않음으로 표시됩니다.
- **HLSL 셰이더** — GLSL 소스와 함께 제공되는 Direct3D 전용 셰이더는 모두 건너뜁니다.
- **효과 스키마 지원 범위** — 알 수 없는 사용자 정의 uniform 이름과 임의의 효과 매개변수 스키마는 여전히 지원되지 않습니다.
- **SceneScript 호환성** — 모든 독점 이벤트 이름, 입력 콜백, 수명 주기의 예외 상황, 정확한 타이밍 의미가 재현되지는 않습니다.
- **파티클 연산자 지원 범위** — 일반적인 스크립트 속도, 저항, 알파 페이드 연산자는 동작하지만, 흔하지 않은 연산자 스크립트, 사용자 정의 파티클 모듈, 임의의 연산자 스키마는 부분적으로만 지원됩니다.
- **외부 에셋 복구** — 일부 창작마당 패키지는 다운로드한 패키지에 없는 공유 TEX 에셋을 참조하므로 원본 Wallpaper Engine 설치가 필요합니다.
- **일부 JPEG 썸네일** — 소수의 TEXB 형식 1 파일에는 macOS가 디코딩할 수 없는 비표준 JPEG 데이터가 포함되어 있습니다.
- **성능 설정 적용 범위** — 품질, 앤티앨리어싱, 포스트 프로세싱 옵션은 장면 배경화면용으로 설계되었으며, 비디오 및 웹 배경화면에는 효과가 제한적입니다.
- **오디오 기능에는 권한이 필요함** — 화면 기록 권한이 없으면 오디오 시각화와 오디오 반응형 SceneScript는 무음을 받습니다.

## 지원되는 배경화면 유형

| 유형 | 상태 |
|------|--------|
| 비디오(.mp4, .webm) | 동작 |
| 웹(HTML/WebGL) | 동작 |
| 장면 — 이미지 레이어 및 타임라인 | 동작(Metal) |
| 장면 — DXT1/DXT3/DXT5 텍스처 | 동작(Metal GPU 디코딩) |
| 장면 — TEXS 스프라이트 / 알파 타임라인 | 동작 |
| 장면 — 스프라이트 파티클 | 동작 |
| 장면 — 고급 파티클 | 부분 지원(스크립트 속도/저항/페이드 지원) |
| 장면 — 네이티브 Metal 효과 | 동작(약 48개 효과) |
| 장면 — 변환된 창작마당 GLSL 효과 | 부분 지원(제한 사항 참고) |
| 장면 — SceneScript | 부분 지원(제한 사항 참고) |
| 장면 — 3D 모델 / 리깅 / 퍼핏 워프 | 지원되지 않음 |
| 응용 프로그램 | 지원되지 않음 |

## 요구 사항

### 필수
- **macOS 13.0 이상**(Ventura). ScreenCaptureKit 오디오 캡처와 Metal 장면 렌더링 모두 이 버전에 의존합니다.

### 선택 사항 — 특정 기능에 필요

| 기능 | 요구 사항 | 설치 |
|---------|-------------|---------|
| Steam 창작마당 탐색 / 다운로드 | `steamcmd` | `brew install steamcmd` |
| 오디오 시각화 및 오디오 반응형 SceneScript | 화면 기록 권한 | 설정 → 권한 |

#### 셰이더

Wallpaper Engine은 효과를 GLSL로 제공합니다. 이 효과는 배경화면에서 처음 사용될 때 앱에 내장된 glslang과 SPIRV-Cross(`Vendor/ShaderToolchain`)에 의해 Metal로 변환(GLSL → SPIR-V → MSL)된 다음 디스크에 캐시됩니다. 따로 설치할 것은 없습니다. 변환 중에 앱을 멈추게 했거나 앱을 두 번 충돌시킨 셰이더는 이후 실행 시 건너뛰며, 나머지 셰이더는 모두 계속 변환됩니다.

#### Wallpaper Engine 에셋

배경화면이 참조하는 공유 효과, 머티리얼, 셰이더, SceneScript 런타임은 앱에 포함되어 있습니다(`Vendor/we-assets`, `Scripts/vendor-we-assets.sh`로 Wallpaper Engine 설치본에서 갱신). 별도로 설정할 것은 없습니다.

## 소스에서 빌드

### 사전 요구 사항
- macOS >= 14.0
- Xcode >= 26.3(macOS 26 SDK)
- Xcode Command Line Tools

### 단계
```sh
git clone https://github.com/unayung/wallpaper-engine-mac
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

Xcode에서 서명 인증서를 본인의 인증서로 변경하거나 'Sign to Run Locally'를 선택한 다음, `Cmd + R`을 눌러 빌드하고 실행합니다.

## 사용법

### Steam 창작마당에서 탐색 및 다운로드

1. steamcmd를 설치(`brew install steamcmd`)하거나 앱에서 기존 바이너리를 지정합니다
2. **창작마당** 탭으로 전환하고 Steam 계정으로 로그인합니다(Wallpaper Engine을 보유하고 있어야 함)
3. 요청이 표시되면 또는 *설정 → 일반*에서 [Steam Web API 키](https://steamcommunity.com/dev/apikey)를 입력합니다. 키는 Steam에서 확인된 후 키체인에 보관되며, Steam 비밀번호는 저장되지 않습니다(steamcmd는 자체 캐시된 세션을 재사용함)
4. 검색하고 필터링한 다음, 원하는 배경화면에서 **다운로드**를 클릭합니다

### 로컬 파일에서 가져오기

- **폴더:** 파일 > 가져오기 > 폴더에서 배경화면 가져오기 — `project.json`이 포함된 배경화면 폴더를 선택합니다
- **zip:** 파일 > 가져오기를 사용하거나, 배경화면 패키지가 포함된 `.zip` 파일을 드래그 앤 드롭합니다
- **수동:** 배경화면 폴더를 `~/Documents/OpenWallpaperEngine/`에 직접 복사합니다

## 프로젝트 구조

- `OpenWallpaperEngine/Services/SceneParsers/` — PKG, TEX/TEXS, scene.json 파서 및 모델
- `OpenWallpaperEngine/Services/SceneEffects/` — 동적 효과 카탈로그와 제작자가 지정한 효과 매개변수 범위
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL 변환(`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), 캐싱, 파이프라인 아카이브
- `Vendor/ShaderToolchain/` — 로컬 패키지로 앱에 내장되는 glslang 및 SPIRV-Cross 소스
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift` — SceneScript 런타임과 오디오/FFT 바인딩
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit 시스템 오디오 캡처
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — Metal 장면 렌더러와 셰이더 라이브러리
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — Steam 창작마당 탐색 및 다운로드
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — 라이브러리 저장, 가져오기, 패키지 변환
- `Scripts/vendor-we-assets.sh` — 변환된 효과 셰이더와 매니페스트를 `we-assets/`로 가져옵니다
- `Scripts/scene-api-coverage.py` — 설치된 배경화면이 사용하는 SceneScript API와 구현된 API를 비교하여 보고합니다
