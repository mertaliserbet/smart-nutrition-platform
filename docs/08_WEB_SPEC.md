# 08 — Diyetisyen ve admin web deneyimi

## Ürün odağı
Web uygulaması **diyetisyenin günlük çalışma masasıdır**; ağırlıklı iş akışı danışan takibi ve beslenme planı yönetimi. Yönetici operasyonları diyetisyen iş akışından ayrılmalıdır. Danışanların tüm özel verileri rol gerekçesi olmadan açılmaz.

## Diyetisyen ekranları
| Ekran | İçerik ve işlemler | İlgili API |
|---|---|---|
| Giriş / Hesabım | hesap, oturum, doğrulama durumu | `/auth/*`, `/me` |
| Dashboard | aktif danışan sayısı, bekleyen istekler, son kayıtların özeti | `/dietitian-relationships`, `/dietitian/clients` |
| Danışan Listesi | ara/filtrele, ilişki durumu, sınırlı özet kartları | `/dietitian/clients` |
| Danışan Detayı | hedefler, günlük/haftalık özet, ölçüm trendi | `/dietitian/clients/{clientId}/dashboard` |
| Öğün Günlüğü | danışanın girdiği yemeklerin zaman çizelgesi ve kalori/makro bilgisi | `/dietitian/clients/{clientId}/meal-logs` |
| Beslenme Planları | taslak plan oluştur, öğün önerilerini düzenle, aktif et | `/nutrition-plans` |
| Laboratuvar Takibi | izinli test değerleri, tarih, referans aralığı, açıklama | `/dietitian/clients/{clientId}/lab-reports` |
| Bağlantı İstekleri | kabul/red ve ilişki sonlandırma | `/dietitian-relationships` |
| Uzman Profili / Ayarlar | hesap/uzmanlık alanları, oturum ve bildirim tercihleri | `/me` |

## Admin ekranları — sınırlı başlangıç
Hesap/rol operasyonları ve diyetisyen doğrulama süreçleri tasarlanacak; admin'in hasta sağlık verilerini varsayılan okuma hakkı **olmayacak**. Yeni admin endpointleri sözleşme onayından sonra `06_API_CONTRACT.md`'a eklenir; tahmin edilerek üretilmez.

## Temel UX davranışları
- Ekranlar profesyonel, erişilebilir, responsive; masaüstünde verimli tablo ve filtreler; tablette kullanılabilir düzen.
- Danışanın yeni öğün kaydı ilk aşamada **yenileme veya isteğe bağlı polling ile** görülebilir; anlık push/WebSocket ancak karar sonrası uygulanır. “Anında düşer” vaadi bağlantı mekanizması yoksa verilmez.
- Yetkisiz danışana erişimde frontend saklama tek başına yeterli değildir; backend ilişkiyi kontrol eder.
- Sonuç kartları kaynağı, tarihi, belirsizliği gösterir. AI tahminleri sanki doğrulanmış gerçekmiş gibi görüntülenmez.
- Formlarda değişiklik kaybı uyarısı, loading, boş durum, hata yönetimi ve geri bildirim bulunur.
- Plan oluşturma aşamalı ve kolay olmalı; uzun tek form yerine mantıklı gruplar tercih edilir. Gereksiz iç içe bileşen/klasör yapılmaz.

## Kabul kriterleri
1. İlgisiz diyetisyen başka danışanın bilgilerini göremez (sunucuda test).
2. Diyetisyen planı oluşturup aktif ettiğinde danışan mobilde görür.
3. Danışanın öğün kaydı webde doğru gram, birim ve zamanla görünür.
4. Her ekran `04/05/06` kanonik adlarını kullanır; farklı DTO tahmin edilmez.
5. Admin işlevleri için yetki ve audit testleri bulunur.
