Open Wallpaper Engine (wersja poprawiona)
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | **Polski** | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Poprawiony fork [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) dla macOS, który dodaje renderowanie tapet typu scena i poprawki tapet internetowych.

> **Uwaga:** Ten projekt NIE jest powiązany z komercyjnym programem Wallpaper Engine dostępnym w Steam. To aplikacja open source dla macOS, która potrafi wyświetlać zasoby tapet z Warsztatu Steam programu Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

## Powiązane projekty

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — graficzny interfejs w PyQt6 dla [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) z integracją z Warsztatem Steam i interfejsem przeniesionym z tej wersji dla macOS.

## Podziękowania

Ten projekt powstał na bazie pracy następujących osób:

- **[MrWindDog](https://github.com/MrWindDog)** — opiekun nadrzędnego forka [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac); dodał nowe funkcje i dopracował interfejs
- **[Haren Chen](https://github.com/haren724)** — twórca oryginalnego projektu [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac); zbudował podstawową architekturę aplikacji (SwiftUI, odtwarzanie tapet wideo, system importu, interfejs playlist)
- **[1ris_W](https://github.com/Erica-Iris)** — tłumaczenie na język chiński
- **[Klaus Zhu](https://github.com/klauszhu1105)** — oryginalny projekt logo
- **[Chen Chia Yang](https://github.com/Unayung)** — renderowanie tapet typu scena, poprawki tapet internetowych, integracja z Warsztatem Steam, obsługa wielu wyświetlaczy, import plików zip
- **[Deepratna Awale](https://github.com/deepratna-awale)** — renderer scen i potok efektów w Metal, tłumaczenie shaderów GLSL→MSL i ich buforowanie, środowisko uruchomieniowe SceneScript, renderowanie reagujące na dźwięk, przebudowa Warsztatu i pobierania, ustawienia rozmieszczenia i wydajności, przeprojektowanie logo

Projekt jest udostępniany na licencji [GPL-3.0](../../LICENSE), tak samo jak projekt oryginalny.

## Co obsługuje wersja 0.9.0

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
- Zainstalowane tapety pokazują swoje tagi z Warsztatu i można je według nich filtrować; elementy zawierające wyłącznie zasoby lub zależności nie trafiają do sekcji Zainstalowane.
- Brakujące zależności z Warsztatu są pobierane automatycznie, a nieużywane są usuwane po usunięciu tapety. Każde pobranie trafia do folderu Magazyn tapet.
- **Resetuj** w Szczegółach przywraca właściwości tapety, a także jej zmiany w inspektorze sceny, do wartości domyślnych ustawionych przez autora.
- Uwzględniane są warunki właściwości, wiersze tekstu i formaty suwaków z ustawień tapety.
- Hasła Steam nigdy nie są zapisywane, a klucz Steam Web API jest przechowywany w pęku kluczy.

### Interfejs i języki
- **Liquid Glass** w macOS 26 — natywny widok dzielony z paskiem narzędzi, inspektorem i szklanymi elementami sterującymi. Starsze wersje macOS zachowują dotychczasowy wygląd.
- **15 nowych języków**: niemiecki, francuski, hiszpański, portugalski (Brazylia), włoski, japoński, koreański, chiński uproszczony i tradycyjny, rosyjski, polski, turecki, ukraiński, arabski i hindi, do wyboru w ustawieniach języka.
- Nowa ikona aplikacji i ikona na pasku menu, która dopasowuje się do wyglądu paska menu.

<details>
<summary>Wcześniej w wersji 0.8.1</summary>

### Odtwarzanie tapet
- **Tapety typu scena** renderowane natywnie za pomocą Metal — warstwy obrazów, przekształcenia, osie czasu z klatkami kluczowymi, kolejność głębi oraz dane kamery i projekcji z pliku `scene.json`.
- **Tapety wideo** (`.mp4`, `.webm`) z regulacją szybkości odtwarzania i głośności, powiązaniem szybkości dźwięku i obrazu oraz opcjonalnym zbliżeniem, pochyleniem i nasyceniem zsynchronizowanymi z muzyką.
- **Tapety internetowe** (HTML/WebGL) z włączonym dostępem do plików lokalnych, dzięki czemu tekstury i zasoby WebGL wczytują się prawidłowo, a także z osadzonymi materiałami zewnętrznymi (YouTube/Vimeo).
- **Tryby rozmieszczenia** — Wypełnij ekran, Dopasuj do ekranu, Na środku, Rozciągnij, aby wypełnić ekran, Powiększ.
- **Wiele wyświetlaczy** — inna tapeta na każdym monitorze, włączanie i wyłączanie dla poszczególnych ekranów, wizualny układ monitorów oraz automatyczne wykrywanie nowo podłączonych wyświetlaczy.
- **Wiele biurek (Spaces)** — ciągłe odtwarzanie na wszystkich biurkach, w tym opcja przypisania `Wszystkie biurka`.
- **Reguły odtwarzania** — dalsze działanie, wyciszenie, wstrzymanie lub zatrzymanie, gdy aktywna jest inna aplikacja; prawidłowe działanie po uśpieniu i wybudzeniu oraz przy przełączaniu biurek.

### Obsługa formatu scen
- **Parser PKG** dla archiwów `PKGV` programu Wallpaper Engine (scene.json, materiały, tekstury, shadery).
- **Parser TEX** dla kontenerów `TEXV0005`: osadzone obrazy JPEG/PNG oraz tekstury DXT1/DXT3/DXT5 z mipmapami dekodowane na GPU za pomocą shadera obliczeniowego Metal.
- **Osie czasu sprite’ów TEXS** (0001/0002/0003), w tym prostokąty klatek w pojedynczym atlasie i sekwencje wielu obrazów.
- **Elastyczne dekodowanie pliku scene.json**, które obsługuje polimorficzne pola programu Wallpaper Engine (zwykłe wartości lub `{"script":…,"value":…}`).
- **Zastępczy podgląd** z pliku `preview.jpg/png/gif`, gdy nie można wyodrębnić tekstur.

### Efekty i shadery
- **Około 48 natywnych efektów Metal** obejmujących zniekształcenia, rozmycie (standardowe/precyzyjne/promieniowe/ruchu), bloom, promienie i snopy światła, fale, zmarszczki, kaustyki i przepływ wody, chmury i mgłę, ziarno filmowe, glitch/VHS, aberrację chromatyczną, kluczowanie kolorem, przekształcenia/pochylenie/obrót/zawirowanie/perspektywę, odbicie, załamanie, połysk/migotanie/brokat, wykrywanie krawędzi i inne.
- **Efekty reagujące na dźwięk** — pulsowanie, słupki audio, przesunięcie odcienia zsynchronizowane z dźwiękiem oraz efekt hyperdrive sterowane widmem dźwięku systemowego na żywo.
- **Semantyczne efekty materiałów** — jasność, kontrast, nasycenie, ekspozycja, gamma, odcień, próg bloom, bloom i rozmycie odwzorowane na natywne przebiegi Metal.
- **Tłumaczenie GLSL → SPIR-V → MSL** podczas wczytywania przez wbudowane w aplikację biblioteki glslang i SPIRV-Cross, z definicjami COMBO, rozwiązywaniem dyrektyw include i przenumerowaniem slotów buforów Metal.
- **Bufor wstępnie skompilowanych shaderów** — przetłumaczone pliki `.metal`, skompilowane pliki `.metallib` i pomocnicze pliki `.reflection.json` są buforowane w katalogu `.open-wallpaper-engine/shaders`; skróty (hash) sprawiają, że ponownie tłumaczone są tylko zmienione shadery, a kompilacja odbywa się w tle, więc nigdy nie blokuje renderowania.
- **Dynamiczny katalog efektów** wczytywany z manifestów `assets/effects/*/effect.json` programu Wallpaper Engine, w tym efekty wieloprzebiegowe i powiązania zmiennych uniform odczytane z refleksji.
- **Maskowanie efektów** (do 4 tekstur masek na warstwę), mieszanie addytywne i alfa oraz pula obiektów docelowych renderowania.

### Cząsteczki
- Emitery sprite’ów z losowym czasem życia, rozmiarem, prędkością, kolorem, obrotem, prędkością kątową, grawitacją, oporem i zanikaniem alfa.
- Zaawansowane zachowanie — turbulencje, atraktory, ruch wirowy i stadny (boid), statyczne i powiązane z kursorem punkty kontrolne, połączone segmenty liny oraz ślady z zanikaniem alfa i rozmiaru.
- Animacja klatek z arkuszy sprite’ów za pomocą sekwencji `.tex-json`.
- Skryptowe operatory szybkości emisji, oporu i czasu zanikania alfa.

### Środowisko uruchomieniowe SceneScript
- Trwałe konteksty skryptów dla każdej warstwy: `init()` wywoływane raz, a `update(value)` w każdej klatce.
- Zmienne globalne: `thisScene`, `thisLayer`, `engine`, `input`, `audio(low, high)`, rzeczywiste `fft(index)`, `setTimeout`/`setInterval` oraz trwałe zmienne globalne skryptów.
- Pełna biblioteka matematyczna `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4` oraz funkcje pomocnicze `WEMath`, `WEVector` i `WEColor`.
- Moduły JS środowiska uruchomieniowego Wallpaper Engine wczytywane z `assets/scripts/jsmodules` i `jsclasses`.
- Zdarzenia kursora (`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`) oraz `resizeScreen`.
- Skrypty mogą sterować wartością alfa, punktem początkowym, rozmiarem, skalą, kątami, jasnością i kolorem warstwy, stałymi materiałów, progami efektów i szybkością emisji cząsteczek.
- Rejestrowanie wyjątków skryptów bez duplikatów, z liczbą powtórzeń.

### Dźwięk
- Przechwytywanie dźwięku systemowego za pomocą ScreenCaptureKit, które dostarcza wygładzone 16-pasmowe widmo, przebieg fali oraz poziomy basów, średnich i wysokich tonów.
- **Synchronizacja z muzyką** dla poszczególnych właściwości — dowolną właściwość użytkownika można modulować poziomem dźwięku z konfigurowalną siłą.

### Właściwości użytkownika i inspektor
- Ustawienia projektu w postaci suwaków, pól wyboru, list rozwijanych, pól tekstowych i kolorów, dostępne na pasku bocznym sceny, stosowane na żywo i czytelne dla SceneScript.
- Śledzenie myszy i paralaksa dla warstw ze zdefiniowanym przez autora parametrem `parallaxDepth`.

### Warsztat Steam
- Przeglądanie, wyszukiwanie i filtrowanie według klasyfikacji treści, typu i tagów gatunku, z sortowaniem Popularne teraz / Najnowsze / Najpopularniejsze / Najczęściej subskrybowane oraz numerowanymi stronami.
- Okna podglądu z przyciskami ustawiania tapety, odtwarzania i głośności, oparte na buforze o ograniczonym rozmiarze; zastosowane podglądy trafiają do biblioteki bez ponownego pobierania.
- Integracja z SteamCMD z automatycznym wykrywaniem, logowaniem hasłem, kodem Steam Guard lub zapisaną sesją, osobną kartą Pobrane, kolejką pobierania z możliwością ponawiania i postępem na żywo.
- Zaznaczanie wielu elementów i zakresów, zbiorcze pobieranie i usuwanie wymagające potwierdzenia, zapamiętywanie identyfikatorów pobranych elementów oraz sortowanie według `Data pobrania`.

### Biblioteka i ustawienia
- Import z folderów, z pakietów `.zip` lub przez przeciąganie i upuszczanie.
- Konfigurowalne miejsce przechowywania tapet z migracją istniejącej biblioteki.
- Menu ostatnich tapet na pasku menu.
- Ustawienia wydajności — jakość, antyaliasing, przetwarzanie końcowe oraz zachowanie odtwarzania po utracie aktywności.
- Diagnostyka — ścieżka dołączonych zasobów, wersje bibliotek wbudowanego kompilatora shaderów i statystyki bufora shaderów.

</details>

<details>
<summary>Wcześniej w wersji 0.8.0</summary>

### Obsługa wielu wyświetlaczy
Przypisuj różne tapety do poszczególnych podłączonych monitorów i włączaj lub wyłączaj je dla każdego ekranu z osobna.
- **Panel Ustawienia wyświetlacza** — wizualny układ monitorów przedstawiający wszystkie podłączone ekrany; kliknij, aby wybrać
- **Tapeta dla każdego ekranu** — każdy wyświetlacz może niezależnie wyświetlać inną tapetę
- **Przełącznik włączania i wyłączania** — włączaj lub wyłączaj tapetę dla każdego monitora
- **Automatyczne wykrywanie** — nowe monitory są automatycznie wykrywane i włączane po podłączeniu

### Obsługa wielu biurek
Tapety są teraz wyświetlane na wszystkich biurkach macOS (Spaces) z ciągłym odtwarzaniem — bez przerw przy przełączaniu biurek.

### Menu ostatnich tapet
Szybko przełączaj tapety z menu na pasku menu. Ostatnich 10 używanych tapet jest dostępnych jednym kliknięciem.

### Ustawienia odtwarzania — poprawione
Ustawienia odtwarzania w sekcji wydajności (wstrzymanie, wyciszenie lub zatrzymanie, gdy aktywne są inne aplikacje) działają teraz prawidłowo dla wszystkich typów tapet.

### Przeglądarka Warsztatu Steam
Przeglądaj, wyszukuj i pobieraj tapety bezpośrednio z Warsztatu Steam bez opuszczania aplikacji.
- **Wyszukiwanie i filtrowanie** — wyszukiwanie według nazwy, filtrowanie według klasyfikacji treści (Dla wszystkich/Wątpliwe/Dla dorosłych), typu (Scena/Wideo/Sieć) i tagów gatunku
- **Opcje sortowania** — Popularne teraz, Najnowsze, Najpopularniejsze, Najczęściej subskrybowane
- **Integracja ze steamcmd** — automatyczne wykrywanie steamcmd (Homebrew lub własna ścieżka) oraz instrukcje instalacji, jeśli nie zostanie znaleziony
- **Logowanie do Steam** — obsługa uwierzytelniania hasłem, kodem Steam Guard i zapisaną sesją
- **Pobieranie z postępem** — aktualizacje stanu w czasie rzeczywistym podczas pobierania (uwierzytelnianie, procent pobrania, weryfikacja, kopiowanie)
- **Bezpieczne ustawienia domyślne** — klasyfikacja treści jest domyślnie ustawiona na „Dla wszystkich”, aby odfiltrować treści dla dorosłych

### Import plików zip
Importuj pakiety tapet bezpośrednio z plików `.zip` — bez wcześniejszego ręcznego rozpakowywania. Działa za pomocą polecenia Plik > Importuj oraz przeciągania i upuszczania.

### Zaznaczanie wielu elementów i zbiorcze anulowanie subskrypcji
Kliknij z klawiszem Cmd, aby zaznaczyć wiele tapet, a następnie kliknij prawym przyciskiem, aby zbiorczo anulować ich subskrypcję.

### Wydzielone miejsce przechowywania tapet
Tapety są teraz przechowywane w katalogu `~/Documents/OpenWallpaperEngine/` zamiast bezpośrednio w katalogu Dokumenty, co zapobiega tapetom z „błędem” po sklonowaniu repozytorium na nowym komputerze.

</details>

<details>
<summary>Co poprawiono względem projektu nadrzędnego</summary>

### Tapety internetowe — poprawione szare/puste renderowanie
Tapety oparte na WebGL były renderowane jako szare prostokąty, ponieważ `WKWebView` blokował dostęp do plików lokalnych z teksturami i zasobami.

**Poprawka:** Włączono `allowFileAccessFromFileURLs` i `allowUniversalAccessFromFileURLs` w konfiguracji WKWebView, dzięki czemu shadery WebGL mogą wczytywać lokalne pliki tekstur.

### Tapety typu scena — zaimplementowane od podstaw
Tapety typu scena (najczęstszy typ w Warsztacie Steam) w ogóle nie były zaimplementowane — wyświetlały jedynie „Hello, World!”.

**Nowa implementacja obejmuje:**
- **Parser PKG** — odczytuje format archiwów PKGV programu Wallpaper Engine, aby wyodrębnić scene.json, modele, materiały i tekstury
- **Parser TEX** — odczytuje kontenery tekstur TEXV0005, wyodrębnia osadzone dane obrazów JPEG/PNG i odczytuje mipmapy DXT1/DXT3/DXT5
- **Dekoder Scene JSON** — analizuje plik scene.json z elastycznym dekodowaniem, które obsługuje polimorficzne pola programu Wallpaper Engine (wartości mogą być typami prostymi lub obiektami `{"script":..,"value":..}`)
- **Renderer Metal** — renderuje warstwy obrazów sceny z kompozycją tekstur na GPU i podstawą pod przyszłe efekty shaderów
- **Dekodowanie DXT na GPU** — rozpakowuje tekstury DXT1 (TEXI 7), DXT3 (TEXI 6) i DXT5 (TEXI 4) za pomocą shadera obliczeniowego Metal podczas wczytywania sceny
- **Cząsteczki sprite’ów** — renderuje typowe emitery sprite’ów `sphererandom` z losowym czasem życia, rozmiarem, prędkością, wartością alfa, kolorem, obrotem, prędkością kątową, grawitacją, oporem i zanikaniem alfa
- **Zaawansowane cząsteczki** — obsługuje obrót, zmienność koloru, turbulencje, statyczne i powiązane z kursorem punkty kontrolne, połączone segmenty liny, ślady oraz animację klatek z arkuszy sprite’ów `.tex-json`
- **Animacja TEXS** — dekoduje osie czasu TEXS0001/0002/0003, w tym prostokąty klatek w pojedynczym atlasie i sekwencje tekstur z wielu obrazów
- **Osie czasu sceny** — interpoluje klatki kluczowe wartości alfa, punktu początkowego, skali i kątów obiektów z szybkością 60 FPS
- **Środowisko uruchomieniowe SceneScript** — wykonuje skrypty właściwości w postaci wyrażeń i `export function update(value)` na podstawie dźwięku systemowego z ScreenCaptureKit. Czas `thisScene`, `thisLayer.value`, `engine`, kursor wejściowy, `audio(low, high)`, rzeczywiste `fft(index)`, wyszukiwanie właściwości i trwałe zmienne globalne sterują przekształceniami obrazów, wartością alfa i szybkością emisji cząsteczek.
- **Trwały cykl życia SceneScript** — ponownie wykorzystuje konteksty skryptów dla każdej warstwy, wywołuje `init()` raz, a `update()` w kolejnych klatkach ze wspólnym stanem `dt`, klatki, myszy, przycisków, modyfikatorów, kursora, dźwięku, FFT, właściwości i warstw.
- **Skryptowe operatory cząsteczek** — obsługuje skrypty szybkości emisji cząsteczek, oporu ruchu i czasu zanikania alfa, z elastycznymi liczbowymi i tekstowymi polami cząsteczek.
- **Śledzenie myszy i paralaksa** — stosuje przesunięcie względem kursora i opcjonalne skalowanie perspektywiczne do warstw z metadanymi `parallaxDepth` zdefiniowanymi przez autora; cząsteczki powiązane z kursorem korzystają z tego samego kursora w przestrzeni sceny.
- **Skryptowe właściwości wizualne** — obsługuje skryptową jasność i kolor RGB obiektów, stałe efektów materiałów, skalarne i wektorowe przekształcenia oraz nadpisywanie progów efektów.
- **Właściwości użytkownika** — udostępnia na pasku bocznym sceny udokumentowane ustawienia projektu w postaci suwaków, pól wyboru, list rozwijanych, pól tekstowych i kolorów oraz przekazuje wartości liczbowe i logiczne do SceneScript
- **Wbudowane efekty scen** — wykonuje w rendererze Metal zdefiniowane przez autora wpisy grafu efektów `pulse`, `shake`, `iris` i `waterwaves`
- **Semantyczne efekty materiałów** — odwzorowuje typowe stałe materiałów i skrypty jasności, kontrastu, nasycenia, ekspozycji, gammy, odcienia, progu bloom, bloom i rozmycia na natywne efekty Metal
- **Tłumaczenie shaderów GLSL** — konwertuje spakowane shadery GLSL programu Wallpaper Engine na SPIR-V i MSL podczas wczytywania za pomocą wbudowanych w aplikację bibliotek glslang i SPIRV-Cross; przetłumaczone warianty są buforowane w katalogu `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants`
- **Zastępczy podgląd** — używa pliku preview.jpg/png/gif, gdy nie można wyodrębnić tekstur

### Import — poprawiony import folderów
Panel importu prawidłowo obsługuje teraz zarówno pojedyncze foldery tapet, jak i katalogi nadrzędne zawierające wiele tapet.

</details>

## Obecne ograniczenia

- **Tapety typu aplikacja** — tapety `type: "application"` nie są obsługiwane i nie zostaną uruchomione.
- **Modele 3D i rigging** — przekształcenia kości, kształty mieszane (blend shapes), załączniki i rigi puppet warp (`.mdl`) mają jedynie implementacje zastępcze; takie warstwy są renderowane jako płaskie atlasy.
- **Funkcje skryptów materiałów** — `getMaterial()`, `getMaterialCount()`, `setMaterialProperty()` i `executeMaterialFunction()` to implementacje zastępcze, które nic nie robią lub zwracają puste wartości.
- **Wiązanie niestandardowych shaderów GLSL** — przekonwertowany kod MSL jest buforowany podczas importu, ale shadery zależne od atrybutów specyficznych dla Wallpaper Engine, łańcuchów tekstur lub nieobsługiwanych plików include nie są wiązane z potokiem Metal w czasie działania. Typowe parametry bloom, rozmycia, korekcji kolorów i przekształceń korzystają zastępczo z natywnych odwzorowań Metal.
- **Limit buforów Metal** — shaderów wymagających więcej niż 31 slotów buforów Metal nie można przetłumaczyć; są one trwale oznaczane jako nieobsługiwane w bieżącej wersji potoku.
- **Shadery HLSL** — shadery tylko dla Direct3D dostarczane obok źródeł GLSL są całkowicie pomijane.
- **Zakres obsługi schematów efektów** — nieznane nazwy niestandardowych zmiennych uniform i dowolne schematy parametrów efektów pozostają nieobsługiwane.
- **Zgodność SceneScript** — nie każda zastrzeżona nazwa zdarzenia, wywołanie zwrotne wejścia, przypadek brzegowy cyklu życia ani dokładna semantyka czasu jest odtworzona.
- **Zakres obsługi operatorów cząsteczek** — typowe skryptowe operatory szybkości, oporu i zanikania alfa działają; nietypowe skrypty operatorów, niestandardowe moduły cząsteczek i dowolne schematy operatorów są obsługiwane częściowo.
- **Odzyskiwanie zasobów zewnętrznych** — niektóre pakiety z Warsztatu odwołują się do współdzielonych zasobów TEX, których brak w pobranym pakiecie, i wymagają oryginalnej instalacji Wallpaper Engine.
- **Niektóre miniatury JPEG** — niewielka liczba plików TEXB w formacie 1 zawiera niestandardowe dane JPEG, których macOS nie potrafi zdekodować.
- **Zakres ustawień wydajności** — opcje jakości, antyaliasingu i przetwarzania końcowego są przeznaczone dla tapet typu scena i mają ograniczony wpływ na tapety wideo i internetowe.
- **Funkcje dźwięku wymagają uprawnienia** — bez uprawnienia Nagrywanie ekranu i dźwięku systemowego wizualizatory dźwięku i SceneScript reagujący na dźwięk otrzymują ciszę.

## Obsługiwane typy tapet

| Typ | Stan |
|------|--------|
| Wideo (.mp4, .webm) | Działa |
| Sieć (HTML/WebGL) | Działa |
| Scena — warstwy obrazów i osie czasu | Działa (Metal) |
| Scena — tekstury DXT1/DXT3/DXT5 | Działa (dekodowanie na GPU w Metal) |
| Scena — sprite’y TEXS / osie czasu alfa | Działa |
| Scena — cząsteczki sprite’ów | Działa |
| Scena — zaawansowane cząsteczki | Częściowo (obsługa skryptowej szybkości/oporu/zanikania) |
| Scena — natywne efekty Metal | Działa (około 48 efektów) |
| Scena — przetłumaczone efekty GLSL z Warsztatu | Częściowo (zobacz Ograniczenia) |
| Scena — SceneScript | Częściowo (zobacz Ograniczenia) |
| Scena — modele 3D / rigging / puppet warp | Nieobsługiwane |
| Aplikacja | Nieobsługiwane |

## Wymagania

### Wymagane
- **macOS 13.0 lub nowszy** (Ventura). Wymagają go zarówno przechwytywanie dźwięku przez ScreenCaptureKit, jak i renderowanie scen w Metal.

### Opcjonalne — potrzebne do określonych funkcji

| Funkcja | Wymaganie | Instalacja |
|---------|-------------|---------|
| Przeglądanie i pobieranie z Warsztatu Steam | `steamcmd` | `brew install steamcmd` |
| Wizualizatory dźwięku i SceneScript reagujący na dźwięk | Uprawnienie Nagrywanie ekranu i dźwięku systemowego | Ustawienia → Uprawnienia |

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
git clone https://github.com/unayung/wallpaper-engine-mac
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

W Xcode zmień certyfikat podpisywania na własny lub wybierz „Sign to Run Locally”, a następnie naciśnij `Cmd + R`, aby skompilować i uruchomić aplikację.

## Użycie

### Przeglądanie i pobieranie z Warsztatu Steam

1. Zainstaluj steamcmd (`brew install steamcmd`) lub wskaż aplikacji istniejący plik wykonywalny
2. Przejdź na kartę **Warsztat** i zaloguj się na swoje konto Steam (konto musi mieć Wallpaper Engine)
3. Po wyświetleniu monitu lub w *Ustawienia → Ogólne* wprowadź [klucz Steam Web API](https://steamcommunity.com/dev/apikey). Jest on weryfikowany w Steam i przechowywany w pęku kluczy; hasło do Steam nigdy nie jest zapisywane (steamcmd korzysta z własnej zapisanej sesji)
4. Wyszukaj i przefiltruj tapety, a następnie kliknij **Pobierz** przy dowolnej z nich

### Import z plików lokalnych

- **Folder:** Plik > Importuj z folderu — wybierz foldery tapet zawierające `project.json`
- **Zip:** Plik > Importuj lub przeciągnij i upuść plik `.zip` zawierający pakiety tapet
- **Ręcznie:** skopiuj foldery tapet bezpośrednio do `~/Documents/OpenWallpaperEngine/`

## Struktura projektu

- `OpenWallpaperEngine/Services/SceneParsers/` — parsery i modele PKG, TEX/TEXS i scene.json
- `OpenWallpaperEngine/Services/SceneEffects/` — dynamiczny katalog efektów i zakresy parametrów efektów zdefiniowane przez autorów
- `OpenWallpaperEngine/Scene/Shaders/` — tłumaczenie GLSL → SPIR-V → MSL (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), buforowanie i archiwum potoków
- `Vendor/ShaderToolchain/` — źródła glslang i SPIRV-Cross, wbudowywane w aplikację jako lokalny pakiet
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift` — środowisko uruchomieniowe SceneScript i powiązania dźwięku/FFT
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — przechwytywanie dźwięku systemowego za pomocą ScreenCaptureKit
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — renderer scen Metal i biblioteka shaderów
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — przeglądanie Warsztatu Steam i pobieranie
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — przechowywanie biblioteki, import i konwersja pakietów
- `Scripts/fill-assets-cache.sh` — narzędzie dla programistów: kopiuje zasoby instalacji Wallpaper Engine do lokalnego folderu lub pamięci podręcznej magazynu tapet
- `Scripts/scene-api-coverage.py` — raportuje, których interfejsów API SceneScript używają zainstalowane tapety w porównaniu z tym, co zostało zaimplementowane
