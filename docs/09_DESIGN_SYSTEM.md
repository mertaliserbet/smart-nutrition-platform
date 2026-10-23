# 09 — UI/UX ve tasarım sistemi

## Hedef deneyim
Gerçek diyetisyen ve danışanların güvenle kullanacağı **premium, modern, temiz** sağlık/beslenme ürünü. Sadece mezuniyet demosu gibi görünmemeli; erişilebilir, tutarlı ve mağaza görsellerine hazır olmalı. `12` karar 22 uyarınca ortak tasarım tokenları ve **açık/koyu tema** onaylıdır; renk/font/değerler ve ekran tasarımları henüz onaylanmamıştır. Nihai ekran kodundan önce ilgili tasarım onayı önerilir; sentetik prototip gerçek API/şema onayı sayılmaz.

## Temel ilkeler
- Kişisel sağlık verisinde **güven**: açık etiket, veri kaynağı, zaman, uyarı ve sade grafik.
- **Hızlı kayıt**: manuel yemek/su girişi mümkün olduğunca az adım; kamera aksiyonu belirgin.
- **Görsel hiyerarşi**: tipografi, beyaz alan/boşluk, kontrollü kartlar, birincil CTA, anlaşılır ikon.
- **Tutarlılık**: mobil ve web aynı marka dilini taşır, platforma özgü navigasyonu korur.
- **Erişilebilirlik**: WCAG AA kontrast hedefi, yeterli dokunma alanı, ekran okuyucu label, yalnız renkle anlam taşıma yok.
- **Duyarlı düzen**: web masaüstü/tablet, mobil dar/geniş ekran; yükleniyor/boş/hata/başarılı durumların görsel tasarımı.
- **Anlamı koruma**: kişisel düzenlenebilir hedef ile diyetisyen salt okunur hedefi, plan ile tüketim, bilinmeyen ölçüm ile sıfır ve erişim kapalı kategori ile boş veri farklı gösterilir. Laboratuvar aralığındaki “normal” etiketi genel sağlık hükmü değildir.

## Tasarım tokenları (değer önerileri — onay bekliyor)
| Token | Öneri | Kullanım |
|---|---|---|
| `color.brand.primary` | sakin koyu yeşil / turkuaz alternatiflerini birlikte seç | Ana CTA ve marka |
| `color.surface` | açık ve koyu temada nötr, göz yormayan yüzey karşılıkları | Kart/zemin; iki tema da desteklenir |
| `color.text.primary` | yüksek kontrastlı koyu/açık metin | Okuma |
| `color.semantic` | success/warning/error + açıklama | Klinik etiketler için tek başına renk kullanılmaz |
| `spacing` | 4pt tabanlı ölçek | Boşluk sistematiği |
| `radius` | kontrollü orta yuvarlaklık | Kart/button/input |
| `typography` | lisanslı, okunabilir ve TR karakter destekli font | Tüm platformlar |

**Renk paleti kesinleşmemiştir.** Eski uygulamadaki renkleri otomatik devralma. Önce moodboard, 2–3 ana ekran ve web dashboard düzeni onayı al.

Token yolları ortak görsel kavramları anlatır; Flutter ve React platformun kendi adlandırmasına eşlenir. Kesin renk, font, spacing/radius değerleri, varsayılan tema ve tema tercihinin saklanması burada seçilmez. 4pt ölçek de başlangıç önerisidir; açık/koyu desteğin kendisi ise karar beklemez.

## Ortak bileşen ilkeleri
- Tasarım sözlüğü: `AppButton`, `AppCard`, `MetricCard`, `EmptyState`, `LoadingState`, `ErrorState`, `MealLogCard`, `LabResultRow` gibi **yalnız gerçekten tekrar kullanılan** bileşenler.
- Flutter ve React kodu paylaşılmaz; **görsel tokenlar/isimlendirme sözlüğü** eşdeğer tutulur.
- Her küçük metin/blok için component açılmaz. Ortak bileşen ihtiyaç, tekrar ve bakım maliyetine göre çıkarılır.
- AI tahminleri için “Tahmini”, “Porsiyonu kontrol et” ve düzeltme CTA'sı görünür; lab ekranında ölçüm/birim/referans birlikte gösterilir.
- AI ve OCR kontrol/onayı görünür bir kullanıcı eylemidir; yükleme/iş tamamlanması onay gibi gösterilmez. Doğru tahmini onaylamak için gereksiz değişiklik zorunluluğu yoktur. Eksik miktar/makro sıfıra çevrilmez.
- Görev durumları, yorum/cevap ve bildirim ekranı açık DTO'lar için kendi enum/alanını üretmez. İlk sürüm yorum/cevap/bildirim şartı, kendiliğinden anlık sohbet/WebSocket tasarımı anlamına gelmez. Katman veya her küçük blok için bileşen açılmaz; kontrollü refactor kuralı korunur.

## Başlangıç ekran tasarım seti
1. Mobil Ana Sayfa: günlük kalori/makro/su, yemek ekleme, kişisel/atanmış program ayrımı, gün özeti; her iki tema.
2. Mobil Fotoğraftan Öğün: kamera/galeri, analiz sonucu, porsiyon düzenleme, onay.
3. Mobil Laboratuvar: değer + birim + laboratuvar aralığı + açıklama, yardım metni.
4. Web Danışan Listesi/Detay: filtre, zaman çizgisi, trend, program erişimi.
5. Web Beslenme Planı Editörü: gün/öğün yapısı, hedef ve atama eylemi.
6. Mobil/Web Öğün Yorumu ve Görev: yorum/cevap/bildirim, görev/son tarih ve açık durum kurallarını belli eden prototip; ayrı sohbet değildir.
7. Paylaşım ve Tahlil Onayı: kategori bazlı erişim, ayrı açık onay, geri çekme ve erişim kesilmesi; cihaz izinleri ayrı açıklanır.

Program alternatif/sürüm, görev durumları ve rapor gövdesi gibi açık veri yapıları prototipte kesin sözleşme diye sabitlenmez; bağımlılıklar `12`de izlenir. Admin ekranlarında MFA adımı bulunur, genel sağlık verisi tarama ekranı varsayılmaz.

## UI kalite kapıları
- Figma/örnek statik onay (varsa), ekranların tema/token uyumu, erişilebilirlik ve hata durumları.
- Demo verisi gerçek kişisel sağlık verisi içermez.
- Scroll/klavye/odak, loading/skeleton, ağ hatası, form doğrulama, responsive kırılmaları manuel test edilir.
- Animasyon kısa ve amaçlı, düşük güçlü cihazlarda performansa zarar vermez.
- İki temada kontrast, tahmin/unknown/izin kapalı etiketleri, salt okunur atanmış program ve onay/geri çekme akışları kontrol edilir. Tema/token ve ekran onayı tamamlanmadan premium/erişilebilir deneyim test edildi denmez.
