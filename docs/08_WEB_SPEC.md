# 08 — Diyetisyen ve admin web deneyimi

## Ürün odağı
Web uygulaması **diyetisyenin günlük çalışma masasıdır**; ağırlıklı iş akışı danışan takibi ve beslenme planı yönetimi. Yönetici operasyonları diyetisyen iş akışından ayrılmalıdır. Danışanların tüm özel verileri rol gerekçesi olmadan açılmaz.

React/TypeScript ve ilk sürüm yönetim panelinin webde olması onaylıdır; Uğur web, Auth ve ilgili API'lerin sahibidir. İlk sürüm öğün yorum/cevap/bildirim şartı korunur; PDF raporu/görev gibi onaylı özelliklerin yayın takvimi `01/12`de ayrıca planlanır. Açık/koyu tema ve ortak tasarım tokenları kullanılır.

## Diyetisyen ekranları
Yollar `/api/v1` tabanına göredir; yeni endpoint veya DTO bu ekran listesinden çıkarılmaz. Açık şemalar `06/12`ye göre önce tamamlanır.

| Ekran | İçerik ve işlemler | İlgili API / açık bağımlılık |
|---|---|---|
| Giriş / Hesabım | E-posta/şifre, doğrulama/sıfırlama, güvenli oturum ve uzman doğrulama durumu | `/auth/*`, `GET /auth/me`; hesap özeti yalnız `06`daki beş alandır. W2 web cookie/CSRF/iptal onaylıdır; uzman doğrulama durumu, sıfırlama ve MFA açık bağımlılıktır |
| Dashboard | aktif danışan sayısı, bekleyen istekler, son kayıtların özeti | `/dietitian-relationships`, `/dietitian/clients` |
| Danışan Listesi | Aktif ilişkili danışanların sınırlı id/displayName listesi; izinli ek özetler ayrı kapsam | `/dietitian/clients`; bekleyen/bitmiş ilişki durumları `/dietitian-relationships`ten |
| Danışan Detayı | hedefler, günlük/haftalık özet, ölçüm trendi | `/dietitian/clients/{clientId}/dashboard` |
| Öğün Günlüğü | İzinli öğün/zaman/kalori/makro; yorum ve cevaplar; diyetisyen tüketimi değiştiremez | `/dietitian/clients/{clientId}/meal-logs`; comments için `06`daki öneri AÇIK ŞEMA |
| Su / Ölçüm / Aktivite | İzinli kayıtlar, kaynak/geçmiş, ölçüm ve gelişim grafikleri | `/dietitian/clients/{clientId}/water-logs`, `/dietitian/clients/{clientId}/body-measurements`, `/dietitian/clients/{clientId}/activity-logs` |
| Beslenme Planları | Kendi atadığı programı oluştur/düzenle/aktif et; alternatif ve sürüm geçmişi; kişisel programı izin kapsamında yalnız oku | `/nutrition-plans`; tam items/sürüm/alternatif ve değiştirme akışı AÇIK ŞEMA |
| Tarifler | Kendi özel tarifleri ve erişime izinli kaynaklarla program hazırlama | `/recipes`; bileşen/görünürlük/geçmiş AÇIK ŞEMA |
| Görevler | Yetkili danışana ClientTask, son tarih, durum ve isteğe bağlı hatırlatma | `/client-tasks`; durum geçişi/son tarih/hatırlatma AÇIK ŞEMA |
| Laboratuvar Takibi | İzinli değer/birim/tarih/referans ve açıklama; ayrıca tahlil açık onayı gerekir | `/dietitian/clients/{clientId}/lab-reports`, `/lab-reports/{labReportId}/insights`; danışan yerine tahlil CRUD yetkisi vermez |
| Analiz ve PDF raporları | İzinli trend, program uyumu ve PDF; kapsam dışında kategori/tahlil eklenmez | Dashboard mevcut; uyum formülü, rapor DTO/dosya erişimi ve PDF endpointi açık |
| Bildirimler | İlk sürüm yorum/cevap bildirimi ve onaylı tercih akışı | Bildirim modeli/kanalı/endpointleri açık; WebSocket varsayılmaz |
| Bağlantı İstekleri | kabul/red ve ilişki sonlandırma | `/dietitian-relationships` |
| Uzman Profili / Ayarlar | hesap/uzmanlık alanları, oturum ve bildirim tercihleri | `GET /auth/me` yalnız hesap özeti; uzmanlık/profil düzenleme ve tercihler bu DTO'ya eklenmez, ilgili açık şemalar ayrıca tamamlanır |

## Admin ekranları — onaylı kapsam, açık uygulama ayrıntıları
Doğrulama, kullanıcı/hesap operasyonları, şikâyetler, besin kataloğu, Audit Log (`AuditEvent`) ve sistem durumu onaylı kapsamdır. İlk sürüm paneli webdedir; yönetim oturumu MFA gerektirir. Admin'in sağlık verilerini varsayılan okuma hakkı **yoktur**; destek/audit ekranı sağlık değerlerini topluca açamaz.

Başvuru mobil veya webden alınabilir; doğrulayan Admin'dir. Başvuru belgeleri, ret/yeniden başvuru, idari rol değişiklikleri, MFA challenge ve admin endpoint DTO'ları açıktır. Bunlar ortak sözleşme onayından sonra `06`da tamamlanır; yeni `/admin/*` yolları bu belgeden tahmin edilmez.

## Temel UX davranışları
Onaylı W2-C1–C7 diliminde giriş mevcut beş alanlı hesap özetine ve hesap ekranına
gider; danışan veya diyetisyen rolü tek başına panel/sağlık yetkisi vermez.
Hesap ekranı yenilenince aynı origin HTTPS cookie ile CSRF ve GET auth/me yeniden
okunur. Başarısız çıkışta hassas bilgiler kaldırılır, sunucuda iptal doğrulanmadığı
gösterilir; eski CSRF/hesap değişiminde yazma otomatik tekrarlanmaz. JWT/CSRF
kalıcı depolama veya URL'ye yazılmaz. Uzman doğrulama durumu beş alanlı hesap
DTO'suna eklenmez; başvuru/MFA ve gerçek panel erişimi ayrı açık bağımlılıktır.

- Ekranlar profesyonel, erişilebilir, responsive; masaüstünde verimli tablo ve filtreler; tablette kullanılabilir düzen.
- Danışanın yeni öğün kaydı ilk aşamada **yenileme veya isteğe bağlı polling ile** görülebilir; anlık push/WebSocket ancak karar sonrası uygulanır. “Anında düşer” vaadi bağlantı mekanizması yoksa verilmez.
- Yetkisiz danışana erişimde frontend saklama yeterli değildir; backend doğrulanmış uzman + aktif ilişki + kategori izni, tahlilde ayrıca açık onay kontrol eder. Geri çekilince yeni okumalar, cache ve PDF erişimi engellenir; listeler/sayılar kapalı kategoriden bilgi sızdırmaz.
- Sonuç kartları kaynağı, tarihi, belirsizliği gösterir. AI tahminleri sanki doğrulanmış gerçekmiş gibi görüntülenmez.
- Formlarda değişiklik kaybı uyarısı, loading, boş durum, hata yönetimi ve geri bildirim bulunur.
- Plan oluşturma aşamalı ve kolay olmalı; uzun tek form yerine mantıklı gruplar tercih edilir. Gereksiz iç içe bileşen/klasör yapılmaz.
- İkinci aktif program `409` ile ele alınır; başka programı veya sahipliği sessizce değiştiren UI akışı kurulmaz. Sürüm geçmişi korunur; program geçişi/alternatif DTO'su açıkken form kendi veri yapısını üretmez.
- OCR'da diyetisyen yardımcı inceleme yapabilir; kullanıcının kontrol/onayı yerine geçemez. Geçersiz/eksik birim-aralıkta kesin klinik yorum veya otomatik alarm eşikleri uydurulmaz.

## Kabul kriterleri
1. İlgisiz diyetisyen başka danışanın bilgilerini göremez (sunucuda test).
2. Diyetisyen planı oluşturup aktif ettiğinde danışan mobilde görür.
3. Danışanın öğün kaydı webde doğru gram, birim ve zamanla görünür.
4. Her ekran `04/05/06` kanonik adlarını kullanır; farklı DTO tahmin edilmez.
5. Admin işlevleri için yetki ve audit testleri bulunur.
6. İlk sürüm yorum/cevap/bildirim akışı, kategori/tahlil onayı geri çekme ve tek aktif program çakışması doğrulanır. Admin MFA ve varsayılan sağlık verisi erişiminin yokluğu test edilir; testin gerçekten çalıştırıldığı raporlanır.
7. Kişisel programın diyetisyen tarafından değiştirilememesi, görev/yorumun başka danışana bağlanamaması, raporlarda izin kapsamı ve açık/koyu tema doğrulanır. Açık DTO'lar için feature bitmiş sayılmaz; hazırlık ve onay listesi `12`dedir.
