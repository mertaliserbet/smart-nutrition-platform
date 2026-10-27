# 06 — HTTP API ortak sözleşmesi

> **İki Codex için ortak kaynak.** URL, request/response anahtarları, rol ve anlamlar burada değiştirilmeden kullanılacak. Bu bir **taslak V1 sözleşmesidir**; `12_TEAM_PLAN_AND_DECISIONS.md` içindeki 22 onaylı karar ile güncel `04/05` esas alınır. Teknoloji ve ürün kararları onaylıdır; açık şema/oturum ayrıntıları ayrıca ortak onay gerektirir.

Mevcut method/route çiftleri korunur; eksik işlemler aynı kaynaklara eklenir. **AÇIK ŞEMA** olarak işaretlenen işlemler yalnız HTTP yönünü/bağımlılığını tanımlar: eksik DTO, enum veya kimlik yapısı kesinleşmeden uygulanmış sözleşme veya hazır mock sayılmaz. Yeni entity adı, alternatif model ya da sırf ekran başına endpoint üretilmez.

## Temel prensipler

- Base path: `/api/v1`. JSON `camelCase`; enum değerleri `04_NAMING_CONVENTIONS.md` içindeki lowercase değerler.
- İç `id`/FK alanları UUID string; zaman UTC ISO 8601 ör. `2026-10-15T12:30:00Z`, tarihler `YYYY-MM-DD`. `externalRecordId` sağlayıcının string kimliğidir, UUID olmak zorunda değildir. Decimal değerler JSON number, boolean true/false; birimler ve nullability `05`e uyar. Ölçümde `null` bilinmeyen, `0` gerçek sıfırdır.
- Onaylı giriş dilimi: 15 dakikalık JWT access token, `Authorization: Bearer <access-token>`. Refresh/logout, istemci secure storage/cookie stratejisi ve MFA ayrıca açık; bu özellikler mevcut giriş dilimine dahil değildir.
- Auth olmayan/geçersiz oturum `401`, rol/ilişki yetkisiz `403`, bulunamayan `404`, doğrulama `400/422`, çakışma `409`, hız limiti `429`, iç hata `500`. Başka danışanın kaydına dair varlık bilgisi sızmaması için uygun yerde `404` kullanılır; aynı kaynak için davranış tutarlı tutulur.
- Liste istekleri `page` (1'den başlayan pozitif integer), `pageSize` (pozitif integer, sunucu limiti); yanıt `{ items: [...], totalCount: integer }`. Varsayılanlar/üst limit **AÇIK**tır. `totalCount` yalnız yetkili filtrelenmiş kümenin sayısıdır. Boş liste `200` ve `items: []` döner.
- Zaman filtresi desteklenen günlük kayıtlarda `from`/`to` UTC instant'tır; `from` dahil, `to` hariçtir; ikisi varsa `from < to` gerekir. Alanlar MealLog/WaterLog için `consumedAt`, ölçüm için `measuredAt`, aktivite için `startedAt`, tahlil için `collectedAt`tır. Yerel gün ve program uyum saat dilimi politikası **AÇIK**tır; istemci/sunucu ayrı ayrı varsaymaz.
- Hata yanıtı: `error: { code: string, message: string, details?: object }, requestId: string`.
- API dokümanı ile uygulamanın OpenAPI çıktısı eşleştirilir; karşılıklı uyumsuzluk testte hata sayılır.

### Ortak istek, yanıt ve hata kuralları

- JSON yazma istekleri `Content-Type: application/json` kullanır; yüklemeler aşağıda belirtilen multipart alanlarıyla yapılır. POST oluşturma `201` ve oluşan kaynağı, GET/PATCH `200` ve güncel kaynağı, başarılı DELETE `204` ve boş gövde döndürür; asenkron analiz ve Auth istisnaları ayrıca belirtilir. `201` yanıtında kaynağın mevcut GET yolu varsa `Location` o yolu gösterir.
- `05`teki `?` JSON anahtarına eklenmez. PATCH'te gönderilmeyen alan korunur; açık `null` yalnız nullable alanı temizler; zorunlu alanı null yapmak `422`dir. İçi boş PATCH `400`dür. Desteklenen `items`/`results` dizisi PATCH'te gönderilirse tam dizi olarak atomik değiştirilir; öğe bazlı kısmi dizi birleştirmesi varsayılmaz. Açık şemalı koleksiyonlar bu kuralla kendiliğinden kesinleşmez.
- `id`, sahiplik kimlikleri, `createdAt`/`updatedAt`, hesaplanan `flag` ve sunucu durumları istemci tarafından atanmaz. Alan tablosunda açıkça istek girdisi sayılan `clientId`, `relationshipId` veya referanslar istisnadır ve sunucuda doğrulanır. Tanımsız/salt okunur alan gönderimi `400`; başka kullanıcının kimliğini geçirerek yetki kazanılamaz.
- Yanıt kaynakları `05`in aynı adlı alan/tiplerini kullanır; `MealLog.items`, `NutritionPlan.items` ve `LabReport.results` ilgili alt kayıtları içerir. Bu, passwordHash, token/secret, özel doğrulama belgesi veya başka kullanıcının alanlarını entity'den otomatik serileştirme izni değildir. Biçimi **AÇIK** alanlar için tam yanıt şeması onaylanmış sayılmaz.
- DELETE normal okumalarda kaydı kaldırır; fiziksel silme, geçmiş ve saklama işlemi `05/11` politikasına uyar. İşlem bu güvenceyle tamamlanamıyorsa sahte `204` verilmez. Cascade davranışı veya anonimleştirme bu belgede seçilmez.

| HTTP | `error.code` | Durum |
|---|---|---|
| `400` | `invalid_request` | Bozuk JSON/UUID/tarih, desteklenmeyen veya salt okunur alan |
| `401` | `unauthenticated` | Oturum yok/geçersiz; hesap/sağlık bilgisi sızdırılmaz |
| `403` | `forbidden` | Rol, ilişki veya kategori kapsamı işlemi karşılamıyor |
| `404` | `not_found` | Kaynak yok veya varlığı açıklanmaması gereken yetkisiz kaynak |
| `409` | `active_relationship_conflict`, `active_nutrition_plan_conflict`, `conflict` | Tek aktif sınırı, tekrar kayıt veya mevcut durumla çatışma |
| `413` / `415` | `payload_too_large` / `unsupported_media_type` | Yükleme sınırı veya desteklenmeyen dosya türü |
| `422` | `validation_failed`, `consent_required` | Geçerli JSON'da miktar/bütünlük/alan kuralı ihlali veya gerekli açık onayın yokluğu |
| `429` / `500` | `rate_limited` / `internal_error` | Hız sınırı veya beklenmeyen hata; iç detay/sağlık değeri dönmez |

`details` yalnız güvenli alan doğrulama bilgilerini içerir; hata gövdesindeki `requestId` izlenebilirlik içindir. Açık bir DTO için yeni enum/alan uydurmak veya sözleşme eksiğini normal kullanıcı hatası gibi sunmak yerine şema onayı tamamlanır.

### Kaynak ve kategori bazlı erişim

- Danışanın `clientId`si oturumdaki User → ClientProfile üzerinden belirlenir. Kendi sağlık kaydına erişmek veya kişisel program oluşturmak için diyetisyen ilişkisi gerekmez.
- Diyetisyenin her sağlık verisi okumasında doğrulanmış uzman durumu, ilgili danışanla güncel `active` ilişki ve ilgili `DataSharingPermission.isGranted = true` kontrol edilir. Kategori kaydı yoksa varsayılan erişim yoktur. Kategori kodları ve endpoint–kategori eşlemesi `05`te **AÇIK**tır; uygulama öncesinde birlikte onaylanır.
- Tahlil için ayrıca aynı danışanın User kaydına ait, kapsamı uygun ve geri çekilmemiş `ConsentRecord` gerekir (`granted = true`, `withdrawnAt = null`). İlişki veya izin sona erince geçmiş kayıt/analiz/PDF dahil diyetisyenin yeni erişimi kesilir; cache ve dosya bağlantısı bu kontrolü atlayamaz.
- Danışanın verisini kaydetme/düzeltme/silme hakkı diyetisyene geçmez. Diyetisyen yalnız kendi atadığı programı/görevi ilgili yetkiyle yönetir ve izinli öğünlere yorum yapar. Diyetisyen kayıtları kendi adına girilmiş tüketim gibi değiştiremez.
- Günlük kayıtların üst düzey yolları danışanın kendi kaydı içindir; diyetisyen okumaları `/dietitian/clients/{clientId}/...` yollarından yapılır. Program, görev, yorum ve insights gibi aşağıda iki role açık olduğu belirtilen kaynaklar aynı kaynak yetkisini ayrıca denetler.
- `Admin` özel sağlık verilerine varsayılan erişemez. Sistem yönetimi/doğrulama yetkisi sağlık kaydı yetkisi değildir; Admin MFA zorunludur. İstisnai erişim ve audit `11`e bağlıdır.

## Endpoint kataloğu (taslak)

| Alan | Method + route | Rol / anlam |
|---|---|---|
| Kimlik | `POST /api/v1/auth/register` | Yalnız danışan kaydı; `201 { id }`, otomatik giriş yok |
| Kimlik | `POST /api/v1/auth/verify-email` | E-postadaki tek kullanımlık token ile doğrulama; `204` |
| Kimlik | `POST /api/v1/auth/resend-verification` | Varlık açıklamayan yeniden gönderim isteği; `202` |
| Kimlik | `POST /api/v1/auth/login` | Doğrulanmış, Admin olmayan hesap için 15 dakikalık JWT access token |
| Kimlik | `POST /api/v1/auth/refresh` | Token yenileme |
| Kimlik | `POST /api/v1/auth/logout` | Oturum kapatma/refresh iptali |
| Kimlik / hesap | `GET /api/v1/auth/me` | Geçerli JWT sahibinin beş alanlı kendi hesap özeti |
| Profil | `PATCH /api/v1/me` | Kendi profilini güncelle |
| Diyetisyen | `GET /api/v1/dietitians` | Uygun uzman arama/görüntüleme (doğrulama şartı) |
| İlişki | `POST /api/v1/dietitian-relationships` | Danışanın ilişki talebi |
| İlişki | `GET /api/v1/dietitian-relationships` | Tarafa göre kendi bağlantıları |
| İlişki | `POST /api/v1/dietitian-relationships/{relationshipId}/accept` | Diyetisyen kabul |
| İlişki | `POST /api/v1/dietitian-relationships/{relationshipId}/reject` | Diyetisyen red |
| İlişki | `POST /api/v1/dietitian-relationships/{relationshipId}/end` | Yetkili taraf bitirir |
| Öğün | `GET /api/v1/meal-logs` | Danışanın kendi kayıtları, tarih filtresi |
| Öğün | `POST /api/v1/meal-logs` | Onaylı öğün kaydı |
| Öğün | `GET /api/v1/meal-logs/{mealLogId}` | Kendi detay |
| Öğün | `PATCH /api/v1/meal-logs/{mealLogId}` | Güncelle |
| Öğün | `DELETE /api/v1/meal-logs/{mealLogId}` | Sil / politikaya uygun işlem |
| Besin | `GET /api/v1/food-items` | Katalog araması (`query`) |
| AI yemek | `POST /api/v1/food-analyses` | Görsel gönder, tahmin işi başlat |
| AI yemek | `GET /api/v1/food-analyses/{analysisId}` | İş durum/sonuç |
| Su | `GET /api/v1/water-logs` | Kendi su kayıtları |
| Su | `POST /api/v1/water-logs` | Su ekle |
| Su | `GET /api/v1/water-logs/{waterLogId}` | Kendi detay |
| Su | `PATCH /api/v1/water-logs/{waterLogId}` | Kendi kaydını düzelt |
| Su | `DELETE /api/v1/water-logs/{waterLogId}` | Kendi kaydını sil |
| Ölçüm | `GET /api/v1/body-measurements` | Kendi geçmiş |
| Ölçüm | `POST /api/v1/body-measurements` | Ölçüm ekle |
| Ölçüm | `GET /api/v1/body-measurements/{bodyMeasurementId}` | Kendi detay |
| Ölçüm | `PATCH /api/v1/body-measurements/{bodyMeasurementId}` | Kendi ölçümünü düzelt |
| Ölçüm | `DELETE /api/v1/body-measurements/{bodyMeasurementId}` | Kendi ölçümünü sil |
| Aktivite | `GET /api/v1/activity-logs` | Kendi aktiviteleri |
| Aktivite | `POST /api/v1/activity-logs` | Aktivite ekle |
| Aktivite | `GET /api/v1/activity-logs/{activityLogId}` | Kendi detay |
| Aktivite | `PATCH /api/v1/activity-logs/{activityLogId}` | Kendi kaydını düzelt; kaynak kimliğini sahteleştiremez |
| Aktivite | `DELETE /api/v1/activity-logs/{activityLogId}` | Kendi kaydını sil |
| Cihaz | `GET /api/v1/wearable-connections` | İzinli bağlantılar |
| Cihaz | `POST /api/v1/wearable-connections/sync` | İzinli/uyumlu senkronizasyon (sonraki aşama) |
| Laboratuvar | `GET /api/v1/lab-reports` | Kendi raporları |
| Laboratuvar | `POST /api/v1/lab-reports` | Ölçüm + değerler ekle |
| Laboratuvar | `GET /api/v1/lab-reports/{labReportId}` | Rapor detay |
| Laboratuvar | `PATCH /api/v1/lab-reports/{labReportId}` | Kendi raporunu/değerlerini düzelt |
| Laboratuvar | `DELETE /api/v1/lab-reports/{labReportId}` | Kendi raporunu sil; saklama politikasına göre |
| Laboratuvar | `POST /api/v1/lab-reports/{labReportId}/insights` | Yetkili kullanıcı için açıklayıcı analiz |
| Laboratuvar | `GET /api/v1/lab-reports/{labReportId}/insights` | Danışan kendi, diyetisyen izinli raporun analizlerini okur; yanıt ayrıntıları AÇIK ŞEMA |
| Diyetisyen | `GET /api/v1/dietitian/clients` | Aktif/uygun danışan listesi |
| Diyetisyen | `GET /api/v1/dietitian/clients/{clientId}/dashboard` | İzinli danışan özetleri |
| Diyetisyen | `GET /api/v1/dietitian/clients/{clientId}/meal-logs` | İzinli öğün kayıtları |
| Diyetisyen | `GET /api/v1/dietitian/clients/{clientId}/water-logs` | İzinli su kayıtları |
| Diyetisyen | `GET /api/v1/dietitian/clients/{clientId}/body-measurements` | İzinli ölçümler |
| Diyetisyen | `GET /api/v1/dietitian/clients/{clientId}/activity-logs` | İzinli aktiviteler |
| Diyetisyen | `GET /api/v1/dietitian/clients/{clientId}/lab-reports` | İzinli tahlil özet/sonuçları |
| Plan | `POST /api/v1/nutrition-plans` | Danışan kişisel, diyetisyen yetkili danışanına taslak program oluşturur |
| Plan | `PATCH /api/v1/nutrition-plans/{nutritionPlanId}` | Danışan yalnız kendi kişisel, diyetisyen yalnız kendi atadığı programı düzenler |
| Plan | `POST /api/v1/nutrition-plans/{nutritionPlanId}/activate` | Yetkili programı aktif etme; tek aktif sınırı |
| Plan | `GET /api/v1/nutrition-plans/active` | Danışan kendi tek aktif kişisel veya atanmış programını görür |
| Plan | `GET /api/v1/nutrition-plans` | Danışanın kendi veya diyetisyenin izinli danışanının program listesi |
| Plan | `GET /api/v1/nutrition-plans/{nutritionPlanId}` | Aynı yetkiyle detay; active literal yolu kimlik yolu olarak yorumlanmaz |

Yeni tarif/görev/paylaşım yolları ve açık şemalı işlemler aşağıdaki tablolardadır; katalogdan ayrı alternatif rotalar değildir. Admin, bildirim, PDF dışa aktarma ve ayrıntılı Auth/MFA gibi şema bağımlı konular için aşağıdaki açık karar sınırları geçerlidir.

## Günlük kayıtlar — request/response ve eksik işlemler

Aşağıdaki POST alanlarında `?` isteğe bağlı/nullable alanı gösteren dokümantasyon işaretidir; gerçek JSON anahtarına eklenmez. Aynı alanların PATCH'te gönderilmeyenleri korunur. `source` oluşturma kaynağını belirtir; sıradan PATCH ile kaynağı/dış kimliği değiştirip cihaz kaydı üretilemez.

| Kaynak | POST gövdesi / düzenlenebilir alanlar | Başarılı yanıt ve doğrulama |
|---|---|---|
| `MealLog` | `mealType`, `consumedAt`, `source`, `items`; opsiyonel `note`, `foodAnalysisId`. Her item: `displayName`, `isEstimated`; nullable `foodItemId`, `recipeId`, `quantityGrams`, `caloriesKcal`, `proteinGrams`, `carbsGrams`, `fatGrams` | `201/200`: `id`, `clientId`, `mealType`, `consumedAt`, `note`, `source`, `foodAnalysisId`, `createdAt`, `items`. Item yanıtında ayrıca `id`, `mealLogId`. En az bir item; gram/kcal/makro kuralları `05`e uyar; tüm referanslar yetkili kaynaklara ait olmalı |
| `WaterLog` | `amountMl`, `consumedAt`, `source`; PATCH yalnız miktar/zaman | `201/200`: `id`, `clientId`, `amountMl`, `consumedAt`, `source`. Miktar pozitif decimal/mL; sıfır/negatif `422` |
| `BodyMeasurement` | `measuredAt`, `source`; nullable `weightKg`, `waistCm`, `bodyFatPercent`. PATCH zaman ve ölçümleri düzeltir | `201/200`: `id`, `clientId` ve aynı ölçüm alanları/source. Son durumda en az bir ölçüm; kg/cm pozitif, yüzde 0–100; aksi `422` |
| `ActivityLog` | Manuel girişte `activityType`, `startedAt`, `source: manual`; nullable `durationMinutes`, `distanceKm`, `caloriesKcal`. PATCH tür/zaman/ölçümleri düzeltir | `201/200`: `id`, `clientId`, giriş alanları, nullable `externalRecordId`, `wearableConnectionId`. Dakika/km/kcal negatif olamaz; aktif/toplam enerji anlamı **AÇIK**tır |
| `LabReport` | `collectedAt`, `results`; nullable `labName`, `note`. Her result: `testName`, `value`, `unit`; nullable `testCode`, `referenceLow`, `referenceHigh`. PATCH aynı alanları düzeltir | `201/200`: `id`, `clientId`, `collectedAt`, `labName`, `note`, `createdAt`, `results`; her result ayrıca `id`, `labReportId`, sunucunun hesapladığı `flag`. En az bir result; bilinen iki sınırda low <= high; eksik/uyumsuz referans `unknown` |

- Bu kaynakların GET detayları aynı yetkili kaynak yanıtını, GET listeleri aynı kaynaklardan `items` ve `totalCount` döndürür. DELETE gövdesizdir. Yazma işlemlerinde ortak hatalara ek olarak referans/yabancı kaynak ihlalleri `422` veya varlık sızdırmayan `404`, geçmiş/silme kısıtıyla çakışma `409`dur.
- MealLog için manuel ve kullanıcı onaylı `ai_assisted` akışları ayrıdır. AI bağlantısı verildiyse aynı danışana ait uygun tamamlanmış analiz doğrulanır; `foodAnalysisId` mevcut sözleşmedeki gibi opsiyoneldir. `foodItemId`/`recipeId` birlikte kullanım kuralı `05`te **AÇIK**tır; iki referanstan çift kalori hesaplanmaz.
- `source = wearable` yalnız izinli senkronizasyon akışında kaynak bilgisiyle kabul edilir. Aktivitede aynı danışana ait `wearableConnectionId` gerekir; `externalRecordId` sağlayıcı kimliğidir. Sıradan manuel POST'a bu alanları eklemek senkronizasyon yetkisi vermez. Sync request/response ayrıntıları **AÇIK ŞEMA**dır; kaynak anahtarı ve manuel/cihaz örtüşmesi kararlaştırılmadan sahte kayıtla kapatılmaz.
- `GET /wearable-connections` yalnız danışanın kendi bağlantılarını `200 { items, totalCount }` içinde `id`, `clientId`, `provider`, `status`, nullable `lastSyncedAt` ile döndürür; secret dönmez. Provider/status kodları ve sync gövdesi açık kalır; OS izni ile diyetisyene paylaşım izni aynı şey değildir.
- Tahlil PATCH sonrası eski LabInsight değişen değerlerin güncel açıklamasıymış gibi gösterilemez; yeniden analiz ve geçmiş gösterimi politikası **AÇIK**tır. Kullanıcı onayı olmayan OCR taslağı bu CRUD gövdelerine otomatik taşınmaz.
- `GET /food-items?query=...` yalnız katalog aramasıdır; `200 { items, totalCount }` içinde FoodItem'ın `05`teki gram temeli, enerji/makro ve `dataSource` alanları bulunur. Yeni katalog yazma endpointi bu görevde açılmaz.
- Diyetisyen günlük kayıt listeleri aynı pagination/zaman filtrelerini ve aynı kaynak şekillerini kullanır; her biri ilgili kategori iznini kontrol eder. Dashboard yalnız izinli bileşenleri sunabilir; kapalı kategoriyi sıfır ölçüm gibi göstermez, izinsiz kayıtlardan sayı/trend sızdırmaz. Dashboard'un tam bileşen şeması ayrıca netleştirilmelidir.
- `GET /dietitian/clients` aktif ilişkili danışanların sınırlı listesini `200 { items, totalCount }` olarak döndürür; item'ın kesin temel alanları ClientProfile `id` ve `displayName`dir. Doğum tarihi, boy ve diğer sağlık özetleri varsayılan liste alanı sayılmaz; ek alanlar kategori kapsamı/yanıt şeması onayı gerektirir.

## NutritionPlan — kişisel/atanmış program sözleşmesi

| İşlem | Request | Response / erişim |
|---|---|---|
| `POST /api/v1/nutrition-plans` | Danışan: `title`, `startDate`; nullable `endDate`, `dailyCaloriesTargetKcal`, `dailyWaterTargetMl`; `items` kısmı aşağıdaki şema sınırına bağlıdır. Diyetisyen bunlara hedef `clientId` ekler | `201` NutritionPlan; başlangıç `status: draft`. Danışanda `clientId` sunucudan, `dietitianId: null`; diyetisyende `dietitianId` kendi profilinden atanır. Başkasına kişisel program veya başkası adına diyetisyen programı oluşturulamaz |
| `GET /api/v1/nutrition-plans` | Pagination; diyetisyen için hedef `clientId` gerekir; danışanın kapsamı kendi profilidir | `200 { items, totalCount }`; diyetisyen aktif ilişki ve uygun kategori izniyle kişisel/atanmış programları okuyabilir; bu okuma düzenleme hakkı vermez |
| `GET /api/v1/nutrition-plans/{nutritionPlanId}` | Gövdesiz | `200` yetkili program detayı; danışan kendi, diyetisyen yalnız izinli danışanının programını okur |
| `GET /api/v1/nutrition-plans/active` | Gövdesiz; danışanın kendi kapsamı | `200` tek aktif kişisel veya atanmış NutritionPlan; yoksa `404`. Kişisel/atanmış için iki ayrı aktif program yolu yoktur |
| `PATCH /api/v1/nutrition-plans/{nutritionPlanId}` | Yukarıdaki düzenlenebilir alanların değişenleri; `clientId`/`dietitianId` değiştirilemez. Aktif etme için PATCH değil mevcut activate işlemi kullanılır | `200` güncel program. Kişisel programı kendi danışanı; atanmış programı yalnız `dietitianId`si eşleşen, aktif/yetkili diyetisyen düzenler. Danışanın atanmış programı/hedefleri değiştirme girişimi `403` |
| `POST /api/v1/nutrition-plans/{nutritionPlanId}/activate` | Gövdesiz; aynı düzenleme yetkisi | `200` aktif program. Başka aktif program varsa `409 active_nutrition_plan_conflict`; hedef zaten tek aktif programsa `200`. Tarihleri farklı olsa da iki active program kabul edilmez |

NutritionPlan yanıtındaki kesin alanlar: `id`, `clientId`, nullable `dietitianId`, `title`, `status`, `startDate`, nullable `endDate`, `dailyCaloriesTargetKcal`, `dailyWaterTargetMl`, `createdAt`, `items`. Item için `id`, `nutritionPlanId`, `mealType`, `description`, `sortOrder` ve nullable `recipeId` ortak alanlardır; kimlikler sunucudan gelir. Tarih/ölçüm tipleri ve pozitiflik kuralları `05`e uyar; `endDate < startDate` `422`dir.

**AÇIK ŞEMA:** `dayOfWeek` numaraları/null anlamı, `recommendedQuantity` biçimi, öğün alternatiflerinin gruplaması, sürüm kimliği/snapshot ve `items` zorunluluğu/nihai gövdesi açık olduğundan bu tablo tam plan DTO onayı değildir. PATCH geçmiş sürümü yeniden yazamaz; sürüm yapısı onaylanmadan geçmiş tutmadan plan güncellemesi tamamlandı sayılmaz. Makro hedefleri veya programsız kişisel hedefler için yeni alan/endpoint türetilmez.

Aktivasyon başka programı sessizce arşivlemez ve kişisel/atanmış sahipliğini değiştirmez. Açıkça onaylanacak program değiştirme/arşivleme akışında eski durum değişimi ve yeni aktivasyon atomik olmalıdır; bunun request'i ve durum geçişleri **AÇIK**tır. İlişkinin sona ermesi eski `dietitianId`yi null yapmaz; programın devam/arşiv davranışı ayrıca kararlaştırılır. Danışan gerçek tüketimini kaydetmek için programdan izin almak zorunda değildir.

## Recipe, ClientTask ve DataSharingPermission yolları

Yeni yollar aynı kanonik kökten türetilir. Aşağıda **AÇIK ŞEMA** bulunan satırların bilinen alanları gösterilir; eksik bileşen/durum/kategori değerleri yerine örnekten gerçekmiş gibi veri uydurulmaz.

| Method + route | Request | Response / yetki ve bağımlılık |
|---|---|---|
| `GET /api/v1/recipes` | Pagination | `200 { items, totalCount }`; en az kendi tarifleri. Ortak/başkasına ait tarif görünürlük politikası **AÇIK**tır; varsayılan herkese açık sayılmaz |
| `GET /api/v1/recipes/{recipeId}` | Gövdesiz | `200` erişilebilir Recipe; kesin metadata `id`, `userId`, `name`, `createdAt`. Bileşen yanıtı AÇIK ŞEMA |
| `POST /api/v1/recipes` | Kesinleşen alan `name`; bileşen/miktar/porsiyon gövdesi AÇIK ŞEMA. `userId` auth'tan | Tam şema onayından sonra `201` Recipe. Yalnız name alanıyla tamamlanmış tarif oluşturulduğu varsayılmaz |
| `PATCH /api/v1/recipes/{recipeId}` | Kendi tarifinde `name` ve onaylanacak bileşen alanları | `200` Recipe; bileşen/değişiklik geçmişi AÇIK ŞEMA. Önceki MealLogItem ve plan geçmişi yeniden hesaplanıp değiştirilmez |
| `GET /api/v1/client-tasks` | Pagination; diyetisyen için izinli `clientId`, danışan için kendi kapsamı | `200 { items, totalCount }`; ClientTask alanları `05`teki gibi. Diyetisyen yalnız atayan tarafsa ve güncel ilişki/kategori izni varsa erişir |
| `GET /api/v1/client-tasks/{clientTaskId}` | Gövdesiz | `200` kendi danışan görevi veya yetkili atayan diyetisyenin görevi |
| `POST /api/v1/client-tasks` | Diyetisyenden `clientId`, `description`; atayan `dietitianId` auth'tan | `201` ClientTask; ilk status değeri, son tarih ve hatırlatma AÇIK ŞEMA. Bu kararlar onaylanmadan eksik görev oluşturma DTO'su uygulanmaz |
| `PATCH /api/v1/client-tasks/{clientTaskId}` | Atayan diyetisyenin açıklama düzeltmesi; status/son tarih/hatırlatma değişiklikleri AÇIK ŞEMA | `200` güncel ClientTask. Danışanın hangi durum geçişini yapabileceği açık olduğundan keyfî status veya atayan/hedef kimlik değişikliği kabul edilmez |
| `GET /api/v1/data-sharing-permissions` | Danışanın kendi kapsamı; opsiyonel `relationshipId`, pagination | `200 { items, totalCount }`; DataSharingPermission alanları `05`teki gibi. Başkasının ilişkisi okunamaz |
| `GET /api/v1/data-sharing-permissions/{dataSharingPermissionId}` | Gövdesiz | `200` danışanın kendi ilişki izni |
| `POST /api/v1/data-sharing-permissions` | `relationshipId`, `category`, `isGranted`, nullable `consentRecordId` | `201` DataSharingPermission; yalnız ilişkinin danışanı yönetir. Aynı ilişki/kategori ikinci kaydı `409`; kategori kodları AÇIK ŞEMA |
| `PATCH /api/v1/data-sharing-permissions/{dataSharingPermissionId}` | `isGranted`, nullable `consentRecordId`; ilişki/kategori değiştirilemez | `200` güncel izin; geri çekme `isGranted: false` ile yapılır, geçmiş silinmez. Diyetisyen/Admin danışan adına izni açamaz |

ClientTask yanıtı: `id`, `clientId`, `dietitianId`, `description`, `status`, `createdAt`; açık son tarih/hatırlatma alanları henüz buna eklenmez. DataSharingPermission yanıtı: `id`, `relationshipId`, `category`, `isGranted`, `consentRecordId`, `createdAt`, `updatedAt`. `id`/zamanlar sunucudan gelir. Recipe/ClientTask silme ve yorum moderasyon kuralları açık olduğundan sırf CRUD tamamlama amacıyla ek DELETE yolları oluşturulmaz.

İzin verme isteğinde ilişki danışana ait olmalı; sağlık verisi erişimi her durumda active ilişkiye bağlıdır. Pending/ended ilişkide izin düzenlemenin ayrıntısı **AÇIK**tır; izni önceden kaydetmek veri erişimi vermez. Tahlil kategorisini açarken ilgili danışana ait, kapsamı uygun ve geri çekilmemiş açık onay bağlantısı yoksa `422 consent_required`; izin geri çekme için yeni onay aranmaz. Kategori listesi onaylanmadan `lab`, `all` gibi varsayılan kodlar uydurulmaz; iznin satır bazında varlığı tek başına erişim izni değildir.

### ConsentRecord — açık onay kaydı ve geri çekme

| Method + route | Request | Response / sınır |
|---|---|---|
| `GET /api/v1/consent-records` | Giriş yapanın kendi User kapsamı; pagination | `200 { items, totalCount }`; ConsentRecord'un `05`teki alanları. Başka kullanıcının onay geçmişi açılmaz |
| `POST /api/v1/consent-records` | `consentType`, `granted`, `policyVersion`; `userId` auth'tan | `201` ConsentRecord; `id`, `recordedAt` sunucudan, başlangıç `withdrawnAt: null`. Geçerli tür/politika/sunulan metin eşlemesi AÇIK ŞEMA; istemcinin keyfî politika sürümü onay kanıtı sayılmaz |
| `POST /api/v1/consent-records/{consentRecordId}/withdraw` | Gövdesiz; yalnız rıza sahibi | `200` güncel ConsentRecord; geri çekme zamanı sunucudan. Tekrar geri çekme aynı kaydı değiştirmeden döndürür; eski kabul zamanı/politikası korunur. Bağlı paylaşımlar yeni erişim vermez |

Rıza oluşturmak tek başına paylaşım izni oluşturmaz; DataSharingPermission ilgili onaya ayrıca bağlanır. Yalnız doğru endpoint çağrıldı diye kullanıcıya gösterilmemiş metne açık onay verilmiş sayılmaz. Kanıt/tür/kapsam tasarımı `05/11` ile tamamlanır; otomatik rıza veya genel tek checkbox varsayılmaz.

## Açık şemaya bağlı yorum, sürüm ve OCR işlemleri

Bu bölümdeki yollar **önerilen HTTP karşılıklarıdır**; `04/05`te açık olan kanonik alt kayıt adları ve tam DTO'lar onaylanmadan uygulama/mock üretimine dayanak değildir.

| Method + route | İstek/yanıtın bilinen kısmı | Açık karar ve güvence |
|---|---|---|
| `GET /api/v1/meal-logs/{mealLogId}/comments` | Pagination; `200 { items, totalCount }`. Yorum alan önerisi `05`teki `id`, `mealLogId`, `authorUserId`, `text`, `createdAt`, nullable `parentCommentId` | Danışan kendi öğünü; diyetisyen aktif ilişki ve öğün/yorum için uygun kategori izniyle. Kanonik yorum modeli/yanıtının nihai onayı beklenir |
| `POST /api/v1/meal-logs/{mealLogId}/comments` | Önerilen gövde `text`, nullable `parentCommentId`; yazar auth'tan. Onay sonrası `201` yorum | Cevap için aynı POST önerilir; ayrı REST yolu varsayılmaz, kalıcı yorum/cevap modeli `04/05` onayına bağlıdır. Başka öğünün ebeveyni `422/404`; döngü kurulamaz. Cevap derinliği ve moderasyon açık; düzenleme/silme yolları henüz eklenmez |
| `GET /api/v1/nutrition-plans/{nutritionPlanId}/versions` | Programla aynı okuma yetkisi; `200` sürüm listesi hedeflenir | Sürüm kimliği/tipi, payload ve pagination ayrıntıları açık; hayalî versionId veya güncel programı geçmişmiş gibi dönen mock oluşturulmaz. Eski sürümü değiştiren endpoint eklenmez |
| `POST /api/v1/lab-reports/ocr` | Önerilen yükleme: multipart `document` dosyası (PDF/fotoğraf); danışanın kendi kapsamı | Kabul edilen dosya tür/limitleri, senkron/asenkron iş, OCR taslak/id/durum/response yapısı ve onay kaydı AÇIK ŞEMA. Bunlar seçilmeden `200/202`, jobId veya yeni durum enumu kesinleştirilmez |

OCR yalnız taslak çıkarır; tamamlanmış LabReport veya klinik değerlendirme üretmez. Kullanıcı test/değer/birim/tarih/referansı kontrol edip düzeltir ve açıkça onayladıktan sonra mevcut `POST /lab-reports` gövdesiyle doğrulanmış kayıt oluşturulur. OCR işi tamamlandı diye otomatik POST/insight tetiklenmez. Kullanıcı onayının sunucuda kanıtlanacağı tasarım açık olduğundan yeni `isConfirmed`/`ocrJobId` alanı bu belgede uydurulmaz. Dosya yükleme hataları `413/415`, yetki hataları ortak kurallara uyar.

### LabInsight işlemleri

`POST /lab-reports/{labReportId}/insights` yalnız kaydın danışanı veya aktif ilişki + ilgili kategori + tahlil açık onayı olan diyetisyen içindir; istek gövdesizdir. Başarı hedefi `201` LabInsight; GET aynı kaynağın yetkili analizlerini ortak liste zarfıyla döndürür. Kesin alanlar `id`, `labReportId`, `createdAt`, `summary`, `method`, nullable `modelVersion`; zorunlu `limitations` biçimi ve method değerleri `05`te AÇIK olduğundan tam yanıt henüz onaylı değildir. Asenkron LabInsight işi/status modeli varsayılmaz.

Geçerli birim/referans yoksa açıklama `unknown` ve sınırlılıkları yansıtır; eksik referans tamamlanmış gibi tahmin edilmez. Metin tanı/tedavi önermez; doğrulanabilir ML opsiyoneldir. Tahlil paylaşım onayı yokluğu diyetisyeni engeller; danışanın kendi manuel kaydını okumasını engellemez. AI sağlayıcısına aktarım için ayrı gereken izinler `11`e göre ayrıca kontrol edilir.

## Kimlik, profil ve ilişki işlemlerinin sınırları

- `POST /auth/register` için aşağıdaki danışan kayıt şeması onaylıdır. Public kayıt Admin/Diyetisyen rolü veya doğrulanmış uzman yetkisi vermez; diyetisyen başvurusunu Admin doğrular. Çoklu rol ve diğer profil sözleşmeleri ayrıca açıktır.
- `POST /auth/login`: aşağıdaki JWT giriş şeması onaylıdır. E-posta doğrulanmadan veya Admin MFA akışı hazır olmadan token verilmez. Refresh/logout mevcut taslak yollarını korur; bu işlemler, cookie stratejisi ve MFA challenge gövdeleri henüz uygulanmaz.
- Kendi hesap okuması, kullanıcının bu görevde açıkça istediği `GET /auth/me` yolunu ve aşağıdaki düz beş alanlı yanıtı kullanır. Eski uygulanmamış `GET /me` taslağı yerine bu yol geçerlidir; GET alias/redirect eklenmez. `PATCH /me` ise ayrı açık profil düzenleme taslağıdır: `displayName`, danışanın nullable `birthDate`/`heightCm` alanları hedeflenir; yanıt/rol ayrıntıları kapanmadan uygulanmaz. `role`, `isVerified`, `isEmailVerified` veya MFA/secret alanı bu yoldan yükseltilemez. `licenseInfo` tipi açıkken keyfî JSON kabul edilmez.
- `GET /dietitians` araması `query` ve pagination kullanabilir; uygun/doğrulanmış uzman profilleri için `id`, `displayName`, `isVerified` gibi paylaşılabilir alanlar sunulur; sağlık kaydı, özel belge veya hesap sırrı dönmez.
- `POST /dietitian-relationships`: danışandan hedef `dietitianId`; `clientId` auth'tan. `201` kendi pending DietitianClientRelationship kaydı; GET aynı User'ın taraf olduğu ilişkileri `05` alanlarıyla listeler. Davet kodu biçimi/ömrü/istek alanı açıktır; ayrı kod modeli veya tek taraflı otomatik onay yolu üretilmez.
- Mevcut accept/reject/end işlemleri gövdesizdir, `200` güncel ilişki döner. Kabul/red ilgili diyetisyene, sonlandırma ilişkinin taraflarına açıktır; kabulde karşılıklı onay ve tek aktif sınırı atomik kontrol edilir. Başka aktif ilişki `409 active_relationship_conflict`, geçersiz durum `409 conflict`; bitmiş ilişkinin tekrar bitirilmesi mevcut sonucu döndürebilir. Geçmiş silinmez; her geçişin tam idempotency politikası **AÇIK**tır.

### Onaylı kayıt ve e-posta doğrulama sözleşmesi — 27.10.2026

Bu üç işlem oturumsuzdur; doğrulama giriş/oturum veya sağlık verisi erişimi sağlamaz. JSON `application/json`, yanıtlar `Cache-Control: no-store` kullanır. Entity'ler doğrudan yanıt olarak serileştirilmez.

| Method + route | Request | Response / hata |
|---|---|---|
| `POST /api/v1/auth/register` | `RegisterUserRequest`: zorunlu `email: string`, `password: string`, `displayName: string`; isteğe bağlı `role: UserRole?` (gönderilmez/null ise `client`, yalnız `client` kabul edilir) | `201` `RegisterUserResponse`: yalnız `{ "id": "<User UUID>" }`. User + ClientProfile atomik oluşturulur; `isEmailVerified = false`. Bozuk/eksik/boş zorunlu alan, geçersiz e-posta veya rol, tanımsız/salt okunur alan `400 invalid_request`; parola politikası `422 validation_failed`; normalleştirilmiş mükerrer/yarışan e-posta `409 conflict`; beklenmeyen hata `500 internal_error` |
| `POST /api/v1/auth/verify-email` | `VerifyEmailRequest`: `{ "token": "<e-postadaki token>" }`; alan zorunlu string | Başarı `204`, boş gövde. Null/boş/yanlış biçimli, bulunmayan, süresi dolmuş, yeniden gönderimle geçersiz kılınmış veya kullanılmış token aynı `422 validation_failed` olur. Eksik alan, bozuk JSON, yanlış JSON tipi veya ek alan `400 invalid_request` |
| `POST /api/v1/auth/resend-verification` | `ResendVerificationRequest`: `{ "email": "synthetic@example.test" }`; zorunlu geçerli e-posta string | `202`, boş gövde. Hesap yoksa, zaten doğrulanmışsa veya hesap gönderim aralığındaysa da aynı sonuç. Geçersiz/eksik girdi veya ek alan `400 invalid_request`; IP sınırı `429 rate_limited` |

- Kayıt `displayName` girdisini düz alır; iç içe `profile`/`clientProfile`, `userId`, `clientId`, `passwordHash` veya doğrulama alanı kabul etmez. ClientProfile'ın kimliği User kimliğinden ayrıdır; doğum tarihi/boy null kalır. Yanıt e-posta, hash, doğrulama tokenı, access/refresh token veya cookie içermez; otomatik giriş olmaz. `GET /auth/me` yetkili hesap özeti içindir, kayıt kaynağı detay yolu sayılmaz; kayıt `Location` başlığı üretmez.
- E-posta kırpılır ve Identity normalizer ile normalleştirilir; harf duyarsız unique indeks yarış durumunu da korur. İlk sürüm parola politikası **8–128 Unicode kod noktası**dır; boşluk/Unicode desteklenir, karakter türü zorunluluğu yoktur. Parola kırpılmaz veya normalize edilmez; politika `Auth:RegistrationPasswordPolicy` ile merkezi yapılandırılır, hash Identity PasswordHasher ile saklanır.
- Token kriptografik 256 bit rastgele, 43 karakter Base64URL'dir; **30 dakika**, tek kullanımlık ve yalnız e-posta doğrulama amaçlıdır. DB'de yalnız SHA-256 hash'i ve `05`teki UTC metadata tutulur. Başarı atomik olarak doğrular ve tokenı tüketir; sürenin tam bittiği an geçersizdir. Yeni gönderim önceki tokenı iptal eder. Ham token istek/yanıt loglarına veya hata detaylarına konmaz.
- Başarılı kayıt DB commit'inden sonra doğrulama gönderimini kuyruğa alır. Yeniden gönderim HTTP yolu da hesap sorgulamadan aynı kuyruğa yazar; SMTP süresi hesap varlığını açığa çıkarmaz. SMTP hatası/kuyruk doluluğu, başarılı kaydın `201` veya geçerli yeniden gönderimin `202` sonucunu değiştirmez; hesap doğrulanmamış kalır. Bu yanıtlar SMTP teslim makbuzu değildir.
- Varsayılan yeniden gönderim aralığı **hesap başına 60 saniye**dir; DB'de atomik kontrol edilir. Ayrıca doğrudan bağlantı IP'si başına **dakikada 5 istek** limiti hesap varlığından bağımsız uygulanır; aşım ortak hata zarfıyla `429`dur. Değerler `Auth:EmailVerification` üzerinden yapılandırılır. IP sayacı mevcut API sürecindedir; çok örnekli dağıtım/proxy için ortak limit ve güvenilir proxy yapılandırması ayrıca değerlendirilmelidir.
- Verify/resend gövdeleri en fazla 4096 byte'tır (`413 payload_too_large`); desteklenmeyen içerik `415 unsupported_media_type`, beklenmeyen sunucu hatası `500 internal_error` ortak zarfı kullanır. Sınırlar token/e-posta değerini yanıta yansıtmaz.
- SMTP ayarları environment/User Secrets'tan alınır; yerel geliştirmede yalnız loopback Mailpit kullanılır. E-posta metni tokenı ve 30 dakikalık süreyi içerir. İstemcilerin bağlantı/deep-link/UI entegrasyonu bu backend göreviyle uygulanmış sayılmaz. Kuyruk sınırlı ve bellektedir; yeniden başlatma/teslim hatasında yeniden gönderim gerekir. Kalıcı teslim/üretim e-posta sağlayıcısı kararı açıktır.

### Onaylı giriş ve JWT sözleşmesi — 27.10.2026

Kullanıcı bu görevde JWT + 15 dakika kararını, ayrıca aşağıdaki istek/yanıt ve ortak `401` davranışını açıkça onaylamıştır. `13`teki opaque token/alternatif yanıt önerileri bu giriş sözleşmesi yerine kullanılmaz.

| İşlem | Request | Başarı / hata |
|---|---|---|
| `POST /api/v1/auth/login` | `LoginUserRequest`: `{ "email": "synthetic@example.test", "password": "<parola>" }`. İki alan zorunlu string; rol/kimlik veya başka alan alınmaz | `200` `LoginUserResponse`: `{ "accessToken": "<JWT>", "tokenType": "Bearer", "expiresAt": "<UTC ISO 8601>" }`. Bulunmayan hesap, yanlış parola, doğrulanmamış e-posta ve Admin için aynı genel `401 unauthenticated`. Şekil/eksik/boş girdi, geçersiz e-posta veya ek alan `400 invalid_request`; hız sınırı `429 rate_limited` |

- Login mevcut Identity normalizer ile e-postayı kırpar/normalleştirir ve Identity PasswordHasher ile parolayı doğrular. Parola aynen korunur; girişte yeni kayıt karmaşıklığı/minimumu yeniden uygulanmaz. Hesap bulunmadığında da Identity parola hash doğrulaması yapılır; sahte User/oturum oluşturulmaz. Başarısızlık yanıtları hesap/doğrulama/MFA ayrımı veya gizli veri içermez.
- Başarı yalnız `client`/`dietitian` ve `isEmailVerified = true` hesaplar içindir. Admin'e token verilmez; middleware imzası geçerli olsa dahi `admin` rolünü kabul etmez. Diyetisyen rolü tek başına uzman doğrulaması veya sağlık kaydı yetkisi değildir; ilgili kaynaklarda `05/11` kontrolleri ayrıca gerekir.
- JWT **15 dakika** geçerlidir. `sub: string` mevcut User UUID'si, `role: string` kanonik roldür; ayrıca `iss`, `aud`, `iat`, `nbf`, `exp` standart claim'leri vardır. E-posta, ad, profil/sağlık verisi, hash veya secret claim'i yoktur. `expiresAt`, tokenın imzalı `exp` değeriyle aynı UTC anıdır; istemci claim çözümleyerek yetki vermez.
- Token `HS256` ile imzalanır, türü `at+jwt`dir. İmzalama anahtarı (Base64, en az 32 kriptografik rastgele byte), issuer ve audience environment/User Secrets'tan alınır; eksik/hatalı yapılandırmada API başlamaz. Token/API yanıtı loglanmaz. Access token DB'ye yazılmaz.
- ASP.NET Core JWT authentication/authorization middleware imza, izinli algoritma/tür, tam issuer/audience, zorunlu expiry ve zaman aralığını doğrular. `ClockSkew = 0`; varsayılan ek beş dakika tanınmaz. Yetkili kaynaklar `[Authorize]`/uygun kaynak politikalarını uygular. Kimlik `sub`dan alınır; User UUID'si ClientProfile UUID'si sayılmaz.
- Yetki isteyen bir kaynağa eksik/geçersiz/süresi dolmuş token `401 unauthenticated`, geçerli kimlikle eksik rol/kaynak yetkisi `403 forbidden` olur. `WWW-Authenticate: Bearer` iç doğrulama ayrıntısı taşımaz; ortak hata zarfı korunur. Login ve auth hata yanıtları `Cache-Control: no-store` kullanır. Kimlik/rol deneme yolları yalnız test host'undadır; yeni genel API kaynağı eklenmez.
- Login varsayılan limiti doğrudan bağlantı IP'si başına **dakikada 10 istek**tir (`Auth:Login:RequestsPerMinute`); hesap varlığından bağımsız ve API süreci içinde uygulanır. Çok örnekli ortak limit/proxy ve hesap bazlı saldırı kontrolleri ayrıca değerlendirilir; kalıcı hesap kilidi bu görevde eklenmez. Gövde sınırı 4096 byte: `413 payload_too_large`; yanlış içerik türü `415 unsupported_media_type`; beklenmeyen hata `500 internal_error`.
- Refresh token/cookie/logout, genel anlık oturum/rol/parola değişikliği iptali, MFA ve parola sıfırlama bu dilimde yoktur. Mevcut JWT, geçerli imza ve süresi boyunca kullanılabilir; kendi hesap okumasındaki aşağıdaki DB kontrolü tüm API için oturum iptali sayılmaz. Yeni entity veya migration varsayılmaz.

### Onaylı kendi hesap endpointi — 27.10.2026

| İşlem | Request | Response / hata |
|---|---|---|
| `GET /api/v1/auth/me` | Geçerli `Authorization: Bearer <access-token>`. Gövde/query parametresi yok; `userId` alınmaz | `200 CurrentUserResponse`: yalnız `id: uuid`, `displayName: string?`, `email: string`, `role: UserRole`, `isEmailVerified: boolean`. Anahtarların beşi de daima vardır. Desteklenmeyen query/gövde `400 invalid_request`; eksik/geçersiz/süresi dolmuş token veya geçersiz mevcut hesap `401 unauthenticated`; beklenmeyen sunucu/DB hatası `500 internal_error` |

- Endpoint yalnız mevcut JWT bearer authentication/authorization ile erişilir. Kimlik, middleware'in doğruladığı tek `sub` claim'indeki User UUID'sidir; istemci kimliği, özel başlık, profil UUID'si veya URL'deki başka ID ile seçilmez.
- User ve varsa kendi ClientProfile'ı yalnız gerekli alanlarla salt okunur sorgulanır. `displayName` profil yoksa açık `null` olur; `client`/`dietitian` için aynı yanıt kullanılır. E-posta ve ad tokena eklenmez, DB'den güncel alınır. User/ClientProfile entity'si, hash, token, güvenlik metadata'sı, `createdAt`/`updatedAt`, sağlık verisi veya iç içe profil dönmez.
- Token süresi bitmemiş olsa dahi User DB'de yoksa, e-posta doğrulaması kalkmışsa veya güncel rol tokenın izinli rolüyle eşleşmiyorsa aynı genel `401` ve `WWW-Authenticate: Bearer` döner. Başka kullanıcı varlığı/durumu hata metnine eklenmez. Mevcut Admin MFA engeli değişmez.
- Yanıt `Cache-Control: no-store` kullanır. Bu işlem kullanıcı, profil, parola veya token alanına yazmaz; yeni entity/migration, yetkisiz rol geçişi veya genel token iptali eklemez. Kayıt ve giriş yanıtları değişmez. Profil düzenleme/uzman profili şemaları açık kalır.

### Henüz uygulanmamış kimlik işlemleri

| İşlem | Request | Response / sınır |
|---|---|---|
| `POST /api/v1/auth/password-reset-requests` | `email: string` | `202`, gövdesiz; hesabın varlığını açıklamayan aynı sonuç. Bildirim servisi, limit/süre ayrıntıları **AÇIK**tır |
| `POST /api/v1/auth/reset-password` | `token: string`, `password: string` | `204`; geçersiz/süresi dolmuş token veya parola kuralı `422`. Sıfırlama tokenı/akışı ve mevcut oturumların iptal ayrıntısı **AÇIK**tır; kayıt parola politikası yukarıda onaylıdır |

Bu token/password alanları yalnız HTTP kimlik girdileridir; User modeline düz metin secret alanı eklemez. Admin MFA doğrulama/kurulum/kurtarma ve diyetisyen başvuru/doğrulama endpointlerinin gövdeleri ilgili güvenlik/başvuru şeması tamamlanınca tanımlanır; sağlık verisi yetkisiyle karıştırılmaz.

## Örnek 1 — manuel öğün oluşturma
```http
POST /api/v1/meal-logs
Authorization: Bearer <access-token>
Content-Type: application/json
```
```json
{
  "mealType": "lunch",
  "consumedAt": "2026-10-15T12:30:00Z",
  "note": "Öğle öğünü",
  "source": "manual",
  "items": [
    {
      "foodItemId": null,
      "displayName": "Mercimek çorbası",
      "quantityGrams": 250,
      "caloriesKcal": 180,
      "proteinGrams": 9,
      "carbsGrams": 25,
      "fatGrams": 5,
      "isEstimated": true
    }
  ]
}
```
Başarılı yanıt `201 Created`: `{ "id": "<uuid>", "clientId": "<uuid>", "mealType": "lunch", "consumedAt": "2026-10-15T12:30:00Z", "source": "manual", "items": [ ... ] }` (kısaltılmış gösterim; tam alanlar günlük kayıt tablosunda). `clientId` auth öznesinden türetilir, istemciden gelen başka kullanıcı ID'sine güvenilmez. Mevcut örnek korunur; tarif kullanılıyorsa opsiyonel `recipeId` aynı item'a eklenebilir.

## Örnek 2 — su ekleme
```json
{ "amountMl": 250, "consumedAt": "2026-10-15T15:00:00Z", "source": "manual" }
```
`POST /api/v1/water-logs`; negatif/sıfır miktar reddedilir. Dönen yanıt `id`, `clientId`, `amountMl`, `consumedAt`, `source` içerir.

## Örnek 3 — görsel analiz / ayrık onay
- `POST /api/v1/food-analyses`: `multipart/form-data` içindeki **`image`** dosyası; `202 Accepted` → `{ "id": "<uuid>", "status": "pending" }`.
- `GET /api/v1/food-analyses/{analysisId}` → `{ "id": "<uuid>", "status": "completed", "modelVersion": "...", "suggestions": [ { "displayName": "...", "quantityGrams": null, "caloriesKcal": null, "proteinGrams": null, "carbsGrams": null, "fatGrams": null, "confidence": 0.72 } ], "limitations": ["Porsiyon doğrulanmadı"] }`.
- Tahminler kaloriye dair kesinlik iddia etmez; kullanıcı düzeltip ayrı `POST /api/v1/meal-logs` gönderir (`source: "ai_assisted"`, opsiyonel `foodAnalysisId`).

Dosya tür/boyut/güvenlik ve aktarım izinleri sunucuda kontrol edilir; limit/sağlayıcı ayrıntıları açık kalır. GET yalnız analizin danışanına açıktır; `status` mevcut `pending/processing/completed/failed` değerlerini kullanır. `05`teki `clientId`, `createdAt`, nullable `completedAt` ve güvenli `errorCode` aynı ad/tiplerle yanıt metadata'sı olabilir. Başarısız analiz öğün oluşturmaz; manuel giriş devam eder.

Öneride `confidence` decimal 0–1; porsiyon gram, enerji kcal, makrolar gram ve bilinmiyorsa null'dır. Mevcut HTTP yerleşimi korunur: `limitations` analiz kökünde `list<string>`dir; her önerinin altına sessizce taşınmaz. `05`te saklama/üretim ayrımı ve `10`daki iç içelik anlatımı ayrıca uyarlanmalıdır. Analiz başlatmak, sonucu görüntülemek veya sunucuda completed olması kullanıcı onayı değildir; ek bir otomatik kayıt/confirm endpointi üretilmez.

## Örnek 4 — laboratuvar verisi
```json
{
  "collectedAt": "2026-10-15T08:00:00Z",
  "labName": "Örnek laboratuvar",
  "results": [
    { "testName": "Örnek analit", "testCode": null, "value": 12.3, "unit": "unit", "referenceLow": null, "referenceHigh": null }
  ]
}
```
Sunucu `flag` hesaplar; referanslar yoksa `unknown`. Birimler normalizasyonu **kontrol edilmeden** karşılaştırma yapılmaz. `LabInsight` tıbbi tanı içeremez.

## Eşzamanlı çalışma güvenlik listesi

- Başka geliştirici API'yi uygulamadan istemci kendi endpointini üretmez; `API_CONTRACT`'a uyar ve mock'ları aynı şemayla hazırlar.
- Endpoint/alan değişikliği → 04 + 05 + 06 + OpenAPI/istemci tipleri için onaylı tek değişiklik.
- API `contract test`, rol/ilişki yetki testi ve karşılıklı parse testleri yapılmadan entegrasyon tamamlandı sayılmaz.
- Tek aktif ilişki/program yarışları, kişisel programa diyetisyen bağlanmadan erişim, atanmış programı danışanın değiştirememesi, kategori/tahlil onayı geri çekme ve başka danışana ait alt kayıt referansları test edilmelidir.
- Örnek senaryolar: geçersiz JSON `400`; negatif su veya boş ölçüm `422`; ikinci aktif ilişki/program `409`; başka danışanın özel kaydı tutarlı `403/404`; tahlil açık onayı olmadan diyetisyenin analiz isteği reddedilir; AI/OCR sonucu onaysız kalıcı sağlık kaydına dönüşmez. Bunlar test gereksinimleridir, çalıştırılmış test sonucu değildir.

## Kalan açık kararlar ve belge uyumu

- `04/05`te açık olan sürüm/alternatif/yorum ad ve veri yapıları, tarif bileşenleri/görünürlük/geçmişi, görev durum/geçiş/son tarih/hatırlatma ve kategori kodları tamamlanmalıdır. İlgili yolların açık request/response parçaları onaylanmadan şema kapanmış sayılmaz.
- Program arşivleme/değiştirme ve ilişkinin bitişindeki program davranışı; programsız kişisel hedefler, makro hedef alanları, program uyum hesabı ve gün/saat dilimi politikası açıktır. Tarihçe korumadan eski programı güncellemek onaylı çözüm değildir.
- OCR dosya kabul limitleri, taslak/iş kimliği ve onay kanıtı; LabInsight method/limitations biçimi ve değişen tahlilde eski analizlerin gösterimi açıktır. FoodAnalysis HTTP limitations kökte korunmuştur; `05/10` açıklamaları bu yerleşimle eşitlenmelidir.
- Cihaz sync request/response, provider/durum kodları, adım/nabız/aktif enerji modelleri, kararlı kimliği olmayan kaynak, manuel/cihaz örtüşmesi, yeniden aktarım ve kullanıcı düzeltmesinin önceliği açıktır; yeni genel ölçüm veya AI job modeli türetilmez.
- Refresh/logout/iptal ve cookie stratejisi, MFA challenge/kurulum/kurtarma gövdeleri, profil düzenleme/uzman profili yanıtı, şifre sıfırlama, diyetisyen başvuru/doğrulama ve davet kodu ayrıntıları açıktır. Kayıt/parola politikası, e-posta doğrulama/yeniden gönderim, 15 dakikalık JWT giriş ve `GET /auth/me` hesap özeti sözleşmeleri onaylıdır; Admin MFA ve karşılıklı ilişki onayı gereksinimleri korunur.
- İlk sürüm yorum/cevap bildirimleri ve diyetisyen PDF raporları onaylı kapsamdır; bildirim/rapor DTO, teslim/dosya yetkilendirmesi ve moderasyon ayrıntıları açık olduğundan bu görevde tahminî yollar açılmaz. İzin dışı veri export edilmez. KVKK, silme, saklama ve audit için `11` kapısı korunur.
- Sayısal hassasiyet/yuvarlama, metin/dosya/pagination limitleri, tekrar denemelerde idempotency ve güvenli silme ayrıntıları ortak onay bekler. Mevcut enumlar ve model adları değişmez.

Kayıt/e-posta doğrulama/JWT giriş/kendi hesap özeti ayrıntıları `04/05/11/12` ile eşgüdümlüdür. Diğer açık şema parçaları iki geliştiricinin onayıyla `04/05/06` ve OpenAPI/istemci tiplerinde birlikte tamamlanmalıdır; bu görev mobil/web entegrasyonu içermez.
