# 07 — Danışan mobil uygulaması

## Kullanıcı deneyimi hedefi
Play Store hedefini gözeten, sade, hızlı, premium, ekran okuma erişilebilirliğine uygun mobil uygulama. Fotoğraf/kamera akışları beslenme kaydını kolaylaştırmalı; tıbbi doğruluk veya kesin kalori vaadi sunmamalı.

## Önerilen navigasyon (onay bekliyor)
Alt sekmeler: `Ana Sayfa` / `Beslenme` / `İlerleme` / `Profil`; `+` veya belirgin CTA üzerinden öğün, su, aktivite ve tahlil ekleme. Diyetisyen planı ana sayfada ve beslenme içinde erişilebilir.

## Ekran listesi ve eylemler
| Ekran | İçerik | Beklenen API |
|---|---|---|
| Onboarding / Login / Register | Hedef, temel profil, rol, yasal bilgilendirme; izinleri gerektiğinde iste | `/auth/*`, `/me` |
| Ana Sayfa | Günlük enerji/makro, su, plan durumu, son öğün, bağlanan diyetisyen, CTA | `/meal-logs`, `/water-logs`, `/nutrition-plans/active` |
| Beslenme Günlüğü | Gün bazlı öğünler, ekle/düzelt/sil, tarih filtresi | `/meal-logs`, `/food-items` |
| Yemek fotoğrafı | kamera/galeri → yükle → tahminleri düzenle → onay | `/food-analyses`, `/meal-logs` |
| Su | hızlı miktar ekleme, günlük toplam, hedef | `/water-logs` |
| Planım | Diyetisyenin atanmış planı; hangi öğün hedefi olduğu | `/nutrition-plans/active` |
| Diyetisyenim | Uzman görüntüle, bağlantı iste, istek durumu | `/dietitians`, `/dietitian-relationships` |
| İlerleme | tarih aralığı, kilo/ölçümler, beslenme trendi | `/body-measurements`, `/meal-logs` |
| Aktivite | manuel yürüyüş/koşu, süre/mesafe; kaynağı göster | `/activity-logs` |
| Laboratuvar | değer/birim/aralık kaydı, sonuç geçmişi, anlaşılır açıklama | `/lab-reports` ve insights |
| Cihaz bağlantıları | açık izin, hangi veri toplanıyor, senkronize et/iptal et | `/wearable-connections` (sonraki faz) |
| Profil ve gizlilik | hesabım, verilerim, cihaz izinleri, hesap silme | `/me`, onaylı yasal uçlar |

## Kritik etkileşimler
1. Kamera ve galeri izinleri sadece gerektiğinde istenir; reddedilirse manuel yemek kaydı devam eder.
2. Fotoğraf sonucu **doğrudan kalori kaydı değildir**; düzenleme ve onay ekranı zorunlu.
3. Tahmin başarısızsa kullanıcının manuel besin seçip devam edebileceği fallback vardır.
4. Öğün, laboratuvar ve su girişinde boş/yükleniyor/hata/başarı/çevrimdışı durumları tasarlanır.
5. Diyetisyenin gördüğü bilgi izinle açıklanır; ilişki bitince sunucu erişimi keser.
6. Laboratuvar ekranı birim/aralık belirsizliğini gösterir; tıbbi tanı görselleştirmez.
7. `RecordSource` veri kaynağı manuel/cihaz/AI destekli olarak görünür olmalıdır.
8. Aktivite takibi spor programı / koçluk özelliği değildir; beslenme bağlamındadır.

## Cihaz entegrasyonu (ayrı faz)
- Android Health Connect / iOS HealthKit için platform izinleri, kullanıcı bilgilendirmesi ve veri türleri ayrı değerlendirilir.
- Başlangıç veri türleri: adım sayısı, mesafe, aktivite süresi, uygun yetki varsa enerji harcaması; **tüm akıllı saatlerin doğrudan entegrasyonu garanti değildir**.
- Yeniden aktarımda `externalRecordId` + sağlayıcı ile tekilleştirme; veri kaynağı ve `lastSyncedAt` gösterimi.
- İzin geri alındığında senkronizasyon durur; veri silme/retention politikası uygulanır.

## Mobil kabul kriterleri
- İstemcinin JSON alanları `04/05/06` ile birebir uyumlu.
- UI küçük/büyük ekranlarda taşmaz; karanlık/açık mod kararına uygun.
- Tokenlar güvenli saklanır, hassas sağlık verileri loglanmaz.
- Öğün + su + plan + diyetisyen izleme akışı gerçek backend ile test edilir.
