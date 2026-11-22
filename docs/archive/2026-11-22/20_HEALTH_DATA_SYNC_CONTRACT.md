> **TARİHSEL ARŞİV — 22.11.2026 öncesindeki metin korunmuştur.** Bu dosyadaki durumlar, test sayıları, teklifler, Git/sahiplik talimatları ve açık kararlar güncel teknik sözleşme değildir. Güncel kaynaklar [aktif belge dizininde](../../../README.md) ve [12](../../12_TEAM_PLAN_AND_DECISIONS.md) içindedir. Aşağıdaki gövde yalnız tarihsel kayıttır; yerel bağlantı yolları arşiv konumuna uyarlanmıştır.

# U3 — Sağlık verisi API teslimi / M3 entegrasyonu

19.11.2026 kullanıcı uygulama talimatı birim, zaman, kaynak, izin ve tekrar aktarım
kararlarını onaylar. Bu belge `04/05/06` sözleşmesinin somut M3 kullanım notudur.
M1 mobil okuyucusu değiştirilmedi; HTTP aktarımını ve senkronizasyon ekranını M3 yapar.

## Kimlik ve izin

Tüm yollar `/api/v1` altında, HTTPS + doğrulanmış `client` JWT bearer ile çalışır.
`X-Profile-Context: client` gönderilir; diyetisyen bağlamı, diyetisyen/Admin rolü
ve web cookie oturumu erişim vermez. Sunucu `sub` → güncel User → kendi ClientProfile
üzerinden sahipliği çözer. Gövdede `userId`/`clientId` kabul edilmez. Yabancı
bağlantı/kayıt `404`; kayıt sayıları da yalnız oturum sahibinindir. Yanıtlar ve
hatalar `no-store` kullanır. Diyetisyen ilişkisi/kategori paylaşım izni aranmaz ve
bu teslim hiçbir sağlık paylaşım kategorisi açmaz.

`WearableConnection.status` **uygulamaya aktarım tercihi**dir; OS izni kanıtı değildir.
M3 okumadan önce/sonra OS izinlerini denetler, reddedilen/başarısız okumanın
verilerini ve bekleyen otomatik aktarımlarını göndermez. Kullanıcı aktarımı
durdurunca bağlantıyı `revoked` yapar; tekrar açmak açık kullanıcı işlemiyle,
güncel sürümle `active` PATCH gerektirir. Sunucu `revoked` bağlantının sync'ini
`403 sync_disabled` ile reddeder. Başlamış ve kilidi önce almış işlem tamamlanabilir;
iptal tamamlandıktan sonraki aktarım reddedilir. Yeniden POST bağlantıyı açmaz.
iOS okuma izninin bilinmemesi/boş okuma, izin verildiği veya kaynak silindiği
anlamına gelmez. Eski kayıtlar otomatik silinmez; kendi geçmiş/özet okuması sürer.
Sunucu OS'ye erişmez ve istemci kaynak beyanına cihaz doğrulaması/attestation uygulamaz.

## Endpointler

| Method / yol | İstek / sonuç |
|---|---|
| `POST /wearable-connections` | `{ "provider": "health_connect" }`; `200 WearableConnection`, aynı danışan+provider için aynı ID; `health_kit` de desteklenir |
| `GET /wearable-connections?page=1&pageSize=100` | `200 {items,totalCount}` |
| `GET /wearable-connections/{id}` | `200 WearableConnection` |
| `PATCH /wearable-connections/{id}` | `{ "expectedVersionNumber": 1, "status": "revoked" }`; `200`, değişiklikte sürüm +1; eski sürüm `409` |
| `POST /wearable-connections/sync` | Aşağıdaki atomik değişiklik batch'i; `200 WearableSyncResult` |
| `GET /wearable-connections/{id}/records?page=1&pageSize=100` | Kaynak başlıkları, **silinenler dahil**; `sourceId`, `rawType`, `externalRecordId` tam eşleşme filtreleriyle güncel sürüm bulunur |
| `GET /wearable-connections/{id}/records/{recordId}` | Tek kaynak başlığı; tombstone okunabilir |
| `GET /health-metric-samples?page=1&pageSize=100` | Aktif skaler/nabız örnekleri; opsiyonel `metric`, `wearableRecordId`, `from`, `to`, `includeDeleted=true` |
| `GET /activity-logs?page=1&pageSize=100` | Manuel+cihaz egzersizleri; opsiyonel `from`, `to` |
| `GET /activity-logs/{id}` | Tek aktif aktivite |
| `POST /activity-logs` | Yalnız manuel; aşağıdaki DTO; `201` ve Location |
| `PATCH /activity-logs/{id}` | Manuel alanların **tam yeni değerleri** + `expectedVersionNumber`; `200`, sürüm +1 |
| `DELETE /activity-logs/{id}?expectedVersionNumber=1` | Gövdesiz; yalnız manuel, soft delete; `204` |
| `GET /activity-logs/daily-summary?from=...&to=...` | Aşağıdaki gün sınırlarıyla gerçek özet |

Sayfalı yollarda `page` ve `pageSize` zorunlu, sayfa ≥1, boyut 1–100,
offset int32 sınırında. Başlıklar güncelleme zamanı azalan+ID; örnek/aktivite
başlangıç zamanı azalan+ID; bağlantılar provider sırasındadır. Zaman filtreleri
**başlangıç ∈ [from,to)**; özet ise güne değen aralıkları ayrıca işler.
Sayfalar ayrı snapshot'lardır; değişiklik sırasında tarama baştan yenilenebilir.
Bilinmeyen/tekrarlanan query anahtarları, GET/DELETE gövdesi ve fazladan JSON
alanı `400`. UTC `Z` veya açık `±hh:mm` zorunlu; saat dilimsiz zaman `400`.

## Birimler ve M1 eşlemesi

| API metric | M1 metric | Native rawType | rawUnit → saklanan birim |
|---|---|---|---|
| `steps` | `steps` | `STEPS` | `COUNT` → `count`, tam sayı ≥0 |
| `distance` | `distance` | HC `DISTANCE_DELTA`; HK `DISTANCE_WALKING_RUNNING` / `DISTANCE_CYCLING` / `DISTANCE_SWIMMING` | `METER` → `km`, rawValue /1000 |
| `exercise` | `exercise` | `WORKOUT` | `MINUTE` → `ActivityLog.durationMinutes` |
| `active_energy` | `activeEnergy` | `ACTIVE_ENERGY_BURNED` | `KILOCALORIE` → `kcal` (yalnız aktif enerji) |
| `heart_rate` | `heartRate` | `HEART_RATE` | `BEATS_PER_MINUTE` → `bpm`, >0 |

M1 `healthConnect` → `health_connect`, `healthKit` → `health_kit`.
M1 `start/end` → `startedAt/endedAt`. **M1 rawValue/rawUnit gönderilir**;
normalize edilmiş `value` tekrar metre olarak gönderilmez. `sourceId` Android
package/bundle kimliği, `externalRecordId` gerçek native ID/UUID, `sourceName`
uygulama adı; her biri boş/kenar boşluklu/kontrol karakterli olamaz, en çok
200 Unicode karakter. ID uydurma, sourceName'i sourceId yerine kullanma.
`recordingMethod` en çok 64 karakterlik native değer olarak korunur; Android
sayısal string/HK enum adı sunucuda tahminle yeniden sınıflandırılmaz.
`exerciseType` yalnız exercise'ta zorunlu (Android native sayısal string veya HK adı).

Sayılar JSON number/decimal; negatif, desteklenmeyen birim/tür, adımda kesir,
nabız/egzersizde sıfır reddedilir. Ölçüm üst sınırı 10^12; klinik eşik/teşhis
anlamı yoktur. Süre >0 ve en çok 7 gün. UTC zamanlar PostgreSQL mikro-saniye
hassasiyetine indirilir; nabız noktası start=end, diğer aralıklar end>start.
Bitiş sunucu saatinden en çok 5 dakika ileride olabilir. Egzersizde raw dakika
ile zaman aralığı en çok **1 ms** farklı olabilir; normalize süre aralıktan hesaplanır,
orijinal raw dakika ayrıca korunur. Tüm mesafe/enerji/süre dönüşümleri sunucudadır.

## Aktarım DTO'su ve tekrar deneme

Sentetik örnek (bağlantı/batch UUID'lerini gerçek kendi bağlantınla değiştir):

```json
{
  "wearableConnectionId": "11111111-1111-4111-8111-111111111111",
  "batchId": "22222222-2222-4222-8222-222222222222",
  "changes": [{
    "operation": "upsert",
    "metric": "distance",
    "sourceId": "example.synthetic.reader",
    "externalRecordId": "native-distance-1",
    "rawType": "DISTANCE_DELTA",
    "expectedVersionNumber": 0,
    "sourceName": "Synthetic reader",
    "recordingMethod": "0",
    "rawUnit": "METER",
    "samples": [{
      "startedAt": "2026-10-20T07:00:00Z",
      "endedAt": "2026-10-20T08:00:00Z",
      "rawValue": 1250
    }]
  }]
}
```

`200` yanıtı `{batchId,wearableConnectionId,committedAt,records:[...]}`.
Her kaynak başlığı: `id,clientId,wearableConnectionId,provider,metric,sourceId,
externalRecordId,rawType,rawUnit,sourceName,recordingMethod,exerciseType,
versionNumber,isDeleted,updatedAt`. İlk kayıt sürümü 1. Örnek yanıtı ayrıca
`id,wearableRecordId,metric,startedAt,endedAt,rawValue,rawUnit,value,unit,isDeleted`
taşır (örnekte `1250 METER` → `1.25 km`).

Kaynak anahtarı: **danışan+provider+sourceId+rawType+externalRecordId**;
danışan/provider bağlantısı unique ve kararlıdır. Aynı native kaydın düzeltmesinde
aynı anahtarla, yeni batchId ve güncel `expectedVersionNumber` ile upsert yapılır;
skaler kayıt tek örneğini, egzersiz aynı ActivityLog'u günceller. Kaynak ID değişirse
eski ID açıkça silinip yeni ID eklenmelidir; sunucu benzer değerlerden kimlik üretmez.

Nabızda aynı native record birden çok örnek içerir: M1 verisini anahtar bazında
grupla, örnek anahtarını normalize UTC başlangıcıyla belirle. Upsert **delta**dır;
gönderilmeyen nabız noktası korunur. Aynı noktada değer düzeltmesi yerinde yapılır.
Zaman düzeltmesinde eski zaman `deletedSampleStarts` listesinde ve yeni nokta
`samples` içinde aynı işlemde gönderilir. Açık nokta silme eski değeri tombstone
olarak korur; henüz kaydedilmemiş noktayı silmek no-op'tur, sıfır ölçüm oluşturmaz.
Nabız dışındaki upsert tam bir örnek ister; deletedSampleStarts kabul etmez.

Kayıt silmek için yalnız kimlik/işlem/sürüm gönder:

```json
{
  "operation": "delete", "metric": "distance",
  "sourceId": "example.synthetic.reader", "externalRecordId": "native-distance-1",
  "rawType": "DISTANCE_DELTA", "expectedVersionNumber": 1
}
```

Silme kaynak başlığını ve tüm alt örnek/aktiviteyi tombstone yapar. Bilinmeyen
kaynak için expectedVersionNumber=0 ile tombstone oluşturulur; eski ilk aktarım
sonradan kaydı diriltemez. Yeniden açma güncel tombstone sürümüyle açık upsert ister.
Boş/eksik batch silme değildir ve `422` olur. Eksik gün/aralık/izin reddi silme değildir.

Bir batch en çok **100 farklı kaynak değişikliği, toplam 1000 örnek ekleme/nokta
silme**, HTTP gövdesi 512 KiB. Aynı kaynak batch'te bir kez bulunur. Tümü tek
transaction; kısmi kabul yoktur. User→ClientProfile kilidi, unique indeksler ve
sürüm kontrolü paralel sunucularda tekrar/yarışları korur. Mevcut duruma tamamen
eşit upsert/delete yeni sürüm üretmez; değişiklik eski sürümle `409` olur.

`batchId` o bağlantıda kalıcı idempotency anahtarıdır. Ağ hatasında **aynı batchId
ve aynı içerikle** tekrar gönder; normalize içerik hash'i aynıysa ilk yanıt ve
committedAt döner, son başarı zamanı yapay ilerlemez. Makbuz tekrarı son deneme
durumunu da yeniden yazmaz; M3 bağlantı durumu ve son HTTP sonucunu ayrı gösterir.
İçerik farklıysa `409 sync_batch_conflict`. Sürüm çatışmasında başlığı/örnekleri yeniden oku, uzlaştır,
yeni batchId ile güncel sürümü gönder; rastgele sürüm yükseltip üzerine yazma.

## Manuel DTO ve günlük özet

Manuel POST:
`{activityType,startedAt,durationMinutes,distanceKm,caloriesKcal,source:"manual"}`.
Üç ölçüm anahtarı zorunlu ama nullable; en az biri dolu. Süre pozitif, mesafe/aktif
kcal ≥0. PATCH aynı alanların tamamını source olmadan, expectedVersionNumber ile
gönderir; null temizler. Yanıt ayrıca `id,clientId,endedAt,rawDurationMinutes,
wearableConnectionId,wearableRecordId,externalRecordId,versionNumber,createdAt,updatedAt`
taşır. Manuel rawDurationMinutes null; cihazda orijinal dakika korunur. Cihaz
aktivitesi bu CRUD'da düzenlenemez/silinemez (`409 source_record_read_only`).

Gün özeti iki **açık offsetli ardışık yerel gece yarısı** alır; UTC farkı 22–26 saat,
DST için farklı offsetler mümkün. Örnek İstanbul: URL-encode edilmiş
`from=2026-10-20T00:00:00+03:00&to=2026-10-21T00:00:00+03:00`.
Sunucu kullanıcının saat dilimini tahmin etmez; doğru gün sınırları M3'ün görevidir.
Yanıttaki from/to UTC'dir, başlangıç dahil/bitiş hariçtir.

`conservative_overlap_v1`: her metric ayrı hesaplanır. Manuel ölçüm →
health_connect → health_kit; aynı provider'da sourceId ordinal; aynı kaynakta
uzun aralık → erken başlangıç → kararlı dış anahtar/ID sırası kullanılır. Her
yüksek öncelikli aralık, kendisi başka aralık yüzünden dışlansa bile doğrudan
örtüştüğü düşük öncelikli aralığı bütünüyle dışlar. Bitişi diğerinin başlangıcı
olan aralıklar örtüşmez. Nabızda yalnız aynı an çakışır. Ham kayıtlar birleştirilmez,
silinmez; değerler orantılanarak tahmin edilmez. Yakın ama örtüşmeyen aralıkların
aynı fiziksel hareket olduğunu API kanıtlamaz.

Scalar adım/mesafe/enerji aralığı gün sınırını aşıyorsa dağılım bilinmediğinden
o günün toplamına alınmaz (`unallocatedCount`); süreli egzersiz gerçek zaman
kesişimiyle dakika hesaplar. Süresiz manuel mesafe/enerjinin kapsadığı aralık
bilinmez; listede korunur, özete eklenmez. Egzersizin enerjisi ayrıca bir cihaz
enerji örneğine kopyalanmaz. Nabız ortalaması kabul edilen örneklerin aritmetik
ortalamasıdır; zaman ağırlıklı klinik ortalama değildir. Gün başına hesaplamanın
her metric sorgusu en çok 100000 adaydır; aşarsa sessiz eksiltme yerine `422` döner.

Özet alanları: `steps,distanceKm,activeEnergyKcal,exerciseMinutes,exerciseCount,
heartRateSampleCount,heartRateMeanBpm,heartRateMinBpm,heartRateMaxBpm,
excludedOverlapCount,unallocatedCount,isPartial,calculationPolicy` ve UTC from/to.
Ölçüm yoksa sayısal toplam **null**, bilinen gerçek sıfırsa 0; sayım alanları 0
olabilir. `isPartial` herhangi bir örtüşme veya dağıtılamayan kayıt varsa true;
istemci eksiksiz platform toplamı iddiasında bulunmaz. Sonuç tanı/tedavi veya
otomatik beslenme hedefi güncellemesi değildir.

## Senkronizasyon durumu ve hatalar

Bağlantı yanıtı: `id,clientId,provider,status,versionNumber,lastSyncedAt,
lastAttemptAt,lastSyncStatus,lastErrorCode`. lastSyncStatus `never/succeeded/failed`.
lastSyncedAt yalnız yeni batch transaction'ı başarıyla commit edilince ilerler;
boş/başarısız istek başarı sayılmaz. Yetki/JSON/gövde/DB kesintisi gibi işlemlerde
attempt metadata'sı yazılamayabilir; M3 son HTTP hatasını ayrıca gösterir.
Semantik/sürüm/batch-limit hatası yalnız attempt metadata'sını günceller; sağlık
satırları ve önceki başarı zamanı korunur. Mobilde veri okunmuş olması başarılı
backend senkronizasyonu değildir.

Ortak zarf: `{error:{code,message},requestId}`; sağlık değeri/kimliği hata/loga yazılmaz.

| HTTP | code |
|---|---|
| 400/401/403/404 | `invalid_request` / `unauthenticated` / `forbidden` / `not_found` |
| 403 | `sync_disabled` |
| 409 | `source_version_conflict`, `sync_batch_conflict`, `source_record_read_only` |
| 413 | `sync_batch_limit` veya HTTP gövdesinde `payload_too_large` |
| 422 | `unsupported_provider`, `unsupported_metric`, `unsupported_source_type`, `unsupported_unit`, `invalid_source_identity`, `invalid_interval`, `invalid_value`, `duration_mismatch`, `invalid_sync_batch`, `duplicate_source_record`, `aggregation_limit_exceeded` |
| 415/429/500 | `unsupported_media_type` / `rate_limited` / `internal_error` |

Migration `20261118222117_AddHealthDataSync`, U1 `20261118204842_AddClientTasks`
sonrasındadır. Yalnız beş yeni tablo/index/constraint ekler; eski veri/izinlere
backfill/değişiklik yapmaz. Veri/bağlantı/receipt varken Down reddedilir.
Uygulama DB'sine uygulanmadı. PostgreSQL API testleri fiziksel Android/iOS sağlık
doğrulaması değildir; cihaz doğrulaması ve M3 HTTP entegrasyonu ayrı teslimdir.

U3 doğrulaması: build 0 hata/0 uyarı; ayrı PostgreSQL'de 20 U3 testi dahil
468 başarılı/0 başarısız/2 Mailpit testi atlandı (toplam 470). Model/snapshot ve
gerçek PostgreSQL sütun/FK/key/index karşılaştırması geçti. Komutlar ve ilk test
ortamı düzeltmeleri [koordinasyon kaydında](PARALLEL_WORK_PLAN_2026-11-19.md).
