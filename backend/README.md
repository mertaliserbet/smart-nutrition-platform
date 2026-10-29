# Smart Nutrition — Ortak Backend

## Program oluşturma, atama ve sürümler — N1–N3

`docs/16` ortak onayıyla `Features/NutritionPlans/` eklendi. Backend dizininde
`dotnet tool run dotnet-ef database update --project src/SmartNutrition.Api`
komutu `AddNutritionPlansAndVersions` migration'ını uygular. Program ve
değişmeyen sürüm tabloları, nullable uzman FK'si, tek active client indeksi,
sürüm numarası unique ve alan check'leri eklenir; mevcut tablolar silinmez.

Danışan kendi kişisel programını oluşturur/yazar; atanmış programı salt okunur
okur. Doğrulanmış uzman aktif ilişki + nutrition_plans izniyle okur ve yalnız
kendi programını oluşturur/düzenler/etkinleştirir/arşivler. POST draft döner;
atama açık activate çağrısıdır. Başka active program 409 verir; gizli geçiş
yoktur. Her geçerli PATCH yeni snapshot ve item UUID'leri oluşturur; status
değişimi içerik sürümünü artırmaz. Aktif ilişki bitişinde o uzmanın active
programı aynı transaction'da arşivlenir, danışan geçmiş erişimi sürer.

Tam yollar/payload ve mobil null/kimlik kuralları `docs/04/05/06`dadır.
Gün/miktar/alternatifler desteklenir; recipeId bu dilimde yalnız null.
Klinik hedefler otomatik hesaplanmaz. Cookie yazmaları W2 CSRF/Origin ister.
Program yazması, izin geri çekme ve ilişki bitişi ortak ClientProfile kilidi
altında güncel yetkiyle yürür; sunucu kaydeden kimliğini yanıta açmaz.

Doğrulama: geçici PostgreSQL/Mailpit ile **250 test geçti, 0 atlandı**.
Yeni dilimde sahiplik, değişmeyen snapshot, alt kayıt erişimi, tek active
yarışı/DB indeksi, atomik rollback, izin geri çekme ve CSRF test edildi.
Test verileri sentetik ve geçicidir. Flutter entegrasyonu bu görevde yapılmadı.

## İlişki/davet ve ilk paylaşım kategorisi — R1–R3

`docs/15` ortak onayıyla `Features/Relationships/` eklenmiştir. Yeni migration
`AddRelationshipsAndSharingPermissions`, mevcut veriyi silmeden ilişki/izin
tablolarını, tek aktif ve pending çift indekslerini ve uzman davet hash/expiry
alanlarını ekler. Normal `dotnet-ef database update` komutu uygulanır.

Doğrulanmış uzman `/dietitians/me/invitation-code` ile 24 saatlik/tek kullanımlık
kod üretir. Danışan `/dietitian-relationships` ile dietitianId veya bu koddan
tam biriyle pending talep açar; yalnız hedef uzman kabul/red verir. Her iki
taraf kendi pending/active ilişkisini sonlandırabilir. Aktif ilişki yarışı
ClientProfile kilidi ve DB unique indeksiyle korunur; geçmiş silinmez.

İlk kategori `nutrition_plans` varsayılan kapalıdır. Danışan aktif ilişkide
`/data-sharing-permissions` ile izin oluşturur, PATCH ile geri çeker.
Başka kategori ve dolu consentRecordId reddedilir; tahlil onayı veya diğer
sağlık kategorileri açılmaz. Kullanıcı/profil kimliği ve güncel rol/doğrulama
her istekte DB'den kontrol edilir. Cookie yazmaları W2 CSRF/Origin ister;
JWT taşıyan mobil istemciye cookie/CSRF şartı eklenmez.

Gerçek `/dietitian/clients` listesi yalnız id/displayName; dashboard yalnız
clientId/displayName döndürür. Aktif ilişki ve doğrulanmış uzman gerekir;
sağlık özeti veya varsayılan sıfır yoktur. Liste page/pageSize ister; query ve
sortOrder asc/desc destekler. İlişki listesi ayrıca mevcut status filtresi alır.

Talep/kod üretimi hem hesap hem doğrudan IP için 5/dakika; ayrı ayarlar
`Relationships__Limits__RequestsPerMinute` ve `InvitationCodesPerMinute`.
Sayaçlar süreç içidir; çok örnekli dağıtım/proxy, tam izin audit'i ve gerçek
yayın için `docs/11` kapısı korunur. Program içerik/sürüm/atama sonraki N1–N3 diliminde eklendi.

Doğrulama: PostgreSQL/Mailpit ile 240 backend testi geçti, 0 atlandı; kod
rotasyonu/expiry/tek kullanım ve rollback, kabul yarışı, ham DB indeksi,
izin geri çekme/sonlandırma ve cookie CSRF kontrol edildi. Test fabrikası
yalnız kendine ait geçici şema bağlantı havuzunu kapatır; ortak havuza dokunmaz.

## Uzman başvurusu ve Admin MFA — B1–B3 (29.10.2026)

`docs/14` ortak onayıyla `Features/Dietitians/` ve Admin MFA eklenmiştir.
`dotnet tool run dotnet-ef database update --project src/SmartNutrition.Api`
komutu yeni uzman/audit tablolarını ve sunucu MFA alanlarını ekler. Mevcut
hesaplara varsayılan uzman doğrulaması veya MFA yetkisi verilmez.

Webden `/uzman-basvurusu` → e-posta doğrulama → normal giriş →
`/uzman/basvuru-durumu` akışı kullanılır. Admin `/yonetici-giris` üzerinden
TOTP/kurtarma koduyla giriş yapar; `/yonetim/uzmanlar` özel mesleki açıklamayı
listeler ve e-postası doğrulanmış uzmanı onaylar. Onay aynı transaction'da
AuditEvent üretir. Sağlık, ilişki ve program API'leri bu dilimde açılmaz.

İlk Admin ve MFA yenilemesi HTTP endpointi değildir. Backend dizininden,
API ile **aynı DB ve W2 Origin/kalıcı korumalı key ring yapılandırmasıyla**:

```powershell
dotnet run --no-launch-profile --project src/SmartNutrition.Api -- --initialize-admin <ozel-girdi-json-yolu> <yeni-enrollment-json-yolu>
```

Girdi Git dışında, yalnız işletmen hesabının okuyabildiği bir dosyadır;
yalnız `email` ve `password` string alanlarını içerir. Parola mevcut 8–128
Unicode politikasına uyar. Parolayı komut satırı argümanına, terminal çıktısına
veya depoya koymayın. Çıktı yolu da Git dışında olmalı ve mevcut olmamalıdır.
Çıktı yalnız `manualKey`, `otpAuthUri`, `recoveryCodes` içerir; uygulama Windows
dosya ACL'ini yalnız çalıştıran hesaba, Unix modunu 0600'a ayarlar. Yerel
işletmen, anahtarı kendi doğrulayıcısına aktarır ve 10 kurtarma kodunu güvenli
yerde tutar; girdi ve enrollment dosyalarını işlemden sonra kaldırır.

Başarı çıkış kodu 0, başarısızlık 1'dir; sırlı içerik/hata ayrıntısı yazdırılmaz.
Mevcut çıktı üzerine yazılmaz ve başka role ait hesap Admin'e dönüştürülmez.
Mevcut Admin için aynı komut güncel parolayı doğrular, MFA'yı yeniler ve tüm
web oturumlarını aynı transaction'da iptal eder. Eski TOTP/kurtarma kodları
geçersizleşir. Yanlış parola, yapılandırma veya dosya hatası DB değişikliğini
geri alır. İlk kurulum işletmeninin sunucuya yerel erişimi güven sınırıdır.

MFA Otp.NET 1.4.1 kullanır: [resmî kaynak](https://github.com/kspearrin/Otp.NET).
6 hane/30 saniye/±1 adım ve kullanılmış adımın DB'de tekrar reddi uygulanır.
Kurtarma kodu 128 bit/32 büyük hex hane; yalnız hash saklanır. Mevcut JWT ve
normal W2 login Admin'e kapalı kalır. Admin cookie'si DB'deki MFA kanıtı ve
güncel rol/doğrulama/süre/iptal ile her istekte kontrol edilir.

Başvuru limiti `Dietitians__Application__RequestsPerMinute` (varsayılan 5/IP/dk).
Admin login mevcut JWT/web login sayacını paylaşır. Liste endpointleri açık
varsayılan seçmemek için page/pageSize'ı zorunlu alır; web pageSize=10 gönderir.
Public arama licenseInfo/e-posta/MFA metadata'sını göstermez.

Ret, yeniden başvuru, uzman doğrulamasını geri alma, mobil refresh/iptal ve
parola sıfırlama bu dilimde açık kalır. Gerçek yayın `docs/11` kapısına bağlıdır.

Tek ASP.NET Core Web API projesi ve bir xUnit test projesi. Hedef .NET 10;
oluşturma ortamı SDK 10.0.401. `global.json`, kararlı .NET 10 SDK feature band'lerini
kabul eder. EF Core/araçlar 10.0.12, Npgsql sağlayıcısı 10.0.3 olarak sabitlendi.

`POST /api/v1/auth/register` ile User ve ClientProfile PostgreSQL'e kaydedilir;
doğrulama e-postası SMTP üzerinden arka planda gönderilir. `verify-email` ve
`resend-verification` uçları hazırdır. `login`, doğrulanmış Admin olmayan hesaplara
15 dakikalık JWT access token verir. `GET /api/v1/auth/me` yalnız oturum sahibinin
kendi hesap özetini döndürür. W2 web çıkışı ve B1–B3 Admin MFA/onayı vardır;
mobil refresh/iptal ve parola sıfırlama açık kalır. `MealLog` ve
`MealLogItem` doğrulanan C# modelleri olarak hazırdır; DbContext'e bağlanmamıştır.
Kayıt/e-posta doğrulama/JWT giriş/kendi hesap özeti şemaları ortak `04/05/06/11/12` belgeleriyle eşgüdümlüdür.

## Yapı

- `src/SmartNutrition.Api/Program.cs`: servisler, JSON/hata kuralları ve HTTP pipeline.
- `Data/AppDbContext.cs`: User/ClientProfile eşlemeleri bulunan Npgsql bağlamı.
- `Data/Migrations/`: Auth tabloları ve e-postada harf duyarsız benzersizlik migration'ları.
- `Health/PostgresHealthCheck.cs`: veritabanı erişimini değiştirmeden kontrol eder.
- `Infrastructure/ApiErrors.cs`: `error: { code, message }, requestId` hata zarfı.
- `tests/SmartNutrition.Api.Tests/`: gerçek uygulama host'u ile altyapı testleri.
- `.config/dotnet-tools.json`: projeye özel `dotnet-ef`; global kurulum gerekmez.
- `compose.yaml`: yalnız yerel geliştirme için PostgreSQL 17 ve Mailpit SMTP.
- `Features/MealLogs/`: MealLog/MealLogItem alanları, yerel bütünlük kuralları ve MealType.
- `Features/Auth/`: User/ClientProfile, EF eşlemeleri, kayıt/e-posta doğrulama/giriş servisleri ve JWT yapılandırması.
- `Models/UserRole.cs`: mevcut `client`, `dietitian`, `admin` değerleri.
- `Models/RecordSource.cs`: ortak kaynak değerleri; AI/cihaz entegrasyonunu etkinleştirmez.

MealLog modelleri UUID, zorunlu alan, UTC an, en az bir kalem, kalem–öğün bağı,
pozitif gram ve negatif olamayan kalori/makro kurallarını uygular. Bilinmeyen
miktar/besin değerleri nullable `decimal` olarak korunur; yuvarlama, porsiyon
dönüşümü, klinik sınır veya günlük saat dilimi politikası seçilmemiştir.
Constructor parametreleri sunucu içi model verileridir, HTTP oluşturma DTO'su değildir.
MealLog modelleri bu görevde de EF modeline eklenmemiştir; MealLog migration'ı yoktur.
Auth entegrasyonunda User → ClientProfile kimlik çözümleme, kaynak sahipliği ve
besin/tarif/analiz referans yetkileri tamamlanmalı; analiz için uygun tamamlanma ve
kullanıcı onayı doğrulanmalıdır. Bunlar yerel model doğrulamasıyla sağlanmış sayılmaz.

Gelecek iş modülleri ihtiyaç oldukça feature klasörlerinde oluşturulur. Ayrı
Domain/Application/Infrastructure projeleri, genel repository veya ek servisler yoktur.

## Auth kullanıcı ve profil temeli

User hesabının UUID'si ile ClientProfile UUID'si ayrı kimliklerdir. Profilin zorunlu
`user_id` FK'si ve benzersiz indeksi, bir hesabın en fazla bir danışan profiline
bağlanmasını sağlar. User'ın profili olmayabilir; rol–profil ve çoklu rol politikası
bu temel tarafından kesinleştirilmez. Profil oluşturulurken User nesnesinden alınan
kimlik kullanılır. JWT middleware `sub` claim'ini güvenilir User UUID'si olarak
doğrular; ilgili iş modülü bunu User → ClientProfile üzerinden danışana çözmelidir.
Kaynak/ilişki/kategori yetkileri bu Auth temelinin yerine geçmez.

`IPasswordHasher<User>` DI üzerinden ASP.NET Core Identity `PasswordHasher<User>`
olarak sunulur; özel hash/salt algoritması veya ek Identity tablo takımı yoktur.
User oluşturulurken yalnız hash saklanır; düz parola modelde tutulmaz ve kırpılmaz.
Entity'nin hash, e-posta doğrulama durumu/token metadata'sı ve hesap–profil gezinme özellikleri JSON'a çıkmaz.
`isEmailVerified` yalnız aşağıdaki onaylı `CurrentUserResponse` içinde ayrıca sunulur.
Entity'ler HTTP kayıt/me DTO'su değildir; kayıt yalnız aşağıdaki DTO'larla çalışır.
Girişte `SuccessRehashNeeded`, yalnız doğrulanmış ve girişe uygun hesabın hash'ini
önceki hash/rol/doğrulama koşuluyla günceller; eşzamanlı parola değişikliğini ezmez.

E-posta alanı harf duyarsız, aksanları ayırt eden ICU collation ve benzersiz indeks
kullanır. `normalizedEmail` gibi yeni bir sözleşme alanı eklenmemiştir. Metin uzunluğu ve
boy hassasiyeti/ölçeği seçilmemiştir; boy `numeric`, doğum tarihi nullable `date`tir.
Zorunlu metin, rol ve pozitif/sonlu boy kısıtları DB'de de korunur. FK otomatik
silme yapmaz (`NO ACTION`); bu, nihai hesap silme/saklama politikasının yerine geçmez.

## Kayıt API'si

- `RegisterUserRequest`: zorunlu `email`, `password`, `displayName`; isteğe bağlı `role`.
  Rol gönderilmezse danışan oluşturulur; yalnız `client` kabul edilir, Admin/Diyetisyen
  ve tanımsız roller reddedilir. Kimlik, hash, doğrulama bayrağı veya iç içe profil alanı gönderilemez.
  E-posta, parola ve görünen ad girdileri JSON'a geri yazılmaz; DTO bir `record` değildir ve
  varsayılan `ToString` girdileri dökmez. İstek nesneleri loglarda destructure edilmez.
- `UserRegistrationService.ValidateAsync`: temel DTO ve parola doğrulamasından sonra
  e-posta benzersizliğini DB'de kontrol eder. E-posta dış boşlukları kırpılır ve
  Identity `UpperInvariantLookupNormalizer` ile Unicode/invariant normalizasyonu yapılır.
- `PrepareAsync`: sunucunun ürettiği kimlik/zamanla, daima `UserRole.Client` ve Identity
  hash'i içeren, EF tarafından izlenmeyen User hazırlayan mevcut yardımcıdır.
- `RegisterAsync`: doğrulamadan sonra User ve ClientProfile nesnelerini oluşturur;
  ikisini tek `SaveChangesAsync` transaction'ında kaydeder. Herhangi bir ekleme
  başarısızsa ikisi de geri alınır. Ön kontrolde veya `ux_users_email` indeksinde
  yakalanan mükerrer/yarışan kayıt `409 conflict` olur; DB hata ayrıntısı dönmez.

`POST /api/v1/auth/register` JSON alır. Örnek alan biçimi (sentetik örnek):

```json
{ "email": "synthetic@example.test", "password": "sentetik parola", "displayName": "Örnek danışan" }
```

Başarı `201 { "id": "<User UUID>" }` döner. ClientProfile kimliği ayrı UUID'dir;
doğum tarihi/boy toplanmaz ve nullable kalır. User'ın `is_email_verified` değeri
başlangıçta `false`tur; istemci bunu atayamaz. Oturum tokenı, cookie veya otomatik giriş
üretilmez. DB commit'inden sonra doğrulama e-postası kuyruğa alınır; ham doğrulama
tokenı API yanıtına çıkmaz. Kayıt `Location` başlığı üretmez; yetkili `/auth/me`
hesap özeti, oluşturulan kayıt kaynağı için ayrı GET detay yolu sayılmaz.
Girdi/JSON/rol hataları `400 invalid_request`, parola politikası hataları
`422 validation_failed`, desteklenmeyen içerik `415 unsupported_media_type`,
beklenmeyen kayıt hataları `500 internal_error` olur. Tümü ortak
`error: { code, message }, requestId` zarfını kullanır.

Parola politikası `Auth:RegistrationPasswordPolicy` bölümünden options ile bağlanır.
İlk sürüm `appsettings.json` değerleri: 8–128 Unicode karakteri (kod noktası),
karakter türü zorunluluğu yok, boşluklar desteklenir. `RequiredUniqueChars = 1`
ek bir farklı karakter zorunluluğu getirmez. Ortam/User Secrets ayarları merkezi
değerleri değiştirebilir; örnek anahtar `Auth__RegistrationPasswordPolicy__RequiredLength`.
Eksik/hatalı politika kullanıcı doğrulama hatası sayılmaz; `InvalidOperationException`
olarak güvenli sunucu hatasına gider. Eski karmaşıklık testleri yalnız
yapılandırılabilirlik senaryolarıdır, ilk sürüm politikasını değiştirmez.

Parola kırpılmaz/normalize edilmez veya loglanmaz; Unicode geçerliliği ve uzunluk
sınırları hash'ten önce denetlenir. İstek doğrulama mesajları denenen değerleri
içermez. EF hassas veri loglaması ve Npgsql hata detayları API bağlantısında kapalıdır.
Onaylanan düz `displayName` girdisi, saklanan `isEmailVerified` alanı ve minimal
`201 { id }` yanıtı ortak belgelere işlenmiştir. Diyetisyen başvurusu/çoklu rol,
Profil düzenleme/uzman profili, refresh/logout/iptal ve istemci oturum sözleşmelerinin açık kısımları uygulanmamıştır.

## Giriş ve JWT access token

`POST /api/v1/auth/login`, `application/json` ile zorunlu `email` ve `password`
alır. Başarı `200 { "accessToken": "<JWT>", "tokenType": "Bearer", "expiresAt": "<UTC ISO 8601>" }`.
Token yalnız bu onaylı başarı yanıtında verilir; kayıt/e-posta doğrulama yanıtlarına
eklenmez. Cookie, refresh token veya profil yanıtı üretilmez.

E-posta mevcut Identity normalizer ile kırpılır/normalleştirilir; parola aynen
Identity PasswordHasher'a verilir. Olmayan hesapta da aynı altyapıyla dummy hash
doğrulaması yapılır; dummy User/oturum/DB kaydı yoktur. Yanlış parola, olmayan
hesap, doğrulanmamış e-posta ve Admin aynı `401 unauthenticated` hatasını alır.
Admin, MFA hazır olana kadar hem token üretiminde hem bearer kabulünde kapalıdır.

JWT süresi 15 dakikadır; claim'ler yalnız `sub` (User UUID), `role` ve standart
`iss`, `aud`, `iat`, `nbf`, `exp` değerleridir. ClientProfile UUID'si, e-posta, ad,
hash veya sağlık verisi taşınmaz. `expiresAt`, imzalı `exp` ile aynıdır.
`Authorization: Bearer <access-token>` kullanılır; token/parola/Authorization
başlığı veya giriş yanıtı loglanmaz. DTO `ToString` tokenı dökmez.

`JwtAuthentication` ASP.NET Core JWT bearer ve authorization middleware'ini kurar.
`HS256` imza, `at+jwt` türü, tam issuer/audience ve lifetime zorunludur;
`ClockSkew = 0` ile fazladan beş dakika tanınmaz. `[Authorize]` isteyen kaynaklar
geçersiz token için ortak `401`, eksik rol/yetki için ortak `403` döndürür.
Gelecek endpointler kendi `[Authorize]` ve kaynak politikalarını açıkça uygulamalıdır.
Genel kimlik deneme endpointi eklenmemiştir; middleware test controller'ı yalnız test host'unda yüklenir.

Varsayılan login limiti bağlantı IP'si başına dakikada 10 istektir:
`Auth:Login:RequestsPerMinute` / `Auth__Login__RequestsPerMinute`.
Sayaç API sürecindedir, hesap varlığından bağımsızdır ve aşım `429 rate_limited`
olur. Gövde sınırı 4096 byte (`413`), şekil/ek alan hataları `400`, yanlış içerik
`415`tir. Auth yanıtları `Cache-Control: no-store` kullanır ve ortak hata zarfı korunur.

### JWT ayarları

`Auth:Jwt:Issuer`, `Auth:Jwt:Audience`, `Auth:Jwt:SigningKeyBase64` zorunludur.
Anahtar Base64 ile kodlanan en az 32 kriptografik rastgele byte olmalıdır;
örnek kurulum 64 byte üretir. Gerçek anahtar repo/appsettings veya komut
geçmişine yazılmaz. Eksik/hatalı JWT ayarı varsa API istek sunmadan başlamayı reddeder.

`backend/` içinde yalnız ilk kurulumda aşağıdakini çalıştırın. Mevcut anahtarı
yeniden üretmeyin; değiştirmek mevcut JWT'lerin doğrulamasını bozar.

```powershell
$nutritionJwtKey = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(64))
@{
    'Auth:Jwt:Issuer' = 'smart-nutrition-api-local'
    'Auth:Jwt:Audience' = 'smart-nutrition-clients-local'
    'Auth:Jwt:SigningKeyBase64' = $nutritionJwtKey
} | ConvertTo-Json -Compress | dotnet user-secrets set --project src/SmartNutrition.Api
Remove-Variable nutritionJwtKey
```

Development, User Secrets'ı okur. Üretimde karşılıklar `Auth__Jwt__Issuer`,
`Auth__Jwt__Audience`, `Auth__Jwt__SigningKeyBase64`; yetkili secret deposu/ortamdan
sağlanmalıdır. Yerel issuer/audience üretim ortamı kararı değildir. Üretim HTTPS,
güvenilir proxy, çok örnekli limit ve anahtar rotasyonu ayrıca yapılandırılır.

Bu dilim stateless access token sağlar; yeni tablo veya migration gerekmez.
Anlık iptal, refresh/logout, cookie/istemci saklama, MFA ve parola sıfırlama
henüz yoktur. İmzalı token süresi boyunca geçerli kalabilir; tam oturum iptali
uygulanmış sayılmaz. Diyetisyen rolü tek başına sağlık verisine erişim sağlamaz.

## Kendi hesap bilgileri

`GET /api/v1/auth/me` JWT bearer veya W2 web cookie authentication ile
erişilir. İstek gövdesi ve query parametresi yoktur; `userId` kabul edilmez.
Kimlik, middleware'in doğruladığı tek `sub` claim'indeki **User UUID'sidir**;
ClientProfile kimliği veya özel istemci başlıkları hesap seçemez.

Başarı `200`, `Cache-Control: no-store` ve yalnız şu beş alanı döndürür:

```json
{
  "id": "<User UUID>",
  "displayName": "Örnek danışan",
  "email": "SYNTHETIC@EXAMPLE.TEST",
  "role": "client",
  "isEmailVerified": true
}
```

`CurrentUserService`, User ve varsa ona ait ClientProfile'ı salt okunur tek
projeksiyonla sorgular; yalnız onaylı alanları seçer. `displayName` profil yoksa
açık null'dır; profilsiz client/dietitian için aynı DTO kullanılır. Yeni profil,
DietitianProfile veya varsayılan ad oluşturulmaz. Email/ad/rol DB'den güncel alınır.
Entity, parola hash'i, tokenlar, güvenlik metadata'sı ve diğer profil/sağlık alanları
dönmez; hesap yanıtı loglanmaz. Okuma kayıtları veya `updatedAt`yi değiştirmez.

Eksik/geçersiz/süresi dolmuş token ortak `401 unauthenticated` alır. Süresi
bitmemiş tokenla da User silinmişse, e-posta doğrulaması kalkmışsa veya güncel rol
token rolünden farklıysa aynı `401` döner. Admin MFA engeli korunur. İstemciden
query/gövde gönderimi `400 invalid_request`, beklenmeyen DB/sunucu hatası ortak
`500 internal_error` olur. Mevcut hata zarfı ve `WWW-Authenticate: Bearer` korunur.
Bu endpointin DB kontrolü tüm kaynaklar için anlık oturum iptali değildir.

Bu görevde açıkça istenen yol `/api/v1/auth/me`dir; eski uygulanmamış
`GET /api/v1/me` taslağına alias eklenmedi. Profil düzenleme (`PATCH /api/v1/me`)
ayrı açık taslaktır. Kayıt/giriş, User/ClientProfile alanları ve EF modeli değişmedi;
yeni tablo, paket veya migration gerekmedi.

## E-posta doğrulama ve SMTP

- `POST /api/v1/auth/verify-email`: `{ "token": "<e-postadaki-token>" }`.
  Başarı gövdesiz `204`; geçersiz/süresi dolmuş/kullanılmış/eski token `422 validation_failed`.
- `POST /api/v1/auth/resend-verification`: `{ "email": "synthetic@example.test" }`.
  Geçerli e-posta için hesap yoksa, doğrulanmışsa veya gönderim aralığındaysa da aynı
  gövdesiz `202` döner. Eksik/bozuk JSON veya geçersiz e-posta `400 invalid_request`.
- İki uçta 4096 byte istek sınırı vardır; fazla gövde `413`, yanlış içerik türü `415`.
  Hatalar ortak `error: { code, message }, requestId` zarfındadır. Auth yanıtları
  `Cache-Control: no-store` kullanır; ham token yanıta/loga yazılmaz.

Token kriptografik 32 byte'tan üretilir (43 Base64URL karakteri); 30 dakika ve tek
kullanımlıktır. DB yalnız SHA-256 hash'i ve UTC süre/gönderim metadata'sını saklar.
Doğrulama tek atomik SQL güncellemesiyle tokenı tüketir; eşzamanlı tekrar reddedilir.
Yeni gönderim önceki tokenı geçersiz kılar. E-posta metni doğrulama kodunu içerir;
mobil/web bağlantı ve ekran entegrasyonu henüz yapılmamıştır.

`Auth:EmailVerification` ayarları: `ResendCooldownSeconds = 60` (DB'de hesap başına),
`ResendRequestsPerMinute = 5` (bağlantı IP'si başına), `QueueCapacity = 100`.
Ortam karşılıkları ör. `Auth__EmailVerification__ResendCooldownSeconds`.
IP aşımı `429 rate_limited` olur; sayaç API sürecindedir. Ters proxy ve birden çok
API örneği için güvenilir proxy/ortak limit dağıtım öncesi ele alınmalıdır.

SMTP HTTP isteğinden bağımsız, sınırlı bellek kuyruğunda işlenir; yeniden gönderim
isteği hesap sorgulamadan kuyruğa alınır. SMTP hatası veya kuyruk doluluğu `201/202`
yanıtını değiştirmez ve hesabı doğrulamaz. Kuyruk kalıcı değildir; yeniden başlatma
veya gönderim hatasında yeniden gönderim gerekir. Son gönderim zamanı SMTP'den
önce ayrılır; başarısız denemeden sonra da 60 saniyelik aralık geçerlidir. Log yalnız
genel hata bilgisi içerir; alıcı/token/SMTP istisna içeriği eklenmez.

### Yerel Mailpit kurulumu

PostgreSQL için mevcut `.env` korunarak `backend/` içinde:

```powershell
docker compose up -d --wait --wait-timeout 60 mailpit
@{
    'Email:Smtp:Host' = '127.0.0.1'
    'Email:Smtp:Port' = '1025'
    'Email:Smtp:FromAddress' = 'no-reply@smart-nutrition.local'
    'Email:Smtp:TlsMode' = 'None'
} | ConvertTo-Json -Compress | dotnet user-secrets set --project src/SmartNutrition.Api
```

Servis `mailpit`, konteyner `smart-nutrition-mailpit`, sabit imaj `axllent/mailpit:v1.32.0`.
SMTP `127.0.0.1:1025`, posta kutusu arayüzü `http://127.0.0.1:8025`.
Her iki port yalnız loopback'e açıktır. Dış iletim yapılandırılmamıştır; sentetik
alıcılara yapılan yerel gönderimler Mailpit'te görüntülenir. SMTP protokol logu açılmaz.
Mailpit kalıcı volume kullanmaz; geliştirme posta kutusu konteyner ömrüyle sınırlıdır.

API Development ortamında başlatılır. SMTP ayarları repoda tutulmaz;
`Email:Smtp:Host`, `Port`, `FromAddress`, `TlsMode`, gerekiyorsa `Username` ve
`Password` User Secrets/environment üzerinden sağlanır. Ortam örneği:
`Email__Smtp__Password`. Gerçek kimlik bilgilerini komut geçmişine veya repoya yazmayın.
Varsayılan `StartTls` zorunlu TLS kullanır; `SslOnConnect` de desteklenir.
`None` yalnız Development ortamında loopback sunucu için kabul edilir.
Üretim SMTP sağlayıcısı, kimlik bilgileri ve kalıcı teslim altyapısı ayrıca hazırlanmalıdır.

Kayıt sonrası Mailpit e-postasındaki token `verify-email` isteğinde kullanılır;
başarıdan sonra aynı token tekrar `422` dönmelidir. Bu işlem oturum açmaz.
E-postayı veya tokenı terminal çıktısına/loga dökmeyin. Otomatik gerçek SMTP testi aşağıdadır.

## Geliştirme ortamı

Komutlar `backend/` içinde çalıştırılır:
PostgreSQL ve yukarıdaki JWT User Secrets ayarlarını hazırladıktan sonra API'yi başlatın.

```powershell
dotnet restore
dotnet tool restore
dotnet build
dotnet test
dotnet run --project src/SmartNutrition.Api --launch-profile http
```

HTTP adresi `http://localhost:5052`; HTTPS profili `https://localhost:7099` kullanır.
HTTPS için yerel geliştirme sertifikası gerekir. Üretim HTTPS/host ve proxy ayarları
dağıtım ortamında ayrıca yapılandırılır.

- `/health/live`: API işlemi çalışıyorsa `200 Healthy`; DB gerektirmez.
- `/health/ready`: PostgreSQL bağlantısı başarılıysa `200 Healthy`; ayar eksik,
  hatalı veya erişilemezse `503 Unhealthy`. Bağlantı ayrıntılarını dışarı vermez.
- `/openapi/v1.json` ve `/swagger`: yalnız `Development` ortamında sunulur.

Health yolları operasyonel altyapı kontrolleridir. Swagger kayıt, giriş, e-posta
doğrulama, yeniden gönderim ve kendi hesap okumasını gösterir; MealLog endpointi içermez.

## PostgreSQL bağlantısı

Bağlantı dizesi koda veya `appsettings*.json` dosyalarına yazılmaz. Anahtar
`ConnectionStrings:DefaultConnection`; depodaki değer bilerek boştur.
API `Development` ortamında User Secrets'ı otomatik okur.

### Yerel Docker kurulumu

Docker Desktop Linux konteynerleriyle çalışmalıdır. Compose kaynakları:

| Kaynak | Ad / adres |
|---|---|
| Compose projesi | `smart-nutrition-platform` |
| Servis / konteyner | `postgres` / `smart-nutrition-postgres` |
| Kalıcı volume | `smart-nutrition-postgres-data` |
| Host bağlantısı | `127.0.0.1:5433` |
| Veritabanı / kullanıcı | `smart_nutrition` / `smart_nutrition` |
| Yerel SMTP / posta kutusu | `smart-nutrition-mailpit`, `127.0.0.1:1025` / `http://127.0.0.1:8025` |

Host portu yalnız loopback'e açılır. `5432` üzerindeki başka PostgreSQL
kurulumlarına dokunulmaz. `5433` doluysa Compose portu ile bağlantı dizesindeki
portu birlikte değiştirin. API host üzerinde çalışır; Docker içine taşınmaz.

İlk kurulumda bir kez aşağıdaki PowerShell komutlarını çalıştırın. Rastgele parola
Git tarafından dışlanan `backend/.env` içine, API bağlantısı User Secrets'a yazılır;
parola komut geçmişine veya konsola basılmaz. Mevcut `.env` üzerine yazılmaz.

```powershell
if (Test-Path -LiteralPath .env) { throw 'Mevcut .env korunuyor; yeniden parola üretmeyin.' }
$nutritionBytes = New-Object byte[] 32
$nutritionRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $nutritionRng.GetBytes($nutritionBytes) } finally { $nutritionRng.Dispose() }
$nutritionPassword = [BitConverter]::ToString($nutritionBytes).Replace('-', '').ToLowerInvariant()
Set-Content -LiteralPath .env -Encoding ascii -Value "SMART_NUTRITION_POSTGRES_PASSWORD=$nutritionPassword"
$nutritionConnection = "Host=127.0.0.1;Port=5433;Database=smart_nutrition;Username=smart_nutrition;Password=$nutritionPassword;Timeout=3;Command Timeout=3"
@{ 'ConnectionStrings:DefaultConnection' = $nutritionConnection } | ConvertTo-Json -Compress | dotnet user-secrets set --project src/SmartNutrition.Api
Remove-Variable nutritionPassword, nutritionConnection, nutritionBytes
```

Ardından veritabanını başlatın; sonraki açılışlarda yalnız bu komutlar gerekir:

```powershell
docker compose config --quiet
docker compose up -d --wait --wait-timeout 60
docker compose ps
```

Compose `.env` değerini `POSTGRES_PASSWORD` ortam değişkeni olarak konteynere verir.
Alternatif olarak `SMART_NUTRITION_POSTGRES_PASSWORD` host ortamında tanımlanabilir;
ortam değişkeni `.env` değerinden önceliklidir ve API parolasıyla aynı olmalıdır.
Parola boşsa Compose başlamaz. Docker sağlık kontrolü sunucunun hazır olmasını
izler; API kimlik bilgilerini doğrulayan kontrol `/health/ready` ve aşağıdaki testtir.

`docker compose stop` veritabanını durdurur; `docker compose down` konteyner ve ağı
kaldırır, volume içindeki veriyi korur. `.env` korunmalıdır: var olan volume'da
`.env` parolasını değiştirmek PostgreSQL parolasını değiştirmez. Bu görevde volume
silme veya parola rotasyonu otomatik yapılmaz.

### Mevcut PostgreSQL / alternatif ayar

Projeye ayrılmış başka bir PostgreSQL varsa Compose gerekmez. Yetkili bağlantıyı
yerel User Secrets'a kaydedin:

```powershell
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "<connection-string>" --project src/SmartNutrition.Api
```

Alternatif olarak mevcut PowerShell oturumunda ortam değişkeni verilebilir:

```powershell
$env:ConnectionStrings__DefaultConnection = '<connection-string>'
```

`<connection-string>` yerine yetkili PostgreSQL bağlantınızı kullanın; gerçek
değeri Git'e veya loglara eklemeyin. User Secrets geliştirme içindir, şifreli
bir üretim secret deposu değildir. JWT ayarları geçerliyken DB ayarı olmadan API/OpenAPI açılır, hazırlık kontrolü
`503` döner. Başlangıçta veritabanı/tablo oluşturulmaz; otomatik `EnsureCreated`
veya `Migrate` çalıştırılmaz.

Compose kullanıcısı PostgreSQL imajının oluşturduğu yerel geliştirme kullanıcısıdır;
üretim kullanıcı/yetki, TLS, secret deposu ve dağıtım kararları bununla belirlenmez.

## Gerçek bağlantıyı doğrulama

API çalışırken ayrı terminalden:

```powershell
Invoke-WebRequest http://localhost:5052/health/live
Invoke-WebRequest http://localhost:5052/health/ready
```

İkisi de `200` / `Healthy` dönmelidir. Readiness, DI üzerinden çözülen
`AppDbContext.Database.CanConnectAsync` ile gerçek PostgreSQL bağlantısını açar;
yalnız connection string varlığını veya Docker durumunu kontrol etmez. DB kapalı,
parola hatalı veya ayar eksikse readiness `503 Unhealthy`, liveness `200 Healthy`
döner. Hata yanıtı bağlantı dizesini ve sağlayıcı hata ayrıntılarını içermez.

Varsayılan `dotnet test` DB gerektirmeyen testleri çalıştırır; gerçek PostgreSQL
ve Mailpit testleri açık gerekçeyle **atlanır**. Docker kurulumuyla PostgreSQL testlerini çalıştırmak için
`backend/` içinde, `.env` parolasını ekrana yazmadan şu adımları kullanın:

```powershell
$nutritionPasswordLine = Get-Content -LiteralPath .env | Where-Object { $_.StartsWith('SMART_NUTRITION_POSTGRES_PASSWORD=') } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($nutritionPasswordLine)) { throw '.env içinde PostgreSQL parolası bulunamadı.' }
$nutritionPassword = $nutritionPasswordLine.Substring('SMART_NUTRITION_POSTGRES_PASSWORD='.Length)
$env:SMART_NUTRITION_TEST_CONNECTION_STRING = "Host=127.0.0.1;Port=5433;Database=smart_nutrition;Username=smart_nutrition;Password=$nutritionPassword;Timeout=3;Command Timeout=3"
try { dotnet test } finally {
    Remove-Item Env:SMART_NUTRITION_TEST_CONNECTION_STRING
    Remove-Variable nutritionPassword, nutritionPasswordLine
}
```

Gerçek SMTP testini de çalıştırmak için yukarıdaki `try { dotnet test }` bloğundan
önce şu değişkenleri tanımlayın; aynı `finally` bloğunda bu değişkenleri de kaldırın:

```powershell
$env:SMART_NUTRITION_TEST_MAILPIT_URL = 'http://127.0.0.1:8025'
$env:SMART_NUTRITION_TEST_SMTP_HOST = '127.0.0.1'
$env:SMART_NUTRITION_TEST_SMTP_PORT = '1025'
$env:SMART_NUTRITION_TEST_SMTP_FROM = 'no-reply@smart-nutrition.local'
# finally bloğuna eklenir:
# Remove-Item Env:SMART_NUTRITION_TEST_MAILPIT_URL, Env:SMART_NUTRITION_TEST_SMTP_HOST, Env:SMART_NUTRITION_TEST_SMTP_PORT, Env:SMART_NUTRITION_TEST_SMTP_FROM
```

Bu test gerçek HTTP kayıt → SMTP teslimi → Mailpit'ten token okuma → yeniden gönderim
→ eski token reddi → doğrulama → tekrar reddi akışını sınar. Tokenı çıktıya yazmaz;
yalnız kendi rastgele sentetik alıcısına ait Mailpit mesajlarını temizler.
Diğer doğrulama testleri SMTP yerine kontrollü test göndericisi ve gerçek PostgreSQL
ile süre sınırı, eşzamanlılık, cooldown, IP limiti ve hassas log davranışını sınar.
Giriş testleri de aynı izole PostgreSQL şemalarını kullanır. Başarılı kayıt/doğrulama/giriş,
yanlış parola, doğrulanmamış hesap, Admin engeli, Identity rehash ve IP sınırına ek olarak
gerçek middleware ile bozuk/yanlış imzalı/süresi dolmuş/yanlış issuer-audience-algoritma-tür
tokenları ve rol yetkilendirmesi sınanır. Test JWT anahtarları her factory için rastgele
üretilir; geliştirici User Secrets anahtarı testlere taşınmaz. Eksik JWT ayarlarıyla
başlangıcın reddi ve Kestrel gövde sınırları ayrıca test edilir.
Kendi hesap testleri, gerçek login tokenlarıyla `/auth/me` yanıtının beş alanını,
iki kullanıcının veri izolasyonunu, query/gövde ile kimlik seçiminin reddini,
profilsiz client/dietitian durumunu, geçersiz/süresi dolmuş tokenı ve silinmiş veya
güncel rol/doğrulaması değişmiş hesabın `401` almasını sınar. Tüm kalıcı sentetik
hesaplar yalnız test factory'sinin rastgele şemasındadır; silinmiş hesap senaryosu
da bu şemayla sınırlıdır. Uygulama tabloları sıfırlanmaz veya silinmez.

Bu değişken `AppDbContext`/`SELECT 1`/readiness testine ek olarak Auth PostgreSQL
testlerini de açar. Önce aşağıdaki migration uygulanmalıdır. Model testleri sentetik
verileri transaction içinde geri alır. Gerçek kayıt API testleri yalnız kendilerinin
oluşturduğu rastgele `registration_api_test_<UUID>` şemasına migration uygular ve
kayıtları orada commit eder; bitince yalnız bu geçici şemayı temizler. Uygulama
tabloları sıfırlanmaz veya silinmez. Bu testler için test bağlantısında şema oluşturma
yetkisi gerekir. Harici PostgreSQL için aynı test değişkenine yetkili test bağlantısını
verin. Normal test host'ları gerçek geliştirici User Secrets'ına geri dönmez.

## Migration altyapısı

İlk migration `AddAuthFoundation`, User ve ClientProfile alanlarını, e-posta ve
profil `user_id` benzersizliğini ve FK'yi ekler; mevcut tabloları silmez/değiştirmez.
`EnforceCaseInsensitiveEmails`, yalnız `users.email` collation'ını değiştirir;
hesap/profil satırlarını veya e-posta yazımını güncellemez. PostgreSQL'de ICU desteği
gerekir (mevcut PostgreSQL 17 Docker imajında vardır). Mevcut harf/Unicode farkıyla
çakışan hesaplar varsa indeks değişikliği transaction içinde başarısız olur; hesaplar
otomatik birleştirilmez veya silinmez. Çakışmalar ayrı kararla çözülmelidir.
`AddUserEmailVerificationState`, `users.is_email_verified` boolean alanını `false`
varsayılanıyla ekler; mevcut hesap/profil verilerini silmez.
`AddEmailVerificationTokens`, yalnız üç nullable token metadata sütununu, hash unique
indeksini ve metadata bütünlük kontrolünü ekler; mevcut hesap/profil verisini silmez.
Başlangıçta otomatik migration veya `EnsureCreated` çalışmaz.
Veritabanını değiştirmeden bağlamı ve mevcut migration listesini kontrol edin:

```powershell
dotnet ef dbcontext info --project src/SmartNutrition.Api
dotnet ef migrations list --no-connect --project src/SmartNutrition.Api
```

Yerel User Secrets bağlantısıyla geliştirme veritabanına uygulamak için:

```powershell
$env:DOTNET_ENVIRONMENT = 'Development'
dotnet ef database update AddEmailVerificationTokens --project src/SmartNutrition.Api
dotnet ef migrations has-pending-model-changes --project src/SmartNutrition.Api
```

Domain eşlemelerinde çoğul `snake_case` tablo ve `snake_case` sütun adları açık
`ToTable`/`HasColumnName` eşlemeleriyle tanımlanır; EF'nin varsayılan PascalCase
adları kullanılmaz. Araçların tarihçe tablosu `__ef_migrations_history`dir.
`database drop`, `EnsureDeleted`, sıfıra geri alma veya `compose down -v` bu süreçte
kullanılmaz. Yeni migration'lar ilgili sözleşme onayıyla hazırlanır; açık alanlar
ve veri silme politikaları kendiliğinden migration'a eklenmez.

DB gerektirmeyen testler eksik/erişilemeyen bağlantıyı, liveness, OpenAPI ortam
sınırlarını ve hata sözleşmesini doğrular. Yalnız bu testlerin geçmesi gerçek DB
erişiminin doğrulandığı anlamına gelmez; gerçek bağlantı testi ayrıca etkinleştirilir.

Başvuru: [ASP.NET Core health checks](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks?view=aspnetcore-10.0),
[OpenAPI](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/openapi?view=aspnetcore-10.0),
[Npgsql](https://www.npgsql.org/efcore/),
[EF CLI](https://learn.microsoft.com/en-us/ef/core/cli/dotnet),
[Identity parola altyapısı](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/consumer-apis/password-hashing?view=aspnetcore-10.0),
[JWT bearer yapılandırması](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/configure-jwt-bearer-authentication?view=aspnetcore-10.0),
[Mailpit Docker](https://mailpit.axllent.org/docs/install/docker/),
[MailKit](https://github.com/jstedfast/MailKit),
[PostgreSQL Docker imajı](https://github.com/docker-library/docs/blob/master/postgres/README.md).
## W2 web cookie oturumu — 27.10.2026

W2-C1–C7 ortak onayıyla aynı API'ye `GET /api/v1/auth/csrf` ve
`POST`/`DELETE /api/v1/auth/web-session` eklendi. `GET /auth/me` artık JWT veya
web cookie kabul eder; mevcut beş alanlı yanıt değişmez. JWT login gövdesi,
15 dakikalık token ve diğer API'lerin bearer yetkisi korunur. Admin MFA'sız
oturum alamaz; bu dilim uzman profili/sağlık/panel yetkisi sağlamaz.

Yeni `AddWebAuthSessions` migration'ı yalnız `auth_sessions`, FK, zaman
kısıtları ve indeksleri ekler. Mevcut User/ClientProfile ve sağlık şeması değişmez.
Yeni migration'ı yerel PostgreSQL'e normal `dotnet ef database update` ile
uygulayın. Gerçek veri üzerinde otomatik migration/dağıtım yapılmaz.

Web oturumu için environment/User Secrets:

```powershell
$env:Auth__WebSession__Origin = 'https://localhost:5173'
$env:Auth__WebSession__KeyRingPath = "$env:LOCALAPPDATA/SmartNutrition/session-keys"
dotnet run --project src/SmartNutrition.Api --launch-profile https
```

DB/JWT/SMTP ayarları aşağıdaki mevcut kurulumla birlikte gerekir. Origin tek
HTTPS authority'dir; son slash/path/query içermez. KeyRingPath mutlak ve Git
dışında olmalıdır. Özel dizini uygulama Windows hesabına kısıtlayın; Windows'ta
Data Protection anahtarları o hesabın DPAPI korumasıyla kalıcı saklanır.
Windows dışı ortamda `Auth__WebSession__KeyProtectionCertificatePath` ve gerekiyorsa
`Auth__WebSession__KeyProtectionCertificatePassword` ile özel anahtarlı PFX sağlayın;
sertifika/anahtar Git'e veya loglara girmez. Çok örnekte aynı uygulama adı
(`SmartNutrition.WebSession.v1`), anahtar halkası ve çözme yetkisi gerekir.
Origin boşken mevcut JWT kurulumu çalışabilir; web yolları 500 ile kapalıdır.
Hatalı web anahtar/origin ayarı başlangıçta reddedilir. Üretim koruma/rotasyon
sağlayıcısı ve izinleri ayrıca yayın kapısında doğrulanır.

Web HTTPS proxy/sertifika kurulumu `apps/web/README.md` içindedir; varsayılan
API HTTPS portu 7099'dur. Secure/SameSite gevşetilmez, TLS doğrulaması kapatılmaz.
Cookie ve antiforgery yalnız web yolları/hesap okuması için kullanılır;
Authorization+cookie beraberliği reddedilir. CSRF tokenı kullanıcı ve sid'ye
bağlıdır. Login yolları aynı IP sayacını paylaşır (10/dakika); CSRF 30/dakikadır.

Her cookie kimliği güncel User ve AuthSession satırlarını DB'den kontrol eder;
DB hatasında erişim açılmaz. Idle 30 dakika, mutlak ömür 8 saattir. Başarılı
hesap okuması idle'ı mutlak sınırı aşmadan ilerletir; CSRF/health/statik dosya
uzatmaz. Logout iptalini atomik uzatma geri alamaz. Gelecekteki parola/rol/e-posta
güvenlik yazmaları, aynı transaction'da `WebSessionService.RevokeAllAsync` ile
User kilidini alıp bütün web oturumlarını iptal ederek User değişimini yapmalıdır.
Başarılı Identity rehash gerçek parola değişikliği değildir. Temizlik normal
çalışmada her 10 dakikada, iptal/bitimden 23 saat 50 dakika geçmiş satırları
siler; kesinti hatası genel logla izlenir. Sağlık/audit satırları etkilenmez.

`WebSessionApiTests` gerçek PostgreSQL'de cookie/CSRF, süre sınırları, replay,
Origin/karışık kimlik, ortak limit, DB kesintisi, şifre değişimiyle login yarışı,
atomik iptal, korumalı kalıcı anahtar/ikinci API örneği ve temizlik testlerini
içerir. Yalnız sentetik hesaplar ve özel geçici şemalar kullanılır. Gerçek test
çalıştırma opt-in'i aşağıdaki mevcut `SMART_NUTRITION_TEST_*` ayarlarıdır.

Mobil JWT refresh/iptal, parola sıfırlama ve Admin MFA; üretim audit şeması,
kalıcı e-posta teslimi, ortak çok örnekli IP sayacı ve proxy yayın kapıları açıktır.
Web logout mevcut stateless JWT'yi iptal etmez. Aşağıdaki önceki görev notlarında
cookie'nin açık olduğu ifadeler tarihsel görev kapsamıdır; güncel W2 sözleşmesi
`docs/04/05/06/11/12`dedir.

Bu değişikliğin doğrulaması: `dotnet build SmartNutrition.Backend.slnx --no-restore`
başarılı (0 uyarı/hata); geçici PostgreSQL 17 ve Mailpit v1.32.0 ile
`dotnet test SmartNutrition.Backend.slnx --no-restore` **214 geçti, 0 atlandı**.
Güvenilir HTTPS Vite proxy/Kestrel üzerinde sentetik kayıt + SMTP doğrulama,
cookie login, beş alanlı me, logout, logout sonrası 401 ve login boyut sınırının
413 yanıtı doğrulandı. Tarayıcıda giriş, hesap yenileme, çıkış ve çıkış sonrası
korunan hesap yolunun girişe dönmesi de doğrulandı.
