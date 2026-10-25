# Smart Nutrition — Ortak Backend

Tek ASP.NET Core Web API projesi ve bir xUnit test projesi. Hedef .NET 10;
oluşturma ortamı SDK 10.0.401. `global.json`, kararlı .NET 10 SDK feature band'lerini
kabul eder. EF Core/araçlar 10.0.12, Npgsql sağlayıcısı 10.0.3 olarak sabitlendi.

Auth, kullanıcı oturumu, domain entity'si, iş endpointi veya migration yoktur.
`04/05/06` ortak sözleşmelerinin açık alanları burada kesinleştirilmemiştir.

## Yapı

- `src/SmartNutrition.Api/Program.cs`: servisler, JSON/hata kuralları ve HTTP pipeline.
- `Data/AppDbContext.cs`: boş Npgsql bağlamı; onaylı feature eşlemeleri burada eklenir.
- `Health/PostgresHealthCheck.cs`: veritabanı erişimini değiştirmeden kontrol eder.
- `Infrastructure/ApiErrors.cs`: `error: { code, message }, requestId` hata zarfı.
- `tests/SmartNutrition.Api.Tests/`: gerçek uygulama host'u ile altyapı testleri.
- `.config/dotnet-tools.json`: projeye özel `dotnet-ef`; global kurulum gerekmez.
- `compose.yaml`: yalnız yerel geliştirme için bağımsız PostgreSQL 17.

Gelecek iş modülleri ihtiyaç oldukça feature klasörlerinde oluşturulur. Ayrı
Domain/Application/Infrastructure projeleri, genel repository veya ek servisler yoktur.

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

Bunlar operasyonel altyapı yollarıdır; `/api/v1` iş sözleşmesine yeni kaynak eklemez.
Swagger'daki iş operasyonları, onaylı modüller geliştirilince eklenecektir.

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

Bu test uygulamanın `AppDbContext` bağlantısını, salt okunur `SELECT 1` sorgusunu
ve gerçek DB ile `/health/ready` yanıtını doğrular. Entity, tablo, seed veya migration
oluşturmaz. Harici PostgreSQL için aynı test değişkenine yetkili test bağlantısını
verin. Normal test host'ları gerçek geliştirici User Secrets'ına geri dönmez.

## Migration altyapısı

Bağlam ve CLI araçları entity olmadan hazırdır. Boş başlangıç migration'ı üretilmedi.
Veritabanını değiştirmeden bağlamı ve mevcut migration listesini kontrol edin:

```powershell
dotnet ef dbcontext info --project src/SmartNutrition.Api
dotnet ef migrations list --no-connect --project src/SmartNutrition.Api
```

İlk entity için `04/05/06` onayı tamamlandıktan sonra:

```powershell
dotnet ef migrations add <MigrationName> --project src/SmartNutrition.Api --output-dir Data/Migrations
dotnet ef database update --project src/SmartNutrition.Api
```

Domain eşlemelerinde çoğul `snake_case` tablo ve `snake_case` sütun adları açık
`ToTable`/`HasColumnName` eşlemeleriyle tanımlanır; EF'nin varsayılan PascalCase
adları kullanılmaz. Araçların tarihçe tablosu `__ef_migrations_history`dir.
Hassasiyet, cascade ve diğer açık şema kararları entity görevi öncesinde kapatılır.

DB gerektirmeyen testler eksik/erişilemeyen bağlantıyı, liveness, OpenAPI ortam
sınırlarını ve hata sözleşmesini doğrular. Yalnız bu testlerin geçmesi gerçek DB
erişiminin doğrulandığı anlamına gelmez; gerçek bağlantı testi ayrıca etkinleştirilir.

Başvuru: [ASP.NET Core health checks](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks?view=aspnetcore-10.0),
[OpenAPI](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/openapi?view=aspnetcore-10.0),
[Npgsql](https://www.npgsql.org/efcore/),
[EF CLI](https://learn.microsoft.com/en-us/ef/core/cli/dotnet),
[PostgreSQL Docker imajı](https://github.com/docker-library/docs/blob/master/postgres/README.md).
