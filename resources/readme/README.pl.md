Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | **Polski** | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine to darmowy odtwarzacz open source dla macOS, który wyświetla tapety Wallpaper Engine: sceny, wideo i tapety internetowe. Ma natywny renderer Metal i obsługuje efekty, cząsteczki, modele 3D, oświetlenie, SceneScript, wizualizacje reagujące na dźwięk oraz Steam Workshop. Powstał jako fork [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) autorstwa Harena Chena i MrWindDoga, a od tamtej pory został w dużej mierze przepisany.

> **Uwaga:** Ten projekt NIE jest powiązany z komercyjnym programem Wallpaper Engine dostępnym w Steam. To aplikacja open source dla macOS, która potrafi wyświetlać zasoby tapet z Warsztatu Steam programu Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** poradniki i dokumentacja są w [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Wymagania

### Wymagane
- **macOS 14.0 lub nowszy** (Sonoma). Wymagają go zarówno przechwytywanie dźwięku przez ScreenCaptureKit, jak i renderowanie scen w Metal.

### Opcjonalne — potrzebne do określonych funkcji

| Funkcja | Wymaganie | Instalacja |
|---------|-------------|---------|
| Przeglądanie i pobieranie z Warsztatu Steam | `steamcmd` | Automatycznie (opcjonalnie: `brew install steamcmd`) |
| Wizualizatory dźwięku i SceneScript reagujący na dźwięk | Uprawnienie Nagrywanie dźwięku systemowego (przed macOS 14.2: Nagrywanie ekranu i dźwięku systemowego) | Ustawienia → Uprawnienia |

#### Shadery

Wallpaper Engine dostarcza swoje efekty w postaci GLSL. Są one tłumaczone na Metal (GLSL → SPIR-V → MSL) przez biblioteki glslang i SPIRV-Cross wbudowane w aplikację (`Vendor/ShaderToolchain`) przy pierwszym użyciu przez tapetę, a następnie buforowane na dysku. Nie trzeba niczego instalować. Shader, którego tłumaczenie zawiesiło aplikację lub dwukrotnie spowodowało jej awarię, jest pomijany przy kolejnych uruchomieniach, a wszystkie pozostałe shadery są nadal tłumaczone.

#### Zasoby Wallpaper Engine

Sceny korzystają ze wspólnych efektów, materiałów, shaderów, czcionek i środowiska uruchomieniowego SceneScript z Twojej kopii Wallpaper Engine w Steam; aplikacja ich nie zawiera. Zainstaluj je w *Ustawienia → Zasoby*: aplikacja pobiera Twoją kopię przez steamcmd (konto musi posiadać Wallpaper Engine), zachowuje tylko zasoby i domyślne tapety, a resztę usuwa. Możesz też wybrać istniejący folder Wallpaper Engine. Tapety wideo i sieciowe działają bez nich.

## Kompilowanie ze źródeł

### Wymagania wstępne
- macOS >= 14.0
- Xcode >= 26.3 (macOS 26 SDK)
- Narzędzia wiersza poleceń Xcode

### Kroki
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

W Xcode zmień certyfikat podpisywania na własny lub wybierz „Sign to Run Locally”, a następnie naciśnij `Cmd + R`, aby skompilować i uruchomić aplikację.

Pierwsza kompilacja ze źródeł pobiera pakiet Swift Sparkle. Wersje zbudowane ze źródeł nie sprawdzają aktualizacji.

## Użycie

### Przeglądanie i pobieranie z Warsztatu Steam

1. Nie trzeba nic instalować: przy pierwszej potrzebie aplikacja pobiera w tle SteamCMD od Valve (z serwerów Valve, nie jest dołączony). Homebrew (`brew install steamcmd`) jest opcjonalny; jeśli zostanie znaleziony istniejący steamcmd (Homebrew, Steam lub wskazany przez Ciebie), jest używany
2. Przejdź na kartę **Warsztat** i zaloguj się na swoje konto Steam (konto musi mieć Wallpaper Engine)
3. Po wyświetleniu monitu lub w *Ustawienia → Ogólne* wprowadź [klucz Steam Web API](https://steamcommunity.com/dev/apikey). Jest on weryfikowany w Steam i przechowywany w pęku kluczy; hasło do Steam nigdy nie jest zapisywane (steamcmd korzysta z własnej zapisanej sesji)
4. Wyszukaj i przefiltruj tapety, a następnie kliknij **Pobierz** przy dowolnej z nich

### Import z plików lokalnych

- **Folder:** Plik > Importuj z folderu — wybierz foldery tapet zawierające `project.json`
- **Zip:** Plik > Importuj lub przeciągnij i upuść plik `.zip` zawierający pakiety tapet
- **Ręcznie:** skopiuj foldery tapet bezpośrednio do `~/Documents/Open Wallpaper Engine/`

## Nowości w wersji 1.0.0-beta.5

- **Edytor sceny (Live)** z kartami Tapeta, Wygaszacz ekranu i Eksport na iPhone’a i iPada; **Edytor tapet** (⌥⌘E) działa jako osobna aplikacja: warstwy, efekty, oś czasu, SceneScript, właściwości użytkownika, cząsteczki i Puppet Warp; mapy głębi ([depth-maps.md](../../docs/depth-maps.md)).
- **Układy monitorów** jak w Wallpaper Engine: tapeta na każdy monitor, rozciągnięta, sklonowana, grupy, podziały i profile ([display-layouts.md](../../docs/display-layouts.md)).
- **Eksport**: Live Photos na iPhone’a i iPada ([iphone-ipad-export.md](../../docs/iphone-ipad-export.md)) oraz pakiety `.mpkg` dla Wallpaper Engine na Androidzie, z wysyłaniem przez Wi-Fi ([android-export.md](../../docs/android-export.md)).
- **Wygaszacz ekranu** i obraz ekranu blokady ([screen-saver.md](../../docs/screen-saver.md)).
- Wtyczka **Serwer MCP** ([mcp.md](../../docs/mcp.md)) i **motywy** macOS w kolorze tapety ([theming.md](../../docs/theming.md)).
- Reguły aplikacji, globalne skróty, zrzuty ekranu, Odkrywaj, foldery biblioteki. Wszystkie zmiany: [CHANGELOG.md](../../CHANGELOG.md).

## Co obsługuje wersja 1.0.0

### Konfiguracja, biblioteka i aktualizacje
- **Asystent konfiguracji** — przy pierwszym uruchomieniu kilka kroków, które można pominąć, ustawia język, pokazuje informacje o prywatności, konfiguruje SteamCMD, logowanie do Steam i opcjonalny klucz Steam Web API, instaluje zasoby Wallpaper Engine i sprowadza Twoje tapety.
- **SteamCMD konfiguruje się sam** — jeśli go nie znajdzie, aplikacja pobiera SteamCMD od Valve; używa istniejącego z Homebrew lub Steam.
- **Zasoby Wallpaper Engine z Twojej kopii na Steam** — instalowane przez SteamCMD po zalogowaniu, opcjonalnie z domyślnymi tapetami Wallpaper Engine.
- **Importy** — Twoje kolekcje i subskrypcje z Warsztatu (z Web API Steam), elementy Warsztatu z istniejącej biblioteki Steam i foldery z tapetami.
- **[wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)** — poradniki, opis ustawień i rozwiązywanie problemów; otwiera ją „Pomoc i FAQ” w aplikacji.
- **Automatyczne aktualizacje** — podpisane aktualizacje instalują się same (przy zamknięciu, po 10 minutach nieobecności lub w ciągu doby, a szybkie ponowne uruchomienie przywraca tapety). W Ustawienia › Ogólne › Aktualizacje możesz tylko sprawdzać, wyłączyć sprawdzanie i otrzymywać wersje beta. „Sprawdź uaktualnienia…” jest w menu aplikacji i w menu na pasku menu.

### Renderowanie scen
- **Własne shadery Wallpaper Engine** — warstwy, efekty i materiały są teraz rysowane oryginalnymi shaderami każdej tapety, przetłumaczonymi na Metal, w tym efekty stworzone samodzielnie przez autorów z Warsztatu.
- Warstwy kompozycji, pełnoekranowe i jednolite, warstwy próbkujące inne warstwy, wszystkie 33 tryby mieszania i więcej masek efektów.
- **Wierny układ tekstu** — tekst ma taki rozmiar, wyrównanie i położenie jak w Wallpaper Engine, z efektami czcionki: kontur, rozmycie i cień.
- **Osie czasu** — animacje klatek kluczowych i tekstur działają według reguł Wallpaper Engine dla odtwarzania jednokrotnego, w pętli i lustrzanego.
- Tablice korekcji kolorów (LUT), korekcja kolorów Wallpaper Engine oraz opcje filtra obrazu i koloru we właściwościach tapety.
- Obrazy **Puppet Warp** poruszane własnymi animacjami, z fizyką kości (sprężyny, grawitacja, ograniczenia) i obiektami przyczepionymi do kości.

### 3D i oświetlenie
- **Modele 3D** ze skinningiem, warstwami animacji, morph targetami i root motion.
- Perspektywiczne kamery sceny ze ścieżkami, przejściami i drganiem; warstwy 2D są umieszczane w głębi.
- **Światła sceny** z maskami światła (cookies), cieniami, odbiciami planarnymi, mgłą zależną od odległości i wysokości oraz światłami wolumetrycznymi.
- **HDR** — sceny HDR są renderowane z poświatą HDR Wallpaper Engine, a jakość „Ultra (HDR wyświetlacza)” wysyła obraz EDR na wyświetlacze, które mogą go pokazać.

### Cząsteczki
- **Cząsteczki na GPU** — każdy system cząsteczek jest symulowany na GPU, w 3D, z punktami kontrolnymi 3D.
- Systemy potomne, w tym uruchamiane przez cząsteczki systemu nadrzędnego; serie emisji, opóźnienia i emisja okresowa; emisja z obrazu warstwy.
- Kolizje, także z kośćmi modelu, reakcja na dźwięk i obrót wokół każdej osi.
- Ustawienia cząsteczek powiązane z właściwościami użytkownika tapety.

### SceneScript i multimedia
- Pełne **środowisko uruchomieniowe SceneScript** — moduły, model obiektowy sceny/warstwy/efektu/materiału, zdarzenia animacji, `localStorage` i wykrywanie obiektu pod kursorem; skrypty każdej tapety działają we własnym wątku.
- Skrypty mogą tworzyć warstwy, systemy cząsteczek i dźwięki, przesuwać mgłę, sterować poświatą oraz ustawiać pozy marionetek i modeli.
- **Teraz odtwarzane** — tapety typu scena i tapety internetowe otrzymują bieżący utwór i stan odtwarzania (macOS 15.4 lub nowszy).
- Tapety internetowe otrzymują swoje właściwości użytkownika i dźwięk na żywo.

### Dźwięk
- Widmo dźwięku jest obliczane tak, jak oblicza je Wallpaper Engine, w stereo.
- **Warstwy dźwiękowe** są odtwarzane według zegara sceny, z **dźwiękiem przestrzennym** rozmieszczonym jak w Wallpaper Engine.

### Wyświetlacze i odtwarzanie
- **Wstrzymaj na danym wyświetlaczu** lub **Wstrzymaj wszystkie**; reguły odtwarzania są sprawdzane dla każdego wyświetlacza, w tym reguła Wallpaper Engine dla zmaksymalizowanych okien.
- Właściwości użytkownika dla każdego wyświetlacza oraz opcja „Synchronizuj właściwości między wyświetlaczami”.
- Tapeta pokazywana na kilku wyświetlaczach jest renderowana raz i wyświetlana na każdym z nich.
- Nowe ustawienia jakości: rozdzielczość renderowania, rozdzielczość tekstur, szczegółowość sceny dopasowana do wyświetlacza, odbicia, cienie i efekty wolumetryczne.
- **Bezpieczne ponowne uruchomienie** — tapeta, która zablokowała aplikację lub spowodowała jej awarię, jest pomijana przy następnym uruchomieniu i oznaczana w bibliotece.

### Warsztat i biblioteka
- Filtry Warsztatu z Wallpaper Engine: Pokaż tylko, filtr rozdzielczości, gatunki łączone przez I/LUB oraz tagi na każdej karcie.
- **Animowane podglądy** — kafelki tapet w bibliotece odtwarzają animację podglądu z Warsztatu (GIF), więc tapetę można zobaczyć w ruchu przed jej zastosowaniem. Są odtwarzane tylko wtedy, gdy są widoczne, i wstrzymują się, gdy okno jest ukryte lub włączony jest tryb niskiego zużycia energii.
- Zainstalowane tapety pokazują swoje tagi z Warsztatu i można je według nich filtrować; elementy zawierające wyłącznie zasoby lub zależności nie trafiają do sekcji Zainstalowane.
- Brakujące zależności z Warsztatu są pobierane automatycznie, a nieużywane są usuwane po usunięciu tapety. Każde pobranie trafia do folderu Magazyn tapet.
- **Resetuj** w Szczegółach przywraca właściwości tapety, a także jej zmiany w inspektorze sceny, do wartości domyślnych ustawionych przez autora.
- Uwzględniane są warunki właściwości, wiersze tekstu i formaty suwaków z ustawień tapety.
- Hasła Steam nigdy nie są zapisywane, a klucz Steam Web API jest przechowywany w pęku kluczy.

### Interfejs i języki
- **Liquid Glass** w macOS 26 — natywny widok dzielony z paskiem narzędzi, inspektorem i szklanymi elementami sterującymi. Starsze wersje macOS zachowują dotychczasowy wygląd.
- **15 nowych języków**: niemiecki, francuski, hiszpański, portugalski (Brazylia), włoski, japoński, koreański, chiński uproszczony i tradycyjny, rosyjski, polski, turecki, ukraiński, arabski i hindi, do wyboru w ustawieniach języka.
- Nowa ikona aplikacji i ikona na pasku menu, która dopasowuje się do wyglądu paska menu.

## Obsługiwane typy tapet

| Typ | Stan |
|------|--------|
| Wideo (.mp4, .webm) | Działa |
| Sieć (HTML/WebGL) | Działa |
| Scena — warstwy obrazów i osie czasu | Działa (Metal) |
| Scena — tekstury DXT1/DXT3/DXT5 | Działa (dekodowanie na GPU w Metal) |
| Scena — sprite’y TEXS / osie czasu alfa | Działa |
| Scena — cząsteczki sprite’ów | Działa |
| Scena — zaawansowane cząsteczki | Częściowo (zobacz Ograniczenia) |
| Scena — efekty Wallpaper Engine i z Warsztatu (własne shadery WE) | Działa |
| Scena — SceneScript | Częściowo (zobacz Ograniczenia) |
| Scena — modele 3D / rigging / puppet warp | Działa |
| Aplikacja | Nieobsługiwane |

## Prywatność

Wszystko, co zapisuje Open Wallpaper Engine, zostaje na Twoim Macu: ustawienia, biblioteka, pamięć podręczna i logowanie SteamCMD. Open Wallpaper Engine nie ma serwera i nie zbiera żadnych danych ani statystyk. Łączy się z Valve (ze Steam, gdy korzystasz z Warsztatu lub instalujesz zasoby, oraz z serwerem Valve, aby pobrać SteamCMD) i z GitHubem, aby sprawdzać aktualizacje aplikacji (appcast w GitHub Pages) i pobierać je z GitHub Releases, bez wysyłania jakichkolwiek danych osobowych. Sprawdzanie aktualizacji można wyłączyć w Ustawienia › Ogólne. Tapety internetowe mogą wczytywać własne treści online. Twoje hasło Steam i kod Steam Guard trafiają bezpośrednio do SteamCMD i nigdy nie są zapisywane, rejestrowane ani wysyłane nigdzie indziej; zapamiętywana jest tylko nazwa konta, aby ponownie użyć zapisanego logowania SteamCMD.

## Struktura projektu

- `OpenWallpaperEngine/Scene/Format/` — parsery i modele PKG, TEX/TEXS i scene.json
- `OpenWallpaperEngine/Scene/Shaders/` — tłumaczenie GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), buforowanie i archiwum potoków
- `Vendor/ShaderToolchain/` — źródła glslang i SPIRV-Cross, wbudowywane w aplikację jako lokalny pakiet
- `OpenWallpaperEngine/Scene/Scripting/` — środowisko uruchomieniowe SceneScript i powiązania dźwięku/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — przechwytywanie dźwięku systemowego za pomocą ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — renderer scen Metal i biblioteka shaderów
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — przeglądanie Warsztatu Steam i pobieranie
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — przechowywanie biblioteki, import i konwersja pakietów
- `Scripts/fill-assets-cache.sh` — narzędzie dla programistów: kopiuje zasoby instalacji Wallpaper Engine do lokalnego folderu lub pamięci podręcznej magazynu tapet
- `Scripts/scene-api-coverage.py` — raportuje, których interfejsów API SceneScript używają zainstalowane tapety w porównaniu z tym, co zostało zaimplementowane

## Powiązane projekty

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — graficzny interfejs w PyQt6 dla [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) z integracją z Warsztatem Steam i interfejsem przeniesionym z tej wersji dla macOS.

## Podziękowania

Ten projekt powstał na bazie pracy następujących osób:

- **[MrWindDog](https://github.com/MrWindDog)** — opiekun nadrzędnego forka [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac); dodał nowe funkcje i dopracował interfejs
- **[Haren Chen](https://github.com/haren724)** — twórca oryginalnego projektu [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac); zbudował podstawową architekturę aplikacji (SwiftUI, odtwarzanie tapet wideo, system importu, interfejs playlist)
- **1ris_W** — tłumaczenie na język chiński
- **[Klaus Zhu](https://github.com/klauszhu1105)** — oryginalny projekt logo
- **[Chen Chia Yang](https://github.com/Unayung)** — renderowanie tapet typu scena, poprawki tapet internetowych, integracja z Warsztatem Steam, obsługa wielu wyświetlaczy, import plików zip
- **[Deepratna Awale](https://github.com/deepratna-awale)** — renderer scen i potok efektów w Metal, tłumaczenie shaderów GLSL→MSL i ich buforowanie, środowisko uruchomieniowe SceneScript, renderowanie reagujące na dźwięk, przebudowa Warsztatu i pobierania, ustawienia rozmieszczenia i wydajności, przeprojektowanie logo

Projekt jest udostępniany na licencji [GPL-3.0](../../LICENSE), tak samo jak projekt oryginalny.
