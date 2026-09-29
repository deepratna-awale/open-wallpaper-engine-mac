Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | **Türkçe** | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine, Wallpaper Engine duvar kâğıtlarını (sahne, video ve web) oynatan ücretsiz ve açık kaynaklı bir macOS oynatıcısıdır. Yerel bir Metal işleyiciye sahiptir; efektleri, parçacıkları, 3B modelleri, aydınlatmayı, SceneScript’i, sese duyarlı görselleri ve Steam Atölyesi’ni destekler. Haren Chen ve MrWindDog’un [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) projesinin bir çatalı olarak başladı ve o zamandan beri büyük ölçüde yeniden yazıldı.

> **Not:** Bu proje, Steam’deki ticari Wallpaper Engine ile bağlantılı DEĞİLDİR. Wallpaper Engine’in Steam Atölyesi’ndeki duvar kâğıdı varlıklarını görüntüleyebilen açık kaynaklı bir macOS uygulamasıdır. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**Wiki:** kılavuzlar ve belgeler [wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)’de.

## Gereksinimler

### Gerekli
- **macOS 14.0 veya sonrası** (Sonoma). ScreenCaptureKit ile ses yakalama ve Metal ile sahne işleme bu sürüme bağlıdır.

### İsteğe bağlı — belirli özellikler için gereklidir

| Özellik | Gereksinim | Kurulum |
|---------|-------------|---------|
| Steam Atölyesi’ne göz atma / Steam Atölyesi’nden indirme | `steamcmd` | Otomatik (isteğe bağlı: `brew install steamcmd`) |
| Ses görselleştiricileri ve sese duyarlı SceneScript | Ekran ve Sistem Sesi Kaydı izni | Ayarlar → İzinler |

#### Gölgelendiriciler

Wallpaper Engine efektlerini GLSL olarak sunar. Bu efektler, bir duvar kâğıdı onları ilk kez kullandığında uygulamaya yerleşik glslang ve SPIRV-Cross (`Vendor/ShaderToolchain`) tarafından Metal’e (GLSL → SPIR-V → MSL) çevrilir ve ardından diskte önbelleğe alınır. Hiçbir şey kurmanız gerekmez. Çevirisi uygulamayı kilitleyen veya iki kez çökerten bir gölgelendirici sonraki açılışlarda atlanır; diğer tüm gölgelendiriciler çevrilmeye devam eder.

#### Wallpaper Engine varlıkları

Sahneler, Steam’deki kendi Wallpaper Engine kopyanızdaki paylaşılan efektleri, malzemeleri, gölgelendiricileri, fontları ve SceneScript çalışma zamanını kullanır; uygulama bunları içermez. Bunları *Ayarlar → Varlıklar*’dan yükleyin: uygulama kopyanızı steamcmd ile indirir (hesabın Wallpaper Engine’e sahip olması gerekir), yalnızca varlıkları ve varsayılan duvar kâğıtlarını tutar, gerisini siler. Mevcut bir Wallpaper Engine klasörünü de seçebilirsiniz. Video ve web duvar kâğıtları onlarsız çalışır.

## Kaynaktan Derleme

### Ön koşullar
- macOS >= 14.0
- Xcode >= 26.3 (macOS 26 SDK)
- Xcode Komut Satırı Araçları

### Adımlar
```sh
git clone https://github.com/deepratna-awale/open-wallpaper-engine-mac.git
cd open-wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

Xcode’da imzalama sertifikasını kendi sertifikanızla değiştirin veya “Sign to Run Locally” seçeneğini belirleyin, ardından derleyip çalıştırmak için `Cmd + R` tuşlarına basın.

Kaynaktan ilk derleme Sparkle Swift paketini indirir. Kaynaktan derlenen sürümler güncelleme denetlemez.

## Kullanım

### Steam Atölyesi’ne Göz Atma ve Steam Atölyesi’nden İndirme

1. Kurulacak bir şey yok: uygulama, Valve’ın SteamCMD’sini ilk gerektiğinde arka planda indirir (Valve’dan, uygulamayla birlikte gelmez). Homebrew (`brew install steamcmd`) isteğe bağlıdır; mevcut bir steamcmd (Homebrew, Steam veya sizin seçtiğiniz) bulunursa o kullanılır
2. **Atölye** sekmesine geçin ve Steam hesabınızla giriş yapın (hesabın Wallpaper Engine’e sahip olması gerekir)
3. İstendiğinde veya *Ayarlar → Genel* bölümünde bir [Steam Web API anahtarı](https://steamcommunity.com/dev/apikey) girin. Anahtar Steam ile doğrulanır ve anahtar zincirinizde saklanır; Steam parolanız hiçbir zaman kaydedilmez (steamcmd kendi önbelleğe alınmış oturumunu yeniden kullanır)
4. Arayın, filtreleyin ve istediğiniz duvar kâğıdında **İndir**’e tıklayın

### Yerel Dosyalardan İçe Aktarma

- **Klasör:** Dosya > Klasörden İçe Aktar — `project.json` içeren duvar kâğıdı klasörlerini seçin
- **Zip:** Dosya > İçe Aktar’ı kullanın veya duvar kâğıdı paketleri içeren bir `.zip` dosyasını sürükleyip bırakın
- **Elle:** Duvar kâğıdı klasörlerini doğrudan `~/Documents/Open Wallpaper Engine/` içine kopyalayın

## 1.0.0 Sürümünün Destekledikleri

### Kurulum, kitaplık ve güncellemeler
- **Kurulum yardımcısı** — ilk açılışta, atlanabilen birkaç adım dili seçer, gizlilik notlarını gösterir, SteamCMD’yi, Steam oturumunu ve isteğe bağlı bir Steam Web API anahtarını ayarlar, Wallpaper Engine varlıklarını yükler ve duvar kâğıtlarınızı getirir.
- **SteamCMD kendini kurar** — bulunamazsa uygulama Valve’ın SteamCMD’sini indirir; Homebrew’un veya Steam’inki varsa o kullanılır.
- **Kendi Steam kopyanızdan Wallpaper Engine varlıkları** — oturum açtıktan sonra SteamCMD ile yüklenir, isteğe bağlı olarak Wallpaper Engine’in varsayılan duvar kâğıtlarıyla.
- **İçe aktarma** — Atölye koleksiyonlarınız ve abonelikleriniz (Steam Web API’sinden), mevcut bir Steam kitaplığının Atölye öğeleri ve duvar kâğıdı klasörleri.
- **[wiki](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)** — kılavuzlar, ayar başvurusu ve sorun giderme; uygulamadaki Destek ve SSS onu açar.
- **Otomatik güncellemeler** — imzalı güncellemeler kendiliğinden yüklenir (çıkışta, Mac’ten 10 dakika uzak kalındığında veya bir gün içinde; ardından hızlı bir yeniden başlatma duvar kâğıtlarınızı geri getirir). Ayarlar › Genel › Güncellemeler’de yalnızca denetlemeyi seçebilir, denetimi kapatabilir ve beta güncellemelerini alabilirsiniz. “Güncellemeleri Denetle…” uygulama menüsünde ve menü çubuğu menüsündedir.

### Sahne işleme
- **Wallpaper Engine’in kendi gölgelendiricileri** — katmanlar, efektler ve malzemeler artık her duvar kâğıdının Metal’e çevrilmiş özgün gölgelendiricileriyle çiziliyor; Atölye yazarlarının kendi yaptığı efektler de buna dahil.
- Kompozisyon, tam ekran ve düz renk katmanları, başka katmanları örnekleyen katmanlar, 33 karışım modunun tümü ve daha fazla efekt maskesi.
- **Özgününe sadık metin yerleşimi** — metin, Wallpaper Engine’deki gibi boyutlandırılır, hizalanır ve konumlandırılır; kontur, bulanıklık ve gölge yazı tipi efektleri de desteklenir.
- **Zaman çizelgeleri** — ana kare ve doku animasyonları, Wallpaper Engine’in tek seferlik, döngü ve ayna oynatma kurallarına uyar.
- Renk arama tabloları, Wallpaper Engine’in renk düzeltmesi ve bir duvar kâğıdının özelliklerindeki görüntü filtresi ve renk seçenekleri.
- Kendi animasyonlarıyla hareket eden **Puppet Warp** görüntüleri; kemik fiziği (yaylar, yerçekimi, sınırlar) ve kemiklere bağlı nesnelerle birlikte.

### 3D ve aydınlatma
- Skinning, animasyon katmanları, morph hedefleri ve root motion destekli **3D modeller**.
- Kamera yolları, geçişler ve sarsıntı destekli perspektif sahne kameraları; 2D katmanlar da derinlikte yer alır.
- Işık maskeleri (cookie), gölgeler, düzlemsel yansımalar, mesafe ve yükseklik sisi ile hacimsel ışıklar destekli **sahne ışıkları**.
- **HDR** — HDR sahneler Wallpaper Engine’in HDR parlamasıyla işlenir ve “Ultra (Ekran HDR)” kalitesi, gösterebilen ekranlara EDR çıktısı verir.

### Parçacıklar
- **GPU parçacıkları** — her parçacık sistemi GPU’da, 3D olarak ve 3D kontrol noktalarıyla simüle edilir.
- Üst sistemin parçacıklarıyla tetiklenenler dahil alt sistemler; yayıcı patlamaları, gecikmeler ve periyodik yayım; bir katmanın görüntüsünden yayım.
- Bir modelin kemikleriyle de çarpışma, sese tepki ve her eksen etrafında dönme.
- Bir duvar kâğıdının kullanıcı özelliklerine bağlı parçacık ayarları.

### SceneScript ve medya
- Eksiksiz bir **SceneScript çalışma zamanı** — modüller, sahne/katman/efekt/malzeme nesne modeli, animasyon olayları, `localStorage` ve imleç isabet testi; her duvar kâğıdının betikleri kendi iş parçacığında çalışır.
- Betikler katman, parçacık sistemi ve ses oluşturabilir, sisi hareket ettirebilir, parlamayı yönetebilir, kuklalara ve modellere poz verebilir.
- **Şu An Çalıyor** — sahne ve web duvar kâğıtları çalan parçayı ve oynatma durumunu alır (macOS 15.4 veya sonrası).
- Web duvar kâğıtları kendi kullanıcı özelliklerini ve canlı sesi alır.

### Ses
- Ses spektrumu, Wallpaper Engine’in hesapladığı şekilde ve stereo olarak hesaplanır.
- **Ses katmanları** sahnenin saatine göre çalar; **uzamsal ses** Wallpaper Engine’deki gibi konumlandırılır.

### Ekranlar ve oynatma
- **Ekran Başına Duraklat** veya **Tümünü Duraklat**; oynatma kuralları, Wallpaper Engine’in büyütülmüş pencere kuralı dahil her ekran için ayrı değerlendirilir.
- Ekran başına kullanıcı özellikleri ve “Özellikleri ekranlar arasında eşitle”.
- Birden fazla ekranda gösterilen bir duvar kâğıdı bir kez işlenir ve her ekranda gösterilir.
- Yeni kalite ayarları: İşleme Çözünürlüğü, Doku Çözünürlüğü, ekrana göre sahne ayrıntısı, yansımalar, gölgeler ve hacimsel efektler.
- **Güvenli yeniden başlatma** — uygulamayı kilitleyen ya da çökerten bir duvar kâğıdı sonraki açılışta atlanır ve arşivde işaretlenir.

### Atölye ve arşiv
- Wallpaper Engine’in Atölye filtreleri: Yalnızca Şunları Göster, bir çözünürlük filtresi, VE/VEYA ile birleştirilen türler ve her kartta etiketler.
- Yüklü duvar kâğıtları Atölye etiketlerini gösterir ve bunlara göre filtrelenebilir; yalnızca varlık ya da bağımlılık içeren öğeler Yüklü bölümünde görünmez.
- Eksik Atölye bağımlılıkları otomatik olarak indirilir, artık kullanılmayanlar silme işleminden sonra kaldırılır. Her indirme Duvar Kâğıdı Deposu klasörüne kaydedilir.
- Ayrıntılar’daki **Sıfırla**, bir duvar kâğıdının özelliklerini ve Sahne Denetçisi’ndeki düzenlemelerini yazarının belirlediği varsayılanlara döndürür.
- Duvar kâğıdının ayarlarındaki özellik koşulları, metin satırları ve sürgü biçimleri dikkate alınır.
- Steam parolaları asla saklanmaz, Steam Web API anahtarı Anahtar Zinciri’nde tutulur.

### Arayüz ve diller
- macOS 26’da **Liquid Glass** — araç çubuğu, denetçi ve cam denetimleriyle yerel bölünmüş görünüm. Daha eski macOS sürümleri alışılmış görünümü korur.
- **15 yeni dil**: Almanca, Fransızca, İspanyolca, Brezilya Portekizcesi, İtalyanca, Japonca, Korece, Basitleştirilmiş ve Geleneksel Çince, Rusça, Lehçe, Türkçe, Ukraynaca, Arapça ve Hintçe; Ayarlar’daki dil seçiciden seçilebilir.
- Yeni bir uygulama simgesi ve menü çubuğunun görünümüne uyan bir menü çubuğu simgesi.

## Mevcut Sınırlamalar

- **Uygulanmamış SceneScript işlevleri** — `setParent()`, `lookAt()`, `lookAtYaw()`, `rotateObjectSpace()`, `transformAttachmentToTexture()`, `getVideoTexture()` henüz hiçbir şey yapmaz.
- **SceneScript uyumluluğu** — Tescilli olay adlarının, giriş geri çağırmalarının, yaşam döngüsü uç durumlarının veya tam zamanlama anlamlarının tümü yeniden üretilmemiştir.
- **Nadir parçacık özellikleri** — Bir sistemin ilkinden sonraki işleyicileri desteklenmez.
- **WebM videoları** — WebM (VP8/VP9) WebKit üzerinden oynatılır, bu yüzden müzik senkronizasyonu efektleri ona uygulanmaz.
- **Bazı JPEG küçük resimleri** — Az sayıda TEXB biçim 1 dosyası, macOS’in çözemediği standart dışı JPEG verileri içerir.
- **Ses özellikleri izin gerektirir** — Ekran ve Sistem Sesi Kaydı izni olmadan ses görselleştiricileri ve sese duyarlı SceneScript yalnızca sessizlik alır.

## Desteklenen Duvar Kâğıdı Türleri

| Tür | Durum |
|------|--------|
| Video (.mp4, .webm) | Çalışıyor |
| Web (HTML/WebGL) | Çalışıyor |
| Sahne — görüntü katmanları ve zaman çizelgeleri | Çalışıyor (Metal) |
| Sahne — DXT1/DXT3/DXT5 dokuları | Çalışıyor (Metal ile GPU’da çözme) |
| Sahne — TEXS hareketli grafikleri / alfa zaman çizelgeleri | Çalışıyor |
| Sahne — hareketli grafik parçacıkları | Çalışıyor |
| Sahne — gelişmiş parçacıklar | Kısmen (bkz. Sınırlamalar) |
| Sahne — Wallpaper Engine ve Atölye efektleri (WE’nin kendi gölgelendiricileri) | Çalışıyor |
| Sahne — SceneScript | Kısmen (bkz. Sınırlamalar) |
| Sahne — 3B modeller / iskelet donatımı / kukla bükme | Çalışıyor |
| Uygulama | Desteklenmiyor |

## Gizlilik

Open Wallpaper Engine’in kaydettiği her şey Mac’inizde kalır: ayarlarınız, kitaplığınız, önbellek ve SteamCMD oturum bilgisi. Open Wallpaper Engine’in sunucusu yoktur ve hiçbir veri ya analiz toplamaz. Valve ile (Atölye’yi kullandığınızda veya varlıkları yüklediğinizde Steam ile, SteamCMD’yi indirmek için de Valve’ın sunucusuyla) ve uygulama güncellemelerini denetlemek (GitHub Pages’teki appcast) ve bunları GitHub Releases’ten indirmek için GitHub ile iletişim kurar; hiçbir kişisel veri gönderilmez. Güncelleme denetimi Ayarlar › Genel’den kapatılabilir. Web duvar kâğıtları kendi çevrimiçi içeriklerini yükleyebilir. Steam parolanız ve Steam Guard kodunuz doğrudan SteamCMD’ye gider; hiçbir zaman saklanmaz, günlüğe kaydedilmez veya başka bir yere gönderilmez. SteamCMD’nin kayıtlı oturumunu yeniden kullanmak için yalnızca hesap adınız hatırlanır.

## Proje Yapısı

- `OpenWallpaperEngine/Scene/Format/` — PKG, TEX/TEXS ve scene.json ayrıştırıcıları ve modelleri
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL çevirisi (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), önbelleğe alma ve ardışık düzen arşivi
- `Vendor/ShaderToolchain/` — uygulamaya yerel bir paket olarak derlenen glslang ve SPIRV-Cross kaynakları
- `OpenWallpaperEngine/Scene/Scripting/` — SceneScript çalışma zamanı ve ses/FFT bağlamaları
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit ile sistem sesi yakalama
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — Metal sahne işleyicisi ve gölgelendirici kitaplığı
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — Steam Atölyesi’ne göz atma ve indirmeler
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — arşiv depolama, içe aktarma ve paket dönüştürme
- `Scripts/fill-assets-cache.sh` — geliştirme yardımcısı: bir Wallpaper Engine kurulumunun varlıklarını yerel bir klasöre veya Duvar Kâğıdı Deposu önbelleğine kopyalar
- `Scripts/scene-api-coverage.py` — kurulu duvar kâğıtlarının hangi SceneScript API’lerini kullandığını ve bunlardan hangilerinin uygulandığını raporlar

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
