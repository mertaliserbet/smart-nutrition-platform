# 09 — UI/UX ve tasarım sistemi

## Hedef deneyim
Gerçek diyetisyen ve danışanların güvenle kullanacağı **premium, modern, temiz** sağlık/beslenme ürünü. Sadece mezuniyet demosu gibi görünmemeli; erişilebilir, tutarlı ve mağaza görsellerine hazır olmalı. Tasarımın koddan önce onaylanması önerilir.

## Temel ilkeler
- Kişisel sağlık verisinde **güven**: açık etiket, veri kaynağı, zaman, uyarı ve sade grafik.
- **Hızlı kayıt**: manuel yemek/su girişi mümkün olduğunca az adım; kamera aksiyonu belirgin.
- **Görsel hiyerarşi**: tipografi, beyaz alan/boşluk, kontrollü kartlar, birincil CTA, anlaşılır ikon.
- **Tutarlılık**: mobil ve web aynı marka dilini taşır, platforma özgü navigasyonu korur.
- **Erişilebilirlik**: WCAG AA kontrast hedefi, yeterli dokunma alanı, ekran okuyucu label, yalnız renkle anlam taşıma yok.
- **Duyarlı düzen**: web masaüstü/tablet, mobil dar/geniş ekran; yükleniyor/boş/hata/başarılı durumların görsel tasarımı.

## Tasarım tokenları (başlangıç önerisi — onay bekliyor)
| Token | Öneri | Kullanım |
|---|---|---|
| `color.brand.primary` | sakin koyu yeşil / turkuaz alternatiflerini birlikte seç | Ana CTA ve marka |
| `color.surface` | nötr, göz yormayan açık yüzey; koyu tema opsiyonu | Kart/zemin |
| `color.text.primary` | yüksek kontrastlı koyu/açık metin | Okuma |
| `color.semantic` | success/warning/error + açıklama | Klinik etiketler için tek başına renk kullanılmaz |
| `spacing` | 4pt tabanlı ölçek | Boşluk sistematiği |
| `radius` | kontrollü orta yuvarlaklık | Kart/button/input |
| `typography` | lisanslı, okunabilir ve TR karakter destekli font | Tüm platformlar |

**Renk paleti kesinleşmemiştir.** Eski uygulamadaki renkleri otomatik devralma. Önce moodboard, 2–3 ana ekran ve web dashboard düzeni onayı al.

## Ortak bileşen ilkeleri
- Tasarım sözlüğü: `AppButton`, `AppCard`, `MetricCard`, `EmptyState`, `LoadingState`, `ErrorState`, `MealLogCard`, `LabResultRow` gibi **yalnız gerçekten tekrar kullanılan** bileşenler.
- Flutter ve React kodu paylaşılmaz; **görsel tokenlar/isimlendirme sözlüğü** eşdeğer tutulur.
- Her küçük metin/blok için component açılmaz. Ortak bileşen ihtiyaç, tekrar ve bakım maliyetine göre çıkarılır.
- AI tahminleri için “Tahmini”, “Porsiyonu kontrol et” ve düzeltme CTA'sı görünür; lab ekranında ölçüm/birim/referans birlikte gösterilir.

## Başlangıç ekran tasarım seti
1. Mobil Ana Sayfa: günlük kalori/makro/su, yemek ekleme, diyetisyen planı, gün özeti.
2. Mobil Fotoğraftan Öğün: kamera/galeri, analiz sonucu, porsiyon düzenleme, onay.
3. Mobil Laboratuvar: değer + birim + laboratuvar aralığı + açıklama, yardım metni.
4. Web Danışan Listesi/Detay: filtre, zaman çizgisi, trend, program erişimi.
5. Web Beslenme Planı Editörü: gün/öğün yapısı, hedef ve atama eylemi.

## UI kalite kapıları
- Figma/örnek statik onay (varsa), ekranların tema/token uyumu, erişilebilirlik ve hata durumları.
- Demo verisi gerçek kişisel sağlık verisi içermez.
- Scroll/klavye/odak, loading/skeleton, ağ hatası, form doğrulama, responsive kırılmaları manuel test edilir.
- Animasyon kısa ve amaçlı, düşük güçlü cihazlarda performansa zarar vermez.
