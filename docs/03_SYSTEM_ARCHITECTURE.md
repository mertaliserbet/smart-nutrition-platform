# 03 — Sistem mimarisi

> Teknolojiler `12` karar 20 ile **onaylıdır**. Paket/sürüm, dağıtım, oturum ve açık şema ayrıntıları ayrıca kararlaştırılır; hazırlık durumu `12`de izlenir. Uygulama iskeleti ayrı uygulama görevinin kapsamıdır.

## Tasarlanan bileşenler
```text
Client Mobile       ─┐
                     ├── HTTPS /api/v1 → Main Backend → PostgreSQL
Dietitian/Admin Web ──┘
Main Backend → (gerekirse) AI Service
                            ├── food-image inference
                            └── lab insight / OCR
Wearable OS APIs → Mobile → Main Backend (izinli, kaynak etiketli)
```

- **Mobil:** danışan deneyimi, kamera/galeri, cihaz izinleri, öğün/su/ölçüm/lab/aktivite, kişisel/atanmış program, görev/yorum ve paylaşım akışları; ayrıca diyetisyen başvurusu.
- **Web:** ilk sürüm diyetisyen ve ayrı Admin yönetim paneli; danışan izleme, program/alternatif/geçmiş, görev/yorum, analiz ve izinli PDF raporları. Admin sağlık içeriğini varsayılan göremez.
- **Backend:** kimlik, doğrulama/MFA, rol, ilişkiler, kişisel/atanmış program yetkileri, kategori paylaşımı/tahlil açık onayı, tek aktif kuralları, kaynak/tekilleştirme, audit ve ortak API.
- **AI:** uygun hazır model/API veya gerektiğinde model çalıştırma; özel eğitim zorunlu değildir. Sahiplik/izin ana backend'de denetlenir; AI servisi veri güvenlik kuralını by-pass etmez. OCR kullanıcı onayı öncesinde kalıcı LabResult üretmez.
- **Veritabanı:** ilişkisel, migration ile versiyonlu.

## Onaylı teknolojiler
| Katman | Seçim | Gerekçe |
|---|---|---|
| Mobile | Flutter / Dart | Android/iOS, kamera ve platform köprüleri |
| Web | React + TypeScript | Diyetisyen paneli, tutarlı tipler |
| Backend | ASP.NET Core Web API / C# | Yetki, DTO, sağlam servis katmanı |
| DB | PostgreSQL | İlişkiler, transaction, indeksleme |
| AI | Gerektiğinde Python / FastAPI | Model/inference ekosistemi; ayrı servis veya belirli sağlayıcı zorunluluğu yok |
| Kontrat | OpenAPI + `docs/06_API_CONTRACT.md` | Aynı client/server sözleşmesi |

## Sınırlar ve entegrasyon ilkeleri
1. Mobil veya web veritabanına doğrudan bağlanmaz.
2. API JSON anahtarları `camelCase`, kalıcı kayıt ID'leri UUID, zamanlar UTC ISO 8601, ölçü birimleri açık (bkz. 04–06).
3. Yetkilendirme kaynak bazlı yapılır: URL'deki `clientId` tek başına erişim izni vermez.
4. AI'ya gönderilen veri en az gerekli miktardır; kişisel veri paylaşımı için açık izin/uygun işleme şartı değerlendirilir.
5. Sağlık verisi için hata mesajları gereksiz kişi/ölçüm bilgisi sızdırmaz.
6. AI yavaş/kapalıysa manuel öğün ve lab kaydı çalışmaya devam eder.
7. Dosya yüklemeleri için içerik türü, boyut, virüs taraması/izin kontrolleri ve güvenli depolama kararları gerekir.
8. `FoodAnalysis` mevcut `pending/processing/completed/failed` durumlarıyla asenkron çalışır; sonuç güncellemesi tekrar güvenli olmalıdır. Bu enum OCR veya LabInsight için otomatik yeniden kullanılmaz; onların iş/durum şeması açıktır.
9. Aktif diyetisyen ilişkisi tek başına tüm kaydı açmaz; doğrulanmış uzman + aktif ilişki + ilgili kategori izni, tahlilde ayrıca açık onay kontrol edilir. İzin geri çekilince cache, analiz veya rapor bağlantısı eski erişimi sürdüremez.
10. Tek aktif ilişki/program yalnız UI kontrolüyle sağlanmaz; backend ve PostgreSQL eşzamanlı işlemlerde de bütünlüğü korur. Kişisel/atanmış program aynı NutritionPlan'dır; kişisel program için diyetisyen gerekmez. Sürüm geçmişi fiziksel yapısı onaylanmadan yerinde güncelleme ile geçiştirilmez.
11. Cihaz kaynağı/dış kimlik, manuel giriş ve tekrar/örtüşme kuralları `05/06`ya uyar. Adım/nabız/aktif kalori için yeni genel ölçüm modeli veya provider enumu uydurulmaz; ortak onay beklenir.

## Repo organizasyonu önerisi
```text
apps/mobile/                  # tek Flutter projesi (uygulama görevi kapsamında)
apps/web/                     # tek web projesi (uygulama görevi kapsamında)
services/api/                 # tek backend; feature/domain klasörleri
services/ai/                  # gerekliyse AI inference/deneyleri
docs/                         # ortak sözleşmeler
```
İç dizinleri ve sınıf ayrımlarını gerçek ihtiyaç çıktıkça feature/domain sorumluluklarına göre kur. `controllers/services/repositories` gibi soyutlamaları sırf şablon olsun diye çoğaltma. Tek dev dosya da üretme; her metot/widget için dosya açma. Ortak bileşen/servis tekrar, sorumluluk veya test ihtiyacı doğduğunda çıkarılır; başka geliştiricinin alanında geniş refactor ayrı görevdir. Flutter/React kodu paylaşılmaz; isimler, JSON ve tasarım token karşılıkları eşdeğerdir.

## API–AI ilişki örnek akışı
1. Mobil `POST /api/v1/food-analyses` çağırır.
2. Backend token, dosya, izin ve hız limitini doğrular; analiz kaydı oluşturur.
3. AI inference tetiklenir, belirsizlik ve model sürümü saklanır.
4. Mobil analizi okur; kullanıcı öneriyi kontrol eder, gerektiğinde düzeltir ve onaylar.
5. Kullanıcı ayrıca `POST /api/v1/meal-logs` ile onaylı öğünü kaydeder. **Analiz otomatik olarak yemek kaydına dönüşmez.**

## İzlenebilirlik / kalite
API istek ID, merkezi yapılandırılmış log, health check, asgari performans ölçümleri, otomatik test ve gizli bilgilerin konfigürasyon yönetimi hedeflenir. Tanımlı olmayan deployment sağlayıcısı veya bulut maliyeti varsayma.

Profil düzenleme/uzman profili, kalan oturum işlemleri, kategori/consent kodları, program sürüm/alternatif ve geçiş, görev/yorum, OCR ve sync DTO'ları için `12` hazırlık tablosu modül giriş koşuludur. Kendi hesap okuması `GET /auth/me` için `06`daki onaylı beş alanlı DTO kullanılır. Queue, WebSocket, depolama sağlayıcısı, ORM/paket sürümü veya OCR iş modeli bu mimari çiziminden çıkarılmaz; ilgili sözleşme açıkken gerçek entegrasyon tamamlandı denmez.
