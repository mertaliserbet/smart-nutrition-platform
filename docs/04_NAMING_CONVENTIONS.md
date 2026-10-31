# 04 — KANONİK İSİMLENDİRME SÖZLEŞMESİ

## 29.10.2026 N1–N3 ortak onay güncellemesi

Kullanıcı `16` için “N1–N3 için ortak onay var; uygula.” dedi. Aşağıdaki
program ad/şeması artık onaylıdır; programla ilgili eski açık notların yerini alır.
`NutritionPlan` ve `NutritionPlanItem`, mevcut `MealType` ve
`NutritionPlanStatus` değerleri korunur. Ayrı PersonalPlan/AssignedPlan yoktur.

- Yeni kanonik kalıcı model `NutritionPlanVersion`; tablo
  `nutrition_plan_versions`. Her programın değişmeyen içerik sürümleridir.
- `NutritionPlanSnapshot`: title/startDate/endDate/dailyCaloriesTargetKcal/
  dailyWaterTargetMl/items. Sahiplik veya güncel status geçmiş içeriğe eklenmez.
- `NutritionPlanResponse`: mevcut alanlar + `versionId`, `versionNumber`.
  `NutritionPlanVersionInfo`: id/nutritionPlanId/versionNumber/createdAt;
  `NutritionPlanVersionResponse`: aynı metadata + snapshot.
- `CreateNutritionPlanRequest`, `PatchNutritionPlanRequest`,
  `NutritionPlanItemRequest` ortak JSON adlarını kullanır. Item'a nullable
  `alternativeGroupId` eklenir; ayrı alternatif entity'si yaratılmaz.
- `recordedByUserId` yalnız sunucudadır; istemci DTO'suna taşınmaz.
  Tam alan/tip ve HTTP davranışı `05/06`dadır. Flutter kaynakları değişmez.

## 29.10.2026 R1–R3 ortak onay güncellemesi

Kullanıcı `15` için “R1–R3 için ortak onay var; uygula.” yanıtını verdi.
Mevcut DietitianClientRelationship/RelationshipStatus ve DataSharingPermission
adları korunur. RelationshipRequest yalnız dietitianId veya invitationCode'dan
birini alır; RelationshipResponse mevcut ilişki alanlarıdır. InvitationCodeResponse
yalnız invitationCode/expiresAt döndürür. İlişki için ikinci eşanlamlı model yoktur.

DietitianProfile.invitationCodeHash/invitationCodeExpiresAt yalnız sunucudadır;
ham davet kodu profil/directory/başvuru yanıtına eklenmez. İlk paylaşım kodu
`nutrition_plans`; diğer kategoriler/tahlil onayı açık ve kapalı erişimde kalır.
ClientListItem id/displayName, ClientDashboardResponse clientId/displayName
olarak sınırlıdır. CreateDataSharingPermissionRequest ve
UpdateDataSharingPermissionRequest aynı mevcut alan adlarını kullanır.
Bu bölüm eski davet/kategori açık notlarının yalnız R1–R3 dilimini kapatır.

## 29.10.2026 B1–B3 ortak onay güncellemesi

Kullanıcı “Ortak onay var devam et.” ile `14`teki B1–B3 paketini teyit etti.
Bu dilimde hesap başına tek rol ve role uygun profil kullanılır; mevcut
danışan hesabı uzmana çevrilmez. Önceki bölümlerde başvuru/MFA'yı açık
gösteren notlar bu onaylı dilim için tarihsel durumdur; diğer açıklar korunur.

- `DietitianProfile.licenseInfo`: zorunlu mesleki açıklama string'i; yalnız
  Admin inceleme DTO'sunda açılır. `isVerified` yalnız Admin tarafından atanır.
- `DietitianApplicationRequest`: email/password/displayName/licenseInfo;
  başarı mevcut `RegisterUserResponse` (`id` = User UUID).
- `DietitianStatusResponse`: id/displayName/isVerified (id = DietitianProfile UUID).
- `DietitianReviewItem`: aynı alanlar + yalnız Admin'e licenseInfo.
- `DietitianListItem`: public aramada yalnız id/displayName.
- `AdminLoginRequest`: email/password/mfaCode. Admin için yeni User/entity
  türetilmez. Başarı aynı beş alanlı `CurrentUserResponse`, role `admin`.
- `User.totpSecretProtected`, `lastUsedTotpStep`, `mfaRecoveryCodeHashes` ve
  `AuthSession.isMfaVerified` yalnız sunucuda tutulur. HTTP hesap/model
  yanıtlarına secret/MFA metadata'sı eklenmez.
- Admin yalnız `/auth/admin-web-session` MFA cookie'siyle kabul edilir.
  JWT/bearer ve normal `/auth/web-session` Admin'e kapalı kalır.
- `AuditEvent` mevcut actorUserId/action/resourceType/resourceId/createdAt/
  metadata adlarını korur; yeni targetId/occurredAt karşılığı oluşturulmaz.
- Web TypeScript karşılıkları aynı DTO adlarını kullanır. Flutter kaynakları
  değişmez; mevcut login JWT ve auth/me JSON anahtarları korunur.

> **TEK KAYNAK (source of truth):** İki Codex'in aynı alanı farklı adlandırmasını engelleyen ortak kurallar. `05_DATA_DICTIONARY.md` alan tiplerini; `06_API_CONTRACT.md` URL ve payloadları belirler. Değişiklik süreci için `AGENTS.md` ve `12_TEAM_PLAN_AND_DECISIONS.md`.

**Karar temeli:** `12_TEAM_PLAN_AND_DECISIONS.md` içindeki 22 onaylı karar. Mevcut kanonik adlar korunur; yeni kavramların aşağıdaki adlandırma karşılıkları alan, tablo, ilişki veya endpoint tasarımı anlamına gelmez. `05/06` uyarlamaları ve iki tarafın ortak sözleşme onayı tamamlanmadan eksik yapılar tahmin edilerek uygulanmaz.

## Kanonik terimler (mevcut veri/API sözleşmeleriyle ortak adlar)

Tip adları C#, Dart ve TypeScript'te `PascalCase` olarak aynıdır. Üçüncü sütun yalnız değişken/alan yazımını gösterir; her yanıtın bu adla sarılmasını veya yeni bir JSON anahtarı eklenmesini gerektirmez. API yolları `/api/v1` tabanına göredir; kesin method/route ve payload kaynağı `06`dır.

| Türkçe kavram | C#/Dart/TypeScript tip adı | Değişken/alan yazımı | Mevcut API karşılığı / sınır |
|---|---|---|---|
| Kullanıcı hesabı | `User` | `user` | Kendi hesap özeti: `GET /auth/me`; önceki `/users` admin önerisi `06`da tanımlı değildir |
| Danışan profili | `ClientProfile` | `clientProfile` | `/dietitian/clients` (diyetisyen görünümü) |
| Diyetisyen profili | `DietitianProfile` | `dietitianProfile` | `/dietitians` |
| Diyetisyen–danışan ilişkisi | `DietitianClientRelationship` | `dietitianClientRelationship` | `/dietitian-relationships` |
| Öğün kaydı | `MealLog` | `mealLog` | `/meal-logs` |
| Öğün besin kalemi | `MealLogItem` | `mealLogItem` | `MealLog.items` altında |
| Besin katalog girdisi | `FoodItem` | `foodItem` | `/food-items` |
| Görsel besin analizi | `FoodAnalysis` | `foodAnalysis` | `/food-analyses` |
| Su kaydı | `WaterLog` | `waterLog` | `/water-logs` |
| Beslenme planı / programı | `NutritionPlan` | `nutritionPlan` | `/nutrition-plans`; N1–N3 kişisel/atanmış program sözleşmesi `05/06`da onaylı |
| Plan öğesi | `NutritionPlanItem` | `nutritionPlanItem` | `NutritionPlan.items` altında |
| Program içerik sürümü | `NutritionPlanVersion` | `nutritionPlanVersion` | `/nutrition-plans/{nutritionPlanId}/versions`; salt okunur geçmiş |
| Vücut ölçümü | `BodyMeasurement` | `bodyMeasurement` | `/body-measurements` |
| Aktivite kaydı | `ActivityLog` | `activityLog` | `/activity-logs` |
| Tahlil raporu | `LabReport` | `labReport` | `/lab-reports` |
| Tahlil değeri | `LabResult` | `labResult` | `LabReport.results` altında |
| Tahlil açıklayıcı analizi | `LabInsight` | `labInsight` | `/lab-reports/{labReportId}/insights` |
| Cihaz bağlantısı | `WearableConnection` | `wearableConnection` | `/wearable-connections` |
| İzin/rıza kaydı | `ConsentRecord` | `consentRecord` | henüz endpoint kararı yok |
| Denetim olayı | `AuditEvent` | `auditEvent` | yalnız backend/admin; endpoint kararı yok |

**Yasak eşanlamlı entity örnekleri:** `FoodRecord`/`MealEntry`/`Meal` yerine `MealLog`; `DietPlan`/`MealPlan` yerine `NutritionPlan`; `BloodTest`/`MedicalReport` yerine `LabReport`; `Coach`/`Trainer` yerine `Dietitian`. `FoodAnalysis` ile `MealLog` farklı kavramlardır.

### 22 karardan doğan ortak kavram adları

Bu bölüm yalnız kavram adlarını netleştirir; yeni entity/tablo zorunluluğu, JSON alanı, enum veya endpoint oluşturmaz. Yeni adların `05/06` karşılıkları henüz tanımlı değildir; ayrıntılı sözleşme önerisi iki geliştiricinin onayına sunulmalıdır.

| Kavram | Ortak ad | Anlam / sınır |
|---|---|---|
| Kişisel beslenme programı | `NutritionPlan` | Diyetisyensiz danışanın oluşturduğu program da aynı kavramdır. `PersonalPlan`, `PersonalNutritionPlan` veya `ClientPlan` adlı eşanlamlı model üretilmez; N1–N3 sahiplik ve düzenleme kuralları `05/06`dadır |
| Özel tarif | `Recipe` | Tarif kavramıdır; katalog besini `FoodItem` ve gerçek tüketim kalemi `MealLogItem` ile karıştırılmaz. İçerik, porsiyon, hesaplama ve katalog bağlantısının yapısı ayrıca kararlaştırılır |
| Diyetisyenin danışana atadığı görev | `ClientTask` | Danışan görevidir; C# asenkron `Task` tipi, antrenman programı veya yalnız bildirim anlamında kullanılmaz. Alanlar, durum değerleri ve geçişler henüz tanımlı değildir |
| Kategori bazlı veri paylaşım izni | `DataSharingPermission` | Danışanın hangi veri kategorisini hangi diyetisyenle paylaşabildiği kavramıdır. Mevcut `ConsentRecord` izin/rıza geçmişini ifade eder; erişim izni ile rıza kaydı eşanlamlı değildir. Aralarındaki ilişki ve kategori listesi açıktır |

`FoodRecipe`/`CustomRecipe` ile `Recipe`, `DietitianTask`/`NutritionTask` ile `ClientTask`, `SharingPermission`/`DataAccessPermission` ile `DataSharingPermission` için paralel eşanlamlı modeller oluşturulmaz. Adlandırma karşılığı seçilmesi bu kavramların ayrı saklama modelleri olacağını kesinleştirmez.

### Kavram sınırları ve onaylı kurallar

- **Rol, hesap ve profil:** `Client`, `Dietitian`, `Admin` rol kavramlarıdır; JSON rol değerleri `client`, `dietitian`, `admin`dir. Hesap `User`, danışan profili `ClientProfile`, diyetisyen profili `DietitianProfile`dır. Ayrı bir `Client`/`Dietitian` entity'si veya `AdminUser` modeli türetilmez. Çoklu rol/profil kuralı açıktır; mobil/web üzerinden başvuru yeni kullanıcı rolü oluşturmaz.
- **Kimlikler ve ilişki:** `userId` hesap kimliğidir; `clientId` → `ClientProfile.id`, `dietitianId` → `DietitianProfile.id`. Birbirlerinin yerine kullanılmaz. `DietitianClientRelationship` arama/davet kodu ve karşılıklı onayla kurulan ilişkiyi temsil eder; danışanın en fazla bir aktif diyetisyeni olur, geçmiş korunur. Davet kodunun teknik yapısı açık kalır.
- **Program, plan ve tüketim:** Ürün metnindeki “plan/program” aynı `NutritionPlan` kavramıdır. Kişisel ve diyetisyen programları toplamında en fazla bir aktif program vardır; öğün alternatifleri ve sürüm geçmişi desteklenir. `NutritionPlanItem` tavsiye, `MealLog` gerçek tüketim, `MealLogItem` tüketilen kalemdir. Danışan diyetisyen programını/hedeflerini değiştiremez; gerçek tüketimi serbestçe kaydeder. N1–N3 sahiplik, gün/miktar/alternatif ve sürüm yapıları `05/06`da onaylıdır; programsız/makro hedefler açıktır.
- **Besin, tarif ve AI:** `FoodItem` hibrit kataloğun besin girdisidir; sağlayıcı değişince eşanlamlı entity adı oluşturulmaz. `Recipe` tarif, `FoodAnalysis` fotoğraf/galeri analizidir. Tahmini kalori/makro ve porsiyon kullanıcı onayından geçer; analiz otomatik tüketim kaydı değildir. Sürekli kamera analizi sonraki aşamadır.
- **Tahlil ve açıklama:** Manuel giriş ve daha sonra kullanıcı onaylı PDF/fotoğraf OCR aynı `LabReport`/`LabResult` kavramlarını kullanır; giriş yöntemi ayrı rapor entity'si oluşturmaz. `LabInsight` açıklayıcı değerlendirmedir; tanı/tedavi değildir. Geçerli birim/aralık yoksa `LabResult.flag` değeri `unknown` olur; ML opsiyoneldir. PDF dışa aktarma raporu ile laboratuvar raporu aynı kavram sayılmaz.
- **Aktivite ve ölçüm:** `ActivityLog` fiziksel aktivite kaydı, `BodyMeasurement` vücut ölçümü, `WearableConnection` sağlık platformu bağlantısıdır. Health Connect/HealthKit'ten gelen adım, mesafe, egzersiz, süre, aktif kalori ve nabız kapsamı onaylıdır; bunların tümünün `ActivityLog` içine konacağı varsayılmaz. Kaynak/geçmiş ve tekilleştirme korunur; ayrı sağlık verilerinin model ve birim adları açık kalır. Antrenör veya antrenman programı kavramı eklenmez.
- **Paylaşım, rıza ve yetki:** Aktif ilişki tek başına kategori erişimi vermez; tahliller için ayrıca açık onay gerekir. `DataSharingPermission`, `ConsentRecord`, rol yetkisi ve cihaz/işletim sistemi izni birbirinin yerine kullanılmaz. Geri çekilen izinle yeni erişim verilmez. `Admin` özel sağlık verilerini varsayılan göremez; Audit Log mevcut `AuditEvent` kavramıdır.

## Dil ve dosya kuralları

Kod tanımlayıcıları İngilizce ve ASCII yazılır; Türkçe kullanıcı arayüzü etiketleri yeni domain adı veya JSON anahtarı üretmez. Aynı kavramın adı platform değişince çevrilmez ya da kısaltılmaz.

| Konum | Kural | Örnek |
|---|---|---|
| C# class/entity/DTO | `PascalCase` | `MealLog`, `CreateMealLogRequest` |
| C# property | `PascalCase` | `ConsumedAt`, `ClientId` |
| C# local/param | `camelCase` | `mealLogId` |
| Dart class/model/enum tipi | `PascalCase` | `MealLog`, `MealType` |
| TypeScript type/component | `PascalCase` | `MealLog`, `MealLogCard` |
| C#/TS/Dart metot/işlev | C# `PascalCase`; TS/Dart `camelCase` | `CreateMealLog` / `createMealLog` (yalnız adlandırma örneği) |
| TS/Dart variable/field/param | `camelCase` | `caloriesKcal`, `consumedAt` |
| Flutter file | `snake_case.dart` | `meal_log_page.dart` |
| Web TSX file | isim tutarlı; component `PascalCase.tsx`, helper `camelCase.ts` | `MealLogCard.tsx` |
| Backend dosya | C# type ile `PascalCase.cs` | `MealLogService.cs` |
| PostgreSQL tablo/sütun | İngilizce, küçük `snake_case`; tablo çoğul, sütun alan adı | `meal_logs`, `client_id`, `consumed_at` |
| REST kaynak adı | `/api/v1/` + çoğul `kebab-case`; yalnız `06`da tanımlı yollar | `/api/v1/meal-logs`; `/auth/me`, `/auth`, `/dietitian` ve açık profil düzenleme yolu `06`ya göre kullanılır |
| JSON fields | **her yerde `camelCase`** | `clientId`, `caloriesKcal` |
| Git dalı | Güncel ortak `main`den görev/feature branch'i açılır ve ortak `main`e PR oluşturulur (`12`, 28.10.2026 kullanıcı kararı) | `feature/web-registration`; dal adında geliştirme aracının adı kullanılmaz |

**Platformlar arası eşleme:** C# `MealLog.ClientId` ↔ Dart/TypeScript `MealLog.clientId` ↔ JSON `clientId` ↔ PostgreSQL `meal_logs.client_id`. C# property yazımı JSON'a taşınmaz; Dart/TypeScript alanları backend'deki PascalCase ile gönderilmez. PostgreSQL adları JSON'a taşınmaz. Serileştirme ve DB eşlemesi bu dönüşümü açıkça korumalıdır.

DTO'lar aynı kanonik kökü kullanır (`CreateMealLogRequest` gibi); DTO, domain modeli ve ekran modeli ayrımı aynı kavramı yeniden adlandırma gerekçesi değildir. Alan listesi, zorunluluk, null kabulü ve yanıt iç içeliği yalnız `05/06`dan alınır; bir tip adından tablo veya endpoint otomatik türetilmez.

## Alan ve birim isimleri

- Kimlik: `id`; ilişki alanları `clientId`, `dietitianId`, `mealLogId` gibi `...Id`. `05/06` gereği tüm kayıt kimlikleri UUID, JSON karşılığı stringdir; `Id` yerine `ID` veya eşanlamlı `clientUserId` kullanılmaz.
- Zaman: olay zamanı `...At` (UTC ISO 8601; ör. `2026-10-15T12:30:00Z`), takvim günü `...Date` (`YYYY-MM-DD`). Yerel gösterim ve günlük toplamların saat dilimi politikası ayrı konudur; yeni tarih alanları varsayılmaz.
- Enerji: `caloriesKcal` (kcal); besin makroları `proteinGrams`, `carbsGrams`, `fatGrams` (gram); su `amountMl` (mL); vücut ağırlığı `weightKg`, boy `heightCm`; porsiyon `quantityGrams` (gram).
- Değer+birim ayrılmaz: laboratuvar `value`, `unit`, `referenceLow`, `referenceHigh`; rapordaki laboratuvar aralığı saklanır.
- Yeni boolean adlarında `is...`/`has...` tercih edilir; ör. `isVerified`, `isEstimated`. Mevcut sözleşmedeki `ConsentRecord.granted` korunur; genel kural gerekçesiyle `isGranted` olarak değiştirilmez.
- İşleme durumu `status`; sabit string enumlar **lowercase** ve gerektiğinde `snake_case`.
- `RecordSource` manuel/cihaz/AI destekli kaynağı, `FoodItem.dataSource` besin veri kaynağını, `WearableConnection.provider` platform sağlayıcısını ifade eder; bu alanlar eşanlamlı sayılmaz. `externalRecordId` dış kaynak kimliğidir; tekilleştirmede sağlayıcıyla bağlantısı `05/06`da netleştirilmelidir.
- Adet/gram dönüşümü, nabız/adım alanları, aktif kalori ayrımı, görev son tarihi, paylaşım kategorileri ve kişisel makro hedefleri için yeni alan veya birim anahtarı bu belgede üretilmez. `null` bilinmeyen, `0` gerçek sıfırdır; eksik değerler yeni ad veya sahte sıfırla gizlenmez.

### Onaylı kayıt ve e-posta doğrulama adları — 27.10.2026

- Kayıt DTO'ları `RegisterUserRequest` / `RegisterUserResponse`; zorunlu düz `displayName`, `ClientProfile.displayName` alanına aittir. Başarıdaki `id`, `User.id` değeridir; `clientId` değildir. Tam şema `06`dadır.
- `User.isEmailVerified` e-posta sahipliğidir; `DietitianProfile.isVerified` Admin'in uzman doğrulamasıdır. Bu iki alan eşanlamlı değildir; `emailConfirmed` / `isVerified` adıyla ikinci bir hesap alanı oluşturulmaz.
- Doğrulama girdisi `VerifyEmailRequest.token`, yeniden gönderim girdisi `ResendVerificationRequest.email` olur. `token` yalnız bu işlemin girdisidir; oturum/access/refresh tokenı değildir ve yeni bir token entity'si oluşturulmaz.
- Sunucu içi alanlar C# `EmailVerificationTokenHash`, `EmailVerificationExpiresAt`, `EmailVerificationLastSentAt`; PostgreSQL karşılıkları `email_verification_token_hash`, `email_verification_expires_at`, `email_verification_last_sent_at` olur. Sözlükteki camelCase gösterimleri HTTP yanıt alanı ilanı değildir: üç token metadata alanı yanıtlara çıkmaz. `isEmailVerified` yalnız aşağıdaki onaylı kendi hesap DTO'sunda açılır; entity JSON'u/kayıt/giriş yanıtı değişmez. Tip ve bütünlük `05`te, işlem yolları `06`dadır.
- Ham token için `User.token`, `verificationCode` veya saklanan düz metin alternatif alan üretilmez. E-posta metnindeki “doğrulama kodu” API'deki `token` ile aynı değerdir; mobil/web ayrı ad veya şema üretmez.

### Onaylı giriş ve JWT adları — 27.10.2026

- Giriş `LoginUserRequest` / `LoginUserResponse` adlarını kullanır: istek `email`, `password`; yanıt `accessToken`, `tokenType`, `expiresAt`, `refreshToken`, `refreshTokenExpiresAt`. Paralel `SignIn`/`Authenticate` DTO'su veya farklı istemci yanıt kökü üretilmez. 31.10.2026 kullanıcı göreviyle refresh alanları eklendi; tam HTTP sözleşmesi `06`dadır.
- JWT `sub` claim'i `User.id` değeridir; `clientId` veya `ClientProfile.id` değildir. `role` claim'i mevcut `client` / `dietitian` değerini taşır. `admin`, MFA hazır olana kadar token üretiminde ve kabulünde kapalıdır.
- `accessToken` 15 dakikalık JWT'dir; e-posta doğrulama girdisi `token` ile karıştırılmaz. `tokenType` tam `Bearer`, `expiresAt` UTC instant'tır. JWT ve `expiresAt` yeni User sütunları değildir. JWT'nin standart `iss`, `aud`, `iat`, `nbf`, `exp` claim adları JSON/domain alanı diye yeniden adlandırılmaz.

### Mobil refresh adları — 31.10.2026

Kullanıcının backend refresh/iptal göreviyle `RefreshToken` → `refresh_tokens`
sunucu içi hash/rotasyon geçmişi eklendi. `familyId` aynı girişten türeyen
tokenları gruplar; ayrı User/profil kimliği veya web `AuthSession` değildir.
`POST /api/v1/auth/refresh` ve `POST /api/v1/auth/logout` aynı
`RefreshTokenRequest { refreshToken }` girdisini kullanır. Yenileme yanıtı
genişletilmiş `LoginUserResponse` olur; `refreshTokenExpiresAt` ailenin mutlak
UTC bitişidir. Ham refresh token JSON'da yalnız giriş/yenileme yanıtındadır;
DB alanı `tokenHash`tır. DTO/rota alias'ı, mobil cookie veya web değişikliği yoktur.
Flutter'ın eski üç alanlı katı login ayrıştırıcısı ayrıca güncellenmelidir.

### Onaylı kendi hesap özeti — 27.10.2026

- Kanonik işlem `GET /api/v1/auth/me`, yanıt DTO'su `CurrentUserResponse` olur; yeni `CurrentUser` entity'si/tablosu oluşturulmaz. Eski uygulanmamış `GET /api/v1/me` taslağı bu görevde kullanıcının açık yol talimatıyla değiştirilmiştir; ikinci GET alias'ı oluşturulmaz. `PATCH /api/v1/me` ayrı, henüz uygulanmamış profil düzenleme taslağıdır.
- Yanıt düz kökte tam beş alan taşır: `id`, `displayName`, `email`, `role`, `isEmailVerified`. `id`, JWT `sub` ile seçilen `User.id`; `displayName`, varsa o User'a ait `ClientProfile.displayName`, yoksa açık `null`dır. `user`/`clientProfile` sarmalayıcısı veya farklı rol için alternatif yanıt kökü üretilmez. Birim/nullability ve erişim kuralları `05/06`dadır.

### Onaylı web oturumu adları — 27.10.2026

Kullanıcı W2-C1–C7 için Uğur–Mert ortak onayını açıkça teyit etti.
`AuthSession` yalnız sunucuda tutulan web cookie oturumudur; PostgreSQL tablosu
`auth_sessions`tir. User/profil veya JWT/refresh token entity'si değildir ve
istemciye serileştirilmez. Alanları `05`, HTTP sözleşmesi `06`dadır.
`CsrfTokenResponse` yalnız `{ requestToken }` yanıt DTO'sudur; entity/tablo değildir.
Web oluşturma mevcut `LoginUserRequest` ve beş alanlı `CurrentUserResponse`
adlarını kullanır. `sid`, yalnız korumalı cookie biletindeki AuthSession UUID'sidir;
JWT claim/yanıtı değişmez. `requestToken` yetkilendirme veya e-posta tokenı değildir.
Cookie adları `__Host-smart-nutrition-session` ve `__Host-smart-nutrition-csrf`,
istek başlığı `X-CSRF-TOKEN` olur. Mobil JWT girişine cookie/CSRF şartı eklenmez.

## Başlangıç enum sözlüğü

| Enum | JSON değerleri |
|---|---|
| `UserRole` | `client`, `dietitian`, `admin` |
| `MealType` | `breakfast`, `lunch`, `dinner`, `snack`, `other` |
| `RelationshipStatus` | `pending`, `active`, `rejected`, `ended` |
| `NutritionPlanStatus` | `draft`, `active`, `archived` |
| `FoodAnalysisStatus` | `pending`, `processing`, `completed`, `failed` |
| `LabFlag` | `low`, `normal`, `high`, `unknown` |
| `RecordSource` | `manual`, `wearable`, `ai_assisted` |

Enum tipi ve JSON değeri ayrıdır: C# üyeleri `PascalCase`, Dart üyeleri `camelCase` olabilir; API'deki sabit değerler aynen korunur (ör. `AiAssisted` / `aiAssisted` → `ai_assisted`). TypeScript temsil seçimi de JSON değerini değiştirmez. `status`, `source`, `flag` gibi mevcut alanlar keyfî olarak yeniden adlandırılmaz. Görev durumları, paylaşım kategorileri, sağlayıcılar ve kişisel/diyetisyen program ayrımı için henüz yeni enum veya değer listesi onaylanmamıştır.

## İki Codex için aynı kavramı kullanma ve modülerlik

- Her görevde önce bu sözlük, ilgili `05/06` bölümü ve `12` kararı eşleştirilir. Mevcut kavram bulunduğunda aynı kök ad kullanılır; mobil/web, kişisel/diyetisyen veya manuel/AI/cihaz ayrımı tek başına eşanlamlı entity üretmez.
- Her platform kendi diline uygun modeli tutar; kavram, JSON anahtarları, enum değerleri ve kimlik anlamları ortak kalır. Aynı platformda aynı sözleşmenin kopya modelleri veya farklı alan adlarıyla paralel sürümleri üretilmez.
- Feature-based yapı ve tek sorumluluk ilkesi korunur. Her küçük metot/widget için dosya, her model için gereksiz service/repository/arayüz katmanı veya derin klasör açılması bu sözlüğün gereği değildir. Ortak bileşen/servis gerçek tekrar, sorumluluk veya test ihtiyacı olduğunda çıkarılır.
- Yorum/cevap, bildirim ve PDF raporu gibi kalan özelliklerin ayrı entity gerektirip gerektirmediği bu adlandırma güncellemesiyle belirlenmez. B/R/N ortak onayları başvuru/davet ve program sürüm/alternatif yapısını kapatmıştır; sözlükte olmayan diğer ad/alias için teklif ve ortak onay gerekir.

## Değişiklik yönetimi — kritik

1. Yeni kavram gerekiyorsa mevcut terimin karşılığı mı, gerçek yeni domain kavramı mı kontrol et.
2. Aynı kavramsa **mevcut adı yeniden kullan**. Yeni gerekliyse ad önerisini ekip onayına sun.
3. Onay sonrası **önce bu sözlüğü**, sonra `05`, `06`, etkilenen UI/AI belgelerini **aynı commit** içinde güncelle.
4. API breaking change ise sürüm/taşıma/istemci etkisini yaz ve iki geliştiriciden onay al.
5. İki geliştirici de aynı commit'i çektikten sonra ilgili kod değişikliğine başlasın; diğer Codex'e çelişkili isim üretme görevi verme.

## `05/06` uyum kontrolü ve açık konular

- Mevcut ortak model adları ve enum değerleri korunmuştur. `/users` yalnız eski bir admin önerisidir; `06`da endpoint olarak tanımlı değildir. Bu dosyadaki kaynak adları method, payload veya erişim yetkisi onayı yerine geçmez.
- Tek aktif ilişki/program kuralları onaylıdır; R/N dilimleri DB unique indeksleriyle uygular. Birden fazla aktif diyetisyen veya program gelecekte yeni ürün/sözleşme onayı gerektirir.
- NutritionPlan.dietitianId nullable ve kişisel/atanmış sahiplik N1–N3 ile `05/06`da eşitlendi. Ayrı PersonalPlan modeli üretilmez.
- `Recipe`, `ClientTask` ve `DataSharingPermission` adlarının ayrıntılı veri/API karşılıkları henüz yoktur. `ConsentRecord` tek başına diyetisyen/kategori bazlı erişim yapısını tanımlamaz. Alanlar, ilişkiler, kategori/durum değerleri ve endpointler için öneri ve iki tarafın onayı gerekir.
- Program dışı/makro kişisel hedefler, yorum/cevap/bildirim ve sağlık platformlarının tüm veri türleri için ayrıntılı yapı/adlandırma açıktır. Program alternatif/sürümleri N1–N3, davet/başvuru B/R ile kapandı. ActivityLog sağlayıcı eşlemesi; laboratuvar test kodları/birim dönüşümleri; hibrit katalog kaynağı/lisansı ve model/API sağlayıcısı ayrıca netleştirilmelidir.
