Open Wallpaper Engine (Yamalı Sürüm)
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | **Türkçe** | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

[Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac)’in macOS için yamalı bir çatalı; sahne duvar kâğıdı işleme ve web duvar kâğıdı düzeltmeleri ekler.

> **Not:** Bu proje, Steam’deki ticari Wallpaper Engine ile bağlantılı DEĞİLDİR. Wallpaper Engine’in Steam Atölyesi’ndeki duvar kâğıdı varlıklarını görüntüleyebilen açık kaynaklı bir macOS uygulamasıdır.

## İlgili Projeler

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) için Steam Atölyesi entegrasyonuna sahip, arayüz tasarımı bu macOS sürümünden aktarılmış bir PyQt6 grafik arayüzü.

## Katkıda Bulunanlar

Bu proje aşağıdaki kişilerin çalışmaları üzerine inşa edilmiştir:

- **[MrWindDog](https://github.com/MrWindDog)** — Üst kaynak [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) çatalının bakımcısı; yeni özellikler ve arayüz iyileştirmeleri ekledi
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac)’in asıl yaratıcısı; uygulamanın temel mimarisini oluşturdu (SwiftUI, video duvar kâğıdı oynatma, içe aktarma sistemi, çalma listesi arayüzü)
- **[1ris_W](https://github.com/Erica-Iris)** — Çince yerelleştirme çevirisi
- **[Klaus Zhu](https://github.com/klauszhu1105)** — Özgün logo tasarımı
- **[Chen Chia Yang](https://github.com/Unayung)** — Sahne duvar kâğıdı işleme, web duvar kâğıdı düzeltmeleri, Steam Atölyesi entegrasyonu, çoklu ekran desteği, zip içe aktarma
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal sahne işleyicisi ve efekt ardışık düzeni, GLSL→MSL gölgelendirici çevirisi ve önbelleğe alma, SceneScript çalışma zamanı, sese duyarlı işleme, Atölye ve İndirilenler bölümlerinin yenilenmesi, yerleşim ve performans ayarları, logo yeniden tasarımı

Orijinal projeyle aynı şekilde [GPL-3.0](../../LICENSE) lisansı altında lisanslanmıştır.

## 0.9.0 Sürümünün Destekledikleri

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

<details>
<summary>Önceki sürüm 0.8.1’deki yenilikler</summary>

### Duvar kâğıdı oynatma
- **Sahne duvar kâğıtları** Metal ile yerel olarak işlenir — görüntü katmanları, dönüşümler, ana kare zaman çizelgeleri, derinlik sıralaması ve `scene.json` dosyasındaki kamera/projeksiyon verileri.
- **Video duvar kâğıtları** (`.mp4`, `.webm`); oynatma hızı, ses düzeyi, ses/görüntü hızı bağlantısı ve isteğe bağlı müzikle eşitlenmiş yakınlaştırma/eğme/doygunluk desteğiyle.
- **Web duvar kâğıtları** (HTML/WebGL); WebGL dokularının ve varlıklarının doğru yüklenmesi için yerel dosya erişimi etkinleştirilmiş olarak, ayrıca harici yerleştirmelerle (YouTube/Vimeo).
- **Yerleşim modları** — Ekranı Doldur, Ekrana Sığdır, Ortala, Ekranı Dolduracak Şekilde Büyüt, Yakınlaştır.
- **Çoklu ekran** — her monitör için farklı duvar kâğıdı, ekran başına etkinleştirme/devre dışı bırakma, görsel monitör yerleşimi ve yeni bağlanan ekranların otomatik algılanması.
- **Çoklu masaüstü (Spaces)** — `Tüm Masaüstleri` atama seçeneği de dahil olmak üzere tüm masaüstlerinde kesintisiz oynatma.
- **Oynatma kuralları** — başka bir uygulama etkinken çalışmaya devam etme, sesi kapatma, duraklatma veya durdurma; uyku/uyanma ve masaüstü geçişlerinde doğru davranış.

### Sahne biçimi desteği
- Wallpaper Engine `PKGV` arşivleri için **PKG ayrıştırıcı** (scene.json, malzemeler, dokular, gölgelendiriciler).
- `TEXV0005` kapsayıcıları için **TEX ayrıştırıcı**: gömülü JPEG/PNG ve bir Metal hesaplama gölgelendiricisiyle GPU’da çözülen, mipmap’li DXT1/DXT3/DXT5.
- Tek atlas kare dikdörtgenleri ve çok görüntülü diziler de dahil olmak üzere **TEXS hareketli grafik zaman çizelgeleri** (0001/0002/0003).
- Wallpaper Engine’in çok biçimli alanlarını (düz değerler veya `{"script":…,"value":…}`) işleyen **esnek scene.json çözümleme**.
- Dokular çıkarılamadığında `preview.jpg/png/gif` dosyasına **önizleme geri dönüşü**.

### Efektler ve gölgelendiriciler
- Bozulma, bulanıklık (standart/hassas/radyal/hareket), bloom, tanrı ışınları ve ışık huzmeleri, su dalgaları/halkaları/kostikleri/akışı, bulutlar ve sis, film greni, glitch/VHS, renk sapması, renk anahtarı, dönüştürme/eğme/döndürme/girdap/perspektif, yansıma, kırılma, parlama/ışıltı/simli parıltı, kenar algılama ve daha fazlasını kapsayan **yaklaşık 48 yerel Metal efekti**.
- **Sese duyarlı efektler** — canlı sistem sesi spektrum verileriyle yönlendirilen nabız, ses çubukları, sesle eşitlenmiş ton kaydırma ve hyperdrive.
- **Anlamsal malzeme efektleri** — parlaklık, karşıtlık, doygunluk, pozlama, gama, ton, bloom eşiği, bloom ve bulanıklık, yerel Metal geçişlerine eşlenir.
- Uygulamaya bağlanmış glslang ve SPIRV-Cross ile yükleme sırasında **GLSL → SPIR-V → MSL çevirisi**; COMBO tanımları, include çözümlemesi ve Metal arabellek yuvası yeniden numaralandırması dahil.
- **Önceden derlenmiş gölgelendirici önbelleği** — çevrilmiş `.metal`, derlenmiş `.metallib` ve `.reflection.json` yardımcı dosyaları `.open-wallpaper-engine/shaders` altında önbelleğe alınır; karma denetimi sayesinde yalnızca değişen gölgelendiriciler yeniden çevrilir ve derleme arka planda yapıldığından işleme hiçbir zaman engellenmez.
- Çok geçişli efektler ve yansıtılan uniform bağlamaları da dahil olmak üzere Wallpaper Engine `assets/effects/*/effect.json` bildirimlerinden okunan **dinamik efekt kataloğu**.
- **Efekt maskeleme** (katman başına en fazla 4 maske dokusu), toplamalı ve alfa karıştırma ve havuzlanmış bir işleme hedefi sistemi.

### Parçacıklar
- Rastgele yaşam süresi, boyut, hız, renk, döndürme, açısal hız, yerçekimi, sürükleme ve alfa solmasına sahip hareketli grafik yayıcıları.
- Gelişmiş davranış — türbülans, çekiciler, girdap ve boid hareketi, statik ve imlece bağlı kontrol noktaları, bağlantılı halat parçaları ve alfa/boyut solmalı izler.
- `.tex-json` dizileriyle hareketli grafik sayfası kare animasyonu.
- Yayma hızı, sürükleme ve alfa solması zamanlaması için betikli operatörler.

### SceneScript çalışma zamanı
- `init()` bir kez, `update(value)` her karede çağrılan, katman başına kalıcı betik bağlamları.
- Global öğeler: `thisScene`, `thisLayer`, `engine`, `input`, `audio(low, high)`, gerçek `fft(index)`, `setTimeout`/`setInterval` ve kalıcı betik global öğeleri.
- Eksiksiz `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4` matematik kitaplığı ile `WEMath`, `WEVector` ve `WEColor` yardımcıları.
- `assets/scripts/jsmodules` ve `jsclasses` konumlarından yüklenen Wallpaper Engine çalışma zamanı JS modülleri.
- İmleç olayları (`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`) ve `resizeScreen`.
- Betikler katman alfasını, orijinini, boyutunu, ölçeğini, açılarını, parlaklığını/rengini, malzeme sabitlerini, efekt eşiklerini ve parçacık hızlarını denetleyebilir.
- Tekrar sayılarıyla birlikte, yinelenenleri ayıklanmış betik istisnası günlükleme.

### Ses
- Yumuşatılmış 16 bantlı bir spektrum, dalga biçimi ve bas/orta/tiz düzeylerini besleyen, ScreenCaptureKit ile sistem sesi yakalama.
- Özellik başına **müzik eşitleme** — herhangi bir kullanıcı özelliği, ayarlanabilir bir miktarla ses düzeyine göre değiştirilebilir.

### Kullanıcı özellikleri ve denetçi
- Sahne kenar çubuğunda gösterilen, anında uygulanan ve SceneScript’ten okunabilen kaydırıcı, onay kutusu, açılır liste, metin ve renk proje ayarları.
- Yazarı tarafından `parallaxDepth` tanımlanmış katmanlar için fare izleme ve paralaks.

### Steam Atölyesi
- İçerik derecelendirmesine, türe ve tür etiketlerine göre göz atma, arama ve filtreleme; Popüler / En Yeni / En Popüler / En Çok Abone Olunan sıralaması ve numaralı sayfalama.
- Sınırlı boyutlu bir önbellekle desteklenen; duvar kâğıdını ayarlama, oynatma ve ses düzeyi denetimlerine sahip önizleme pencereleri. Uygulanan önizlemeler yeniden indirilmeden arşive taşınır.
- Otomatik algılama, parola / Steam Guard / önbelleğe alınmış oturumla giriş, ayrı bir İndirilenler sekmesi, sıraya alınan ve yeniden denenebilen indirmeler ve canlı ilerleme durumuyla SteamCMD entegrasyonu.
- Çoklu seçim, aralık seçimi, onaya bağlı toplu indirme ve silme, kalıcı olarak kaydedilen indirilmiş kimlikler ve `İndirilme Tarihi` sıralaması.

### Arşiv ve ayarlar
- Klasörlerden, `.zip` paketlerinden veya sürükleyip bırakarak içe aktarma.
- Mevcut arşivin taşınmasıyla birlikte yapılandırılabilir duvar kâğıdı depolama konumu.
- Menü çubuğunda son kullanılan duvar kâğıtları menüsü.
- Performans ayarları — kalite, kenar yumuşatma, son işleme ve odak kaybında oynatma davranışı.
- Tanılar — paketlenmiş varlıkların yolu, yerleşik gölgelendirici derleyicisinin kitaplık sürümleri ve gölgelendirici önbelleği istatistikleri.

</details>

<details>
<summary>Önceki sürüm 0.8.0’daki yenilikler</summary>

### Çoklu Ekran Desteği
Bağlı her monitöre farklı duvar kâğıtları atayın ve bunları ekran başına etkinleştirin veya devre dışı bırakın.
- **Ekran Ayarları paneli** — Bağlı tüm ekranları gösteren görsel monitör yerleşimi; seçmek için tıklayın
- **Ekran başına duvar kâğıdı** — Her ekran bağımsız olarak farklı bir duvar kâğıdı gösterebilir
- **Etkinleştirme/devre dışı bırakma anahtarı** — Duvar kâğıdını monitör başına açın veya kapatın
- **Otomatik algılama** — Yeni monitörler bağlandığında otomatik olarak algılanır ve etkinleştirilir

### Çoklu Masaüstü Desteği
Duvar kâğıtları artık tüm macOS masaüstlerinde (Spaces) kesintisiz oynatılır — masaüstleri arasında geçiş yaparken kesinti olmaz.

### Son Kullanılan Duvar Kâğıtları Menüsü
Menü çubuğundaki menüden duvar kâğıtlarını hızla değiştirin. Kullandığınız son 10 duvar kâğıdı tek tıklamayla erişim için listelenir.

### Oynatma Ayarları — Düzeltildi
Performans bölümündeki oynatma ayarları (başka uygulamalar etkinken duraklatma/sesi kapatma/durdurma) artık tüm duvar kâğıdı türlerinde doğru çalışır.

### Steam Atölyesi Tarayıcısı
Uygulamadan çıkmadan duvar kâğıtlarına doğrudan Steam Atölyesi’nden göz atın, arayın ve indirin.
- **Arama ve filtreleme** — Ada göre arama; içerik derecelendirmesine (Herkes/Şüpheli/Yetişkin), türe (Sahne/Video/Web) ve tür etiketlerine göre filtreleme
- **Sıralama seçenekleri** — Popüler, En Yeni, En Popüler, En Çok Abone Olunan
- **steamcmd entegrasyonu** — steamcmd’yi otomatik olarak algılar (Homebrew veya özel yol); bulunamazsa kurulum yönergeleri sunar
- **Steam girişi** — Parola, Steam Guard ve önbelleğe alınmış oturumla kimlik doğrulamayı destekler
- **İlerleme durumuyla indirme** — İndirme sırasında gerçek zamanlı durum güncellemeleri (kimlik doğrulama, indirme yüzdesi, doğrulama, kopyalama)
- **Güvenli varsayılanlar** — Yetişkin içeriği filtrelemek için içerik derecelendirmesi varsayılan olarak “Herkes” şeklindedir

### Zip İçe Aktarma
Duvar kâğıdı paketlerini doğrudan `.zip` dosyalarından içe aktarın — önce elle arşivden çıkarmanıza gerek yoktur. Dosya > İçe Aktar ile ve sürükleyip bırakarak çalışır.

### Çoklu Seçim ve Toplu Abonelikten Çıkma
Birden fazla duvar kâğıdı seçmek için Cmd tuşuna basılı tutarak tıklayın, ardından toplu olarak abonelikten çıkmak için sağ tıklayın.

### Duvar Kâğıdı Depolamasının Ayrılması
Duvar kâğıtları artık doğrudan Belgeler dizini yerine `~/Documents/OpenWallpaperEngine/` içinde saklanır; böylece depo yeni bir bilgisayarda klonlandığında “hatalı” duvar kâğıtları oluşmaz.

</details>

<details>
<summary>Üst kaynağa göre yamalanan özellikler</summary>

### Web Duvar Kâğıtları — Gri/boş görüntü sorunu düzeltildi
`WKWebView`, dokular ve varlıklar için yerel dosya erişimini engellediğinden WebGL tabanlı duvar kâğıtları gri dikdörtgenler olarak görüntüleniyordu.

**Düzeltme:** WKWebView yapılandırmasında `allowFileAccessFromFileURLs` ve `allowUniversalAccessFromFileURLs` etkinleştirildi; böylece WebGL gölgelendiricileri yerel doku dosyalarını yükleyebilir.

### Sahne Duvar Kâğıtları — Sıfırdan uygulandı
Sahne duvar kâğıtları (Steam Atölyesi’ndeki en yaygın tür) hiç uygulanmamıştı — yalnızca “Hello, World!” gösteriyordu.

**Yeni uygulama şunları içerir:**
- **PKG ayrıştırıcı** — scene.json, modeller, malzemeler ve dokuları çıkarmak için Wallpaper Engine’in PKGV arşiv biçimini okur
- **TEX ayrıştırıcı** — TEXV0005 doku kapsayıcılarını okur, gömülü JPEG/PNG görüntü verilerini çıkarır ve DXT1/DXT3/DXT5 mipmap’lerini okur
- **Scene JSON çözücü** — scene.json dosyasını, Wallpaper Engine’in çok biçimli alanlarını (değerler düz türler veya `{"script":..,"value":..}` nesneleri olabilir) işleyen esnek bir çözümlemeyle ayrıştırır
- **Metal işleyicisi** — Sahne görüntü katmanlarını GPU doku birleştirmesiyle işler ve gelecekteki gölgelendirici efektleri için bir temel sağlar
- **GPU’da DXT çözme** — Sahne yüklenirken DXT1 (TEXI 7), DXT3 (TEXI 6) ve DXT5 (TEXI 4) dokularını bir Metal hesaplama gölgelendiricisiyle açar
- **Hareketli grafik parçacıkları** — Yaygın `sphererandom` hareketli grafik yayıcılarını rastgele yaşam süresi, boyut, hız, alfa, renk, döndürme, açısal hız, yerçekimi, sürükleme ve alfa solmalarıyla işler
- **Gelişmiş parçacıklar** — Döndürme, renk çeşitliliği, türbülans, statik ve imlece bağlı kontrol noktaları, bağlantılı halat parçaları, izler ve `.tex-json` hareketli grafik sayfası kare animasyonunu destekler
- **TEXS animasyonu** — Tek atlas kare dikdörtgenleri ve çok görüntülü doku dizileri de dahil olmak üzere TEXS0001/0002/0003 zaman çizelgelerini çözer
- **Sahne zaman çizelgeleri** — Nesne alfası, orijini, ölçeği ve açıları ana karelerini 60 FPS’de ara değerlerle hesaplar
- **SceneScript çalışma zamanı** — İfade ve `export function update(value)` özellik betiklerini ScreenCaptureKit sistem sesine göre değerlendirir. `thisScene` zamanlaması, `thisLayer.value`, `engine`, giriş imleci, `audio(low, high)`, gerçek `fft(index)`, özellik araması ve kalıcı global öğeler; görüntü dönüşümlerini, alfayı ve parçacık yayma hızlarını yönlendirir.
- **Kalıcı SceneScript yaşam döngüsü** — Katman başına betik bağlamlarını yeniden kullanır, `init()` işlevini bir kez çağırır ve `update()` işlevini paylaşılan `dt`, kare, fare, düğme, değiştirici tuş, imleç, ses, FFT, özellik ve katman durumuyla kareler boyunca çağırır.
- **Betikli parçacık operatörleri** — Esnek sayısal/dize parçacık alanlarıyla birlikte parçacık yayma hızı, hareket sürüklemesi ve alfa solması zamanlaması betiklerini destekler.
- **Fare izleme ve paralaks** — Yazarı tarafından `parallaxDepth` meta verisi tanımlanmış katmanlara imlece göreli öteleme ve isteğe bağlı perspektif ölçekleme uygular; imlece bağlı parçacıklar aynı sahne uzayı imlecini kullanır.
- **Betikli görsel özellikler** — Betikli nesne parlaklığını/RGB rengini, malzeme efekti sabitlerini, skaler/vektör dönüşümleri ve efekt eşiği geçersiz kılmalarını destekler.
- **Kullanıcı özellikleri** — Belgelenmiş kaydırıcı, onay kutusu, açılır liste, metin ve renk proje ayarlarını sahne kenar çubuğunda gösterir ve sayısal ve boole değerlerini SceneScript’in kullanımına sunar
- **Yerleşik sahne efektleri** — Yazarı tarafından tanımlanmış `pulse`, `shake`, `iris` ve `waterwaves` efekt grafiği girdilerini Metal işleyicisinde yürütür
- **Anlamsal malzeme efektleri** — Parlaklık, karşıtlık, doygunluk, pozlama, gama, ton, bloom eşiği, bloom ve bulanıklık için yaygın malzeme sabitlerini ve betiklerini yerel Metal efektlerine eşler
- **GLSL gölgelendirici çevirisi** — Paketlenmiş Wallpaper Engine GLSL gölgelendiricilerini, uygulamaya bağlanmış glslang ve SPIRV-Cross ile yükleme sırasında SPIR-V ve MSL’ye dönüştürür; çevrilmiş varyantlar `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants` altında önbelleğe alınır
- **Önizleme geri dönüşü** — Dokular çıkarılamadığında preview.jpg/png/gif dosyasına geri döner

### İçe Aktarma — Klasör içe aktarma düzeltildi
İçe aktarma paneli artık hem tek tek duvar kâğıdı klasörlerini hem de birden fazla duvar kâğıdı içeren üst dizinleri doğru şekilde işler.

</details>

## Mevcut Sınırlamalar

- **Uygulama duvar kâğıtları** — `type: "application"` duvar kâğıtları desteklenmez ve çalışmaz.
- **3B modeller ve iskelet donatımı** — Kemik dönüşümleri, karışım şekilleri (blend shapes), ekler ve kukla bükme (puppet warp) donatımları (`.mdl`) yalnızca yer tutucu olarak uygulanmıştır; etkilenen katmanlar düz atlaslar olarak işlenir.
- **Malzeme betiği işlevleri** — `getMaterial()`, `getMaterialCount()`, `setMaterialProperty()` ve `executeMaterialFunction()` hiçbir şey yapmayan veya boş değer döndüren yer tutuculardır.
- **Özel GLSL gölgelendirici bağlama** — Dönüştürülmüş MSL içe aktarma sırasında önbelleğe alınır, ancak Wallpaper Engine’e özgü niteliklere, doku zincirlerine veya desteklenmeyen include dosyalarına bağımlı gölgelendiriciler çalışma zamanındaki Metal ardışık düzenine bağlanmaz. Yaygın bloom, bulanıklık, renk düzeltme ve dönüşüm parametreleri yerel Metal eşlemelerine geri döner.
- **Metal arabellek sınırı** — Metal’in 31 arabellek yuvasından fazlasını gerektiren gölgelendiriciler çevrilemez ve geçerli ardışık düzen revizyonu için kalıcı olarak desteklenmiyor şeklinde işaretlenir.
- **HLSL gölgelendiricileri** — GLSL kaynaklarının yanında gelen yalnızca Direct3D’ye yönelik gölgelendiriciler tamamen atlanır.
- **Efekt şeması kapsamı** — Bilinmeyen özel uniform adları ve rastgele efekt parametresi şemaları desteklenmemeye devam etmektedir.
- **SceneScript uyumluluğu** — Tescilli olay adlarının, giriş geri çağırmalarının, yaşam döngüsü uç durumlarının veya tam zamanlama anlamlarının tümü yeniden üretilmemiştir.
- **Parçacık operatörü kapsamı** — Yaygın betikli hız, sürükleme ve alfa solması operatörleri çalışır; nadir operatör betikleri, özel parçacık modülleri ve rastgele operatör şemaları kısmen desteklenir.
- **Harici varlık kurtarma** — Bazı Atölye paketleri, indirilen pakette bulunmayan paylaşılan TEX varlıklarına başvurur ve orijinal Wallpaper Engine kurulumunu gerektirir.
- **Bazı JPEG küçük resimleri** — Az sayıda TEXB biçim 1 dosyası, macOS’in çözemediği standart dışı JPEG verileri içerir.
- **Performans ayarlarının kapsamı** — Kalite, kenar yumuşatma ve son işleme seçenekleri sahne duvar kâğıtları için tasarlanmıştır ve video ile web duvar kâğıtları üzerinde sınırlı etkiye sahiptir.
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
| Sahne — gelişmiş parçacıklar | Kısmen (betikli hız/sürükleme/solma desteklenir) |
| Sahne — yerel Metal efektleri | Çalışıyor (yaklaşık 48 efekt) |
| Sahne — çevrilmiş Atölye GLSL efektleri | Kısmen (bkz. Sınırlamalar) |
| Sahne — SceneScript | Kısmen (bkz. Sınırlamalar) |
| Sahne — 3B modeller / iskelet donatımı / kukla bükme | Desteklenmiyor |
| Uygulama | Desteklenmiyor |

## Gereksinimler

### Gerekli
- **macOS 13.0 veya sonrası** (Ventura). ScreenCaptureKit ile ses yakalama ve Metal ile sahne işleme bu sürüme bağlıdır.

### İsteğe bağlı — belirli özellikler için gereklidir

| Özellik | Gereksinim | Kurulum |
|---------|-------------|---------|
| Steam Atölyesi’ne göz atma / Steam Atölyesi’nden indirme | `steamcmd` | `brew install steamcmd` |
| Ses görselleştiricileri ve sese duyarlı SceneScript | Ekran ve Sistem Sesi Kaydı izni | Ayarlar → İzinler |

#### Gölgelendiriciler

Wallpaper Engine efektlerini GLSL olarak sunar. Bu efektler, bir duvar kâğıdı onları ilk kez kullandığında uygulamaya yerleşik glslang ve SPIRV-Cross (`Vendor/ShaderToolchain`) tarafından Metal’e (GLSL → SPIR-V → MSL) çevrilir ve ardından diskte önbelleğe alınır. Hiçbir şey kurmanız gerekmez. Çevirisi uygulamayı kilitleyen veya iki kez çökerten bir gölgelendirici sonraki açılışlarda atlanır; diğer tüm gölgelendiriciler çevrilmeye devam eder.

#### Wallpaper Engine varlıkları

Duvar kâğıtlarının başvurduğu paylaşılan efektler, malzemeler, gölgelendiriciler ve SceneScript çalışma zamanı uygulamanın içinde gelir (`Vendor/we-assets`; bir Wallpaper Engine kurulumundan `Scripts/vendor-we-assets.sh` ile yenilenir). Yapılandırmanız gereken hiçbir şey yoktur.

## Kaynaktan Derleme

### Ön koşullar
- macOS >= 14.0
- Xcode >= 26.3 (macOS 26 SDK)
- Xcode Komut Satırı Araçları

### Adımlar
```sh
git clone https://github.com/unayung/wallpaper-engine-mac
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

Xcode’da imzalama sertifikasını kendi sertifikanızla değiştirin veya “Sign to Run Locally” seçeneğini belirleyin, ardından derleyip çalıştırmak için `Cmd + R` tuşlarına basın.

## Kullanım

### Steam Atölyesi’ne Göz Atma ve Steam Atölyesi’nden İndirme

1. steamcmd’yi kurun (`brew install steamcmd`) veya uygulamayı mevcut bir yürütülebilir dosyaya yönlendirin
2. **Atölye** sekmesine geçin ve Steam hesabınızla giriş yapın (hesabın Wallpaper Engine’e sahip olması gerekir)
3. İstendiğinde veya *Ayarlar → Genel* bölümünde bir [Steam Web API anahtarı](https://steamcommunity.com/dev/apikey) girin. Anahtar Steam ile doğrulanır ve anahtar zincirinizde saklanır; Steam parolanız hiçbir zaman kaydedilmez (steamcmd kendi önbelleğe alınmış oturumunu yeniden kullanır)
4. Arayın, filtreleyin ve istediğiniz duvar kâğıdında **İndir**’e tıklayın

### Yerel Dosyalardan İçe Aktarma

- **Klasör:** Dosya > Klasörden İçe Aktar — `project.json` içeren duvar kâğıdı klasörlerini seçin
- **Zip:** Dosya > İçe Aktar’ı kullanın veya duvar kâğıdı paketleri içeren bir `.zip` dosyasını sürükleyip bırakın
- **Elle:** Duvar kâğıdı klasörlerini doğrudan `~/Documents/OpenWallpaperEngine/` içine kopyalayın

## Proje Yapısı

- `OpenWallpaperEngine/Services/SceneParsers/` — PKG, TEX/TEXS ve scene.json ayrıştırıcıları ve modelleri
- `OpenWallpaperEngine/Services/SceneEffects/` — dinamik efekt kataloğu ve yazarı tarafından tanımlanan efekt parametresi aralıkları
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL çevirisi (`ShaderVariant.swift`, `InProcessShaderCompiler.swift`), önbelleğe alma ve ardışık düzen arşivi
- `Vendor/ShaderToolchain/` — uygulamaya yerel bir paket olarak derlenen glslang ve SPIRV-Cross kaynakları
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift` — SceneScript çalışma zamanı ve ses/FFT bağlamaları
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit ile sistem sesi yakalama
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`, `SceneShaders.metal` — Metal sahne işleyicisi ve gölgelendirici kitaplığı
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`, `WorkshopAPIService.swift`, `WorkshopViewModel.swift` — Steam Atölyesi’ne göz atma ve indirmeler
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`, `ZipImporter.swift`, `WallpaperPackageConverter.swift` — arşiv depolama, içe aktarma ve paket dönüştürme
- `Scripts/vendor-we-assets.sh` — çevrilmiş efekt gölgelendiricilerini ve bildirimleri `we-assets/` içine aktarır
- `Scripts/scene-api-coverage.py` — kurulu duvar kâğıtlarının hangi SceneScript API’lerini kullandığını ve bunlardan hangilerinin uygulandığını raporlar
