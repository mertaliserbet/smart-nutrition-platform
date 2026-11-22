> **TARİHSEL ARŞİV — 22.11.2026 öncesindeki metin korunmuştur.** Bu dosyadaki durumlar, test sayıları, teklifler, Git/sahiplik talimatları ve açık kararlar güncel teknik sözleşme değildir. Güncel kaynaklar [aktif belge dizininde](../../../README.md) ve [12](../../12_TEAM_PLAN_AND_DECISIONS.md) içindedir. Aşağıdaki gövde yalnız tarihsel kayıttır; yerel bağlantı yolları arşiv konumuna uyarlanmıştır.

# U4 — Diyetisyen su takibi / M4 mobil entegrasyonu

19.11.2026 kullanıcı uygulama onayıyla bağımsız `water_logs` paylaşımı ve
salt okunur diyetisyen API/React görünümü tamamlandı. WaterLog entity'si, kendi
su CRUD/toplam yolları ve kişisel hedef davranışı korunur. Flutter M4 ayrı görevdir.

## Bağımsız izin ve M4 açılımı

Kategori kodu **`water_logs`**. İzin kaydı yoksa veya isGranted=false ise erişim
kapalıdır. Yeni/mevcut ilişkide otomatik su izni oluşturulmaz. nutrition_plans,
meal_logs, body_measurements, client_tasks izinleri suyu açmaz; su izni de bu
kategorileri açmaz. consentRecordId yalnız null/atlanmış kabul edilir.

Mevcut mobil `DietitianApi.sharingCategories` dört kategori içerir;
`permissions()` satır sayısını bu uzunlukla sınırlar, `_permission()` bilinmeyen
kategoriyi reddeder. **M4 yalnız bir etiket eklemekle tamamlanmaz:**

1. sharingCategories ve katı ayrıştırıcıya water_logs ekle; beş kategori,
   sayfalama, tekil kategori/ID, aynı relationshipId ve eksik/false izin testlerini güncelle.
2. Bağlantı izin ekranına su başlık/açıklama/kontrolünü ekle. Mevcut izinler
   korunur; yalnız su satırını POST/PATCH et. Danışan aktif ilişkisinde yönetir;
   diyetisyen danışan adına izin açamaz.
3. İzin verme/geri alma, beş kategori listesi ve diğer izinlerin değişmemesi
   ortak main üzerinde doğrulandıktan sonra ilgili ortamda
   `Relationships:Sharing:WaterLogsEnabled=true` açılır. **Varsayılan false**;
   bu U4 teslimi Development dahil ayarı otomatik açmaz.

Kapalı açılım yeni water_logs POST'unu (true/false) ve mevcut satırın PATCH true
işlemini `422 validation_failed` ile reddeder. Mevcut satırın PATCH false ile
geri çekilmesi mümkündür. Ayar GET satırlarını gizlemez, mevcut açık iznin
yerine geçmez; eski mobil sürüme dönüşte bilinmeyen satır etkisi değerlendirilir.

Danışan kendi JWT'si ve `X-Profile-Context: client` ile:

```http
POST /api/v1/data-sharing-permissions
Content-Type: application/json

{"relationshipId":"11111111-1111-4111-8111-111111111111","category":"water_logs","isGranted":true}
```

`201` yanıtı mevcut DataSharingPermission şeklidir:

```json
{
  "id":"22222222-2222-4222-8222-222222222222",
  "relationshipId":"11111111-1111-4111-8111-111111111111",
  "category":"water_logs","isGranted":true,"consentRecordId":null,
  "createdAt":"2026-11-19T00:00:00Z","updatedAt":"2026-11-19T00:00:00Z"
}
```

Geri alma: `PATCH /api/v1/data-sharing-permissions/{id}` + `{"isGranted":false}`;
yeniden açma aynı ID'ye `{"isGranted":true}`. Kimlik/kategori PATCH ile değişmez.
Liste: `GET /api/v1/data-sharing-permissions?relationshipId=...&page=1&pageSize=10`
→ `{items,totalCount}`. Aynı ilişki/kategori ikinci POST `409 conflict`;
istemci listeyi yeniden okuyup mevcut ID'yi kullanır. Pending/ended ilişkide
izin yazımı `409`; başka ilişkinin ID'si `404`, diyetisyen yazımı `403`.

## Salt okunur diyetisyen API

W2 uzman web cookie veya mevcut JWT + diyetisyen profil bağlamı kabul edilir;
JWT/cookie birlikte 400. Her istekte güncel doğrulanmış uzman, kendisine ait
**active ilişki** ve aynı ilişkide **açık water_logs** aynı RepeatableRead
snapshot'ında satır/sayım/toplamla kontrol edilir. Eksik/false izin veya uzman
doğrulamasının kalkması 403; yabancı danışan/uzman veya pending/ended ilişki 404.
Admin MFA erişim vermez. Danışanın kendi `/api/v1/water-logs` erişimi ilişkisizdir.

| Endpoint | Query / yanıt |
|---|---|
| `GET /api/v1/dietitian/clients/{clientId}/water-logs` | page/pageSize zorunlu, from/to opsiyonel; `200 {items:WaterLog[],totalCount}` |
| `GET /api/v1/dietitian/clients/{clientId}/water-logs/daily-total` | from/to zorunlu ardışık açık offsetli yerel gece yarıları; `200 WaterLogDailyTotalResponse` |
| `GET /api/v1/dietitian/clients/{clientId}/water-logs/daily-history` | page/pageSize/from/to/timeZone zorunlu; en çok 31 yerel gün; `200 {items:WaterLogDailyTotalResponse[],totalCount}` |

WaterLog yanıtı mevcut beş alanın aynısıdır:

```json
{"items":[{"id":"33333333-3333-4333-8333-333333333333","clientId":"44444444-4444-4444-8444-444444444444","amountMl":250.125,"consumedAt":"2026-11-10T07:00:00Z","source":"manual"}],"totalCount":1}
```

Günlük DTO: `{"from":"2026-11-09T21:00:00Z","to":"2026-11-10T21:00:00Z","totalAmountMl":250.125}`.
Miktar/toplam **decimal mL**, JSON number. Hedef/profil/başka sağlık alanı yoktur.
Source mevcut manual/wearable/ai_assisted enumudur; kendi mevcut POST yalnız manual
kabul etmeye devam eder. Diyetisyene POST/PATCH/DELETE veya farklı WaterLog modeli yoktur.

Sayfa ≥1, pageSize 1–100, int32 offset sınırı; varsayılan sayfa yok. Kayıt sırası
consumedAt azalan + ID artan. from dahil/to hariç; zaman filtresi sayfalardan
önce uygulanır. Günlük toplam tüm güne aittir, liste sayfasından hesaplanmaz.
Tarih geçmişi **günler** üzerinden artan sırada sayfalanır; totalCount kayıt
değil istenen yerel gün sayısıdır. Kayıt olmayan yetkili gün 0 içerir.
Silinmiş ve yabancı danışan kayıtları hiçbir toplama girmez. Decimal kapasitesini
aşan toplam 422; kısmi/yanıltıcı sıfır verilmez.

## Tarih ve saat dilimi

Liste günlük kayıtların mevcut açık `Z`/`±HH:mm` ISO kuralını kullanır.
Daily-total kendi su API'sinin 00:00/ardışık yerel gün kuralını aynen kullanır;
farklı başlangıç/bitiş offsetleri 23/25 saatlik günleri ifade edebilir.
URL içindeki + işareti URLSearchParams veya `%2B` ile kodlanır.

Daily-history için örnek:

```text
/api/v1/dietitian/clients/{clientId}/water-logs/daily-history?page=1&pageSize=31&from=2026-11-01T00%3A00%3A00%2B03%3A00&to=2026-11-08T00%3A00%3A00%2B03%3A00&timeZone=Europe%2FIstanbul
```

Bu 1–7 Kasım günlerini içerir. IANA timeZone (veya UTC) aradaki her günün
gerçek gece yarısını belirler; endpoint offsetleri de bu bölgeyle uyuşmalıdır.
Sunucunun yerel saati kullanılmaz, sabit offsetle DST boyunca 24 saat eklenmez.
Her gün 22–26 saatlik geçerli aralık olmalıdır; atlanan/belirsiz gece yarısı,
uyuşmayan offset, bilinmeyen/Windows saat dilimi veya >31 gün 400'dür; sessiz
saat düzeltmesi yoktur. Dönen from/to UTC'dir. History her istekte en çok 31
indeksli SUM sorgusu yapar; yeni günlük tablo/cache gerekmez.

## React, hedefler ve hata davranışı

Gerçek danışan çalışma alanındaki Su takibi bölümünde gün seçimi, 10'lu kayıt
sayfaları, miktar/saat/kaynak, günlük toplam ve en çok 31 günlük grafik+tablo
vardır. UI geçmiş başlangıç/bitişini dahil gösterir; API to ertesi gece yarısıdır.
Saat dilimi tarayıcının IANA bölgesidir, başlangıç ve bitiş offsetleri ayrı üretilir.
Mevcut tarih yardımcısı, WaterLogList, tema/chart CSS ve SVG kullanılır; yeni paket yoktur.

Kişisel su hedefi su iznine dahil değildir; U4 hedef endpointi çağırmaz/hedef
göstermez. Program kartı ve varsa program hedefi kendi nutrition_plans yetkisiyle
çalışır; program izni kapalı olması su tüketimini kapatmaz. Su izni kapalıyken
web danışanın mobil uygulamadan izin yönetmesi gerektiğini söyler, izin açma düğmesi sunmaz.

Yüklenme/boş/403/404/bağlantı/hesaplama hatası ayrıdır. Hata sıfır değildir;
üç okumanın birinde 403/404 varsa toplam/kayıt/grafik tümü kaldırılır. Kalıcı
sağlık önbelleği yok; fetch no-store, yanıt/hatalar no-store. Danışan/oturum/
tarih değişiminde eski görünüm anında gizlenir, AbortController ile eski yanıtlar
elenir. Görünür sekmede 30 sn, fokus/görünürlük dönüşü ve elle yenileme vardır;
gizli sekmede içerik kaldırılır/yeni okuma yapılmaz. Başlamış yetkili snapshot
tamamlanabilir; iptal sonrası yeni okumalar reddedilir. WebSocket eklenmez.

Ortak zarf `{error:{code,message},requestId}`: 400 invalid_request, 401
unauthenticated, 403 forbidden, 404 not_found, 409 conflict, 422 validation_failed,
500 internal_error. Kayıt sayısı/toplam/sağlık değeri hata içine konmaz.

Migration `20261118230136_AddWaterLogSharingCategory`, U3 sonrasındadır; yalnız
kategori check'ini genişletir, tablo/index/veri/backfill eklemez. Mevcut ilişki
kategori unique indeksi ve su client/consumedAt/ID indeksi kullanılır. false
dahil su izin satırı varken Down reddedilir; uygulama DB'sine uygulanmadı.
Flutter M4 ve gerçek cihaz/tarayıcı görsel doğrulaması bu backend/React DOM
testlerinden çıkarılmaz; mobil kaynaklar değiştirilmedi.

Doğrulama: ayrı gerçek PostgreSQL'de U4 **11/11**, tüm backend **479 başarılı /
0 başarısız / 2 Mailpit testi atlandı**. Web U4 **37/37**, tüm web **319 başarılı /
0 başarısız / 3 opt-in canlı test atlandı**. Backend/web build, lint ve migration
model kontrolü geçti. Komutlar ve dosya dökümü [koordinasyon kaydında](PARALLEL_WORK_PLAN_2026-11-19.md).
