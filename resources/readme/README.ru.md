Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | **Русский** | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine — бесплатный плеер с открытым исходным кодом для macOS, воспроизводящий обои Wallpaper Engine: сцены, видео и веб-обои. В нём собственный рендерер на Metal и поддержка эффектов, частиц, 3D-моделей, освещения, SceneScript, визуализаций, реагирующих на звук, и Мастерской Steam. Проект начинался как форк [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) Харена Чена (Haren Chen) и MrWindDog и с тех пор был в основном переписан.

> **Примечание.** Этот проект НЕ связан с коммерческим Wallpaper Engine в Steam. Это приложение для macOS с открытым исходным кодом, которое умеет показывать ресурсы обоев из Мастерской Steam для Wallpaper Engine. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Сайт:** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Вики:** [руководства и решение проблем](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![Медиатека](../../docs/images/library.jpg)

## Основные возможности

- **Обои-сцены, видео и веб-обои** — сцены отрисовываются собственными шейдерами Wallpaper Engine каждых обоев, переведёнными на Metal, с эффектами, частицами, 3D-моделями, источниками света, таймлайнами, SceneScript и визуализациями, реагирующими на звук. Веб-обои работают в WebKit или в дополнительном движке Chromium.
- **Мастерская Steam** — просматривайте, фильтруйте и скачивайте обои из Мастерской прямо в приложении или импортируйте папки и zip-архивы с обоями.
- **Правка/экспорт сцены** — меняйте слои и эффекты запущенных обоев прямо на рабочем столе, делайте из них свою заставку или экспортируйте их (сцены и видео) как экран блокировки с Live Photo для iPhone и iPad либо как пакет для Android-приложения Wallpaper Engine.

  ![Правка/экспорт сцены](../../docs/images/scene-editor-live.jpg)

- **Редактор обоев** — редактор в духе редактора Wallpaper Engine: слои, эффекты с предпросмотром, таймлайн, SceneScript, пользовательские свойства, частицы, Puppet Warp и маски из карты глубины. Вы правите черновик: **Сохранить** применяет его к обоям, **Сохранить как новые обои** добавляет копию в медиатеку, а собственные файлы обоев никогда не меняются.

  ![Редактор обоев](../../docs/images/wallpaper-editor.jpg)

- **Дисплеи** — свои обои на каждом дисплее, одни обои, растянутые на все дисплеи или продублированные на каждом, а также группы, разделение и профили — как в Wallpaper Engine.

  ![Дисплеи](../../docs/images/displays.png)

- **Плейлисты** — смена обоев по таймеру, при входе в систему, по времени суток или дню недели, с переходами Wallpaper Engine.

  ![Настройки плейлиста](../../docs/images/playlists.png)

- **Экспорт** — экраны блокировки с Live Photo для iPhone и iPad и пакеты для Android-приложения Wallpaper Engine; на телефон они отправляются по Wi-Fi через QR-код.

  ![Отправка по Wi-Fi](../../docs/images/send-over-wifi.png)

- **Цветовая тема** — строка меню, акцентный цвет, тонированные значки и папки подстраиваются под цвет обоев; собственные окна Open Wallpaper Engine могут использовать точный цвет.

  ![Цветовая тема](../../docs/images/theming.png)

- **Плагин MCP-сервера** — MCP-клиенты могут устанавливать обои, плейлисты и настройки и редактировать сцены через локальное подключение, открыть которое может только ваша учётная запись.

  ![Плагин MCP-сервера](../../docs/images/mcp-plugin.png)

Всё остальное, по разделам: [docs/features.md](../../docs/features.md).

## Установка

1. Скачайте последний выпуск с [openwallpaperengine.app](https://openwallpaperengine.app/) или из [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases). Приложение подписано и нотариально заверено и обновляется само.
2. Откройте DMG и перетащите **Open Wallpaper Engine** в папку «Программы».

Нужна **macOS 14.0 (Sonoma) или новее**. Для некоторых функций требуется более новая macOS, отдельное разрешение или плагин: см. [Начало работы](../../docs/getting-started.md#requirements).

## Быстрый старт

1. Откройте приложение. Ассистент настройки задаст язык, SteamCMD, вход в Steam и ресурсы Wallpaper Engine, а также может импортировать ваше избранное из Wallpaper Engine; любой шаг можно пропустить.
2. Если вам нужны обои-сцены, установите ресурсы Wallpaper Engine (*Настройки › Ресурсы*). Они берутся из вашей собственной копии Wallpaper Engine в Steam; видео- и веб-обои работают и без них.
3. Ищите обои на вкладках **Рекомендации** и **Мастерская** или импортируйте папку или zip-архив с обоями (*Файл › Импортировать обои из папки…*, ⌘I).
4. Нажмите на обои в медиатеке, а затем — **Установить обои** в их сведениях (или нажмите на них правой кнопкой мыши и выберите **Сделать обоями**). Свойства обоев перечислены ниже.

Подробнее: [Начало работы](../../docs/getting-started.md) и [вики](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Конфиденциальность

Всё, что сохраняет приложение, остаётся на вашем Mac, и оно не собирает никаких данных или аналитики. Приложение обращается к Steam (для Мастерской и ресурсов), к openwallpaperengine.app (чтобы проверить обновления) и к GitHub (чтобы их скачать), а плагины скачиваются только тогда, когда вы их устанавливаете. Подробнее: [к чему подключается приложение](../../docs/getting-started.md#what-the-app-connects-to) и [Политика конфиденциальности](../../docs/legal/privacy-policy.md).

## Документация

- [Начало работы](../../docs/getting-started.md) — требования, ресурсы, Мастерская и импорт
- [Возможности](../../docs/features.md) — всё, что поддерживает приложение, и как этим пользоваться
- Руководства: [раскладки дисплеев](../../docs/display-layouts.md) · [плейлисты](../../docs/playlists.md) · [заставка](../../docs/screen-saver.md) · [экспорт для iPhone и iPad](../../docs/iphone-ipad-export.md) · [экспорт для Android](../../docs/android-export.md) · [карты глубины](../../docs/depth-maps.md) · [оформление](../../docs/theming.md) · [MCP-сервер](../../docs/mcp.md) · [веб-движок Chromium](../../docs/chromium-engine.md)
- [Разработка](../../docs/development.md) — сборка из исходного кода и структура проекта; см. также [CONTRIBUTING.md](../../CONTRIBUTING.md) и [архитектуру](../../docs/architecture.md)
- [Вики](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — руководства, справочник по настройкам и решение проблем

## Связанные проекты

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — графический интерфейс на PyQt6 для [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) с интеграцией Мастерской Steam и дизайном интерфейса, перенесённым из этой версии для macOS.

## Благодарности

Этот проект основан на работе следующих людей:

- **[MrWindDog](https://github.com/MrWindDog)** — сопровождающий вышестоящего форка [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac), добавил новые функции и улучшения интерфейса
- **[Haren Chen](https://github.com/haren724)** — автор оригинального [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac), создал базовую архитектуру приложения (SwiftUI, воспроизведение видеообоев, система импорта, интерфейс плейлистов)
- **1ris_W** — перевод на китайский язык
- **[Klaus Zhu](https://github.com/klauszhu1105)** — оригинальный дизайн логотипа
- **[Chen Chia Yang](https://github.com/Unayung)** — рендеринг обоев типа «Сцена», исправления веб-обоев, интеграция Мастерской Steam, поддержка нескольких дисплеев, импорт zip-архивов
- **[Deepratna Awale](https://github.com/deepratna-awale)** — рендерер сцен на Metal и конвейер эффектов, трансляция шейдеров GLSL→MSL и их кэширование, среда выполнения SceneScript, рендеринг, реагирующий на звук, переработка Мастерской и загрузок, настройки размещения и производительности, редизайн логотипа

Распространяется по лицензии [GPL-3.0](../../LICENSE), как и исходный проект.

## Правовая информация

[Условия использования](../../docs/legal/terms-of-use.md) · [Политика конфиденциальности](../../docs/legal/privacy-policy.md) · [Политика безопасности](../../SECURITY.md)

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
