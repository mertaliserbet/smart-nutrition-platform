# 09 — Uygulanan tasarım tokenları ve deneyim kuralları

Açık/koyu tema ve ortak görsel dil onaylıdır. Aşağıdaki değerler kaynakta uygulanmıştır; nihai marka paleti, kapsamlı erişilebilirlik veya mağaza tasarım onayı verildiği anlamına gelmez.

## Mevcut tokenlar

Kaynaklar: [Flutter AppTokens](../mobile/lib/core/theme/app_tokens.dart), [AppTheme](../mobile/lib/core/theme/app_theme.dart), [web tokens.css](../apps/web/src/core/theme/tokens.css).

| Kavram | Flutter | Web açık / koyu |
|---|---|---|
| Ana marka | seedColor #386A5E | --brand-primary #386a5e / #9bcec0 |
| Güçlü marka / yumuşak yüzey | Material 3 ColorScheme'den | #285347 / #b4e0d4; #eaf2ee / #243d35 |
| Kart yüzeyi | Material 3 rolü | #ffffff / #1b2522 |
| Sayfa yüzeyi | Material 3 rolü | #f7f8fa / #141c19 |
| Ana metin | Material 3 rolü | #243a36 / #e6eee9 |
| İkincil metin | Material 3 rolü | #62736e / #a9bdb3 |
| Kenarlık | Material 3 rolü | #e3e9e6 / #34443c |
| Hata | Material 3 rolü | #b13535 / #ffb2ab |
| Boşluklar | 8, 16, 24, 32 logical px | 8, 16, 24, 32 px |
| Orta radius | 16 | 16 px |
| Mobil içerik / marka ikonu | maxWidth 480 / 40 | Web ekranına özgü responsive CSS |

Flutter useMaterial3 ve ColorScheme.fromSeed kullanır; başlık ağırlığı w600, bodyLarge satır yüksekliği 1.5'tir. Web sistem font zinciri Segoe UI, system-ui, -apple-system, BlinkMacSystemFont, sans-serif'tir; harici font servisine istek yoktur. Ortak token kavramı her platformun bütün üretilmiş renklerinin aynı hex olduğu iddiası değildir.

Flutter ThemeMode.system kullanır. Web ThemeProvider system/light/dark seçimini yalnız sayfa belleğinde tutar ve sistem değişimini izler; kalıcı tercih saklama kararı yoktur.

## Tasarım ve bileşen kuralları

- Temiz hiyerarşi, okunabilir metin, kontrollü beyaz alan ve hızlı manuel kayıt; mobil/web kendi navigasyon düzenini korur.
- Sağlık değeri yanında birim, tarih, kaynak ve tahmin etiketi bulunur. null “Bilinmiyor”, gerçek 0 “0”, izin kapalı “Erişim yok”, kayıt olmayan gün “Kayıt yok” olarak ayrılır. Aralık içindeki lab bayrağı genel sağlık hükmü değildir.
- Kişisel düzenlenebilir hedef, atanmış salt okunur hedef ve gerçek tüketim farklı sunulur. Alternatif program öğeleri ayrı zorunlu öğün gibi gösterilmez.
- AI/OCR için kontrol, gerekirse düzeltme ve açık onay görünür eylemdir; işin tamamlanması onay değildir. Doğru öneriyi değiştirme zorunluluğu ve eksik besini sıfıra çevirme yoktur.
- Ortak bileşen yalnız tekrar/sorumluluk/test ihtiyacıyla çıkarılır. Flutter/React bileşen kodu paylaşılmaz; görsel kavramlar eşlenir.
- WCAG AA kontrast hedefi, ekran okuyucu etiketleri, yeterli dokunma alanları, klavye/odak ve yalnız renkle anlam taşımama korunur. Kaynakta skip-link, odaklanabilir başlık, aria form durumları ve klavyeyle tema menüsü vardır; bunlar tam uygunluk sertifikası değildir.
- Yüklenme, boş, ağ/sunucu hatası ve yetki kaybı ayrı görünür; hata halinde sentetik başarı/sağlık verisi gösterilmez.
- Tablo/grafikte birim ve eksiklik açıklaması vardır; grafik metin/tablo alternatifiyle anlaşılır kalmalıdır. Animasyon kısa ve düşük güçlü cihazlara uygun olmalıdır.

## Tasarım ve doğrulama durumu

Gerçek ekranlar [07](07_MOBILE_SPEC.md) ve [08](08_WEB_SPEC.md)'dedir. Webde sentetik önizleme ayrı Development rotasıdır; tasarım örneği gerçek veri kanıtı değildir.

Nihai marka/font/palet onayı, bütün ekranlarda iki tema/kontrast, ekran okuyucu, küçük ekran, scroll/klavye, zayıf ağ ve fiziksel cihaz performansı ayrıca doğrulanmalıdır. Planlanan fotoğraf, laboratuvar, bildirim ve paylaşım/onay akışları da aynı kurallara tabidir. Tarihsel test raporları ve güncel doğrulama sınırı [12](12_TEAM_PLAN_AND_DECISIONS.md)'dedir.
