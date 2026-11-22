# 06 — HTTP, DTO, yetkilendirme ve hata sözleşmesi

İnceleme tabanı: 22.11.2026 / `4f160b3`. “Uygulanan” yollar kaynakta mevcuttur; bu görevde API/DB veya test çalıştırılmadı. Onaylı ürün kararıyla uyuşmayan uygulama kendi kendine yeni sözleşme sayılmaz; açık farklar [12](12_TEAM_PLAN_AND_DECISIONS.md)'dedir. Kalıcı şema [05](05_DATA_DICTIONARY.md), izin/mahremiyet ilkeleri [11](11_SECURITY_AND_RELEASE.md)'dedir.

## Ortak biçim ve kimlik

API kökü `/api/v1`, JSON camelCase, UUID string, decimal JSON number, enum [04](04_NAMING_CONVENTIONS.md)'teki string değeridir. Instant açık Z/±HH:mm ISO 8601 olarak girilir; UTC ve PostgreSQL mikro-saniye hassasiyetine normalize edilir. Date YYYY-MM-DD'dir. Nullable yanıt alanları, özel auth token istisnası dışında açık null kalır.

Sayfalı yanıt `{items,totalCount}` biçimindedir. page/pageSize listelerde zorunlu, page≥1 ve int32 offset sınırı geçerlidir. Öğün/su/ölçüm/görev/sağlık listelerinde pageSize≤100; eski uzman/ilişki/izin/program/Admin listelerinde yalnız pozitiflik ve offset sınırı vardır. Bütün uçlara sessizce ortak üst limit eklenmez.

Anonim kayıt/doğrulama/reset, mobil bearer, W2 web cookie ve MFA Admin farklı bağlamlardır. İkisinin kabul edildiği uçlarda bearer+auth cookie birlikte 400'dür; başarısız kimlikten diğerine düşülmez. Kendi öğün/su/ölçüm/hedef yolları JWT + client profil bağlamı; ortak program/ilişki/yorum/görev ve uzman okumaları JWT veya W2 cookie kullanır. Sağlık yolları yalnız **role=client JWT + client bağlamı** kabul eder; ayrıntı [20](20_HEALTH_DATA_SYNC_CONTRACT.md)'dedir.

`X-Profile-Context: client|dietitian` tek değerli olmalıdır; başlık hesap rolünü/uzman doğrulamasını değiştirmez. Web cookie client sağlık bağlamı açmaz. client temel rollü, onaylı DietitianProfile sahibi hesap uzman bağlamında ortak yetkili uçlara erişebilir. Kendi veri kapsamı User sub → ClientProfile üzerinden çözülür; istemci clientId göndererek sahip seçemez.

Cookie yazmaları için same-origin HTTPS, tam yapılandırılmış Origin, antiforgery cookie ve X-CSRF-TOKEN gerekir. Bearer yazmasına CSRF eklenmez. Yalnız belirtilen query/gövde kabul edilir; katı JSON eşlemede ek alan/yanlış tip 400'dür. Eski controller'ların query/tekrar kontrolleriyle yeni katı günlük uçlar birebir aynı değildir; 12'de açık fark olarak izlenir.

## Hata ve yanıt

```json
{"error":{"code":"validation_failed","message":"The request could not be validated."},"requestId":"<request-id>"}
```

| HTTP | Ortak code / anlam |
|---|---|
| 400 | invalid_request: biçim/tip/ek alan veya desteklenmeyen istek |
| 401 | unauthenticated: geçersiz/eksik kimlik; bearer challenge korunur |
| 403 | forbidden: rol/profil/kategori yetkisi yok |
| 404 | not_found: olmayan/yabancı kaynak veya uygun aktif ilişki yok |
| 409 | conflict; özel tek aktif hataları active_relationship_conflict / active_nutrition_plan_conflict |
| 413 / 415 | payload_too_large / unsupported_media_type |
| 422 | validation_failed: semantik değer/kural ihlali |
| 429 / 500 | rate_limited / internal_error |

Sağlık aktarımının özel code'ları [20](20_HEALTH_DATA_SYNC_CONTRACT.md)'dedir. Hatalar kişi/sağlık değeri/toplam/token açıklamaz; altyapı hatası boş veri veya sıfır başarıya çevrilmez. API yanıtları no-store'dur; HTML/302 auth yönlendirmesi yoktur.

## Uygulanan endpoint envanteri

Aşağıdaki method/route çiftleri kaynak controller'lardan doğrulanmıştır; route constraint'leri gösterimde sadeleştirilmiştir. Sağlık aktarımının ayrıntılı HTTP sözleşmesi 20'dedir. Operasyonel health/OpenAPI yolları bu listeye dahil değildir.

| Alan | Method + route |
|---|---|
| Auth | `POST /api/v1/auth/password-reset-requests` |
| Auth | `POST /api/v1/auth/reset-password` |
| Auth | `GET /api/v1/auth/me` |
| Auth | `POST /api/v1/auth/login` |
| Auth | `POST /api/v1/auth/refresh` |
| Auth | `POST /api/v1/auth/logout` |
| Auth | `POST /api/v1/auth/register` |
| Auth | `POST /api/v1/auth/verify-email` |
| Auth | `POST /api/v1/auth/resend-verification` |
| Auth | `POST /api/v1/auth/admin-email-code` |
| Auth | `POST /api/v1/auth/admin-web-session` |
| Auth | `GET /api/v1/auth/csrf` |
| Auth | `POST /api/v1/auth/web-session` |
| Auth | `DELETE /api/v1/auth/web-session` |
| BodyMeasurements | `POST /api/v1/body-measurements` |
| BodyMeasurements | `GET /api/v1/body-measurements` |
| BodyMeasurements | `GET /api/v1/body-measurements/{bodyMeasurementId}` |
| BodyMeasurements | `PATCH /api/v1/body-measurements/{bodyMeasurementId}` |
| BodyMeasurements | `DELETE /api/v1/body-measurements/{bodyMeasurementId}` |
| BodyMeasurements | `GET /api/v1/dietitian/clients/{clientId}/body-measurements` |
| ClientTasks | `GET /api/v1/client-tasks` |
| ClientTasks | `GET /api/v1/client-tasks/{clientTaskId}` |
| ClientTasks | `GET /api/v1/client-tasks/{clientTaskId}/versions` |
| ClientTasks | `POST /api/v1/client-tasks` |
| ClientTasks | `PATCH /api/v1/client-tasks/{clientTaskId}` |
| Dietitians | `GET /api/v1/admin/dietitians` |
| Dietitians | `POST /api/v1/admin/dietitians/{dietitianId}/verify` |
| Dietitians | `POST /api/v1/dietitians/me/application` |
| Dietitians | `POST /api/v1/dietitians/apply` |
| Dietitians | `GET /api/v1/dietitians/me` |
| Dietitians | `GET /api/v1/dietitians` |
| HealthData | `POST /api/v1/wearable-connections` |
| HealthData | `GET /api/v1/wearable-connections` |
| HealthData | `GET /api/v1/wearable-connections/{wearableConnectionId}` |
| HealthData | `PATCH /api/v1/wearable-connections/{wearableConnectionId}` |
| HealthData | `POST /api/v1/wearable-connections/sync` |
| HealthData | `GET /api/v1/wearable-connections/{wearableConnectionId}/records` |
| HealthData | `GET /api/v1/wearable-connections/{wearableConnectionId}/records/{wearableRecordId}` |
| HealthData | `GET /api/v1/health-metric-samples` |
| HealthData | `POST /api/v1/activity-logs` |
| HealthData | `GET /api/v1/activity-logs` |
| HealthData | `GET /api/v1/activity-logs/daily-summary` |
| HealthData | `GET /api/v1/activity-logs/{activityLogId}` |
| HealthData | `PATCH /api/v1/activity-logs/{activityLogId}` |
| HealthData | `DELETE /api/v1/activity-logs/{activityLogId}` |
| MealLogs | `GET /api/v1/dietitian/clients/{clientId}/meal-logs` |
| MealLogs | `GET /api/v1/meal-logs/{mealLogId}/comments` |
| MealLogs | `POST /api/v1/meal-logs/{mealLogId}/comments` |
| MealLogs | `POST /api/v1/meal-logs` |
| MealLogs | `GET /api/v1/meal-logs` |
| MealLogs | `GET /api/v1/meal-logs/{mealLogId}` |
| MealLogs | `PATCH /api/v1/meal-logs/{mealLogId}` |
| MealLogs | `DELETE /api/v1/meal-logs/{mealLogId}` |
| NutritionPlans | `GET /api/v1/nutrition-plans/{nutritionPlanId}/versions/{versionId}/meal-comparison` |
| NutritionPlans | `POST /api/v1/nutrition-plans` |
| NutritionPlans | `GET /api/v1/nutrition-plans` |
| NutritionPlans | `GET /api/v1/nutrition-plans/active` |
| NutritionPlans | `GET /api/v1/nutrition-plans/{nutritionPlanId}` |
| NutritionPlans | `PATCH /api/v1/nutrition-plans/{nutritionPlanId}` |
| NutritionPlans | `POST /api/v1/nutrition-plans/{nutritionPlanId}/activate` |
| NutritionPlans | `POST /api/v1/nutrition-plans/{nutritionPlanId}/archive` |
| NutritionPlans | `GET /api/v1/nutrition-plans/{nutritionPlanId}/versions` |
| NutritionPlans | `GET /api/v1/nutrition-plans/{nutritionPlanId}/versions/{versionId}` |
| PersonalNutritionTargets | `GET /api/v1/personal-nutrition-targets` |
| PersonalNutritionTargets | `PATCH /api/v1/personal-nutrition-targets` |
| Relationships | `GET /api/v1/data-sharing-permissions` |
| Relationships | `GET /api/v1/data-sharing-permissions/{dataSharingPermissionId}` |
| Relationships | `POST /api/v1/data-sharing-permissions` |
| Relationships | `PATCH /api/v1/data-sharing-permissions/{dataSharingPermissionId}` |
| Relationships | `GET /api/v1/dietitian/clients` |
| Relationships | `GET /api/v1/dietitian/clients/{clientId}/dashboard` |
| Relationships | `POST /api/v1/dietitian-relationships` |
| Relationships | `GET /api/v1/dietitian-relationships` |
| Relationships | `POST /api/v1/dietitian-relationships/{relationshipId}/accept` |
| Relationships | `POST /api/v1/dietitian-relationships/{relationshipId}/reject` |
| Relationships | `POST /api/v1/dietitian-relationships/{relationshipId}/end` |
| Relationships | `POST /api/v1/dietitians/me/invitation-code` |
| WaterLogs | `GET /api/v1/dietitian/clients/{clientId}/water-logs` |
| WaterLogs | `GET /api/v1/dietitian/clients/{clientId}/water-logs/daily-total` |
| WaterLogs | `GET /api/v1/dietitian/clients/{clientId}/water-logs/daily-history` |
| WaterLogs | `POST /api/v1/water-logs` |
| WaterLogs | `GET /api/v1/water-logs` |
| WaterLogs | `GET /api/v1/water-logs/daily-total` |
| WaterLogs | `GET /api/v1/water-logs/{waterLogId}` |
| WaterLogs | `PATCH /api/v1/water-logs/{waterLogId}` |
| WaterLogs | `DELETE /api/v1/water-logs/{waterLogId}` |


## Hesap, e-posta ve mobil oturum

| İşlem | Request | Başarı / önemli sınır |
|---|---|---|
| POST auth/register | RegisterUserRequest: email/password/displayName zorunlu; role atlanmış/null/client olabilir | 201 RegisterUserResponse {id}; User+ClientProfile atomik, e-posta doğrulanmamış; oturum yok. Diğer rol 422, mükerrer e-posta 409 |
| POST auth/verify-email | VerifyEmailRequest {token} | Gövdesiz 204; geçersiz/eski/tüketilmiş kod 422 |
| POST auth/resend-verification | ResendVerificationRequest {email} | Gövdesiz genel 202; hesap/teslim durumu açıklanmaz |
| POST auth/login | LoginUserRequest {email,password} | 200 LoginUserResponse: accessToken, tokenType="Bearer", expiresAt, refreshToken, refreshTokenExpiresAt |
| POST auth/refresh | RefreshTokenRequest {refreshToken} | 200 aynı beş alan; başarılı rotasyon |
| POST auth/logout | RefreshTokenRequest {refreshToken} | Gövdesiz 204; yalnız ilgili refresh ailesi iptal |
| GET auth/me | Query/gövde yok | 200 CurrentUserResponse: id, nullable displayName, email, role, isEmailVerified |
| POST auth/password-reset-requests | PasswordResetRequest {email} | Gövdesiz genel 202; uygun olmayan/cooldown/kuyruk dolu hesapta da aynı |
| POST auth/reset-password | ResetPasswordRequest {token,password} | Commit sonrası gövdesiz 204; geçersiz/eski/tüketilmiş kod veya parola kuralı 422 |

Parola 8–128 Unicode kod noktası, boşluk destekli ve karakter türü zorunluluğu olmadan merkezi politikaya tabidir; kırpılmaz/normalize edilmez. E-posta dış boşluğu kırpılır ve normalize edilir. Kayıt adı boş olamaz; uzman adındaki 120 sınırı genel danışan kaydına kendiliğinden uygulanmaz. CurrentUserResponse.displayName mobil danışanda ClientProfile'dan, uzman/web bağlamında DietitianProfile'dan gelir; uygun profil yoksa açık null'dır.

JWT 15 dakika, HS256, at+jwt, issuer/audience ve sıfır clock skew kullanır. sub User UUID'si, role ve canonical nonnegative int64 string credentialsVersion dahil gerekli claim'ler vardır; ad/e-posta/sağlık verisi yoktur. Her doğrulamada güncel hesap/e-posta/rol/sürüm DB'den denetlenir; eksik/tekrarlı/bozuk veya eşleşmeyen sürüm 401, DB hatası 500 ve kapalı erişimdir.

Refresh 256 bit/43 Base64URL'dir; yalnız SHA-256 hash'i tutulur. Her login ayrı aile, varsayılan 30 gün mutlak süre; rotasyon süreyi uzatmaz. Tüketilmiş token replay'i bütün aileyi iptal eder. Hash geçmişi mutlak expiry'ye kadar korunur, 10 dakikalık temizleyici yalnız süresi dolanları siler. LifetimeDays 1–365; refresh/logout ayrı IP sayaçları varsayılan 30/dakikadır. Bunlar JWT'yi sırf logout nedeniyle anında iptal etmez.

E-posta/reset kodları 256 bit/43 Base64URL, 30 dakika ve tek kullanımlıdır; tam bitiş anında geçersizdir. Yeni kod eskiyi bozar. Reset hash amacı `password-reset:v1:` önekiyle ayrılır. Reset doğrulanmış client/dietitian/**Admin** için geçerlidir; rol/e-posta/MFA doğrulaması sağlamaz.

Reset User kilidi altında parola+updatedAt, checked credentialsVersion+1, token tüketimi, bütün web oturumları ve bütün refresh ailelerini tek transaction'da günceller. Login/refresh aynı User kilit sırasını kullanır; eski parolayla yarışan yeni kimlik üretilemez. Hata/taşma rollback, eşzamanlı tüketimde tek başarıdır. Rehash sürüm artırmaz; Admin TOTP/recovery alanları korunur.

Reset iki endpointi query kabul etmez, application/json ve 4096 byte sınırı kullanır; cookie/bearer kimliği hesap seçmez, istemci göndermez. Talep IP 5/dakika, tüketim 10/dakika, hesap cooldown 60 saniye; bounded bellek kuyruğu varsayılan 100'dür. SMTP/bellek kuyruğu genel 202 için teslim garantisi değildir. Başarı bildirimi parola/kod içermez. Expired reset metadata'sı 10 dakikada, eski lastSentAt canlı kod yokken 24 saat sonrası temizlenir.

E-posta yeniden gönderim IP 5/dakika ve hesap 60 saniye, login ortak IP 10/dakika; ayarlar yapılandırılabilir. Yeni backend sürümü credentialsVersion claim'i olmayan JWT'yi reddeder; karma eski/yeni middleware ile reset açılmaz. Geçerli iptal edilmemiş refresh yeni claim'li JWT verebilir.

Web origin yapılandırılmışsa reset e-postası aynı standalone kod yanında `/sifremi-unuttum#token=...` bağlantısını içerir; Host'tan URL üretilmez. Mobil manuel kodu korur. URL temizliği ve istemci davranışı [07](07_MOBILE_SPEC.md)/[08](08_WEB_SPEC.md)'dedir.

## W2 cookie ve Admin MFA

GET auth/csrf → 200 CsrfTokenResponse {requestToken}; anonim veya geçerli cookie bağlamında token üretir. POST auth/web-session LoginUserRequest alır; 200 CurrentUserResponse ve korumalı cookie verir. Normal danışanın uzman profili yoksa genel 401; bekleyen uzman başvuru takibine girebilir, sağlık paneline giremez. Admin bu yolu kullanamaz. Geçerli açık oturumda tekrar login 409'dur.

POST auth/admin-web-session AdminLoginRequest {email,password,mfaCode} alır; geçerli Admin+MFA için aynı hesap DTO'su/cookie, yanlış hesap/parola/MFA genel 401. TOTP 6 hane/30 saniye/±1 adım, adım tekrar kullanılamaz; 10 tek kullanımlık recovery hash'i vardır. Bootstrap/yeniden kurulum HTTP endpointi değildir.

POST auth/admin-email-code yalnız Development + Enabled + loopback SMTP:1025 koşulunda LoginUserRequest ile 202 verir; kapalıyken 404, uygun olmayan kimlik 401. Kod 6 hane/5 dakika/tek kullanım, 60 saniye cooldown ve en çok 5 tüketim denemesidir; IP limiti 5/dakika. Üretimde bu kanıtla açılan cookie kabul edilmez.

DELETE auth/web-session query/gövdesiz, CSRF/Origin ile DB iptali sonrası 204 ve auth/CSRF cookie temizliği yapar. Olmayan/bozuk/bitmiş oturum da geçerli CSRF/Origin ile 204'tür; diğer oturumlar değişmez.

Cookie adları `__Host-smart-nutrition-session` ve `__Host-smart-nutrition-csrf`; Secure/HttpOnly/SameSite=Strict, Path=/, Domain'sizdir. Auth cookie tarayıcı oturum cookie'sidir; beni hatırla/Expires/MaxAge yoktur. Bilet User/rol/sid ve framework zamanları taşır; JWT/refresh veya sağlık verisi taşımaz.

Idle 30 dakika, absolute 8 saattir; DB her istekte revocation/süre/güncel hesabı kontrol eder. Başarılı yetkili okuma idle'ı mutlak sınırı aşmadan ilerletir; CSRF/statik/health/başarısız istek ve keepalive uzatmaz. İptal eski uzatmayla geri alınmaz. Oturum satırı iptal/expiry sonrası en geç 24 saat içinde, normal 10 dakikalık temizlikle kaldırılır.

Web auth yollarında Authorization kabul edilmez. Origin yapılandırılmış HTTPS scheme/host/port ile tam eşleşir; eksik/null/yabancı yazma Origin'i 403; eksik/geçersiz CSRF 400; varsa CSRF GET Origin'i de eşleşir, cross-site fetch 403'tür. CSRF IP limiti 30/dakika; login gövdesi 4096 byte'tır. Üretim anahtar/SMTP/proxy koşulları 11'dedir.

## Uzman, ilişki ve paylaşım

| İşlem/DTO | Girdi / çıktı |
|---|---|
| POST dietitians/apply | DietitianApplicationRequest {email,password,displayName,licenseInfo}; 201 {id} User UUID |
| POST dietitians/me/application | Yalnız doğrulanmış client JWT, ExistingDietitianApplicationRequest {displayName,licenseInfo}; 201 DietitianStatusResponse; mevcut ClientProfile/rol korunur |
| GET dietitians/me | 200 DietitianStatusResponse {id,displayName,isVerified}; profil yoksa 404 |
| GET dietitians | page/pageSize, opsiyonel query; {items:[{id,displayName}],totalCount}; yalnız e-postası/uzmanlığı doğrulanmış hesaplar |
| GET admin/dietitians | MFA Admin; page/pageSize, opsiyonel isVerified; items {id,displayName,licenseInfo,isVerified} |
| POST admin/dietitians/{dietitianId}/verify | Gövdesiz; 200 DietitianStatusResponse; zaten onaylıysa aynı sonuç/audit tekrarı yok; e-posta doğrulanmamışsa 409 |
| POST dietitians/me/invitation-code | Onaylı uzman, gövdesiz; 200 {invitationCode,expiresAt} |
| POST dietitian-relationships | RelationshipRequest: yalnız dietitianId veya invitationCode; 201 RelationshipResponse pending |
| GET dietitian-relationships | page/pageSize, opsiyonel status; kendi taraf olduğu ilişkiler, requestedAt DESC/id ASC |
| POST …/{relationshipId}/accept, /reject, /end | Gövdesiz; 200 güncel ilişki; accept/reject yalnız ilgili onaylı uzman, end taraflar |
| GET dietitian/clients | page/pageSize, opsiyonel query ve sortOrder=asc veya desc; {items:[{id,displayName}],totalCount} |
| GET dietitian/clients/{clientId}/dashboard | 200 yalnız {clientId,displayName}; toplu sağlık özeti değildir |

Uzman adı kırpılmış 1–120, licenseInfo 1–2000 Unicode kod noktasıdır; başvuru gövdesi 16 KiB, varsayılan IP 5/dakikadır. Mesleki açıklama özel tutulur; belge yükleme, otomatik meslek doğrulama, ret/yeniden başvuru/geri alma endpointi yoktur.

Davet 10 rastgele byte → 16 karakter Base32, 24 saat, tek kullanım; DB yalnız hash/expiry tutar. Yeni kod eskiyi bozar; pending ilişkiyle atomik tüketilir. Kod girişi kırpılıp büyük harfe çevrilir. Aynı pending çift veya mevcut active ilişki 409'dur; kabulde active unique DB kuralı da yarışları engeller. İstek/kod üretimi varsayılan kullanıcı+IP 5/dakika sınırındadır. Kendine bağlantı 422'dir.

RelationshipResponse: id, clientId, dietitianId, status, requestedAt, nullable respondedAt/endedAt. Aynı hedef duruma tekrar geçiş mevcut sonucu döndürebilir; geçersiz geçiş 409'dur. Aktif ilişki sonu aynı transaction'da o uzmanın aktif atanmış programını arşivler ve açık görevlerini iptal snapshot'ıyla kapatır.

Paylaşım DTO'su `{id,relationshipId,category,isGranted,consentRecordId,createdAt,updatedAt}`tir. GET liste **relationshipId/page/pageSize zorunlu**, detay ID ile; ilişkinin tarafı okur. POST CreateDataSharingPermissionRequest {relationshipId,category,isGranted,nullable consentRecordId} →201; PATCH UpdateDataSharingPermissionRequest {isGranted,nullable consentRecordId} →200. İki yazma yalnız aktif ilişkinin danışanına aittir; pending/ended 409, yabancı kaynak 404, uzman/Admin yazması 403. Tekrarlı ilişki/kategori POST 409'dur.

Beş kategori 04'tedir; mevcut consentRecordId null'dır, dolu veya tanımsız kategori 422. Bayrak kapalıyken yeni kategori POST'u true/false fark etmeksizin ve PATCH true 422; mevcut PATCH false geri çekmesi mümkündür. nutrition_plans için ek rollout bayrağı yoktur; meal_logs/client_tasks/water_logs kendi bayrağına, body_measurements ayrıca **Development ortamına** bağlıdır. Bayrak GET'teki satırları gizlemez, satırları silmez veya rıza sağlamaz. Üretim açılımı açık konu olarak 12'dedir.

## Manuel öğün, su, ölçüm ve kişisel hedef

Kendi yolları JWT/client profilini kullanır; clientId/userId girdi değildir. CRUD POST→201 + Location, detay/liste/PATCH→200, DELETE→gövdesiz 204; silinmiş/yabancı kayıt normal okumada 404'tür. İlişki/uzman gerekmez. PUT veya sırf CRUD tamamlama amacıyla ek route yoktur.

| Kaynak | POST / PATCH | Yanıt |
|---|---|---|
| MealLog | CreateMealLogRequest: mealType, consumedAt, source, items zorunlu; note/foodAnalysisId nullable. PatchMealLogRequest: mealType/consumedAt/items/note/foodAnalysisId; source ve sahiplik değişmez | MealLogResponse: id, clientId, mealType, consumedAt, note, source, foodAnalysisId, createdAt, items |
| MealLogItem | displayName ve isEstimated zorunlu; nullable foodItemId/recipeId/quantityGrams/caloriesKcal/proteinGrams/carbsGrams/fatGrams | Aynı alanlar + id, mealLogId |
| WaterLog | CreateWaterLogRequest: amountMl, consumedAt, source; PatchWaterLogRequest yalnız amountMl/consumedAt | WaterLogResponse: id, clientId, amountMl, consumedAt, source |
| BodyMeasurement | CreateBodyMeasurementRequest: measuredAt/source; nullable weightKg/waistCm/hipCm/chestCm/bodyFatPercent/note. PatchBodyMeasurementRequest aynı ölçüm/zaman/not alanları, source yok | BodyMeasurementResponse: id, clientId, measuredAt ve bütün nullable ölçümler/not, source |
| PersonalNutritionTarget | POST/DELETE yok; PatchPersonalNutritionTargetRequest beş nullable günlük hedef alanından en az biri | PersonalNutritionTargetResponse: dailyCaloriesTargetKcal, dailyProteinTargetGrams, dailyCarbsTargetGrams, dailyFatTargetGrams, dailyWaterTargetMl, source="personal" |

Mevcut manuel POST'lar yalnız source=manual kabul eder. Öğünde foodAnalysisId/foodItemId/recipeId yalnız null/atlanmış olabilir; varsayılan AI/katalog kaydı oluşmaz. items 1–100, displayName boş olmayan/en çok 2000 kod noktası, not null veya en çok 2000/NUL içermeyen metindir. Bilinen quantityGrams>0, enerji/makrolar≥0; gramdan enerji türetilmez.

PATCH'te gönderilmeyen alan korunur; nullable alan null ile temizlenir. Boş PATCH 400, zorunlu öğün/zaman/items veya su miktar/zaman null ise 422'dir. items gönderilirse tüm koleksiyon değiştirilir; sunucu yeni kalem UUID'leri üretir. Öğün gövde sınırı 128 KiB, su 4096 byte, ölçüm 16 KiB, hedef 4096 byte'tır.

Ölçümde en az bir değer gerekir; kg/cm>0, yağ 0–100; hepsi birden temizlenemez. Kişisel hedef kaydı yoksa GET beş null + source=personal ile 200'dür; PATCH upsert'tir. Dolu hedefler pozitif ve kcal≤10000, makro≤1000g, su≤15000mL'dir; otomatik hesap veya klinik öneri değildir. Kişisel hedef uzman paylaşımına dahil değildir.

Öğün/su/ölçüm listeleri page/pageSize, opsiyonel from/to kullanır; [from,to), açık offset, from<to ve default tüketim/ölçüm zamanı DESC/id ASC. Ölçümde sortOrder=asc|desc de vardır. Günlük toplam listeden hesaplanmaz.

GET water-logs/daily-total zorunlu from/to alır: açık offsetli ardışık yerel 00:00 sınırları, gerçek gün aralığı; farklı offsetler DST gününü ifade edebilir. WaterLogDailyTotalResponse `{from,to,totalAmountMl}`; UTC sınırlar, decimal mL, yetkili boş gün 0. Decimal kapasite aşımı 422, sessiz kırpma/yuvarlama yoktur.

## Uzman sağlık okumaları ve su geçmişi

GET dietitian/clients/{clientId}/meal-logs ve body-measurements kendi kaynaklarıyla **aynı yanıt DTO'sunu** sayfalı döndürür; page/pageSize zorunlu, from/to opsiyonel, ölçümde sortOrder vardır. Uzman değişiklik yapamaz. Yabancı/aktif olmayan ilişki404, mevcut aktif ilişkide eksik/false kategori403; bilgi/sayı sızmaz.

Su liste/daily-total aynı WaterLogResponse/WaterLogDailyTotalResponse kullanır. GET …/water-logs/daily-history için page/pageSize/from/to/**timeZone** zorunludur. IANA bölgesi veya UTC kabul edilir, Windows adı kabul edilmez; başlangıç/bitiş offsetleri bu bölgeyle uyuşmalıdır. 1–31 yerel gün, her gün gerçek 00:00 ve 22–26 saat; belirsiz/atlanmış gece yarısı/uyumsuz offset/boş veya fazla aralık 400'dür. URL'de + kodlanır.

History `{items:WaterLogDailyTotalResponse[],totalCount}`; günler ASC, totalCount su kayıt sayısı değil istenen gün sayısıdır. Her ara gün kendi timezone sınırıyla hesaplanır; yetkili boş gün 0, silinmiş/yabancı kayıtlar hariçtir. Her istekte en çok 31 indeksli SUM; kişisel hedef/profil/başka kategori alanı veya günlük kalıcı cache yoktur. Su gözetimi için onaylı uzman+aktif ilişki+water_logs aynı RepeatableRead snapshot'ında kontrol edilir.

## Program, sürüm ve tüketim karşılaştırması

CreateNutritionPlanRequest: title/startDate/items zorunlu; nullable endDate/dailyCaloriesTargetKcal/dailyWaterTargetMl. Danışan clientId/dietitianId göndermez; uzman clientId gönderir, dietitianId sunucudan gelir. Başlangıç draft/version 1. PatchNutritionPlanRequest yalnız bu içerik alanlarını alır; status/sahiplik yoktur. Gövde128 KiB; title1–120, tarihlerde end≥start, bilinen hedefler>0.

NutritionPlanItemRequest: mealType/description/sortOrder zorunlu; nullable dayOfWeek/recommendedQuantity/recipeId/alternativeGroupId. Description1–2000, miktar metni≤200, boş miktar null, sortOrder≥0 ve içerikte tekil; items1–100. dayOfWeek null veya ISO1–7. Aynı alternatif grup en az iki öğeyle aynı gün/mealType'tadır; başka öğeye FK değildir. recipeId mevcut yazmada null'dır. id/nutritionPlanId sunucu üretir.

NutritionPlanResponse: id, clientId, nullable dietitianId, title, status, startDate, nullable endDate/dailyCaloriesTargetKcal/dailyWaterTargetMl, createdAt, items, versionId, versionNumber. Item yanıtı girdi alanlarına id/nutritionPlanId ekler. Liste createdAt DESC/id ASC; danışan kendi kapsamında clientId göndermez, uzman zorunlu clientId ile okur. GET active yalnız kendi danışan bağlamıdır, aktif yoksa 404.

GET versions → sayfalı NutritionPlanVersionInfo {id,nutritionPlanId,versionNumber,createdAt}; GET version → NutritionPlanVersionResponse aynı metadata + snapshot {title,startDate,endDate,dailyCaloriesTargetKcal,dailyWaterTargetMl,items}. recordedByUserId/snapshotJson açılmaz. Her geçerli içerik PATCH'i aynı içerikte bile yeni sürüm ve yeni kalem UUID'leri üretir; geçmiş değişmez.

Activate/archive gövdesizdir,200 güncel program döner; aynı durum tekrarı değişmez200, başka active 409 active_nutrition_plan_conflict. Status içerik sürümünü artırmaz. Genel atomik replace veya sahipliği değiştirme yoktur. Danışan kendi kişisel programını, uzman yalnız kendi atadığını yazar; atanmış program danışana salt okunur. Uzman okuması aktif ilişki+nutrition_plans ister; kişisel veri sahipliği ilişkisiz korunur.

Meal-comparison yalnız zorunlu from/to ile seçilmiş sürüm/günü okur; pagination/gövde yok. Açık offsetli ardışık yerel00:00, [from,to); gün snapshot tarih aralığında değilse422. Snapshot dayOfWeek filtresi ve beş MealType grubu kullanılır. Bütün kayıtlardan gerçek tüketim toplanır; otomatik ad/miktar eşleştirme veya uyum yüzdesi yoktur.

NutritionPlanMealComparisonResponse: clientId, nutritionPlanVersion, date, from, to, actual, nullable caloriesDifferenceKcal, meals. Meal öğesi mealType/plannedItems/actual; actual MealLogNutritionSummary {mealLogCount,itemCount,estimatedItemCount,caloriesKcal,proteinGrams,carbsGrams,fatGrams}; her besin NutritionValueSummary {knownTotal,missingItemCount}. Kcal farkı yalnız en az bir kalem+tüm kaloriler biliniyor+snapshot hedefi varsa knownTotal−hedef, aksi null'dır.

Karşılaştırma geçmişte o gün aktif sürümün kanıtı değildir; genel aktivasyon zaman çizelgesi tutulmaz. Uzman için **hem nutrition_plans hem meal_logs** gerekir; kısmi hedef/özet dönmez. Aktör/izin/snapshot/toplam tek RepeatableRead snapshot'ında okunur; Admin erişmez.

## Öğün yorumu ve görev

CreateMealLogCommentRequest {text,nullable parentCommentId} →201 MealLogCommentResponse {id,mealLogId,authorUserId,text,createdAt,parentCommentId}. Text kırpılmış1–2000/NUL içermeyen metin; gövde 32 KiB. Parent aynı öğündeki kök olmalıdır; başka öğün/yok kaynak 404, yanıtın yanıtı 422. GET comments page/pageSize ile createdAt ASC/id ASC'dir. Danışan kendi, uzman active+meal_logs izniyle yazar/okur. PATCH/DELETE yorum/moderasyon ve bildirim teslimi henüz yoktur.

CreateClientTaskRequest {clientId,description,nullable dueAt} yalnız uzman →201; source/başlangıç durumu/ilişki istemciden alınmaz. ClientTaskResponse: id,clientId,dietitianId,relationshipId,description,status,dueAt,isReminderEnabled,createdAt,updatedAt,versionNumber. Açıklama kırpılmış1–2000, dueAt verilmiş/yeni değiştirilmişse gelecekte UTC instant; son tarihi geçen görevin tamamlanması mümkündür.

GET liste page/pageSize ve uzman için clientId; danışan clientId göndermez. Sıra createdAt DESC/id ASC. Detay ve versions aynı kaynak yetkisini ister. Version yanıtı {id,clientTaskId,versionNumber,createdAt,snapshot:ClientTaskResponse}, versionNumber DESC'dir.

PatchClientTaskRequest **expectedVersionNumber** ve en az bir description/dueAt/status/isReminderEnabled alanı ister; gövde 32 KiB. Başlangıç pending/version 1/reminder false. Danışan pending→in_progress veya completed, in_progress→completed yapabilir, yalnız kendi reminder tercihini değiştirir. Uzman yalnız kendi açık görevinin açıklama/son tarihini değiştirir veya cancelled yapar; danışan adına tamamlamaz. DueAt kaldırılınca reminder false, dueAt yokken true 422'dir.

Eski sürüm/terminal görev 409; başka rolün alanı 403, boş PATCH 400. Açık görevde aynı değer no-op, gerçek değişiklik sürüm+snapshot üretir. İlişki bitişi açık görevleri iptal eder; izin geri çekilmesi görev durumunu değiştirmez. Danışan geçmiş/kendi görevini ilişkisiz okumayı sürdürür. Görevler özgün ilişkiye bağlıdır, yeni uzman eski atayana ait görevi devralmaz. Bildirim/hatırlatma gönderimi bu modelin varlığından türetilmez.

## Sağlık aktarımı ve manuel aktivite

Envanterdeki 14 HealthData route'unun bütün DTO/query/birim/zaman/limit, kaynak kimliği, tombstone, idempotency, hata ve conservative_overlap_v1 kuralları **[20_HEALTH_DATA_SYNC_CONTRACT.md](20_HEALTH_DATA_SYNC_CONTRACT.md)** içinde tek kaynaktır. Bağlantı durumu OS izni değildir; bu yollar uzman paylaşımı açmaz.

## Planlanan HTTP kapsamı — çalışan endpoint değil

Aşağıdaki yollar önceki belgelerin taslaklarıdır; kaynak envanterinde yoktur. Ürün gereksinimi korunur; açık DTO/yetki/dosya/onay kararları kapanmadan uygulama/mock dayanağı değildir.

| Taslak method/route | Korunan gereksinim / açık parça |
|---|---|
| PATCH /api/v1/me | Profil güncelleme; alan/kayıt politikası açık; GET /me yerine mevcut auth/me kullanılır |
| GET /api/v1/food-items | Hibrit katalog araması; kaynak/lisans/yanıt açık |
| GET/POST /api/v1/recipes; GET/PATCH /api/v1/recipes/{recipeId} | Kendi tarifleri; bileşen/porsiyon/görünürlük/geçmiş açık, DELETE türetilmez |
| POST /api/v1/food-analyses; GET /api/v1/food-analyses/{analysisId} | Taslak image multipart,202 id/status ve kontrollü öneri okuma; dosya/onay/üretim şeması açık |
| GET/POST /api/v1/lab-reports; GET/PATCH/DELETE /api/v1/lab-reports/{labReportId} | Manuel rapor/değer/birim/referans; tam alt kayıt/güncelleme/saklama açık |
| POST/GET /api/v1/lab-reports/{labReportId}/insights | Açıklayıcı analiz; method/limitations ve güncellenmiş raporda eski sonuç davranışı açık |
| POST /api/v1/lab-reports/ocr | Taslak document multipart; PDF/fotoğraf,limit,iş/taslak yanıtı/onay kanıtı açık;200/202 kesinleştirilmez |
| GET /api/v1/dietitian/clients/{clientId}/activity-logs; GET /api/v1/dietitian/clients/{clientId}/lab-reports | Planlanan kategori/yetki; tahlilde ayrıca geri çekilmemiş açık onay gerekir |
| GET/POST /api/v1/consent-records; POST /api/v1/consent-records/{consentRecordId}/withdraw | Kendi consentType/granted/policyVersion kaydı ve geri çekme; tür/kapsam/metin/kanıt açık |

Korunan FoodAnalysis önerisi displayName, confidence 0..1, nullable quantityGrams/caloriesKcal/proteinGrams/carbsGrams/fatGrams; limitations kökte list<string>'dir. Kullanıcı ayrı MealLog ile onaylar, otomatik confirm route'u eklenmez.

Korunan manuel lab taslağı collectedAt, nullable labName/note ve results {testName,nullable testCode,value,unit,nullable referenceLow/referenceHigh}; flag sunucudan ve uygun olmayan aralıkta unknown olur. ConsentRecord oluşturmak tek başına paylaşım vermez; geri çekme zamanı sunucudan gelir ve önceki politika/kabul geçmişi korunur.

Bildirim, PDF, şikâyet ve diğer Admin operasyonları onaylı kapsamdır fakat kesin route/DTO yoktur; uydurulmaz. Kalan kararlar [12](12_TEAM_PLAN_AND_DECISIONS.md)'dedir.
