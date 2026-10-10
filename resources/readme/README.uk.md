Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | **Українська** | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine — безкоштовний плеєр із відкритим кодом для macOS, що відтворює шпалери Wallpaper Engine: сцени, відео та вебшпалери. Він має власний рендерер на Metal і підтримує ефекти, частинки, 3D-моделі, освітлення, SceneScript, візуалізації, що реагують на звук, і Майстерню Steam. Проєкт починався як форк [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) від Харена Чена (Haren Chen) і MrWindDog, а відтоді його здебільшого переписано.

> **Примітка.** Цей проєкт НЕ повʼязаний із комерційною програмою Wallpaper Engine у Steam. Це програма з відкритим кодом для macOS, яка може показувати ресурси шпалер із Майстерні Steam програми Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Сайт:** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Вікі:** [посібники та усунення проблем](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![Бібліотека](../../docs/images/library.png)

## Основні можливості

- **Шпалери-сцени, відео та вебшпалери** — сцени малюються власними шейдерами Wallpaper Engine кожної шпалери, перекладеними на Metal, з ефектами, частинками, 3D-моделями, джерелами світла, таймлайнами, SceneScript і візуалізаціями, що реагують на звук. Вебшпалери працюють у WebKit або в додатковому рушії Chromium.
- **Майстерня Steam** — переглядайте, фільтруйте й викачуйте шпалери з Майстерні просто в програмі або імпортуйте теки й zip-архіви зі шпалерами.
- **Редагування/експорт сцени** — змінюйте шари й ефекти запущеної шпалери просто на робочому столі, робіть її своєю заставкою або експортуйте її (сцени та відео) як екран блокування з Live Photo для iPhone та iPad чи як пакет для Android-застосунку Wallpaper Engine.

  ![Редагування/експорт сцени](../../docs/images/scene-editor-live.png)

- **Редактор шпалер** — редактор у дусі редактора Wallpaper Engine: шари, ефекти з попереднім переглядом, таймлайн, SceneScript, властивості користувача, частинки, Puppet Warp і маски з карти глибини. Ви редагуєте чернетку: **Зберегти** застосовує її до шпалери, **Зберегти як нову шпалеру** додає копію до бібліотеки, а власні файли шпалери ніколи не змінюються.

  ![Редактор шпалер](../../docs/images/wallpaper-editor.png)

- **Дисплеї** — окрема шпалера на кожному дисплеї, одна шпалера, розтягнута на всі дисплеї або продубльована на кожному, а також групи, поділ і профілі — як у Wallpaper Engine.

  ![Дисплеї](../../docs/images/displays.png)

- **Списки відтворення** — зміна шпалер за таймером, під час входу, залежно від часу доби або дня тижня, з переходами Wallpaper Engine.

  ![Параметри списку відтворення](../../docs/images/playlists.png)

- **Експорт** — екрани блокування з Live Photo для iPhone та iPad і пакети для Android-застосунку Wallpaper Engine; на телефон вони надсилаються через Wi-Fi за QR-кодом.

  ![Надсилання через Wi-Fi](../../docs/images/send-over-wifi.png)

- **Колірна тема** — смуга меню, колір акценту, тоновані іконки й теки підлаштовуються під колір шпалери; власні вікна Open Wallpaper Engine можуть використовувати точний колір.

  ![Колірна тема](../../docs/images/theming.png)

- **Плагін MCP-сервера** — MCP-клієнти можуть установлювати шпалери, списки відтворення й параметри та редагувати сцени через локальне зʼєднання, відкрити яке може лише ваш обліковий запис.

  ![Плагін MCP-сервера](../../docs/images/mcp-plugin.png)

Усе інше, за розділами: [docs/features.md](../../docs/features.md).

## Встановлення

1. Викачайте останній випуск з [openwallpaperengine.app](https://openwallpaperengine.app/) або з [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases). Програма підписана й нотаризована та оновлюється самостійно.
2. Відкрийте DMG і перетягніть **Open Wallpaper Engine** до теки «Програми».

Потрібна **macOS 14.0 (Sonoma) або новіша**. Для деяких функцій потрібні новіша macOS, окремий дозвіл або плагін: див. [Початок роботи](../../docs/getting-started.md#requirements).

## Швидкий старт

1. Відкрийте програму. Асистент налаштування задасть мову, SteamCMD, вхід у Steam і ресурси Wallpaper Engine, а також може імпортувати ваші улюблені з Wallpaper Engine; будь-який крок можна пропустити.
2. Якщо вам потрібні шпалери-сцени, встановіть ресурси Wallpaper Engine (*Параметри › Ресурси*). Вони беруться з вашої власної копії Wallpaper Engine у Steam; відео- та вебшпалери працюють і без них.
3. Шукайте шпалери на вкладках **Огляд** і **Майстерня** або імпортуйте теку чи zip-архів зі шпалерою (*Файл › Імпортувати шпалери з папки…*, ⌘I).
4. Клацніть шпалеру в бібліотеці, а потім — **Встановити шпалеру** в її деталях (або клацніть її правою кнопкою й виберіть **Зробити шпалерою**). Її властивості наведено нижче.

Докладніше: [Початок роботи](../../docs/getting-started.md) і [вікі](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Конфіденційність

Усе, що зберігає програма, залишається на вашому Mac, і вона не збирає жодних даних чи аналітики. Програма звертається до Steam (для Майстерні й ресурсів), до openwallpaperengine.app (щоб перевіряти оновлення) і до GitHub (щоб їх викачувати), а плагіни викачуються лише тоді, коли ви їх встановлюєте. Докладніше: [до чого підключається програма](../../docs/getting-started.md#what-the-app-connects-to) і [Політика конфіденційності](../../docs/legal/privacy-policy.md).

## Документація

- [Початок роботи](../../docs/getting-started.md) — вимоги, ресурси, Майстерня та імпорт
- [Можливості](../../docs/features.md) — усе, що підтримує програма, і як цим користуватися
- Посібники: [розкладки дисплеїв](../../docs/display-layouts.md) · [списки відтворення](../../docs/playlists.md) · [заставка](../../docs/screen-saver.md) · [експорт для iPhone та iPad](../../docs/iphone-ipad-export.md) · [експорт для Android](../../docs/android-export.md) · [карти глибини](../../docs/depth-maps.md) · [оформлення](../../docs/theming.md) · [MCP-сервер](../../docs/mcp.md) · [вебрушій Chromium](../../docs/chromium-engine.md)
- [Розробка](../../docs/development.md) — збирання з вихідного коду та структура проєкту; див. також [CONTRIBUTING.md](../../CONTRIBUTING.md) і [архітектуру](../../docs/architecture.md)
- [Вікі](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — посібники, довідник параметрів і усунення проблем

## Повʼязані проєкти

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — графічний інтерфейс на PyQt6 для [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) з інтеграцією Майстерні Steam і дизайном інтерфейсу, перенесеним із цієї версії для macOS.

## Подяки

Цей проєкт створено на основі роботи таких людей:

- **[MrWindDog](https://github.com/MrWindDog)** — супровідник висхідного форка [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac); додав нові функції та вдосконалив інтерфейс
- **[Haren Chen](https://github.com/haren724)** — автор оригінального [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac); створив базову архітектуру програми (SwiftUI, відтворення відеошпалер, система імпорту, інтерфейс списків відтворення)
- **1ris_W** — переклад китайською
- **[Klaus Zhu](https://github.com/klauszhu1105)** — оригінальний дизайн логотипа
- **[Chen Chia Yang](https://github.com/Unayung)** — рендеринг шпалер-сцен, виправлення вебшпалер, інтеграція Майстерні Steam, підтримка кількох дисплеїв, імпорт zip-архівів
- **[Deepratna Awale](https://github.com/deepratna-awale)** — рендерер сцен і конвеєр ефектів на Metal, трансляція шейдерів GLSL→MSL та їх кешування, середовище виконання SceneScript, рендеринг, що реагує на звук, оновлення Майстерні та викачування, параметри розміщення й продуктивності, редизайн логотипа

Поширюється за ліцензією [GPL-3.0](../../LICENSE), як і оригінальний проєкт.

## Правова інформація

[Умови використання](../../docs/legal/terms-of-use.md) · [Політика конфіденційності](../../docs/legal/privacy-policy.md) · [Політика безпеки](../../SECURITY.md)

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
