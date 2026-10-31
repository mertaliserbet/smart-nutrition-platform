# 06 — HTTP API ortak sözleşmesi

## 29.10.2026 N1–N3 ortak onaylı program dilimi

Kullanıcı `16` için “N1–N3 için ortak onay var; uygula.” dedi. Normatif
istek/yanıt ve yetki kaynağı aşağıdaki **NutritionPlan — kişisel/atanmış
program sözleşmesi** bölümüdür; eski program şeması açık notları kapanmıştır.
`04/05` aynı değişiklikte güncellenir. Mobil register/JWT gövdeleri değişmez;
Mert yeni program alan/yollarını kullanmadan ortak main sürümünü çeker.

## 29.10.2026 R1–R3 ortak onaylı ilişki/paylaşım dilimi

Kullanıcı `15` R1–R3 için ortak onayı teyit etti. Bu bölüm eski davet/kategori
açık notlarının bu dilimini kapatır; tahlil/diğer sağlık DTO'ları ayrıca
onaylanır. Program DTO'ları N1–N3 bölümündedir. Yollar `/api/v1` tabanına göredir.

| İşlem | Onaylı gövde/yanıt ve sınır |
|---|---|
| `POST /dietitians/me/invitation-code` | Gövde/query yok; doğrulanmış diyetisyen. `200 InvitationCodeResponse { invitationCode, expiresAt }`; 16 büyük Base32, 24 saat, tek kullanım; yeni üretim eskisini iptal eder |
| `POST /dietitian-relationships` | RelationshipRequest'te dietitianId veya invitationCode'dan tam biri; clientId sunucudan. `201 RelationshipResponse`, status pending; mevcut id/clientId/dietitianId/status/requestedAt/respondedAt/endedAt alanları |
| `GET /dietitian-relationships` | Kendi ilişkileri; zorunlu page/pageSize, opsiyonel mevcut status. `200 { items, totalCount }`, requestedAt azalan/id |
| `POST /dietitian-relationships/{relationshipId}/accept` | Gövde/query yok; hedef doğrulanmış diyetisyen. pending→active, respondedAt atanır; ikinci aktif 409; aynı active sonucu tekrar 200 |
| `POST /dietitian-relationships/{relationshipId}/reject` | Gövde/query yok; hedef doğrulanmış diyetisyen. pending→rejected; aynı rejected sonucu tekrar 200 |
| `POST /dietitian-relationships/{relationshipId}/end` | Gövde/query yok; ilişkinin iki tarafı kendi pending/active ilişkisini ended yapar; endedAt atanır. Pending'de respondedAt null; aynı ended tekrar 200. N3 ile aktif ilişki bittiğinde o uzmanın active atanmış programı aynı transaction'da archived olur |
| `GET /data-sharing-permissions` | Zorunlu relationshipId/page/pageSize; iki taraf yalnız kendi ilişki izin durumunu `{ items, totalCount }` içinde okur |
| `GET /data-sharing-permissions/{dataSharingPermissionId}` | Gövde/query yok; kendi ilişkisinin mevcut izin kaydı |
| `POST /data-sharing-permissions` | Mevcut relationshipId/category/isGranted ve nullable consentRecordId. Yalnız danışan, aktif ilişki. category yalnız nutrition_plans, consentRecordId yalnız null. `201` mevcut DataSharingPermission; aynı kategori 409 |
| `PATCH /data-sharing-permissions/{dataSharingPermissionId}` | Zorunlu isGranted; consentRecordId yalnız null/atlanmış. Kimlik/kategori değişmez. Yalnız ilişkinin danışanı ve active ilişki; `200` güncel kayıt |
| `GET /dietitian/clients` | Doğrulanmış diyetisyenin aktif danışanları. page/pageSize zorunlu; opsiyonel query (literal harf duyarsız ad), sortOrder asc/desc (varsayılan asc). `200 { items: ClientListItem[], totalCount }`; item yalnız id/displayName |
| `GET /dietitian/clients/{clientId}/dashboard` | R3'te onaylı minimal ClientDashboardResponse yalnız clientId/displayName. Aktif ilişkisiz 404; sağlık özeti/ölçüm/hedef/sayı eklenmez |

İlişki talebi ve kod üretimi ayrı operation sayaçlarıyla hem hesap hem doğrudan
IP başına dakikada 5 (Relationships:Limits:RequestsPerMinute ve
InvitationCodesPerMinute); aşım ortak 429. Proxy başlığı güvenilir sayılmaz;
çok örnekli ortak sayaç üretim kapısıdır. Hatalı/bilinmeyen/bitmiş/tüketilmiş
kod aynı 422; kod kırpılıp büyük harfe normalize edilir. Kod ile birlikte ID
veya clientId/rol gibi ek girdi 400. İlişki talebi ve izin JSON gövdeleri 4096 byte.

Farklı uzmanlara pending talepler olabilir; aynı çiftte ikinci pending veya
aktif ilişkisi olan danışanın yeni talebi 409. Kabul ikinci aktif ilişki
yaratamaz; diğer pending kayıtlar sessizce değiştirilmez. Geçersiz durum
geçişi 409; yabancı ilişki/kayıt 404; kendi kaydında yanlış işlem rolü 403.
İzin yazması pending/ended ilişkide 409; başka kategori veya dolu consentRecordId
422. Eksik/gönderilemeyen query/gövde/ID biçimi 400; 413/415 ortak kurallardır.

Bu kaynaklar JWT veya W2 cookie kullanır; Admin yetkisi yoktur. Cookie
yazmasında CSRF/Origin/HTTPS, çift kimlikte 400 uygulanır. User → profil
kimliği, güncel e-posta/rol ve uzman doğrulaması sunucuda kontrol edilir.
Liste sayısı yalnız kendi yetkili kümesidir; temel danışan kimlik görünümü
diğer sağlık kategorilerinin izni sayılmaz. Program erişimi ayrıca aktif
ilişki + nutrition_plans izni ister; kayıt yoksa kapalıdır. Danışan kendi
verisini okumak için diyetisyen ilişkisine ihtiyaç duymaz.

## 29.10.2026 B1–B3 ortak onaylı uzman/Admin dilimi

Kullanıcı `14`teki B1–B3 kararlarını “Ortak onay var devam et.” ile teyit etti.
Bu bölüm, aşağıdaki eski başvuru/MFA açık notları ve Admin cookie yasağı için
bu dilimin güncel normatif istisnasıdır; diğer açık şemalar onaylanmamıştır.

| Method + route | İstek | Başarı / yetki |
|---|---|---|
| `POST /api/v1/dietitians/apply` | JSON DietitianApplicationRequest: zorunlu email/password/displayName/licenseInfo, ek alan yok; oturumsuz, query yok; 16 KiB | `201 RegisterUserResponse { id }` User UUID. Yalnız dietitian/henüz doğrulanmamış hesap ve profil atomik oluşur. İstemci role/isVerified atayamaz |
| `GET /api/v1/dietitians/me` | Gövde/query yok; kendi dietitian JWT veya W2 cookie | `200 DietitianStatusResponse { id, displayName, isVerified }`; profil yoksa 404. id uzman profil UUID'si; özel licenseInfo dönmez |
| `GET /api/v1/dietitians` | Public; zorunlu page/pageSize pozitif integer; opsiyonel query, ada göre harf duyarsız literal arama | `200 { items: DietitianListItem[], totalCount }`; item yalnız id/displayName. Hem e-posta hem uzman doğrulaması gerekir |
| `POST /api/v1/auth/admin-web-session` | JSON AdminLoginRequest: zorunlu email/password/mfaCode, ek alan/query yok; 4096 byte; W2 CSRF/Origin/HTTPS | `200 CurrentUserResponse`; role=admin, displayName profil yoksa null. Cookie yalnız MFA tüketimi ve oturum commit'inden sonra verilir; JWT/secret yok |
| `GET /api/v1/admin/dietitians` | Zorunlu isVerified boolean, page/pageSize pozitif integer; başka query/gövde yok; yalnız MFA Admin cookie | `200 { items: DietitianReviewItem[], totalCount }`; item id/displayName/licenseInfo/isVerified; sağlık kaydı yok |
| `POST /api/v1/admin/dietitians/{dietitianId}/verify` | Gövde/query yok; MFA Admin cookie + W2 CSRF/Origin/HTTPS | `200 DietitianStatusResponse { id, displayName, isVerified: true }`; tekrar aynı sonuç/tek audit; bilinmeyen profil 404; e-postası doğrulanmamış uzman 409 |

Ad ve mesleki açıklama dış boşlukları kırpılır; sınırlar `05`tedir. Mevcut
8–128 Unicode parola politikası korunur. Eksik/yanlış tip/boş zorunlu alan,
ek alan veya query ihlali 400; parola politikası ve ad/açıklama uzunluğu 422;
mükerrer e-posta 409, gövde aşımı 413, yanlış medya 415; ortak hata zarfı ve
no-store geçerlidir. Başvuru IP başına dakikada 5 (Dietitians:Application:
RequestsPerMinute) ile sınırlıdır. `201` e-posta teslimi/oturum/uzman onayı değildir.

Liste varsayılanı/ürün üst sınırı halen açık olduğundan bu iki liste page ve
pageSize'ı açıkça ister; eksik/sıfır/negatif veya int32 offset taşması 400.
Web inceleme sayfası pageSize=10 gönderir; bu bir sunucu varsayılanı değildir.
Sıra displayName, ardından id; totalCount yetkili/filtrelenmiş kümeye aittir.

Admin TOTP 6 hane/30 saniye/±1 adım; kullanılan adım tekrar kabul edilmez.
Alternatif 10 kurtarma kodu kriptografik rastgele 128 bit/32 büyük hex hane,
tek kullanımlıdır; yalnız hash saklanır. Kod kırpılır; parola aynen korunur.
Yanlış parola/MFA veya uygun olmayan hesap aynı 401; login IP sayacı normal
web/JWT girişle ortaktır. Mevcut geçerli cookie ile yeniden giriş 409.

Admin yalnız yeni MFA cookie yoluyla kabul edilir. Mevcut JWT login/bearer ve
normal web-session Admin'e kapalıdır. auth/me, csrf, web logout MFA Admin'i
kabul eder; cookie süreleri/DB kontrolü/iptal W2 ile aynıdır. auth/me beş alanı
korunur; Admin rolü MFA cookie bağlamında yeni izinli değerdir. Admin yolları
Authorization kabul etmez (400); kaynakta eksik oturum 401, yanlış rol 403.
Her Admin yazmasında güncel DB yetkisi ve CSRF yeniden denetlenir. Bu dilim
diğer sağlık API'lerine cookie yetkisi veya Admin sağlık erişimi vermez.

İlk Admin ve MFA yenilemesi yalnız yerel `--initialize-admin` komutudur;
public kurulum/kurtarma endpointi yoktur. Ayrıntı `backend/README.md`dedir.
Mevcut Admin yenilemesinde güncel parola gerekir, tüm web oturumları aynı
transaction'da iptal edilir. Ret/yeniden başvuru/doğrulamayı geri alma açıktır.

> **İki Codex için ortak kaynak.** URL, request/response anahtarları, rol ve anlamlar burada değiştirilmeden kullanılacak. Bu bir **taslak V1 sözleşmesidir**; `12_TEAM_PLAN_AND_DECISIONS.md` içindeki 22 onaylı karar ile güncel `04/05` esas alınır. Teknoloji ve ürün kararları onaylıdır; açık şema/oturum ayrıntıları ayrıca ortak onay gerektirir.

Mevcut method/route çiftleri korunur; eksik işlemler aynı kaynaklara eklenir. **AÇIK ŞEMA** olarak işaretlenen işlemler yalnız HTTP yönünü/bağımlılığını tanımlar: eksik DTO, enum veya kimlik yapısı kesinleşmeden uygulanmış sözleşme veya hazır mock sayılmaz. Yeni entity adı, alternatif model ya da sırf ekran başına endpoint üretilmez.

## Temel prensipler

- Base path: `/api/v1`. JSON `camelCase`; enum değerleri `04_NAMING_CONVENTIONS.md` içindeki lowercase değerler.
- İç `id`/FK alanları UUID string; zaman UTC ISO 8601 ör. `2026-10-15T12:30:00Z`, tarihler `YYYY-MM-DD`. `externalRecordId` sağlayıcının string kimliğidir, UUID olmak zorunda değildir. Decimal değerler JSON number, boolean true/false; birimler ve nullability `05`e uyar. Ölçümde `null` bilinmeyen, `0` gerçek sıfırdır.
- Onaylı JWT girişi: 15 dakikalık access token, `Authorization: Bearer <access-token>`. 31.10.2026 kullanıcı göreviyle mobil refresh rotasyonu/iptal eklendi (aşağıda). Web cookie/CSRF/iptal W2-C1–C7 olarak ayrıdır; mobil secure storage/istemci entegrasyonu açık kalır.
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
| Kimlik / web | `GET /api/v1/auth/csrf` | Anonim veya geçerli cookie bağlamında CSRF request tokenı |
| Kimlik / web | `POST /api/v1/auth/web-session` | CSRF/Origin ile korunan web cookie oturumu oluşturma |
| Kimlik / web | `DELETE /api/v1/auth/web-session` | CSRF/Origin ile mevcut web oturumunu sunucuda iptal etme |
| Kimlik / hesap | `GET /api/v1/auth/me` | Geçerli JWT veya web cookie sahibinin beş alanlı kendi hesap özeti |
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

**N1–N3 ortak onaylı ve backend/webde uygulanmıştır.** Yollar `/api/v1`
tabanındadır. JWT veya W2 cookie; yalnız client/dietitian. Admin kapalıdır.
Cookie yazmalarında CSRF/Origin/HTTPS, karışık bearer/cookie'de 400 gerekir.

| İşlem | Request | Response / erişim |
|---|---|---|
| `POST /api/v1/nutrition-plans` | Zorunlu title/startDate/items; nullable endDate/dailyCaloriesTargetKcal/dailyWaterTargetMl. Diyetisyen ayrıca clientId gönderir; danışan clientId (null dahil) ve dietitianId göndermez | `201 NutritionPlanResponse`, Location; draft, versionNumber=1. Kişiselde dietitianId=null, atanmışta oturumdaki uzman profil UUID'si |
| `GET /api/v1/nutrition-plans` | page/pageSize zorunlu; diyetisyende clientId zorunlu. Danışan yalnız kendi kapsamı için page/pageSize gönderir | `200 { items: NutritionPlanResponse[], totalCount }`; createdAt azalan/id. Diyetisyen aktif ilişki + nutrition_plans izniyle kişisel/atanmış tüm programları okur |
| `GET /api/v1/nutrition-plans/{nutritionPlanId}` | Gövdesiz | `200` yetkili program detayı; danışan kendi, diyetisyen yalnız izinli danışanının programını okur |
| `GET /api/v1/nutrition-plans/active` | Gövdesiz; danışanın kendi kapsamı | `200` tek aktif kişisel veya atanmış NutritionPlan; yoksa `404`. Kişisel/atanmış için iki ayrı aktif program yolu yoktur |
| `PATCH /api/v1/nutrition-plans/{nutritionPlanId}` | Yalnız title/startDate/endDate/iki hedef/items. Atlanmış korunur; nullable alan açık null ile temizlenir; title/startDate/items null olamaz. Items verilirse tüm koleksiyon değişir | `200 NutritionPlanResponse`, her geçerli kaydetmede yeni versionId ve artan versionNumber. Güncel item UUID'leri yeniden üretilir; eski snapshot değişmez |
| `POST /api/v1/nutrition-plans/{nutritionPlanId}/activate` | Gövdesiz; aynı düzenleme yetkisi | `200` aktif program. Başka aktif program varsa `409 active_nutrition_plan_conflict`; hedef zaten tek aktif programsa `200`. Tarihleri farklı olsa da iki active program kabul edilmez |
| `POST /api/v1/nutrition-plans/{nutritionPlanId}/archive` | Gövdesiz; aynı düzenleme yetkisi | `200 NutritionPlanResponse`, archived; tekrarda değişmeyen 200. Başka program etkinleşmez. Status işlemleri içerik sürümünü artırmaz |
| `GET /api/v1/nutrition-plans/{nutritionPlanId}/versions` | page/pageSize zorunlu; programla aynı okuma yetkisi | `200 { items: NutritionPlanVersionInfo[], totalCount }`, versionNumber azalan. Metadata id/nutritionPlanId/versionNumber/createdAt |
| `GET /api/v1/nutrition-plans/{nutritionPlanId}/versions/{versionId}` | Gövde/query yok; sürüm mutlaka bu programa ait olmalı | `200 NutritionPlanVersionResponse`: aynı metadata + snapshot. Başka programın sürüm UUID'si 404 |

NutritionPlanResponse eksiksiz alanları: id/clientId/dietitianId/title/status/
startDate/endDate/dailyCaloriesTargetKcal/dailyWaterTargetMl/createdAt/items/
versionId/versionNumber. Nullable alanlar yanıtta atlanmaz. DietitianId
User değil DietitianProfile kimliğidir. title kırpılmış 1–120; hedefler null
veya pozitif decimal kcal/mL, tarihler date ve endDate >= startDate.

Items 1–100 kalem; request'te zorunlu mealType/description/sortOrder;
nullable dayOfWeek/recommendedQuantity/recipeId/alternativeGroupId atlanabilir.
mealType mevcut enumdur; description kırpılmış 1–2000 Unicode kod noktası;
sortOrder >=0 ve aynı sürümde tek. dayOfWeek ISO 1–7, null her gün;
recommendedQuantity kırpılmış 1–200 metin, boş null. RecipeId ilk dilimde
yalnız null/atlanmış; dolu değer 422. AlternativeGroupId boş olmayan UUID;
aynı grupta aynı gün/mealType'a ait en az iki üye gerekir. Item yanıtı bu
yedi alanı ve sunucunun ürettiği id/nutritionPlanId'yi taşır; bu kimlikler
request'te kabul edilmez. Alternatifler birlikte tüketilecek toplam değildir.

Snapshot yalnız title/startDate/endDate/dailyCaloriesTargetKcal/
dailyWaterTargetMl/items; eski item ve grup kimlikleri korunur. RecordedByUserId
yalnız sunucudadır. Başarılı PATCH birebir tekrar gönderilse bile yeni sürüm
oluşturur; istemci yazmayı otomatik tekrarlamaz. Program+snapshot atomik kaydolur.

Danışan kendi tüm program/geçmişini ilişkisiz okuyabilir; yalnız kişisel
programını düzenler/etkinleştirir/arşivler. Atanmış program salt okunurdur.
Doğrulanmış diyetisyen aktif ilişki + nutrition_plans izniyle okur; yalnız
dietitianId'si kendisi olan programı yazar. Kendi kayıtlarında yanlış sahiplik
403; izin kapalıysa 403; ilişkisiz/başka danışanın kaynağında varlık açıklamayan
404. User/ClientProfile/program kilitleri altında yazmadan önce yetki yeniden
kontrol edilir; izin geri çekme ve ilişki sonlandırmayla yarış serileştirilir.

POST/PATCH JSON gövdesi 128 KiB. Eksik/ek alan, biçim/tip, boş PATCH, request'te
id/status/kimlik değiştirme 400; değer sınırları veya zorunlu alan null 422;
boyut aşımı 413, yanlış medya 415. Liste/sürüm listesi dışında query alınmaz.
Paging ortak sınırları kullanır. Yanıtlar no-store; hata ortak error/requestId
biçiminde, aktif çakışması yalnız `409 active_nutrition_plan_conflict` kodudur.

Etkinleştirme draft/archived→active; arşivleme draft/active→archived olabilir.
İkinci active DB kısmi unique ile de engellenir. Başka aktif program sessizce
arşivlenmez; mevcut sahibi açıkça durdurur. Genel atomik replace/geçiş yolu
bu dilimde açılmaz. Aktif ilişki bittiğinde yalnız o uzmanın o danışana ait
active atanmış programı aynı transaction'da archived olur. Sahiplik/içerik/
geçmiş değişmez; kişisel program etkilenmez, danışan geçmişi okur. Eski uzman
yeni isteklerde erişemez. Makro/programsız hedef ve uyum hesabı açık kalır.

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

## Açık şemaya bağlı yorum ve OCR işlemleri

Bu bölümdeki yollar **önerilen HTTP karşılıklarıdır**; `04/05`te açık olan kanonik alt kayıt adları ve tam DTO'lar onaylanmadan uygulama/mock üretimine dayanak değildir.

| Method + route | İstek/yanıtın bilinen kısmı | Açık karar ve güvence |
|---|---|---|
| `GET /api/v1/meal-logs/{mealLogId}/comments` | Pagination; `200 { items, totalCount }`. Yorum alan önerisi `05`teki `id`, `mealLogId`, `authorUserId`, `text`, `createdAt`, nullable `parentCommentId` | Danışan kendi öğünü; diyetisyen aktif ilişki ve öğün/yorum için uygun kategori izniyle. Kanonik yorum modeli/yanıtının nihai onayı beklenir |
| `POST /api/v1/meal-logs/{mealLogId}/comments` | Önerilen gövde `text`, nullable `parentCommentId`; yazar auth'tan. Onay sonrası `201` yorum | Cevap için aynı POST önerilir; ayrı REST yolu varsayılmaz, kalıcı yorum/cevap modeli `04/05` onayına bağlıdır. Başka öğünün ebeveyni `422/404`; döngü kurulamaz. Cevap derinliği ve moderasyon açık; düzenleme/silme yolları henüz eklenmez |
| `POST /api/v1/lab-reports/ocr` | Önerilen yükleme: multipart `document` dosyası (PDF/fotoğraf); danışanın kendi kapsamı | Kabul edilen dosya tür/limitleri, senkron/asenkron iş, OCR taslak/id/durum/response yapısı ve onay kaydı AÇIK ŞEMA. Bunlar seçilmeden `200/202`, jobId veya yeni durum enumu kesinleştirilmez |

OCR yalnız taslak çıkarır; tamamlanmış LabReport veya klinik değerlendirme üretmez. Kullanıcı test/değer/birim/tarih/referansı kontrol edip düzeltir ve açıkça onayladıktan sonra mevcut `POST /lab-reports` gövdesiyle doğrulanmış kayıt oluşturulur. OCR işi tamamlandı diye otomatik POST/insight tetiklenmez. Kullanıcı onayının sunucuda kanıtlanacağı tasarım açık olduğundan yeni `isConfirmed`/`ocrJobId` alanı bu belgede uydurulmaz. Dosya yükleme hataları `413/415`, yetki hataları ortak kurallara uyar.

### LabInsight işlemleri

`POST /lab-reports/{labReportId}/insights` yalnız kaydın danışanı veya aktif ilişki + ilgili kategori + tahlil açık onayı olan diyetisyen içindir; istek gövdesizdir. Başarı hedefi `201` LabInsight; GET aynı kaynağın yetkili analizlerini ortak liste zarfıyla döndürür. Kesin alanlar `id`, `labReportId`, `createdAt`, `summary`, `method`, nullable `modelVersion`; zorunlu `limitations` biçimi ve method değerleri `05`te AÇIK olduğundan tam yanıt henüz onaylı değildir. Asenkron LabInsight işi/status modeli varsayılmaz.

Geçerli birim/referans yoksa açıklama `unknown` ve sınırlılıkları yansıtır; eksik referans tamamlanmış gibi tahmin edilmez. Metin tanı/tedavi önermez; doğrulanabilir ML opsiyoneldir. Tahlil paylaşım onayı yokluğu diyetisyeni engeller; danışanın kendi manuel kaydını okumasını engellemez. AI sağlayıcısına aktarım için ayrı gereken izinler `11`e göre ayrıca kontrol edilir.

## Kimlik, profil ve ilişki işlemlerinin sınırları

- `POST /auth/register` için aşağıdaki danışan kayıt şeması onaylıdır. Public kayıt Admin/Diyetisyen rolü veya doğrulanmış uzman yetkisi vermez; diyetisyen başvurusunu Admin doğrular. Çoklu rol ve diğer profil sözleşmeleri ayrıca açıktır.
- `POST /auth/login`: aşağıdaki JWT giriş şeması onaylıdır. Doğrulanmamış hesaba veya Admin'e bearer token verilmez. Mobil refresh/logout sözleşmesi 31.10.2026 bölümündedir; web ayrı W2 cookie kaynağını kullanır. Mobil MFA challenge gövdeleri açık kalır.
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
| `POST /api/v1/auth/login` | `LoginUserRequest`: `{ "email": "synthetic@example.test", "password": "<parola>" }`. İki alan zorunlu string; rol/kimlik veya başka alan alınmaz | `200` `LoginUserResponse`: `{ "accessToken": "<JWT>", "tokenType": "Bearer", "expiresAt": "<UTC ISO 8601>", "refreshToken": "<opak token>", "refreshTokenExpiresAt": "<UTC ISO 8601>" }`. Refresh alanları 31.10.2026 görevinde eklendi. Bulunmayan hesap, yanlış parola, doğrulanmamış e-posta ve Admin için aynı genel `401 unauthenticated`. Şekil/eksik/boş girdi, geçersiz e-posta veya ek alan `400 invalid_request`; hız sınırı `429 rate_limited` |

- Login mevcut Identity normalizer ile e-postayı kırpar/normalleştirir ve Identity PasswordHasher ile parolayı doğrular. Parola aynen korunur; girişte yeni kayıt karmaşıklığı/minimumu yeniden uygulanmaz. Hesap bulunmadığında da Identity parola hash doğrulaması yapılır; sahte User/oturum oluşturulmaz. Başarısızlık yanıtları hesap/doğrulama/MFA ayrımı veya gizli veri içermez.
- Başarı yalnız `client`/`dietitian` ve `isEmailVerified = true` hesaplar içindir. Admin'e token verilmez; middleware imzası geçerli olsa dahi `admin` rolünü kabul etmez. Diyetisyen rolü tek başına uzman doğrulaması veya sağlık kaydı yetkisi değildir; ilgili kaynaklarda `05/11` kontrolleri ayrıca gerekir.
- JWT **15 dakika** geçerlidir. `sub: string` mevcut User UUID'si, `role: string` kanonik roldür; ayrıca `iss`, `aud`, `iat`, `nbf`, `exp` standart claim'leri vardır. E-posta, ad, profil/sağlık verisi, hash veya secret claim'i yoktur. `expiresAt`, tokenın imzalı `exp` değeriyle aynı UTC anıdır; istemci claim çözümleyerek yetki vermez.
- Token `HS256` ile imzalanır, türü `at+jwt`dir. İmzalama anahtarı (Base64, en az 32 kriptografik rastgele byte), issuer ve audience environment/User Secrets'tan alınır; eksik/hatalı yapılandırmada API başlamaz. Token/API yanıtı loglanmaz. Access token DB'ye yazılmaz.
- ASP.NET Core JWT authentication/authorization middleware imza, izinli algoritma/tür, tam issuer/audience, zorunlu expiry ve zaman aralığını doğrular. `ClockSkew = 0`; varsayılan ek beş dakika tanınmaz. Yetkili kaynaklar `[Authorize]`/uygun kaynak politikalarını uygular. Kimlik `sub`dan alınır; User UUID'si ClientProfile UUID'si sayılmaz.
- Yetki isteyen bir kaynağa eksik/geçersiz/süresi dolmuş token `401 unauthenticated`, geçerli kimlikle eksik rol/kaynak yetkisi `403 forbidden` olur. `WWW-Authenticate: Bearer` iç doğrulama ayrıntısı taşımaz; ortak hata zarfı korunur. Login ve auth hata yanıtları `Cache-Control: no-store` kullanır. Kimlik/rol deneme yolları yalnız test host'undadır; yeni genel API kaynağı eklenmez.
- Login varsayılan limiti doğrudan bağlantı IP'si başına **dakikada 10 istek**tir (`Auth:Login:RequestsPerMinute`); hesap varlığından bağımsız ve API süreci içinde uygulanır. Çok örnekli ortak limit/proxy ve hesap bazlı saldırı kontrolleri ayrıca değerlendirilir; kalıcı hesap kilidi bu görevde eklenmez. Gövde sınırı 4096 byte: `413 payload_too_large`; yanlış içerik türü `415 unsupported_media_type`; beklenmeyen hata `500 internal_error`.
- 27.10 JWT diliminde refresh/logout yoktu; 31.10.2026 görevi aşağıdaki hash rotasyonunu ekler. Genel anlık access JWT iptali, mobil MFA ve parola sıfırlama sağlanmaz. Mevcut JWT, geçerli imza ve süresi boyunca kullanılabilir; kendi hesap okumasındaki aşağıdaki DB kontrolü tüm API için oturum iptali sayılmaz.

### Mobil refresh rotasyonu ve çıkış — 31.10.2026

Bu bölüm kullanıcının backend refresh/iptal göreviyle eklenmiştir. Login isteği,
JWT claim'leri/HS256/at+jwt/issuer/audience/sıfır clock skew ve 15 dakika korunur.
Login yanıtına iki alan eklenmesi **mevcut Flutter'ın tam üç alan bekleyen
ayrıştırıcısı için uyumsuzdur**. Mobil/web kodu bu görevde değiştirilmez;
Flutter entegrasyonu aynı sözleşme sürümüyle ayrıca güncellenmeden eski giriş
akışı bu yanıtı kabul etmez. Web cookie/Admin MFA yanıtları etkilenmez.

| İşlem | İstek | Başarı / hata |
|---|---|---|
| `POST /api/v1/auth/refresh` | `RefreshTokenRequest`: yalnız `{ "refreshToken": "<opak token>" }`; oturumsuz JSON, Authorization/cookie/query yok | `200` yukarıdaki beş alanlı `LoginUserResponse`. Bulunmayan/yanlış biçimli/süresi dolmuş/iptal edilmiş/tüketilmiş token veya uygun olmayan hesap aynı `401 unauthenticated` |
| `POST /api/v1/auth/logout` | Aynı `RefreshTokenRequest`; Authorization/cookie/query yok | Boş `204`. Bilinen tokenın tüm ailesi iptal edilir; tüketilmiş eski aile tokenı da iptal için kullanılabilir. Bilinmeyen/yanlış biçimli/önceden iptal edilmiş tokenla da aynı idempotent `204`; bu bir yenileme/giriş başarısı değildir |

- Refresh CSPRNG ile 32 byte (256 bit), 43 karakter Base64URL üretilir. Sır
  yalnız login/refresh yanıtında ve geçici işlem belleğindedir; DB'ye yalnız
  SHA-256 hash ve `05`teki metadata yazılır. Gövde/yanıt/Authorization/token
  loglanmaz. Tokenın içinden User/rol veya aile bilgisi türetilmez.
- Aile başına mutlak süre `Auth:RefreshTokens:LifetimeDays` ile 1–365 gün,
  varsayılan **30 gün**dür. Her rotasyonda yeni refresh token üretilir; ailenin
  `refreshTokenExpiresAt` değeri uzamaz. Tam bitiş anı geçersizdir.
- Login, güncel parola hash/rol/e-posta durumunu User satır kilidinde yeniden
  kontrol eder. Refresh de aynı kilidi alıp güncel doğrulanmış client/dietitian
  ve giriş rolünü denetler; Admin veya rol/doğrulama değişiminde aileyi iptal eder.
  Tüketme, yeni hash ve commit atomiktir; DB hatasında eski tüketim de geri alınır.
- Tüketilmiş herhangi bir ata tokenın tekrar kullanımı aynı ailedeki tüm
  refresh tokenları iptal eder; bağımsız girişler etkilenmez. Çalıntı tokenın
  ilk kullanımını meşru kullanımdan ayırt etmek mümkün değildir; iki tarafın
  yeniden kullanımıyla ihlal saptanır. Sessiz grace/replay kabulü yoktur.
- Flutter yenilemeyi **tek eşzamanlı işlem** olarak yürütmeli ve access/refresh
  çiftini birlikte değiştirmelidir. Eşzamanlı aynı-token yenilemesinde en fazla
  biri `200` alır, diğeri replay sayılıp kazananın ailesini de iptal eder.
  Kaybolan başarılı yanıtı eski tokenla otomatik tekrarlamak aynı sonuca yol açar;
  böyle bir belirsizlikte yeniden giriş gerekir.
- Logout/refresh aynı kilitle serileştirilir; logout döndükten sonra aileden
  yeni yenileme yapılamaz. Önceden üretilmiş **access JWT anında iptal edilmez**;
  en fazla kalan 15 dakikası boyunca JWT kabul eden kaynaklarda kullanılabilir.
  JWT denylist/sid veya web cookie iptali eklenmemiştir.
- Eksik/null/boş alan, bozuk JSON/yanlış tip/ek alan veya auth/cookie/query
  `400 invalid_request`; JSON olmayan içerik `415`; 4096 byte üstü `413`;
  ayrı bağlantı IP sayaçlarında refresh/logout için varsayılan 30/dakika
  (`Auth:RefreshTokens:RequestsPerMinute`) aşımı `429`; altyapı hatası `500`.
  Ortak hata zarfı ve tüm yanıtlarda `no-store` korunur. Sayaçlar süreç içidir;
  çok örnekli dağıtım/güvenilir proxy koruması ayrıca hazırlanır.
- Yalnız mutlak süresi bitmiş hash geçmişi on dakikada bir temizlenir. Süresi
  dolmayan tüketilmiş/iptal edilmiş aile geçmişi replay tespiti için korunur.
  Güvenli mobil saklama, istemci yenileme koordinasyonu ve gelecekteki parola
  değişikliklerinde tüm ailelerin iptali sonraki entegrasyon sorumluluklarıdır.

### Onaylı kendi hesap endpointi — 27.10.2026

| İşlem | Request | Response / hata |
|---|---|---|
| `GET /api/v1/auth/me` | Geçerli JWT bearer veya W2 web cookie. Gövde/query parametresi yok; `userId` alınmaz | `200 CurrentUserResponse`: yalnız `id: uuid`, `displayName: string?`, `email: string`, `role: UserRole`, `isEmailVerified: boolean`. Anahtarların beşi de daima vardır. Desteklenmeyen query/gövde `400 invalid_request`; eksik/geçersiz/süresi dolmuş token veya geçersiz mevcut hesap `401 unauthenticated`; beklenmeyen sunucu/DB hatası `500 internal_error` |

- Endpoint JWT bearer veya aşağıdaki onaylı web cookie authentication ile erişilir. Kimlik, middleware'in doğruladığı tek `sub` claim'indeki User UUID'sidir; istemci kimliği, özel başlık, profil UUID'si veya URL'deki başka ID ile seçilmez. İki kimlik birlikte gönderilmez.
- User ve varsa kendi ClientProfile'ı yalnız gerekli alanlarla salt okunur sorgulanır. `displayName` profil yoksa açık `null` olur; `client`/`dietitian` için aynı yanıt kullanılır. E-posta ve ad tokena eklenmez, DB'den güncel alınır. User/ClientProfile entity'si, hash, token, güvenlik metadata'sı, `createdAt`/`updatedAt`, sağlık verisi veya iç içe profil dönmez.
- Süre bitmemiş olsa dahi User DB'de yoksa, e-posta doğrulaması kalkmışsa veya güncel rol kimliğin izinli rolüyle eşleşmiyorsa aynı genel `401` döner; JWT modunda `WWW-Authenticate: Bearer` korunur. Hesap durumu hata metnine eklenmez. Admin MFA engeli değişmez.
- Yanıt `Cache-Control: no-store` kullanır. User/profil/parola/token alanları değişmez; W2 cookie modunda yalnız başarılı isteğin AuthSession idle süresi ilerler. Genel JWT iptali eklenmez. Kayıt/JWT giriş yanıtları değişmez; profil düzenleme/uzman profili açıktır.

### Henüz uygulanmamış kimlik işlemleri

| İşlem | Request | Response / sınır |
|---|---|---|
| `POST /api/v1/auth/password-reset-requests` | `email: string` | `202`, gövdesiz; hesabın varlığını açıklamayan aynı sonuç. Bildirim servisi, limit/süre ayrıntıları **AÇIK**tır |
| `POST /api/v1/auth/reset-password` | `token: string`, `password: string` | `204`; geçersiz/süresi dolmuş token veya parola kuralı `422`. Sıfırlama tokenı/akışı ve mevcut oturumların iptal ayrıntısı **AÇIK**tır; kayıt parola politikası yukarıda onaylıdır |

Bu token/password alanları yalnız HTTP kimlik girdileridir; User modeline düz metin secret alanı eklemez. Admin MFA doğrulama/kurulum/kurtarma ve diyetisyen başvuru/doğrulama endpointlerinin gövdeleri ilgili güvenlik/başvuru şeması tamamlanınca tanımlanır; sağlık verisi yetkisiyle karıştırılmaz.

### Onaylı web cookie oturumu — W2-C1–C7 (27.10.2026)

Kullanıcı iki tarafın ortak onayını teyit etmiştir. Mevcut JWT login yolu,
15 dakikalık süresi ve claim'leri korunur; login yanıtı 31.10.2026'da yukarıdaki
refresh alanlarıyla genişletildi. JWT login cookie üretmez.
Web akışı ayrı kaynak kullanır; JWT login'i çağırmaz, refresh token üretmez.

| Method + route | İstek | Yanıt |
|---|---|---|
| `GET /api/v1/auth/csrf` | Gövde/query yok; mevcut geçerli cookie veya anonim bağlam | `200 CsrfTokenResponse { requestToken: string }`; framework CSRF cookie'si hazırlanır, hesap/oturum ID'si dönmez |
| `POST /api/v1/auth/web-session` | Mevcut `LoginUserRequest { email, password }`; JSON; query yok; CSRF cookie + `X-CSRF-TOKEN`, tam Origin | Auth istisnası `200 CurrentUserResponse`: yalnız id/displayName/email/role/isEmailVerified; oturum commit'inden sonra korumalı cookie; Location/JWT/refresh/sid yok |
| `GET /api/v1/auth/me` | Gövde/query yok; JWT veya web cookie | Mevcut beş alanlı `200 CurrentUserResponse` aynen korunur; opsiyonel profil adı null olabilir |
| `DELETE /api/v1/auth/web-session` | Gövde/query yok; CSRF cookie + `X-CSRF-TOKEN`, tam Origin; yalnız mevcut cookie | DB iptalinden sonra boş `204`; auth ve CSRF cookie'leri temizlenir. Olmayan/bozuk/bitmiş/iptal edilmiş oturumda da geçerli CSRF/Origin ile `204`; başka oturum etkilenmez |

- Yeni web yollarında Authorization kabul edilmez (`400`). Hesap okumasında
  Authorization ve auth cookie birlikteyse `400`; başarısız kimlikten diğerine
  düşülmez. Geçerli web oturumuyla yeniden login `409 conflict`tir. Bozuk cookie
  kimlik sayılmaz; anonim CSRF ile yeniden giriş yapılabilir. Olmayan hesap,
  yanlış parola, doğrulanmamış e-posta ve Admin aynı genel `401`i alır.
- Web/API aynı HTTPS origin'dedir. Cookie'ler Secure/HttpOnly/SameSite=Strict,
  Path=/, Domain'sizdir: `__Host-smart-nutrition-session` ve
  `__Host-smart-nutrition-csrf`. Auth cookie tarayıcı oturum cookie'sidir;
  Expires/Max-Age ve beni hatırla yoktur. Bilet ASP.NET Core AddCookie/Data
  Protection ile korunur; yalnız tek sub(User UUID), role, sid(AuthSession UUID)
  ve framework zamanlarını taşır. Anahtarlar Git dışında kalıcı/şifreli depoda,
  aynı uygulama adıyla yönetilir; eksik/geçersiz ayar web erişimini kapatır.
- CSRF `IAntiforgery` ile kullanıcıya ve oturum sid'sine bağlanır; aynı User'ın
  yeni oturumu da eski tokenı geçersiz kılar. Girişten sonra yeni token alınır.
  Login/logout ve ileride cookie yetkisi kazanan yazmalar iş kuralından önce
  CSRF ister. Yazmada Origin tek yapılandırılmış HTTPS scheme/host/port ile tam
  eşleşir; eksik/null/farklı Origin `403`. CSRF GET'inde varsa Origin aynı kurala
  uyar; Sec-Fetch-Site cross-site `403`. Geçersiz/eksik CSRF `400`; ham ayrıntı
  dönmez. Credential CORS açılmaz. Mevcut diğer API yolları cookie yetkisi kazanmaz.
- Her cookie isteği DB'de revokedAt=null, now<idleExpiresAt, now<absoluteExpiresAt,
  doğru User/FK, güncel doğrulanmış e-posta ve aynı client/dietitian rolünü denetler.
  Admin kabul edilmez. DB hatası genel `500`, erişim kapalıdır; olumlu sonuç önbelleği yoktur.
  Başlangıç idle 30 dakika, mutlak süre 8 saattir. Başarılı yetkili hesap okuması
  idle'ı min(now+30 dakika,absoluteExpiresAt) sınırında atomik ilerletir; CSRF,
  statik dosya, sağlık kontrolü, başarısız istek veya keepalive polling'i uzatmaz.
  Bilet mutlak sınıra kadar geçerlidir; DB idle kontrolü her istekte zorunludur.
- Logout iptalini eski uzatma silemez. Login doğruladığı User hash/rol/doğrulama
  durumunu aynı User satır kilidinde yeniden denetler; yarışta `401`, cookie yoktur.
  Gelecekteki güvenlik yazmaları aynı kilit/transaction içinde tüm web oturumlarını
  iptal eder. Rehash gerçek parola değişikliği sayılmaz. İptalden önce yetkili
  istek tamamlanabilir. Web çıkışı mevcut stateless JWT'yi iptal etmez; mobil
  mobil refresh/iptal 31.10.2026 bölümündedir; mobil MFA ayrı açık kapsamdır.
- Tüm yanıtlar no-store ve ortak hata zarfını kullanır; HTML/302 yönlendirmesi yoktur.
  Yanlış JSON içerik `415`; ek/eksik/boş alan veya query/gövde ihlali `400`;
  4096 byte login aşımı `413`; IP aşımı `429`; altyapı hatası `500`dür.
  Web/JWT login aynı IP başına dakikada 10 istek sayacını paylaşır; CSRF GET
  ayrı dakikada 30 istek sınırını kullanır; ikisi yapılandırılabilir.
  Proxy başlığı keyfî güvenilir sayılmaz; çok örnekli ortak sayaç yayın kapısıdır.
- Web credentials=same-origin kullanır; hesap özeti/CSRF yalnız geçici sayfa
  belleğinde tutulur. Hesap ekranı yenilenince CSRF ve GET me ile yeniden okunur;
  token/hesap cookie'si JS depolama/URL/loga yazılmaz. 401 ve çıkış hassas UI'yi
  temizler; geç yanıtlar eski hesabı geri getiremez. CSRF/hesap değişiminde yazma
  otomatik tekrarlanmaz. Çıkış yalnız 204 ile doğrulanır; ağ/500 hatasında
  “Çıkış sunucuda doğrulanamadı; tekrar deneyin” gösterilir. E-posta işlemleri
  oturum oluşturmaz/uzatmaz; mobil bearer'a CSRF eklenmez.

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

- Yorum ad/veri yapıları, tarif bileşenleri/görünürlük/geçmişi, görev durum/geçiş/son tarih/hatırlatma ve nutrition_plans dışı kategori kodları açık kalır. N1–N3 program sürüm/alternatif DTO'su bu listeden çıkarılmıştır.
- Genel atomik program replace/geçişi, programsız kişisel hedefler, makro hedef alanları, program uyum hesabı ve yerel gün/saat dilimi politikası açıktır. N1–N3 arşivleme ve aktif ilişki bitişinde atanmışı arşivleme onaylıdır.
- OCR dosya kabul limitleri, taslak/iş kimliği ve onay kanıtı; LabInsight method/limitations biçimi ve değişen tahlilde eski analizlerin gösterimi açıktır. FoodAnalysis HTTP limitations kökte korunmuştur; `05/10` açıklamaları bu yerleşimle eşitlenmelidir.
- Cihaz sync request/response, provider/durum kodları, adım/nabız/aktif enerji modelleri, kararlı kimliği olmayan kaynak, manuel/cihaz örtüşmesi, yeniden aktarım ve kullanıcı düzeltmesinin önceliği açıktır; yeni genel ölçüm veya AI job modeli türetilmez.
- Mobil güvenli saklama/istemci refresh entegrasyonu ve mobil MFA, profil düzenleme/uzman profili ve sıfırlama açık kalır. Backend mobil refresh/iptal 31.10.2026 bölümünde uygulanmıştır; kayıt/e-posta doğrulama, JWT giriş/hesap özeti ve W2 web cookie/CSRF/iptal korunur. Başvuru, web Admin MFA, ilişki/davet ve programlar için üstteki tarihli ortak sözleşmeler geçerlidir.
- İlk sürüm yorum/cevap bildirimleri ve diyetisyen PDF raporları onaylı kapsamdır; bildirim/rapor DTO, teslim/dosya yetkilendirmesi ve moderasyon ayrıntıları açık olduğundan bu görevde tahminî yollar açılmaz. İzin dışı veri export edilmez. KVKK, silme, saklama ve audit için `11` kapısı korunur.
- Sayısal hassasiyet/yuvarlama, metin/dosya/pagination limitleri, tekrar denemelerde idempotency ve güvenli silme ayrıntıları ortak onay bekler. Mevcut enumlar ve model adları değişmez.

Kayıt/e-posta doğrulama/JWT giriş/kendi hesap özeti ayrıntıları `04/05/11/12` ile eşgüdümlüdür. Diğer açık şema parçaları iki geliştiricinin onayıyla `04/05/06` ve OpenAPI/istemci tiplerinde birlikte tamamlanmalıdır; bu görev mobil/web entegrasyonu içermez.
