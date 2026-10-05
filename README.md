# The Machine

Person of Interest'teki Makine'nin (ve istenirse Samaritan'ın) kamera görüntüsü. iOS ve Android.

## Sınıflar

Kutu renkleri dizinin çizimlerinden alındı (kesikli kenar, yuvarlatılmış köşe, kenar ortasında çizgi).

| Kutu | Etiket | Samaritan'da |
| --- | --- | --- |
| Beyaz | `IRRELEVANT` | daire, `IRRELEVANT` |
| Sarı | `ADMIN` (altında adı) | çift üçgen, `PRIORITY TARGET` |
| Sarı | `ASSET` | üçgen, `TARGET` |
| Siyah, sarı köşeler | `ANALOG INTERFACE` | çift üçgen |
| Mavi | `CATALYST` | daire, `ASSET` |
| Kırmızı | `RELEVANT` / `THREAT` | kırmızı daire + nişangah |
| Beyaz, kırmızı köşeler | `PERPETRATOR` | nişangah, `DEVIANT` |
| Beyaz, sarı çizgiler | `PERSON OF INTEREST` (The Number) | — |
| Düz dikey kenarlı kutu + hedef | `VEHICLE` | daire + kare |
| Elmas | `WATERCRAFT` | daire + kare |
| Yeşil üçgen, uçuş no | `AIRCRAFT` | daire + kare |

SYSTEM → BOX STYLE ile 1. sezon, 2. sezon ya da 3–5. sezon kutuları seçilebilir.

## Kullanım

- **Kutuya dokun:** `RELEVANT` yap. **Tehdide dokun** (`RELEVANT`/`THREAT`/`PERPETRATOR`): simülasyon.
  **Basılı tut:** sınıf menüsü (temizleme ve simülasyon da burada). **Çift dokun:** enhance (yakınlaşma).
- **Simülasyon:** Makine yüz binlerce olasılığı dener; başarısız yollar kırmızıya döner, sonunda seçtiği yol,
  rol (kurban/fail) ve "PROBABILITY OF SURVIVAL" gibi bir yüzde çıkar. Samaritan modunda "PREDICTIVE ANALYSIS".
- **ADMIN:** admin profilleri (ekle, adlandır, yeniden tara, sil).
- **NUMBER:** kadrajdaki birinin numarası gelir (zil + ses). Geçmiş SYSTEM → NUMBER HISTORY'de; numarası
  verilen kişi tekrar görülünce kutusunda numarası belirir ve kayıtta sayılır.
- **Sol üstteki sistem adına dokun:** Makine (ya da Samaritan) ile konuşma. Mikrofon düğmesiyle sesli sor
  (TR/EN seçilebilir) ya da yaz. Sesli soruya cevap verince tekrar dinler; susunca durur. Cevaplar kadrajı,
  konumu bilir ("neredeyim"); "ne olacak / simülasyon" deyince simülasyon açılır.
- **ADMIN → profil (⚙):** gözlüklü/maskeli ek tarama, kişiye özel hassasiyet, yeniden tarama, silme.
- **CAPTURE:** dokun = fotoğraf, basılı tut = ekran kaydı (iOS). İkisi de Fotoğraflar'a kaydedilir.
- **SYSTEM:** Makine / Samaritan, eşik, canlılık (göz kırpma), profil öğrenme, uzun menzil, ses, uyarılar,
  olay kaydı, admin kilidi, kişi veritabanı.
- Yatay mod desteklenir. Kamera butonu: arka → telefoto → ön.
- Gece modu: karanlıkta pozlama artar, görüntü ve yüzler aydınlatılır (HUD'da `NIGHT`).
- Rastgele sistem çökmesi (isteğe bağlı) ya da SYSTEM → SIMULATE SYSTEM CRASH.
- Siri: "Talk to The Machine" (açılır, "Can you hear me?" der ve dinler), "Get a number from The Machine",
  "Open The Machine". Ana ekran ve kilit ekranı widget'ı. Android'de ikon kısayolları ve ana ekran widget'ı.
- Arkası dönük (ya da yüzü görünmeyecek kadar uzak) insanlar da kafalarında beyaz kutu alır (`GAIT ANALYSIS`).
  Arkasını dönen biri kimliğini korur: admin arkasını dönse de `ADMIN` kalır.
- Konum: HUD'da koordinat ve semt, fotoğraflarda damga, numaralarda verildiği ve son görüldüğü yer.
  SYSTEM → SURVEILLANCE MAP.

## Nasıl çalışıyor

- Yüz bulma: Google ML Kit. iOS'ta kare dönüşümü yamalandı (`packages/google_mlkit_commons/PATCHED.md`):
  algılama 19 ms → 8 ms.
- Tanıma: InsightFace MobileFaceNet. iOS'ta Core ML (`ios/Runner/FaceEmbedder.mlmodelc`), Android'de ONNX Runtime
  (`android/app/src/main/assets/FaceEmbedder.onnx`); ikisi aynı sonucu verir (kosinüs 0,999).
- Bulanık ya da hızlı hareket eden kareler, karanlıkta görülen sahte yüzler ayıklanır.
- Araç/tekne/uçak: ML Kit nesne algılama + EfficientNet-Lite0 ImageNet sınıflandırıcısı
  (`assets/models/vehicles.tflite`), 3 karede bir.
- İnsanlar (yüzü görünmese de): iOS'ta Vision (`VNDetectHumanRectanglesRequest`), Android'de EfficientDet-Lite0
  COCO (`android/app/src/main/assets/PersonDetector.tflite`, LiteRT), 3 karede bir.
- Sesli soru: iOS'ta Speech (mümkünse cihaz üstünde), Android'de SpeechRecognizer.
- Harita: OpenStreetMap karoları (© OpenStreetMap katkıcıları), semt adı telefonun ters coğrafi kodlamasıyla.
- Yüzler, profiller ve numaralar cihazda kalır (`Application Support/machine/`). Dışarı giden: harita karoları
  (OpenStreetMap), semt adı sorgusu (Apple/Google) ve telefon cihaz üstünde tanıyamıyorsa sesli sorular (Apple/Google).

## Derleme ve test

```sh
flutter run --release                                   # iPhone
flutter build apk --release --split-per-abi            # Android (arm64 APK ~110 MB)
flutter test                                            # birim testleri
tool/fetch_test_photos.sh                               # test fotoğrafları (repoda yok, bir kez)
flutter test integration_test -d <cihaz>                # tanıma hattı, gerçek cihazda/emülatörde
```

iPhone'da ölçüm: `xcrun devicectl device process launch --console -e '{"POI_DIAG":"1"}' ...`
(`POI_FEED=front`, `POI_MODE=samaritan` ayarları değiştirmeden başlatır).

Ücretsiz Apple hesabıyla imza 7 gün geçerli. Modelleri yeniden üretmek: `tool/convert_face_model.py`.

## Lisans notu

InsightFace modelleri ticari olmayan kullanım içindir. EfficientDet-Lite0 ve EfficientNet-Lite0 Apache 2.0.
Share Tech Mono ve Barlow fontları SIL OFL ile gelir. Sesler uygulama için sentezlendi
(`tool/simulation_sound.py`). Test fotoğrafları repoda yok; kaynak ve lisansları `tool/fetch_test_photos.sh` içinde.
