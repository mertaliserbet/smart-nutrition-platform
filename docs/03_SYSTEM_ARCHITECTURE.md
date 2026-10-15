# 03 — Sistem mimarisi

> Teknoloji isimleri **öneridir, henüz kesin seçim değildir**. Kullanıcı onayı olmadan proje iskeleti veya ek bağımlılık oluşturma.

## Tasarlanan bileşenler
```text
Client Mobile ─┐
               ├── HTTPS /api/v1 → Main Backend → PostgreSQL
Dietitian Web ─┘                         │
                                       └── (gerekirse) AI Service
                                             ├── food-image inference
                                             └── lab insight inference
Wearable OS APIs → Mobile → Main Backend (izinli, kaynak etiketli)
```

- **Mobil:** kullanıcı deneyimi, kamera, cihaz izinleri, yemek/su/lab/aktivite kayıtları.
- **Web:** diyetisyen paneli; gerektiğinde sınırlı admin ekranları.
- **Backend:** kimlik, rol, ilişkiler, iş kuralları, sağlık verisi yetkileri, audit, API sözleşmesi.
- **AI:** model eğitimi/inference; API sahibi/özne yetkisi ana backend'de; AI servisi veritabanı güvenlik kuralını by-pass etmez.
- **Veritabanı:** ilişkisel, migration ile versiyonlu.

## Teknoloji önerisi (karar defteri onayı bekliyor)
| Katman | Öneri | Gerekçe |
|---|---|---|
| Mobile | Flutter / Dart | Android/iOS, kamera ve platform köprüleri |
| Web | React + TypeScript | Diyetisyen paneli, tutarlı tipler |
| Backend | ASP.NET Core Web API / C# | Yetki, DTO, sağlam servis katmanı |
| DB | PostgreSQL | İlişkiler, transaction, indeksleme |
| AI | Python, gerekirse FastAPI | Model/inference ekosistemi |
| Kontrat | OpenAPI + `docs/06_API_CONTRACT.md` | Aynı client/server sözleşmesi |

## Sınırlar ve entegrasyon ilkeleri
1. Mobil veya web veritabanına doğrudan bağlanmaz.
2. API JSON anahtarları `camelCase`, kalıcı kayıt ID'leri UUID, zamanlar UTC ISO 8601, ölçü birimleri açık (bkz. 04–06).
3. Yetkilendirme kaynak bazlı yapılır: URL'deki `clientId` tek başına erişim izni vermez.
4. AI'ya gönderilen veri en az gerekli miktardır; kişisel veri paylaşımı için açık izin/uygun işleme şartı değerlendirilir.
5. Sağlık verisi için hata mesajları gereksiz kişi/ölçüm bilgisi sızdırmaz.
6. AI yavaş/kapalıysa manuel öğün ve lab kaydı çalışmaya devam eder.
7. Dosya yüklemeleri için içerik türü, boyut, virüs taraması/izin kontrolleri ve güvenli depolama kararları gerekir.
8. Asenkron işleme gerekiyorsa `pending/processing/completed/failed` durumlarıyla idempotent sonuç güncelleme kullanılır.

## Repo organizasyonu önerisi
```text
apps/mobile/                  # tek Flutter projesi (onay sonrası)
apps/web/                     # tek web projesi (onay sonrası)
services/api/                 # tek backend; feature/domain klasörleri
services/ai/                  # gerekliyse AI inference/deneyleri
docs/                         # ortak sözleşmeler
```
İç dizinleri ve sınıf ayrımlarını gerçek ihtiyaç çıktıkça kur. `controllers/services/repositories` gibi soyutlamaları sırf şablon olsun diye çoğaltma. Tek dev dosya da üretme.

## API–AI ilişki örnek akışı
1. Mobil `POST /api/v1/food-analyses` çağırır.
2. Backend token, dosya, izin ve hız limitini doğrular; analiz kaydı oluşturur.
3. AI inference tetiklenir, belirsizlik ve model sürümü saklanır.
4. Mobil analizi okur ve öneriyi kullanıcıya düzenletir.
5. Kullanıcı ayrıca `POST /api/v1/meal-logs` ile onaylı öğünü kaydeder. **Analiz otomatik olarak yemek kaydına dönüşmez.**

## İzlenebilirlik / kalite
API istek ID, merkezi yapılandırılmış log, health check, asgari performans ölçümleri, otomatik test ve gizli bilgilerin konfigürasyon yönetimi hedeflenir. Tanımlı olmayan deployment sağlayıcısı veya bulut maliyeti varsayma.
