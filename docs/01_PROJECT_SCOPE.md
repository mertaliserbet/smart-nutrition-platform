# 01 — Proje kapsamı ve ürün vizyonu

**Sürüm:** DOCS-V1 · **Durum:** taslak. Eski fitness projesinden hiçbir kod, şema veya ekran devralınmaz.

## Ürün tanımı
Diyetisyen–danışan ilişkisinin merkezde olduğu, beslenme verisi takibini ve kanıt düzeyi açık AI destekli analizleri birleştiren mobil + web + API sistemi. Kullanıcı diyetisyensiz de günlük kayıt tutabilir; diyetisyenle bağlandığında yetki kapsamında kayıtları diyetisyene görünür.

## Kullanıcılar ve temel değer önerisi
- **Danışan (`Client`)**: öğün, su, ölçüm ve aktivite kayıtlarını kolay girer; atanmış planı ve gelişimini görür; AI tahminlerini düzeltip onaylar.
- **Diyetisyen (`Dietitian`)**: danışanını görür, program atar/günceller, öğünleri ve ilerlemeyi yorumlar; klinik kararı kendisi verir.
- **Yönetici (`Admin`)**: hesap/uzman doğrulama, güvenli operasyon, şikâyet ve erişim denetimi.

## Özellikler ve aşamalar
| Başlık | MVP (öncelik) | Sonraki sürüm / araştırma |
|---|---|---|
| Hesap | kayıt/giriş/rol, profil ve bağlantı talebi | çoklu diyetisyen, ücretlendirme |
| Öğün | manuel öğün + besin + gram/adet + kalori/makro | barkod, ürün kataloğu genişletme |
| Görsel AI | fotoğrafı analiz et, olası besinleri öner, kullanıcı onaylasın | sürekli canlı kamera, gelişmiş porsiyon kestirimi |
| Su | manuel su ekle, günlük toplam, hedef | kişiselleştirilmiş hatırlatmalar |
| Ölçüm | kilo, bel vb. zaman çizelgesi | vücut kompozisyon entegrasyonları |
| Aktivite | yürüyüş/koşu vb. manuel kayıt | Health Connect/HealthKit senkronizasyonu |
| Diyetisyen | danışan listesi, günlük kayıt izleme, plan oluşturma/atama | güvenli mesajlaşma, raporlama, randevu |
| Laboratuvar | değer, birim, tarih, laboratuvar referansı gir; aralık farkını göster | belge okuma/OCR, doğrulanmış ML deneyleri |
| Gelişim | günlük/haftalık trend, hedef-uyum | kişiselleştirilmiş öngörüler |
| Bildirim | sistem içi kritik olaylar | push/e-posta tercihleri |

**MVP** mutlak teslim taahhüdü değildir; 2 kişilik kapasite ve dönem süresi için aşama aşama doğrulanacak kapsamdır.

## Ürün ilkeleri
1. Beslenme ve diyetisyen merkezde; antrenör, spor salonu, egzersiz programı yok. Aktivite bilgisi beslenme ve sağlık takibine yardımcı veri.
2. Görsel kalori ve makro değerleri **yaklaşık**; kayda geçmeden kullanıcı doğrulaması gerekir.
3. Laboratuvar sonuçlarında “iyisin/kötüsün” veya hastalık tanısı yerine ölçüm, birim, laboratuvar aralığı, zaman ve açıklama verilir. Hekim/diyetisyen görüşü gerektiği vurgulanır.
4. Sağlık verilerine erişim açık kullanıcı izni, en az ayrıcalık ve denetim izleri ile sağlanır.
5. Mobil ve web, aynı sözleşmeli API üzerinden çalışır.
6. Tasarım; hızlı, okunaklı, erişilebilir, güven veren ve ürün olarak pazarlanabilir olmalı.

## MVP başarı kriterleri (hedef; doğrulanacak)
- Danışan kendi öğününü kaydedebilir, düzeltebilir ve günlük toplamını görebilir.
- Diyetisyen ilişkisi açık olan danışanın kayıtlarını yetki kapsamında görebilir; plan atayabilir.
- Fotoğraf analizi tahmin ve belirsizlik sunar, kullanıcı düzenlemeden kayıt oluşmaz.
- Lab verileri doğru birim/referans olmadan klinik bayrak üretmez.
- Kullanıcılar başka danışanın sağlık verisine erişemez.
- En az bir mobil-web-backend uçtan uca test akışı çalışır.

## Kesinleşmesi gerekenler
Diyetisyen doğrulama yöntemi; ücretli model; ülke/dil kapsamı; mobil platform ilk önceliği; teknoloji seçimi; harici besin veri kaynağı/lisans; bildirim/cihaz kapsamı. Kararlar `12_TEAM_PLAN_AND_DECISIONS.md` dosyasında takip edilir.
