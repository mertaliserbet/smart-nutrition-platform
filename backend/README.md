# Smart Nutrition — Ortak Backend

Tek ASP.NET Core Web API projesi ve bir xUnit test projesi. Hedef .NET 10;
oluşturma ortamı SDK 10.0.401. `global.json`, kararlı .NET 10 SDK feature band'lerini
kabul eder. EF Core/araçlar 10.0.12, Npgsql sağlayıcısı 10.0.3 olarak sabitlendi.

`POST /api/v1/auth/register` ile User ve ClientProfile PostgreSQL'e kaydedilir.
Giriş, kullanıcı oturumu, JWT, MFA veya e-posta gönderimi yoktur. `MealLog` ve
`MealLogItem` doğrulanan C# modelleri olarak hazırdır; DbContext'e bağlanmamıştır.
Bu görevde onaylanan kayıt şeması aşağıdadır; ortak `04/05/06` belgeleri değiştirilmemiştir.

## Yapı

- `src/SmartNutrition.Api/Program.cs`: servisler, JSON/hata kuralları ve HTTP pipeline.
- `Data/AppDbContext.cs`: User/ClientProfile eşlemeleri bulunan Npgsql bağlamı.
- `Data/Migrations/`: Auth tabloları ve e-postada harf duyarsız benzersizlik migration'ları.
- `Health/PostgresHealthCheck.cs`: veritabanı erişimini değiştirmeden kontrol eder.
- `Infrastructure/ApiErrors.cs`: `error: { code, message }, requestId` hata zarfı.
- `tests/SmartNutrition.Api.Tests/`: gerçek uygulama host'u ile altyapı testleri.
- `.config/dotnet-tools.json`: projeye özel `dotnet-ef`; global kurulum gerekmez.
- `compose.yaml`: yalnız yerel geliştirme için bağımsız PostgreSQL 17.
- `Features/MealLogs/`: MealLog/MealLogItem alanları, yerel bütünlük kuralları ve MealType.
- `Features/Auth/`: User/ClientProfile modelleri, EF eşlemeleri, kayıt doğrulamaları ve AuthController.
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
kimlik kullanılır; gelecekte oturumdaki doğrulanmış User bu bağlantıyla çözülecektir.
Şu anda oturum/claim çözümleme veya yetkilendirme uygulanmamıştır.

`IPasswordHasher<User>` DI üzerinden ASP.NET Core Identity `PasswordHasher<User>`
olarak sunulur; özel hash/salt algoritması veya ek Identity tablo takımı yoktur.
User oluşturulurken yalnız hash saklanır; düz parola modelde tutulmaz ve kırpılmaz.
Hash, e-posta doğrulama durumu ve hesap–profil gezinme özellikleri JSON'a çıkmaz.
Entity'ler HTTP kayıt/me DTO'su değildir; kayıt yalnız aşağıdaki DTO'larla çalışır.
Parola doğrulamasında gelecekte `SuccessRehashNeeded` sonucu da ele alınmalıdır.

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
başlangıçta `false`tur; istemci bunu atayamaz. Token, cookie, otomatik giriş veya
doğrulama e-postası üretilmez. `/me` henüz uygulanmadığından sahte Location verilmez.
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
`201 { id }` yanıtı ortak belgelere ayrı görevde işlenmelidir. `06`daki diyetisyen
başvurusu/rol anlatımı da mevcut yalnız danışan kayıt kuralıyla uyarlanmalıdır.

## Geliştirme ortamı

Komutlar `backend/` içinde çalıştırılır:
PostgreSQL'i aşağıdaki adımlarla hazırladıktan sonra API'yi başlatın.

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

Health yolları operasyonel altyapı kontrolleridir. Swagger yalnız kayıt operasyonunu
ve onaylanan giriş/yanıt alanlarını gösterir; giriş veya MealLog endpointi içermez.

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
bir üretim secret deposu değildir. Ayar olmadan API/OpenAPI açılır, hazırlık kontrolü
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
testi açık gerekçeyle **atlanır**. Docker kurulumuyla gerçek testi de çalıştırmak için
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
Başlangıçta otomatik migration veya `EnsureCreated` çalışmaz.
Veritabanını değiştirmeden bağlamı ve mevcut migration listesini kontrol edin:

```powershell
dotnet ef dbcontext info --project src/SmartNutrition.Api
dotnet ef migrations list --no-connect --project src/SmartNutrition.Api
```

Yerel User Secrets bağlantısıyla geliştirme veritabanına uygulamak için:

```powershell
$env:DOTNET_ENVIRONMENT = 'Development'
dotnet ef database update AddUserEmailVerificationState --project src/SmartNutrition.Api
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
[PostgreSQL Docker imajı](https://github.com/docker-library/docs/blob/master/postgres/README.md).
