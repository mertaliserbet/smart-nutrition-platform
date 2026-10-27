# 07 — Danışan mobil uygulaması

## Kullanıcı deneyimi hedefi
Play Store hedefini gözeten, sade, hızlı, premium, ekran okuma erişilebilirliğine uygun mobil uygulama. Fotoğraf/kamera akışları beslenme kaydını kolaylaştırmalı; tıbbi doğruluk veya kesin kalori vaadi sunmamalı.

Flutter/Dart onaylıdır; Mert mobil ve ilgili API entegrasyonlarının sahibidir. Danışan diyetisyensiz de kayıt tutar ve kişisel program/hedef oluşturur. Diyetisyen mobil üzerinden başvurabilir; ilk sürüm yönetim paneli webdedir. İlk sürüm öğün yorum/cevap/bildirim şartı ile diğer özelliklerin takvim ayrımı `01/12`ye uyar; açık/koyu tema desteklenir.

## Önerilen navigasyon (onay bekliyor)
Alt sekmeler: `Ana Sayfa` / `Beslenme` / `İlerleme` / `Profil`; `+` veya belirgin CTA üzerinden öğün, su, aktivite ve tahlil ekleme. Diyetisyen planı ana sayfada ve beslenme içinde erişilebilir.

## Ekran listesi ve eylemler
Yollar `/api/v1` tabanına göredir; method, alan ve yetki kaynağı `06`dır. **AÇIK ŞEMA** işaretli gövde/akışlar onaylanmadan gerçek entegrasyon veya kesin mock sayılmaz.

| Ekran | İçerik | Mevcut API / açık bağımlılık |
|---|---|---|
| Onboarding / Login / Register | E-posta/şifre, doğrulama, şifre sıfırlama, profil ve yasal bilgilendirme; izinleri gerektiğinde iste | `/auth/*`, `GET /auth/me`; kayıt/JWT giriş/kendi hesap özeti `06`da onaylı. Refresh/logout, profil düzenleme ve istemci entegrasyonu ayrı |
| Ana Sayfa | Günlük enerji/makro, su, plan durumu, son öğün, bağlanan diyetisyen, CTA | `/meal-logs`, `/water-logs`, `/nutrition-plans/active` |
| Beslenme Günlüğü | Gün bazlı öğünler, ekle/düzelt/sil, tarih filtresi | `/meal-logs`, `/food-items` |
| Tarifler | Kendi özel tarifleri ve erişilebilir katalog; geçmiş tüketim değerlerini değiştirmeden kayıt | `/recipes`; bileşen/porsiyon/görünürlük AÇIK ŞEMA |
| Yemek fotoğrafı | kamera/galeri → yükle → tahminleri düzenle → onay | `/food-analyses`, `/meal-logs` |
| Su | hızlı miktar ekleme, günlük toplam, hedef | `/water-logs` |
| Planım / Kişisel program | Diyetisyensiz kişisel program oluştur/düzenle; atanmış programı/hedefleri salt okunur gör; tek aktif program, alternatif ve geçmiş | `/nutrition-plans`, `/nutrition-plans/active`; tam items/alternatif/sürüm ve program geçişi AÇIK ŞEMA |
| Diyetisyenim | Doğrulanmış uzman ara, davet kodu/karşılıklı onay, ilişki durumu/geçmişi ve sonlandırma | `/dietitians`, `/dietitian-relationships`; davet kodu girdisi açık |
| Diyetisyen başvurusu | Uzman başvurusu ve doğrulama durumunu gör; rol seçimi doğrulanmış yetki vermez | `/auth/*`, `GET /auth/me` yalnız hesap özeti içindir; uzman başvuru/doğrulama durumu bu DTO'da yoktur. Başvuru belge/endpoint DTO'su açık |
| Görevlerim | Atanan ClientTask, son tarih, durum ve isteğe bağlı hatırlatma | `/client-tasks`; durum geçiş yetkisi/son tarih/hatırlatma AÇIK ŞEMA |
| Öğün yorumları/cevaplar | Kendi öğününde yorum/cevap ve bildirim akışı; ayrı sohbet yok | `06`daki `/meal-logs/{mealLogId}/comments` önerisi AÇIK ŞEMA; bildirim DTO/kanalı açık |
| İlerleme | tarih aralığı, kilo/ölçümler, beslenme trendi | `/body-measurements`, `/meal-logs` |
| Aktivite | manuel yürüyüş/koşu, süre/mesafe; kaynağı göster | `/activity-logs` |
| Laboratuvar | Manuel değer/birim/aralık, sonuç geçmişi ve açıklama; ardından kullanıcı kontrol/onaylı PDF/fotoğraf OCR | `/lab-reports` ve insights; OCR yolu/yanıtı `06`da öneri, AÇIK ŞEMA |
| Cihaz bağlantıları | açık izin, hangi veri toplanıyor, senkronize et/iptal et | `/wearable-connections` (sonraki faz) |
| Profil ve gizlilik | Hesabım; kategori paylaşımı/tahlil açık onayı ve geri çekme; cihaz izinleri; veri indirme/hesap silme talepleri | `GET /auth/me` kendi hesap özeti; profil düzenleme ayrı açık taslak. `/data-sharing-permissions`, `/consent-records`; silme/indirme uçları ve onay kanıtı henüz tam tanımlı değil |

## Kritik etkileşimler
1. Kamera ve galeri izinleri sadece gerektiğinde istenir; reddedilirse manuel yemek kaydı devam eder.
2. Fotoğraf sonucu **doğrudan kalori kaydı değildir**; kontrol/düzeltme ve onay ekranı zorunlu, kullanıcı her doğru öneriyi değiştirmek zorunda değildir. Onay ayrı MealLog isteğini başlatır; OCR taslağı da kullanıcı onayı öncesi kalıcı tahlil olmaz.
3. Tahmin başarısızsa kullanıcının manuel besin seçip devam edebileceği fallback vardır.
4. Öğün, laboratuvar ve su girişinde boş/yükleniyor/hata/başarı/çevrimdışı durumları tasarlanır.
5. Diyetisyenin gördüğü kategoriler kullanıcıya açıklanır; ilişki/izin bitince sunucu yeni erişimi keser. Tahliller ayrıca geri çekilmemiş açık onay gerektirir; cihaz izni paylaşım onayı değildir. Danışanın kendi verisi ilişki olmadan erişilebilir kalır.
6. Laboratuvar ekranı birim/aralık belirsizliğini gösterir; tıbbi tanı görselleştirmez.
7. `RecordSource` veri kaynağı manuel/cihaz/AI destekli olarak görünür olmalıdır.
8. Aktivite takibi spor programı / koçluk özelliği değildir; beslenme bağlamındadır.
9. Kişisel öneriler düzenlenebilir; diyetisyen programı/hedefi için salt okunur davranış sunucuda da korunur. Alternatif öğün seçimi programı değiştirmez; tüketim serbesttir. İkinci aktif programda `409` gösterilir, diğer program sessizce arşivlenmez.
10. Görev/yorum durumları ve bildirimler onaylı akışlara dayanır; serbest status, yeni onay bayrağı veya örnek token alanı uydurulmaz. Çevrimdışı/hata durumunu tasarlamak offline sağlık verisi kuyruğu veya arka plan sync seçimi anlamına gelmez.

## Cihaz entegrasyonu (ayrı faz)
- Android Health Connect / iOS HealthKit için platform izinleri, kullanıcı bilgilendirmesi ve veri türleri ayrı değerlendirilir.
- Onaylı veri türleri: adım, mesafe, egzersiz, süre, aktif kalori ve nabız; **tüm akıllı saatlerin doğrudan entegrasyonu garanti değildir**. Yayın/OS önceliği ve adım/nabız veri yapısı açıktır; tüm ölçümler ActivityLog'a zorlanmaz.
- Yeniden aktarımda `externalRecordId` + sağlayıcı ile tekilleştirme; `wearableConnectionId` üzerinden aynı danışanın kaynağı ve `lastSyncedAt` gösterimi. Manuel/cihaz örtüşme politikası ve aktif/toplam enerji ayrımı açıkken çift sayım sessizce kabul edilmez.
- İzin geri alındığında senkronizasyon durur; veri silme/retention politikası uygulanır.

## Mobil kabul kriterleri
- İstemcinin JSON alanları `04/05/06` ile birebir uyumlu.
- UI küçük/büyük ekranlarda taşmaz; açık/koyu tema ve ortak token karşılıklarına uygundur.
- Tokenlar güvenli saklanır, hassas sağlık verileri loglanmaz.
- Öğün + su + plan + diyetisyen izleme akışı gerçek backend ile test edilir.
- İlk sürüm yorum/cevap/bildirim, kişisel/atanmış düzenleme farkı, tek aktif çakışması ve kategori/tahlil onayı geri çekme doğrulanır. Görev/sürüm/OCR/sync için ilgili açık sözleşme önce kapatılır; belge veya UI prototipi tamamlanmış feature testi sayılmaz. Hazırlık bağımlılıkları `12`de izlenir.
