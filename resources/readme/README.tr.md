Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | **Türkçe** | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine, Wallpaper Engine duvar kâğıtlarını (sahne, video ve web) oynatan ücretsiz ve açık kaynaklı bir macOS oynatıcısıdır. Yerel bir Metal işleyiciye sahiptir; efektleri, parçacıkları, 3B modelleri, aydınlatmayı, SceneScript’i, sese duyarlı görselleri ve Steam Atölyesi’ni destekler. Haren Chen ve MrWindDog’un [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) projesinin bir çatalı olarak başladı ve o zamandan beri büyük ölçüde yeniden yazıldı.

> **Not:** Bu proje, Steam’deki ticari Wallpaper Engine ile bağlantılı DEĞİLDİR. Wallpaper Engine’in Steam Atölyesi’ndeki duvar kâğıdı varlıklarını görüntüleyebilen açık kaynaklı bir macOS uygulamasıdır. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Web sitesi:** [openwallpaperengine.app](https://openwallpaperengine.app/) · **Wiki:** [kılavuzlar ve sorun giderme](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![Kitaplık](../../docs/images/library.jpg)

## Öne Çıkanlar

- **Sahne, video ve web duvar kâğıtları** — sahneler, her duvar kâğıdının Metal’e çevrilmiş kendi Wallpaper Engine gölgelendiricileriyle çizilir; efektler, parçacıklar, 3B modeller, ışıklar, zaman çizelgeleri, SceneScript ve sese duyarlı görseller desteklenir. Web duvar kâğıtları WebKit’te veya isteğe bağlı Chromium motorunda çalışır.
- **Steam Atölyesi** — Atölye’ye uygulamanın içinden göz atın, filtreleyin ve indirin ya da duvar kâğıdı klasörlerini ve zip dosyalarını içe aktarın.
- **Sahne Düzenle/Dışa Aktar** — çalışan duvar kâğıdının katmanlarını ve efektlerini doğrudan masaüstünde canlı olarak değiştirin, onu ekran koruyucunuz yapın ya da onu (sahneler ve videolar) iPhone ve iPad için Live Photo kilit ekranı veya Wallpaper Engine’in Android uygulaması için bir paket olarak dışa aktarın.

  ![Sahne Düzenle/Dışa Aktar](../../docs/images/scene-editor-live.jpg)

- **Duvar Kâğıdı Düzenleyici** — Wallpaper Engine’in düzenleyicisinin ruhunu taşıyan bir düzenleyici: katmanlar, önizlemeli efektler, zaman çizelgesi, SceneScript, kullanıcı özellikleri, parçacıklar, Puppet Warp ve derinlik haritasından oluşturulan maskeler. Bir taslağı düzenlersiniz: **Kaydet** taslağı duvar kâğıdına uygular, **Yeni Duvar Kâğıdı Olarak Kaydet** kitaplığa bir kopya ekler; duvar kâğıdının kendi dosyaları hiçbir zaman değiştirilmez.

  ![Duvar Kâğıdı Düzenleyici](../../docs/images/wallpaper-editor.jpg)

- **Ekranlar** — Wallpaper Engine’deki gibi her ekrana ayrı bir duvar kâğıdı, tüm ekranlara yayılan ya da her birine kopyalanan tek bir duvar kâğıdı; ayrıca gruplar, bölmeler ve profiller.

  ![Ekranlar](../../docs/images/displays.png)

- **Çalma listeleri** — duvar kâğıtlarını zamanlayıcıyla, oturum açılışında, günün saatine veya haftanın gününe göre, Wallpaper Engine’in geçişleriyle değiştirin.

  ![Çalma listesi ayarları](../../docs/images/playlists.png)

- **Dışa aktarma** — iPhone ve iPad için Live Photo kilit ekranları ve Wallpaper Engine’in Android paketleri; bir QR koduyla Wi-Fi üzerinden telefona gönderilir.

  ![Wi-Fi üzerinden gönder](../../docs/images/send-over-wifi.png)

- **Renk Teması** — menü çubuğu, vurgu rengi ve renklendirilmiş simgeler ile klasörler duvar kâğıdının rengine uyar; Open Wallpaper Engine’in kendi pencereleri tam rengi kullanabilir.

  ![Renk Teması](../../docs/images/theming.png)

- **MCP Sunucusu eklentisi** — MCP istemcileri duvar kâğıtlarını, çalma listelerini ve ayarları belirleyebilir ve sahneleri düzenleyebilir; bunu yalnızca sizin hesabınızın açabildiği yerel bir bağlantı üzerinden yapar.

  ![MCP Sunucusu eklentisi](../../docs/images/mcp-plugin.png)

Geri kalan her şey, alan alan: [docs/features.md](../../docs/features.md).

## Yükleme

1. En son sürümü [openwallpaperengine.app](https://openwallpaperengine.app/) adresinden veya [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases) sayfasından indirin. Uygulama imzalı ve noter onaylıdır, kendini kendisi günceller.
2. DMG’yi açın ve **Open Wallpaper Engine**’i Uygulamalar klasörüne sürükleyin.

**macOS 14.0 (Sonoma) veya daha yeni bir sürüm** gerekir. Bazı özellikler daha yeni bir macOS, bir izin ya da bir eklenti gerektirir: bkz. [Başlarken](../../docs/getting-started.md#requirements).

## Hızlı Başlangıç

1. Uygulamayı açın. Kurulum yardımcısı dili, SteamCMD’yi, Steam oturumunuzu ve Wallpaper Engine varlıklarını ayarlar ve Wallpaper Engine favorilerinizi içe aktarabilir; her adım atlanabilir.
2. Sahne duvar kâğıtlarını kullanmak istiyorsanız Wallpaper Engine varlıklarını yükleyin (*Ayarlar › Varlıklar*). Bunlar Steam’deki kendi Wallpaper Engine kopyanızdan gelir; video ve web duvar kâğıtları bunlar olmadan da çalışır.
3. **Keşfet** ve **Atölye** sekmelerinde duvar kâğıdı bulun ya da bir duvar kâğıdı klasörünü veya zip dosyasını içe aktarın (*Dosya › Klasörden Duvar Kâğıdı İçe Aktar…*, ⌘I).
4. Kitaplıkta bir duvar kâğıdına tıklayın, ardından ayrıntılarında **Duvar Kâğıdı Yap**’a tıklayın (ya da duvar kâğıdına sağ tıklayıp **Duvar Kâğıdı Yap**’ı seçin). Özellikleri hemen altında listelenir.

Daha fazlası: [Başlarken](../../docs/getting-started.md) ve [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## Gizlilik

Uygulamanın kaydettiği her şey Mac’inizde kalır; uygulama hiçbir veri ya analiz toplamaz. Steam (Atölye ve varlıklar için), openwallpaperengine.app (güncellemeleri denetlemek için) ve GitHub (güncellemeleri indirmek için) ile iletişim kurar; eklentiler yalnızca siz yüklediğinizde indirilir. Ayrıntılar: [uygulamanın bağlandığı yerler](../../docs/getting-started.md#what-the-app-connects-to) ve [Gizlilik Politikası](../../docs/legal/privacy-policy.md).

## Belgeler

- [Başlarken](../../docs/getting-started.md) — gereksinimler, varlıklar, Atölye ve içe aktarma
- [Özellikler](../../docs/features.md) — uygulamanın desteklediği her şey ve nasıl kullanılacağı
- Kılavuzlar: [ekran düzenleri](../../docs/display-layouts.md) · [çalma listeleri](../../docs/playlists.md) · [ekran koruyucu](../../docs/screen-saver.md) · [iPhone ve iPad’e dışa aktarma](../../docs/iphone-ipad-export.md) · [Android’e dışa aktarma](../../docs/android-export.md) · [derinlik haritaları](../../docs/depth-maps.md) · [temalar](../../docs/theming.md) · [MCP Sunucusu](../../docs/mcp.md) · [Chromium web motoru](../../docs/chromium-engine.md)
- [Geliştirme](../../docs/development.md) — kaynaktan derleme ve proje yapısı; ayrıca [CONTRIBUTING.md](../../CONTRIBUTING.md) ve [mimari](../../docs/architecture.md)
- [Wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — kılavuzlar, ayar başvurusu ve sorun giderme

## İlgili Projeler

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) için Steam Atölyesi entegrasyonuna sahip, arayüz tasarımı bu macOS sürümünden aktarılmış bir PyQt6 grafik arayüzü.

## Katkıda Bulunanlar

Bu proje aşağıdaki kişilerin çalışmaları üzerine inşa edilmiştir:

- **[MrWindDog](https://github.com/MrWindDog)** — Üst kaynak [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) çatalının bakımcısı; yeni özellikler ve arayüz iyileştirmeleri ekledi
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac)’in asıl yaratıcısı; uygulamanın temel mimarisini oluşturdu (SwiftUI, video duvar kâğıdı oynatma, içe aktarma sistemi, çalma listesi arayüzü)
- **1ris_W** — Çince yerelleştirme çevirisi
- **[Klaus Zhu](https://github.com/klauszhu1105)** — Özgün logo tasarımı
- **[Chen Chia Yang](https://github.com/Unayung)** — Sahne duvar kâğıdı işleme, web duvar kâğıdı düzeltmeleri, Steam Atölyesi entegrasyonu, çoklu ekran desteği, zip içe aktarma
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal sahne işleyicisi ve efekt ardışık düzeni, GLSL→MSL gölgelendirici çevirisi ve önbelleğe alma, SceneScript çalışma zamanı, sese duyarlı işleme, Atölye ve İndirilenler bölümlerinin yenilenmesi, yerleşim ve performans ayarları, logo yeniden tasarımı

Orijinal projeyle aynı şekilde [GPL-3.0](../../LICENSE) lisansı altında lisanslanmıştır.

## Yasal

[Kullanım Koşulları](../../docs/legal/terms-of-use.md) · [Gizlilik Politikası](../../docs/legal/privacy-policy.md) · [Güvenlik Politikası](../../SECURITY.md)

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
