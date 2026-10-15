# 02 — Roller, izinler ve kullanıcı akışları

**Kanonik roller:** `Client`, `Dietitian`, `Admin`. API rol değerleri `client`, `dietitian`, `admin` (bkz. `04_NAMING_CONVENTIONS.md`).

## Yetki matrisi (taslak)
| İşlem | Client | Dietitian | Admin |
|---|---|---|---|
| Kendi profilini/sağlık verilerini görüntüleme | Evet | Kendi profilini | Kural gerektiren sınırlı yönetim |
| Kendi yemek/su/aktivite/lab kaydı | Oluştur/düzenle/sil | Hayır | Hayır |
| Diyetisyen ilişki talebi | Talep et/sonlandır | Kabul/red/sonlandır | Denetle (istisnai) |
| Danışanın paylaşılmış kayıtları | Kendi kayıtları | **Aktif ilişki + erişim kapsamı** | Varsayılan hayır |
| Beslenme planı | Kendi aktif planını gör | Yetkili danışana oluştur/atama/düzenle | Varsayılan hayır |
| Hesap/yetki operasyonu | Kendi hesap silme | Kendi hesap tercihleri | Yetkili idari işlem |

Yönetici, “tüm laboratuvar sonuçlarını istediği gibi görür” varsayımıyla tasarlanmaz. Minimum erişim; destek taleplerinde gerekçe ve audit zorunluluğu.

## Akış A — ilk kullanım
1. Kullanıcı hesap oluşturur, rol seçer; diyetisyen rolü için uzmanlık doğrulaması daha sonra/operasyonda yapılır.
2. Gizlilik bilgilendirmesi ve gerekli açık rıza işlemleri ayrı tutulur; zorunlu olmayan iznin reddi temel işlemleri mümkün olduğunca engellemez.
3. Danışan ölçüm/hedef (isteğe bağlı) girer; diyetisyen bağlamadan günlük takip yapabilir.
4. Bir diyetisyen ile ilişki isteği başlatabilir. Başka danışan verisi görünmez.

## Akış B — yemek kaydı
1. Manuel besin girişi veya fotoğraf çekimi/seçimi.
2. AI sonucu: tahmin edilen besin(ler), porsiyon/gram belirsizliği, tahmini enerji ve makrolar.
3. Kullanıcı miktarı ve besini değiştirir; açık onayından sonra `MealLog` kaydedilir.
4. Aktif diyetisyen ilişkisi ve paylaşım izni varsa güncellenen kayıt diyetisyen panelinde görünür; bildirim varsa kapsam/tercihlere bağlıdır.
5. Düzenleme/silmede diyetisyen görünümü güncel durumu yansıtır; audit politikası uygulanır.

## Akış C — beslenme planı
1. Diyetisyen aktif danışanı seçer.
2. `NutritionPlan` taslağını öğün önerileri, hedefler ve tarih aralığıyla hazırlar.
3. Planı aktif olarak atar; danışan mobilde planı ve güncel sürümü görür.
4. Danışan planı değiştiremez; öğün tüketim kaydı planla ilişkilendirilebilir (zorunlu eşleştirme değil).
5. Plan revizyonlarında geçmiş sürüm ve değişiklik kaydı korunur (ayrıntılı sürümleme ileri faz olabilir).

## Akış D — tahlil kaydı
1. Danışan `LabReport` kaydı açar; `LabResult` değerlerini tarih, birim, test adı ve rapor referans aralığı ile ekler.
2. Sistem ölçümle referansı karşılaştırır, mümkün değilse `unknown` döner.
3. AI varsa yalnızca açıklayıcı/kanıtlanabilir metin üretir; tanı veya tedavi önermez.
4. Diyetisyen paylaşımı izne bağlıdır; kritik/beklenmeyen değerlerde sağlık uzmanına başvurma yönlendirmesi kullanıcı dostu biçimde sunulur.

## Akış E — aktivite
Danışan yürüyüş, koşu, bisiklet gibi aktiviteleri manuel kaydeder. Desteklenen cihazlarda ayrı izinle veri aktarımı başlatılır. İçe aktarılan kayıtlar kaynağıyla etiketlenir; manuel ve cihaz verisi çift sayılmaz.

## Açık ürün kararları
- MVP'de bir danışanın aynı anda **tek aktif diyetisyen** ile çalışması önerilir; resmî onay bekliyor.
- Diyetisyen erişim kapsamı granular mı yoksa tek kapsam mı? Karar bekliyor.
- Diyetisyen ilişkisi sona erdiğinde yeni erişim anında kesilir; eski audit kayıtları mevzuata göre korunur.
