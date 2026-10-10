Open Wallpaper Engine
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | **हिन्दी**

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

Open Wallpaper Engine, Wallpaper Engine वॉलपेपर (सीन, वीडियो और वेब) चलाने वाला एक मुफ़्त, ओपन-सोर्स macOS प्लेयर है. इसमें नेटिव Metal रेंडरर है, और यह इफ़ेक्ट, पार्टिकल, 3D मॉडल, लाइटिंग, SceneScript, ऑडियो पर प्रतिक्रिया देने वाले विज़ुअल और Steam Workshop सपोर्ट करता है. इसकी शुरुआत Haren Chen और MrWindDog के [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) के fork के रूप में हुई थी, और तब से इसका ज़्यादातर हिस्सा दोबारा लिखा जा चुका है.

> **नोट:** यह Steam पर उपलब्ध कमर्शियल Wallpaper Engine से संबद्ध नहीं है. यह एक ओपन-सोर्स macOS ऐप है, जो Wallpaper Engine के Steam Workshop के वॉलपेपर एसेट दिखा सकता है. → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

**वेबसाइट:** [openwallpaperengine.app](https://openwallpaperengine.app/) · **विकी:** [गाइड और समस्या निवारण](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki)

![लाइब्रेरी](../../docs/images/library.png)

## ख़ास बातें

- **सीन, वीडियो और वेब वॉलपेपर** — सीन हर वॉलपेपर के अपने Wallpaper Engine शेडर से ड्रॉ होते हैं, जिन्हें Metal में बदला जाता है; इनमें इफ़ेक्ट, पार्टिकल, 3D मॉडल, लाइट, टाइमलाइन, SceneScript और ऑडियो पर प्रतिक्रिया देने वाले विज़ुअल शामिल हैं. वेब वॉलपेपर WebKit में या वैकल्पिक Chromium इंजन में चलते हैं.
- **Steam Workshop** — ऐप के अंदर ही Workshop ब्राउज़ करें, फ़िल्टर करें और डाउनलोड करें, या वॉलपेपर फ़ोल्डर और zip इंपोर्ट करें.
- **सीन एडिट/एक्सपोर्ट** — चल रहे वॉलपेपर की लेयर और इफ़ेक्ट सीधे डेस्कटॉप पर लाइव बदलें, उसे अपना स्क्रीन सेवर बनाएँ, या उसे (सीन और वीडियो) iPhone और iPad के लिए Live Photo लॉक स्क्रीन के रूप में या Wallpaper Engine के Android ऐप के पैकेज के रूप में एक्सपोर्ट करें.

  ![सीन एडिट/एक्सपोर्ट](../../docs/images/scene-editor-live.png)

- **वॉलपेपर एडिटर** — Wallpaper Engine के एडिटर की तर्ज़ पर बना एडिटर: लेयर, प्रीव्यू के साथ इफ़ेक्ट, टाइमलाइन, SceneScript, यूज़र प्रॉपर्टी, पार्टिकल, Puppet Warp और डेप्थ मैप से बने मास्क. आप एक ड्राफ़्ट एडिट करते हैं: **सहेजें** उसे वॉलपेपर पर लागू करता है, **नए वॉलपेपर के रूप में सहेजें** लाइब्रेरी में एक कॉपी जोड़ता है, और वॉलपेपर की अपनी फ़ाइलें कभी नहीं बदलतीं.

  ![वॉलपेपर एडिटर](../../docs/images/wallpaper-editor.png)

- **डिस्प्ले** — हर डिस्प्ले पर अलग वॉलपेपर, एक वॉलपेपर सभी डिस्प्ले पर फैला हुआ या हर डिस्प्ले पर क्लोन किया हुआ, साथ ही ग्रुप, स्प्लिट और प्रोफ़ाइल — बिल्कुल Wallpaper Engine की तरह.

  ![डिस्प्ले](../../docs/images/displays.png)

- **प्लेलिस्ट** — टाइमर पर, लॉगिन पर, दिन के समय या हफ़्ते के दिन के हिसाब से वॉलपेपर बदलें, Wallpaper Engine के ट्रांज़िशन के साथ.

  ![प्लेलिस्ट सेटिंग](../../docs/images/playlists.png)

- **एक्सपोर्ट** — iPhone और iPad के लिए Live Photo लॉक स्क्रीन, और Wallpaper Engine के Android पैकेज, जो QR कोड के ज़रिए Wi-Fi पर फ़ोन में भेजे जाते हैं.

  ![Wi-Fi पर भेजें](../../docs/images/send-over-wifi.png)

- **थीमिंग** — मेन्यू बार, एक्सेंट कलर और टिंट किए गए आइकन और फ़ोल्डर वॉलपेपर के रंग के हिसाब से बदलते हैं; Open Wallpaper Engine की अपनी विंडो ठीक वही रंग इस्तेमाल कर सकती हैं.

  ![थीमिंग](../../docs/images/theming.png)

- **MCP सर्वर प्लग-इन** — MCP क्लाइंट एक लोकल कनेक्शन के ज़रिए वॉलपेपर, प्लेलिस्ट और सेटिंग सेट कर सकते हैं और सीन एडिट कर सकते हैं; यह कनेक्शन सिर्फ़ आपका अकाउंट खोल सकता है.

  ![MCP सर्वर प्लग-इन](../../docs/images/mcp-plugin.png)

बाकी सब कुछ, हिस्से के हिसाब से: [docs/features.md](../../docs/features.md).

## इंस्टॉल करें

1. नया रिलीज़ [openwallpaperengine.app](https://openwallpaperengine.app/) या [GitHub Releases](https://github.com/deepratna-awale/open-wallpaper-engine-mac/releases) से डाउनलोड करें. यह साइन और नोटराइज़ किया हुआ है, और ख़ुद को अपने-आप अपडेट करता है.
2. DMG खोलें और **Open Wallpaper Engine** को Applications में ड्रैग करें.

आपको **macOS 14.0 (Sonoma) या उसके बाद का वर्ज़न** चाहिए. कुछ फ़ीचर के लिए नया macOS, कोई अनुमति या कोई प्लग-इन चाहिए: देखें [शुरुआत करें](../../docs/getting-started.md#requirements).

## जल्दी शुरुआत

1. ऐप खोलें. सेटअप असिस्टेंट भाषा, SteamCMD, आपका Steam लॉगिन और Wallpaper Engine एसेट सेट करता है, और आपके Wallpaper Engine पसंदीदा इंपोर्ट कर सकता है; हर चरण छोड़ा जा सकता है.
2. अगर आप सीन वॉलपेपर चाहते हैं, तो Wallpaper Engine एसेट इंस्टॉल करें (*सेटिंग › ऐसेट*). ये Steam पर Wallpaper Engine की आपकी अपनी कॉपी से आते हैं; वीडियो और वेब वॉलपेपर इनके बिना भी चलते हैं.
3. **खोजें** और **Workshop** टैब में वॉलपेपर ढूँढें, या कोई वॉलपेपर फ़ोल्डर या zip इंपोर्ट करें (*फ़ाइल › फ़ोल्डर से वॉलपेपर इंपोर्ट करें…*, ⌘I).
4. लाइब्रेरी में किसी वॉलपेपर पर क्लिक करें, फिर उसके विवरण में **वॉलपेपर सेट करें** पर क्लिक करें (या उस पर राइट-क्लिक करके **वॉलपेपर बनाएँ** चुनें). उसकी प्रॉपर्टी उसके नीचे दिखती हैं.

और जानकारी: [शुरुआत करें](../../docs/getting-started.md) और [विकी](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki).

## निजता

ऐप जो कुछ भी सेव करता है, वह आपके Mac पर ही रहता है, और यह कोई डेटा या एनालिटिक्स इकट्ठा नहीं करता. यह Steam (Workshop और एसेट के लिए), openwallpaperengine.app (अपडेट जाँचने के लिए) और GitHub (उन्हें डाउनलोड करने के लिए) से संपर्क करता है, और प्लग-इन सिर्फ़ तभी डाउनलोड होते हैं जब आप उन्हें इंस्टॉल करते हैं. विवरण: [ऐप किन चीज़ों से कनेक्ट होता है](../../docs/getting-started.md#what-the-app-connects-to) और [गोपनीयता नीति](../../docs/legal/privacy-policy.md).

## डॉक्यूमेंटेशन

- [शुरुआत करें](../../docs/getting-started.md) — ज़रूरी चीज़ें, एसेट, Workshop और इंपोर्ट
- [फ़ीचर](../../docs/features.md) — ऐप जो कुछ भी सपोर्ट करता है, और उसे कैसे इस्तेमाल करें
- गाइड: [डिस्प्ले लेआउट](../../docs/display-layouts.md) · [प्लेलिस्ट](../../docs/playlists.md) · [स्क्रीन सेवर](../../docs/screen-saver.md) · [iPhone और iPad एक्सपोर्ट](../../docs/iphone-ipad-export.md) · [Android एक्सपोर्ट](../../docs/android-export.md) · [डेप्थ मैप](../../docs/depth-maps.md) · [थीमिंग](../../docs/theming.md) · [MCP सर्वर](../../docs/mcp.md) · [Chromium वेब इंजन](../../docs/chromium-engine.md)
- [डेवलपमेंट](../../docs/development.md) — सोर्स से बिल्ड करना और प्रोजेक्ट लेआउट; साथ ही [CONTRIBUTING.md](../../CONTRIBUTING.md) और [आर्किटेक्चर](../../docs/architecture.md)
- [विकी](https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki) — गाइड, सेटिंग रेफ़रेंस और समस्या निवारण

## संबंधित प्रोजेक्ट

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) के लिए एक PyQt6 GUI, जिसमें Steam Workshop इंटीग्रेशन है और जिसका UI डिज़ाइन इसी macOS वर्ज़न से लिया गया है.

## आभार

यह प्रोजेक्ट इनके काम पर आधारित है:

- **[MrWindDog](https://github.com/MrWindDog)** — अपस्ट्रीम [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) fork के मेंटेनर, जिन्होंने नए फ़ीचर और UI सुधार जोड़े
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac) के मूल निर्माता, जिन्होंने ऐप का मुख्य आर्किटेक्चर बनाया (SwiftUI, वीडियो वॉलपेपर प्लेबैक, इंपोर्ट सिस्टम, प्लेलिस्ट UI)
- **1ris_W** — चीनी अनुवाद
- **[Klaus Zhu](https://github.com/klauszhu1105)** — मूल लोगो डिज़ाइन
- **[Chen Chia Yang](https://github.com/Unayung)** — सीन वॉलपेपर रेंडरिंग, वेब वॉलपेपर के सुधार, Steam Workshop इंटीग्रेशन, एक से ज़्यादा डिस्प्ले का सपोर्ट, zip इंपोर्ट
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal सीन रेंडरर और इफ़ेक्ट पाइपलाइन, GLSL→MSL शेडर ट्रांसलेशन और कैशिंग, SceneScript रनटाइम, ऑडियो पर प्रतिक्रिया देने वाली रेंडरिंग, Workshop/डाउनलोड का नया रूप, प्लेसमेंट और परफ़ॉर्मेंस सेटिंग, लोगो रीडिज़ाइन

मूल प्रोजेक्ट की तरह, [GPL-3.0](../../LICENSE) के तहत लाइसेंस प्राप्त.

## कानूनी जानकारी

[उपयोग की शर्तें](../../docs/legal/terms-of-use.md) · [गोपनीयता नीति](../../docs/legal/privacy-policy.md) · [सुरक्षा नीति](../../SECURITY.md)

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
