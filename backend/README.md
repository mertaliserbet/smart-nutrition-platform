# Smart Nutrition — Ortak Backend

## 1. Amaç ve güncel özellikler

Mobil ve webin kullandığı ortak `/api/v1` API'si, PostgreSQL verisi ve sunucu iş/yetki kuralları bu modüldedir. Kaynak inceleme tabanı **22.11.2026 / `4f160b3`**; aşağıdaki komutlar bu belge görevi sırasında çalıştırılmamıştır.

| Alan | Kaynakta mevcut |
|---|---|
| Auth | Danışan kaydı/e-posta doğrulama, JWT login/me, dönen refresh token ve aile iptali, W2 cookie/CSRF, Admin MFA |
| Parola sıfırlama | Genel talep ve tek kullanımlık reset; credentialsVersion ile eski JWT, bütün web oturumları ve refresh ailelerinin iptali; Admin MFA korunur |
| Uzman/ilişki | Yeni/mevcut hesap başvurusu, Admin onayı/audit, uzman arama, davet, kabul/red/sonlandırma ve tek aktif ilişki |
| Program | Kişisel/atanmış program, alternatifler, değişmeyen içerik sürümleri, açık aktivasyon/arşiv ve tek aktif program |
| Kayıt/takip | Manuel MealLog/MealLogItem, su ve ölçüm CRUD; kişisel hedefler; izinli uzman okumaları, su geçmişi ve günlük program–tüketim karşılaştırması |
| İletişim/görev | Öğün yorumu/tek düzey cevap; sürümlü görev atama, durum/tercih/geçmiş ve ilişki sonunda iptal |
| Sağlık | Manuel aktivite, bağlantı/kaynak/örnek/receipt, atomik sync ve conservative_overlap_v1 günlük özet |

MealLog/MealLogItem artık EF'e bağlıdır ve migration/API'si vardır. Mobil refresh, reset ve görev/sağlık API'leri “henüz yok” değildir. Katalog/tarif, yemek AI, tahlil/OCR, bildirim teslimi, PDF ve kapsamlı Admin operasyonları onaylı fakat henüz tamamlanmamış kapsamdadır.

Tam endpoint/DTO ve yetki kaynağı [06](../docs/06_API_CONTRACT.md), kalıcı şema [05](../docs/05_DATA_DICTIONARY.md), sağlık aktarımı [20](../docs/20_HEALTH_DATA_SYNC_CONTRACT.md)'dir. README yeni sözleşme tanımlamaz. Backend sorumluluğu kişi adına göre değil [AGENTS.md](../AGENTS.md)'deki güncel göreve göre belirlenir.

## 2. Gereksinimler ve kurulum

Komutlar aksi belirtilmedikçe **backend/** içindedir. PowerShell örnekleri PowerShell 7 içindir.

- .NET 10 SDK: `global.json` 10.0.100 tabanından kararlı latestFeature sürümüne izin verir. Solution `SmartNutrition.Backend.slnx`, API projesi `src/SmartNutrition.Api`dır.
- EF Core/yerel dotnet-ef 10.0.12, Npgsql sağlayıcısı 10.0.3; gerçek bağımlılıklar csproj/araç manifestindedir.
- PostgreSQL 17 ve ICU collation desteği. Yerel Docker kurulumu için Docker Desktop Linux motoru gerekir.
- SMTP için yerel Mailpit; web/Admin için güvenilir HTTPS ve korumalı Data Protection key ring.

```powershell
dotnet restore
dotnet tool restore
dotnet build SmartNutrition.Backend.slnx --no-restore
```

### PostgreSQL ve User Secrets

`compose.yaml` yalnız PostgreSQL ve Mailpit'i başlatır; API hostta çalışır.

| Kaynak | Yerel değer |
|---|---|
| Compose projesi | smart-nutrition-platform |
| PostgreSQL servis/konteyner | postgres / smart-nutrition-postgres |
| Host / DB / kullanıcı | 127.0.0.1:5433 / smart_nutrition / smart_nutrition |
| Kalıcı volume | smart-nutrition-postgres-data |
| Mailpit servis/konteyner | mailpit / smart-nutrition-mailpit |
| Mailpit SMTP/UI | 127.0.0.1:1025 / http://127.0.0.1:8025 |

**Yalnız ilk yerel kurulumda**, mevcut .env yoksa parolayı konsola yazmadan oluşturun. Var olan .env veya volume için bu bloğu yeniden kullanmayın:

```powershell
if (Test-Path -LiteralPath .env) { throw 'Mevcut .env korunuyor; yeniden parola üretmeyin.' }
$nutritionBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
$nutritionPassword = [Convert]::ToHexString($nutritionBytes).ToLowerInvariant()
Set-Content -LiteralPath .env -Encoding ascii -Value "SMART_NUTRITION_POSTGRES_PASSWORD=$nutritionPassword"
$nutritionConnection = "Host=127.0.0.1;Port=5433;Database=smart_nutrition;Username=smart_nutrition;Password=$nutritionPassword;Timeout=3;Command Timeout=3"
@{ 'ConnectionStrings:DefaultConnection' = $nutritionConnection } | ConvertTo-Json -Compress | dotnet user-secrets set --project src/SmartNutrition.Api
Remove-Variable nutritionPassword, nutritionConnection, nutritionBytes
```

.env Git tarafından dışlanır; gerçek değerleri depoya/mesaja/loga eklemeyin. Environment değişkeni .env'den önceliklidir. Mevcut volume varken .env parolasını değiştirmek PostgreSQL parolasını değiştirmez.

```powershell
docker compose config --quiet
docker compose up -d --wait --wait-timeout 60
docker compose ps
```

Başka yetkili PostgreSQL kullanılıyorsa `ConnectionStrings:DefaultConnection` User Secrets veya `ConnectionStrings__DefaultConnection` environment değişkeniyle sağlanır. Ortam değişkeni User Secrets'ı geçersiz kılar. User Secrets geliştirme deposudur; şifreli üretim secret deposu değildir. `docker compose stop` veriyi silmez; volume silme/parola rotasyonu bu kurulumun parçası değildir.

### JWT

Auth:Jwt:Issuer, Audience ve SigningKeyBase64 zorunludur. Eksik/geçersiz ayarda API kimlik doğrulamayı açmaz. Anahtar Base64 kodlu en az 32 rastgele byte'tır; mevcut anahtarı rutin kurulumda yeniden üretmek mevcut JWT'leri geçersiz kılar.

Aşağıdaki **yalnız ilk kurulum** örneği 64 byte üretir; anahtar terminal çıktısına veya komut geçmişine düz değer olarak girilmez:

```powershell
$nutritionJwtKey = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(64))
@{
    'Auth:Jwt:Issuer' = 'smart-nutrition-api-local'
    'Auth:Jwt:Audience' = 'smart-nutrition-clients-local'
    'Auth:Jwt:SigningKeyBase64' = $nutritionJwtKey
} | ConvertTo-Json -Compress | dotnet user-secrets set --project src/SmartNutrition.Api
Remove-Variable nutritionJwtKey
```

Üretim karşılıkları Auth__Jwt__Issuer/Audience/SigningKeyBase64'tür; yerel issuer/audience üretim kararı değildir.

### Mailpit / SMTP

Mevcut .env korunarak yerel SMTP'yi ayarlayın:

```powershell
docker compose up -d --wait --wait-timeout 60 mailpit
@{
    'Email:Smtp:Host' = '127.0.0.1'
    'Email:Smtp:Port' = '1025'
    'Email:Smtp:FromAddress' = 'no-reply@smart-nutrition.local'
    'Email:Smtp:TlsMode' = 'None'
} | ConvertTo-Json -Compress | dotnet user-secrets set --project src/SmartNutrition.Api
```

Mailpit imajı axllent/mailpit:v1.32.0, portları yalnız loopback'tir. Dış iletim/kalıcı mail volume'u yoktur; sentetik alıcı kullanılır. SMTP Username/Password gerekiyorsa User Secrets veya environment ile sağlanır. None yalnız Development + loopback içindir; üretimde StartTls/SslOnConnect ve gerçek sağlayıcı gerekir.

E-posta doğrulama/reset akışları sınırlı bellek kuyruğu kullanır; 201/202 teslim garantisi değildir. Hata/yeniden başlatmada kullanıcı yeniden gönderim isteyebilir. Token/alıcı/SMTP protokolü veya ayrıntılı istisna loglanmaz. Reset e-postası güvenilir WebSession Origin varsa web fragment bağlantısını da içerir; mobil standalone kodu kullanabilir.

### EF migration

Migration dosyasının kodda bulunması, uygulama DB'sine uygulanması değildir. Kaynakta 20 migration vardır; sonuncusu `20261118230136_AddWaterLogSharingCategory`dır. Başlangıçta EnsureCreated/Migrate otomatik çalışmaz.

DB'ye bağlanmadan kaynak bağlamı/modeli kontrol etme komutları:

```powershell
dotnet ef dbcontext info --project src/SmartNutrition.Api
dotnet ef migrations list --no-connect --project src/SmartNutrition.Api
dotnet ef migrations has-pending-model-changes --project src/SmartNutrition.Api
```

DB güncellemesi yalnız hedef bağlantı doğrulanmış, kod ile DB geçmişi uyumlu ve mevcut veri için doğrulanabilir yedek alınmış yetkili kurulumda yapılır. Bu koşullarda **eski migration adı vermeden güncel kaynak hedefine**:

```powershell
$env:DOTNET_ENVIRONMENT = 'Development'
dotnet ef database update --project src/SmartNutrition.Api
```

Bu komut bağlı DB'yi değiştirir; test ortamı ile uygulama ortamı karıştırılmaz. Daha yeni/başka dalın migration geçmişi görülürse otomatik geri alma veya geçmiş düzeltme yapılmaz. Eski bir migration'ı hedeflemek sonraki migration'ları geri almaya çalışabilir; günlük kurulum talimatı değildir.

Geçmiş tablosu `__ef_migrations_history`dir. Yeni modül/kategori migration'larının veri bulunan Down işlemleri korumalıdır. Migration silme/yeniden adlandırma, database drop, EnsureDeleted, sıfıra geri alma veya volume silme normal kurulum değildir.

## 3. Çalıştırma

Bütün bileşenler için repo kökünden `./start.ps1` kullanılabilir; ayrıntı [kök README](../README.md)'dedir. Betik paket/sır/migration kurmaz.

Yalnız API için, DB/JWT/SMTP hazırken:

```powershell
dotnet run --project src/SmartNutrition.Api --launch-profile https
```

HTTPS 7099, aynı profilde HTTP 5052'dir. `--launch-profile http` da kaynakta vardır; web cookie akışı ve ortak mobil/web geliştirme HTTPS gerektirir. HTTP'ye düşerek cookie/TLS güvenliği gevşetilmez.

Güvenilir geliştirme sertifikası hazırken servis kontrolü:

```powershell
Invoke-WebRequest https://localhost:7099/health/live
Invoke-WebRequest https://localhost:7099/health/ready
```

live DB gerektirmez; ready PostgreSQL bağlantısını kontrol eder, başarısızlıkta genel 503 döner. `/openapi/v1.json` ve `/swagger` yalnız Development'tadır; mevcut öğün/görev/sağlık yollarını da içerir. Readiness başarısı bütün migration'ların veya ürün akışlarının doğrulandığı anlamına gelmez.

## 4. Geliştirme ortamı ve güvenlik

### Web oturumu ve HTTPS

Web ile API aynı HTTPS origin sözleşmesini kullanır; geliştirmede Vite API'ye proxy yapar. API'nin bağımsız HTTPS portu 7099, browser origin 5173'tür:

```powershell
$env:Auth__WebSession__Origin = 'https://localhost:5173'
$env:Auth__WebSession__KeyRingPath = "$env:LOCALAPPDATA/SmartNutrition/session-keys"
dotnet run --project src/SmartNutrition.Api --launch-profile https
```

Origin yalnız HTTPS authority, son slash/path/query olmadan tanımlanır. KeyRingPath mutlak, Git dışında ve uygulama hesabına kısıtlı kalıcı dizindir. Windows'ta DPAPI kullanılır. Windows dışında özel anahtarlı PFX için Auth__WebSession__KeyProtectionCertificatePath ve gerekiyorsa KeyProtectionCertificatePassword gerekir. Aynı key ring/uygulama adı bütün API örneklerinde korunur; klasörü rutin çalıştırmada silmeyin. Sertifika kurulumu [web README](../apps/web/README.md#web-oturumu-w2)'dedir.

Cookie Secure/HttpOnly/SameSite=Strict ve host kapsamlıdır. Cookie yazmaları Origin + CSRF ister; bearer ile cookie birlikte kabul edilmez. Idle 30 dakika, absolute 8 saat; güncel User/AuthSession her istekte kontrol edilir. Normal logout refresh ailesini veya ilgili web oturumunu iptal eder; mevcut access JWT kalan sürede geçebilir. Reset credentialsVersion artırır ve eski JWT/web/refresh'i yeni doğrulamada reddettirir.

### Admin kurulumu ve MFA

Genel kayıt/login/refresh Admin erişimi vermez. İlk Admin veya MFA yenilemesi HTTP endpointi değildir; API ile **aynı hedef DB, W2 Origin ve kalıcı korumalı key ring** ile backend/ içinden:

```powershell
$env:DOTNET_ENVIRONMENT = 'Development'
dotnet run --no-launch-profile --project src/SmartNutrition.Api -- --initialize-admin '<ozel-girdi-json-yolu>' '<yeni-enrollment-json-yolu>'
```

Development satırı yerel User Secrets kullanan kurulum içindir; gerçek dağıtımda o ortamın yetkili yapılandırması kullanılır. İki yer tutucu gerçek, Git dışındaki mutlak yollarla değiştirilir. Girdi yalnız email/password string alanlarını içerir; yalnız işletmen okuyabilir. Çıktı mevcut olmamalıdır; manualKey/otpAuthUri/recoveryCodes içerir, Windows ACL işletmene, Unix modu 0600'a kısıtlanır. Parola/TOTP/recovery'yi argümana veya loga koymayın; enrollment güvenli doğrulayıcıya aktarıldıktan sonra geçici özel dosyaları işletmen temizler.

**Mevcut Admin'de bu komut MFA'yı yeniler ve web oturumlarını iptal eder**; her geliştirme açılışında çalıştırılmaz. Mevcut parolayı doğrular, başka roldeki hesabı Admin'e dönüştürmez. Başarı 0/hata 1; dosya/DB hatasında rollback, mevcut çıktı üzerine yazma yoktur.

TOTP 6 hane/30 saniye/±1 adım, kullanılmış adım tekrar reddedilir; 10 adet 128 bit kurtarma kodunun yalnız hash'i tutulur. Parola reseti MFA'yı kaldırmaz. Development + Auth:AdminEmailCode:Enabled + loopback SMTP:1025 koşulunda Mailpit e-posta giriş kodu seçeneği vardır: 5 dakika, tek kullanım, 60 saniye gönderim aralığı ve 5 tüketim denemesi. Production/Staging bu alternatifi ve onun oturum kanıtını kabul etmez.

### Paylaşım ve veri koruma

Mevcut beş kategori bağımsızdır. Genel açılım bayrağı izin değildir; onaylı uzman + aktif ilişki + ilgili açık kategori sunucuda denetlenir. Admin MFA sağlık yetkisi vermez; kendi danışan verisi diyetisyen ilişkisine bağlı değildir.

appsettings.json'da MealLogsEnabled, BodyMeasurementsEnabled, ClientTasksEnabled, WaterLogsEnabled false'tur. Development dosyası yalnız MealLogsEnabled/ClientTasksEnabled değerlerini true yapar. **body_measurements yeni izin yazma/açma işlemi ayrıca Development şartı taşır.** WaterLogsEnabled da bu checkout'ta otomatik açık değildir. Gerçek ortam override'ları ayrıca değerlendirilir; yeni kategori açılımı istemci uyumu ve danışan onayı yerine geçmez.

Sağlık aktarımı yalnız client JWT/kendi profilidir; web/uzman paylaşımı açmaz. Ham sağlık verisi/token/parola/açıklama loglanmaz; sentetik test verisi kullanılır. Soft delete/tombstone, kalıcı KVKK silme değildir. Kalan üretim SMTP/proxy/ortak limit/audit/silme kapıları [11](../docs/11_SECURITY_AND_RELEASE.md)'dedir.

## 5. Testler ve doğrulama

### Ayrı, geçici PostgreSQL/Mailpit ortamı

**Uygulama DB'sini veya 5433 smart_nutrition bağlantısını test değişkenine vermeyin.** Factory test başına geçici schema oluşturur; bu, uygulama DB'sini test hedefi yapmayı güvenli hale getirmez. Testler DDL/migration/sentetik veri yazar ve temizlik yapar.

Aşağıdaki bilinen U6 ortamı backend testleri ve [web E2E rehberi](../apps/web/README.md#u5u6-gerçek-edge-https-testleri) için kullanılabilir. **Yeni, yalnız teste ayrılmış PowerShell terminalinde**, backend/ içinden çalıştırılır. Aynı isimde kaynak zaten varsa sahipliği doğrulanmadan yeniden kullanılmaz/silinmez. PostgreSQL verisi tmpfs'tedir; üretimde trust kullanılmaz.

```powershell
docker run --rm -d --name nutrition-u6-postgres --label smart-nutrition.test=U6 --tmpfs /var/lib/postgresql/data -p 127.0.0.1:55586:5432 -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_USER=nutrition_test -e POSTGRES_DB=nutrition_u6_test postgres:17
docker run --rm -d --name nutrition-u6-mailpit --label smart-nutrition.test=U6 -p 127.0.0.1:58028:8025 -p 127.0.0.1:51028:1025 axllent/mailpit:v1.32.0

$env:SMART_NUTRITION_TEST_CONNECTION_STRING = 'Host=127.0.0.1;Port=55586;Database=nutrition_u6_test;Username=nutrition_test;Pooling=true'
$env:SMART_NUTRITION_TEST_MAILPIT_URL = 'http://127.0.0.1:58028'
$env:SMART_NUTRITION_TEST_SMTP_HOST = '127.0.0.1'
$env:SMART_NUTRITION_TEST_SMTP_PORT = '51028'
$env:SMART_NUTRITION_TEST_SMTP_FROM = 'synthetic-u6@example.test'
$env:ConnectionStrings__DefaultConnection = $env:SMART_NUTRITION_TEST_CONNECTION_STRING
$env:DOTNET_ENVIRONMENT = 'Development'
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:Auth__WebSession__Origin = ''
$env:Auth__Jwt__Issuer = 'synthetic-u6'
$env:Auth__Jwt__Audience = 'synthetic-u6'
$env:Auth__Jwt__SigningKeyBase64 = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))

dotnet build SmartNutrition.Backend.slnx --no-restore
dotnet ef database update --project src/SmartNutrition.Api --no-build
dotnet test SmartNutrition.Backend.slnx --no-build --no-restore
```

Docker sağlıklı/hazır olmadan DB komutlarına geçilmez. EF komutunun hedefi burada **yalnız 55586/nutrition_u6_test**'tir; User Secrets'taki uygulama bağlantısı environment override ile kullanılmaz. Bu test terminalinden uygulama başlatıcısını çalıştırmayın; işlem sonunda terminali kapatarak test bağlantı/anahtar değişkenlerini bırakın. Restore/yerel EF tool kurulumu önceden yapılmış olmalıdır.

PostgresFact ve MailpitFact ortam değişkenleri yoksa ilgili testleri atlar; yeşil bir koşuda skip sayısını da inceleyin. Auth, reset, kategori matrisi, program/görev sürümleri, sağlık tekilleştirme ve migration veri koruması gerçek PostgreSQL testlerini içerir. Bu README'nin güncellenmesi testin çalıştırıldığı anlamına gelmez.

E2E için konteynerler gerekiyorsa açık bırakılır. İşiniz bitince yalnız bu koşuda başlattığınız konteynerlerin ID ve smart-nutrition.test=U6 etiketini `docker inspect` ile doğrulayıp `docker stop nutrition-u6-postgres nutrition-u6-mailpit` kullanın; --rm/tmpfs test verisini kaldırır. Uygulama konteynerlerine/volume'una dokunulmaz.

### Kapsam ve kanıt

Build/unit/API/PostgreSQL/Mailpit testleri, React tarayıcı ve fiziksel sağlık platformu testleri ayrı düzeylerdir. Geçmiş U5/U6 raporlarının tarih/commit/kapsamı [12](../docs/12_TEAM_PLAN_AND_DECISIONS.md)'dedir; eski sayılar güncel sonuç değildir. Bu belge görevinde build/test/servis/DB/migration çalıştırılmadı; komutlar kaynak/manifest üzerinden incelendi.

## 6. Bilinen sınırlamalar

- Migration'ın uygulama DB'sindeki durumu bu kaynak incelemesinde doğrulanmadı.
- Mevcut danışanın aynı hesapla uzman başvuru API'si vardır; aktif mobil navigasyon bağlantısı eksiktir.
- Üretimde yeni ölçüm izni açılımı, genel profil/uzman ret/geri alma akışları ve üretim güvenlik/teslim kapıları açık.
- Sağlık API testi fiziksel Android/Health Connect veya iOS/HealthKit doğrulaması değildir.
- AI/katalog/tarif/tahlil/OCR, bildirim teslimi, PDF ve genel uyum yöntemi tamamlanmış değildir; kapsamda korunur.

## 7. İlgili güncel dokümantasyon

[Ürün](../docs/01_PROJECT_SCOPE.md) · [Mimari](../docs/03_SYSTEM_ARCHITECTURE.md) · [Adlar](../docs/04_NAMING_CONVENTIONS.md) · [Veri](../docs/05_DATA_DICTIONARY.md) · [HTTP/DTO](../docs/06_API_CONTRACT.md) · [Güvenlik](../docs/11_SECURITY_AND_RELEASE.md) · [Durum/açık kararlar](../docs/12_TEAM_PLAN_AND_DECISIONS.md) · [Sağlık aktarımı](../docs/20_HEALTH_DATA_SYNC_CONTRACT.md)

Su veri/API/güvenlik kuralları 05/06/11 içindedir; eski 21 aktif kaynak değildir. Eski teslim/öneri kayıtları [mevcut arşivde](../docs/archive/README.md) tarihsel olarak bulunur.
