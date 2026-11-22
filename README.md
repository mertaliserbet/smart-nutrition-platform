# Smart Nutrition Platform

Diyetisyen odaklı beslenme takip platformu: danışan için Flutter mobil uygulama, diyetisyen/Admin için React web paneli ve ortak ASP.NET Core/PostgreSQL API.

**Kaynak inceleme tarihi: 22.11.2026 · kod tabanı: `4f160b3`.** Bu README mevcut kaynak kodla karşılaştırılmıştır; bu dokümantasyon görevinde servis, uygulama testi, cihaz veya veritabanı çalıştırılmadı. Tarihsel test beyanları ve doğrulama eksikleri [güncel durum belgesinde](docs/12_TEAM_PLAN_AND_DECISIONS.md) ayrılır.

## Mevcut ve planlanan özellikler

| Kaynakta mevcut | Onaylı, geliştirmesi veya doğrulaması kalan |
|---|---|
| Kayıt/e-posta, JWT/refresh, cookie/CSRF, Admin MFA, mobil/web parola sıfırlama | Üretim e-posta/anahtar/proxy, hesap silme ve kapsamlı veri hakları |
| Uzman başvuru/onay, arama/davet, aktif ilişki ve bağımsız kategori izinleri | Aynı danışan hesabıyla uzman başvurusunun aktif UI erişimi, uzman ret/yeniden başvuru/geri alma |
| Program oluşturma/atama/sürüm, mobil aktif program okuma, günlük tüketim karşılaştırması | Tam kişisel mobil program editörü, genel uyum yöntemi/aktivasyon zaman çizelgesi |
| Manuel öğün/su/ölçüm, kişisel hedefler, grafik, yorum/cevap ve görevler | Bildirim/hatırlatma teslimi, PDF raporu, geniş Admin/audit operasyonları |
| Native sağlık okuma ve ön plan HTTP aktarımı, manuel aktivite API'si | Fiziksel Android/iOS sağlık doğrulaması; mobil manuel aktivite formu |
| Açık/koyu tema ve ortak başlangıç tokenları | Nihai marka ve kapsamlı erişilebilirlik/cihaz onayı |
| Manuel kayıtların AI'dan bağımsız çalışması | Hibrit besin kataloğu/tarif, fotoğraftan yemek tahmini, manuel tahlil, ardından kullanıcı onaylı OCR ve açıklayıcı değerlendirme |

Mobil “Aktivite ekle”/“Tahlil ekle” ve web laboratuvar/aktivite önizlemeleri çalışan kayıt akışı değildir. Sentetik API testi fiziksel sağlık cihazı testi sayılmaz. Ürün kapsamı ve akışlar [01](docs/01_PROJECT_SCOPE.md), gerçek mobil/web ekranları [07](docs/07_MOBILE_SPEC.md)/[08](docs/08_WEB_SPEC.md)'dedir.

Fotoğraf kalorisi/porsiyonu tahmindir; kullanıcı kontrol/onayı gerekir. Tahlil çıktısı tanı/tedavi değildir. Gerçek kullanıcıya açılış, sentetik demo ve mağaza yayını ayrı aşamalardır; [güvenlik/yayın kapıları](docs/11_SECURITY_AND_RELEASE.md) korunur.

## Teknoloji ve yapı

- Mobil: Flutter/Dart, Material 3, flutter_secure_storage ve health.
- Web: React/TypeScript, React Router, Vite; Vitest/Testing Library, oxlint ve Playwright.
- Backend: .NET 10 / ASP.NET Core, EF Core/Npgsql, PostgreSQL 17; MailKit, Otp.NET ve yerel Mailpit.
- AI: henüz ayrı servis/model yok; gerektiğinde Python/FastAPI kullanımı onaylı.

Gerçek klasörler `mobile/`, `apps/web/`, `backend/src/SmartNutrition.Api/`, `backend/tests/`, `tools/` ve `docs/`'tur. Ayrıntı ve yapılandırma kaynakları [03](docs/03_SYSTEM_ARCHITECTURE.md)'tedir.

## Yerel kurulum

Komutlar mevcut betik, manifest ve yapılandırmayla kontrol edilmiştir; aşağıdaki servis/kurulum komutları bu görevde yürütülmedi.

1. Windows'ta Docker Desktop Linux motoru, PowerShell 7, .NET 10 SDK, uygun Node.js (`^20.19.0 || >=22.12.0`) ve Flutter hazır olmalıdır. iOS derleme/cihaz testi ayrıca macOS/Xcode gerektirir.
2. [Backend kurulumuna](backend/README.md) göre yerel `backend/.env`, ConnectionStrings:DefaultConnection, Auth:Jwt:Issuer/Audience/SigningKeyBase64 ve SMTP ayarlarını Git dışında hazırlayın. Mevcut sırları/.env veya DB volume'unu yeniden oluşturup ezmeyin.
3. Web cookie akışı için güvenilir localhost HTTPS sertifikası/özel anahtarı, Auth:WebSession:Origin=`https://localhost:5173` ve korumalı KeyRingPath gerekir. Ayrıntı [web](apps/web/README.md) ve [backend](backend/README.md) README'lerindedir. Bu dosyalardaki eski teslim/özellik notları yerine güncel [06](docs/06_API_CONTRACT.md)/[12](docs/12_TEAM_PLAN_AND_DECISIONS.md) kullanılır.
4. Uygulama DB'si gerekli migration sürümünde ayrıca hazırlanmış olmalıdır; başlangıçta otomatik migration yoktur. Migration uygulama, veri/volume silme veya üretim ayarı değiştirme ayrı yetkili işlemdir.
5. Paketleri kendi klasörlerinde hazırlayın:

```powershell
# backend/ içinde
dotnet restore
dotnet tool restore
```

```powershell
# apps/web/ içinde
npm ci --include=optional
```

```powershell
# mobile/ içinde
flutter pub get
```

Sertifika yolları `SMART_NUTRITION_HTTPS_CERT` ve `SMART_NUTRITION_HTTPS_KEY` ile verilir; ikisi de yoksa başlatıcı `LOCALAPPDATA/SmartNutrition/dev-cert.pem` ve `dev-cert.key` arar. Node güveni için mevcut NODE_EXTRA_CA_CERTS değeri yerel sertifikayı kapsamalıdır; başlatıcı değer verilmemişse PEM'i alt sürece geçirir. Özel anahtar Git'e veya cihaza kopyalanmaz; TLS doğrulaması kapatılmaz.

## Çalıştırma

Proje kökünden:

```powershell
.\start.ps1
```

VS Code'daki Smart Nutrition PowerShell profili PowerShell 7/RemoteSigned kullanır; önceden açık terminal ayar yenilendikten sonra yeniden açılmalıdır. Windows PowerShell 5.1'de betik aynı terminalde PowerShell 7'ye geçer. Script daha yüklenmeden policy engeline takılırsa önce [yerel kurulum notlarını](docs/03_SYSTEM_ARCHITECTURE.md) ve kendi ortam politikanızı kontrol edin; bu görevde sistem ayarı değiştirilmedi.

Başlatıcı Docker/API/web/uygun Android emülatörü ve Flutter'ı aynı terminalde yönetir. Paket kurmaz, sır üretmez, migration uygulamaz. Çalışan emülatör yoksa SDK'daki tek AVD soğuk başlatılabilir; verisi silinmez, birden çok AVD'de kullanıcı seçimi gerekir. Başkasının portunu kullanan süreç kapatılmaz. Ctrl+C yalnız bu çalıştırmanın sahip olduğu süreç/servisleri kapatır; volume ve önceden çalışan servisler korunur.

| Bileşen | Yerel adres |
|---|---|
| Diyetisyen web | [Giriş](https://localhost:5173/giris), [Başvuru](https://localhost:5173/uzman-basvurusu) |
| Admin | [Ayrı MFA girişi](https://localhost:5173/yonetici-giris) |
| API | [Swagger — yalnız Development](https://localhost:7099/swagger), [liveness](https://localhost:7099/health/live), [DB readiness](https://localhost:7099/health/ready) |
| PostgreSQL | 127.0.0.1:5433; Compose API'yi çalıştırmaz |
| Mailpit | [Yerel posta kutusu](http://127.0.0.1:8025), SMTP 127.0.0.1:1025 |

Mobil API `adb reverse tcp:7099 tcp:7099` ve debug'da açık geliştirme sertifikasıyla HTTPS kullanır. WEB_BASE_URL da Flutter'a aktarılır; mobil JWT harici web bağlantısına eklenmez. Release için API_BASE_URL ve WEB_BASE_URL gerçek HTTPS origin'leriyle ayarlanır.

### Android Chrome için yerel HTTPS

Android Chrome için Flutter güveni yeterli değildir. Yalnız test AVD'sinde PowerShell 7.5+ ile:

```powershell
adb devices
.\setup-local-https.ps1 -EmulatorId emulator-5580 # listeden kendi test AVD kimliğiniz
```

Yalnız açık CA Android standart CA yükleme ekranından kurulmalıdır. Windows güven deposuna veya kişisel cihaza CA eklemeyin; sertifika hatasını atlamayın. Geçit/tünel/geri alma ve CA ömrü [03](docs/03_SYSTEM_ARCHITECTURE.md)'tedir.

## Test ve doğrulama

| Klasör | Mevcut komutlar | Koşul / kapsam |
|---|---|---|
| backend/ | `dotnet build SmartNutrition.Backend.slnx --no-restore`; `dotnet test SmartNutrition.Backend.slnx --no-restore` | Birim ve gerçek PostgreSQL/API testleri; ayrı sentetik test DB/SMTP ortamı gerekir |
| apps/web/ | `npm run typecheck`, `npm run lint`, `npm test`, `npm run build` | React DOM/DTO/statik analiz ve paket derlemesi; gerçek tarayıcı değildir |
| apps/web/ | `npm run test:e2e` | Playwright/kurulu Edge + ayrı U6 HTTPS/API/DB ortamı; kurulum alt web README/e2e betiğinde |
| mobile/ | `flutter analyze`, `flutter test` | Unit/widget; live/device probe'lar ayrıca ve kendi sentetik ortamında çalışır |
| Repo kökü | `git diff --check` | Whitespace; uygulama davranış testi değildir |

Backend test DB'si için SMART_NUTRITION_TEST_CONNECTION_STRING kullanılır; Mailpit testlerinin ek ortam değişkenleri alt backend README'sindedir. Uygulama DB'si test hedefi değildir. Testlerin atlanması, özellikle PostgreSQL/SMTP veya opt-in canlı senaryoların çalıştığı anlamına gelmez.

Tarihsel test sayıları burada güncel sonuç diye verilmez. Tarih/commit/kapsam ve bu incelemenin sınırı [12](docs/12_TEAM_PLAN_AND_DECISIONS.md)'dedir. Bu görevde yalnız dokümantasyon/dosya/bağlantı ve diff kontrolleri yapılmıştır.

## Ortak çalışma

Önce [AGENTS.md](AGENTS.md) okunur. Mobil/web ağırlıkları uzmanlık dağılımıdır; backend/API/migration/entegrasyon her iki geliştiricinin görev kapsamına girebilir. Aynı dosya/özellik üzerinde koordinasyonsuz paralel yazılmaz. Yazma/Git izinleri ve mevcut Mert main / Uğur fork–PR modeli AGENTS.md'dedir; bu README otomatik senkronizasyon veya commit talimatı vermez.

## Aktif dokümantasyon

| Belge | Tek ana sorumluluk |
|---|---|
| [01](docs/01_PROJECT_SCOPE.md) | Ürün kapsamı, roller, kullanıcı akışları |
| [03](docs/03_SYSTEM_ARCHITECTURE.md) | Gerçek mimari, klasörler ve yerel altyapı |
| [04](docs/04_NAMING_CONVENTIONS.md) | Kanonik adlar ve terminoloji |
| [05](docs/05_DATA_DICTIONARY.md) | Kalıcı model/alan/ilişki/kısıtlar |
| [06](docs/06_API_CONTRACT.md) | HTTP/DTO/yetki/hatalar |
| [07](docs/07_MOBILE_SPEC.md) | Gerçek Flutter ekranları |
| [08](docs/08_WEB_SPEC.md) | Gerçek React ekranları |
| [09](docs/09_DESIGN_SYSTEM.md) | Uygulanan tokenlar ve tasarım kuralları |
| [10](docs/10_AI_SPEC.md) | AI/katalog/tahlil/OCR gereksinimleri |
| [11](docs/11_SECURITY_AND_RELEASE.md) | Mahremiyet, veri hakları ve yayın kapıları |
| [12](docs/12_TEAM_PLAN_AND_DECISIONS.md) | Görev sahipliği, durum, doğrulama ve açık kararlar |
| [20](docs/20_HEALTH_DATA_SYNC_CONTRACT.md) | Sağlık aktarımı, birim, kaynak ve tekilleştirme |

[Arşiv](docs/archive/README.md) eski plan, proposal ve teslim kayıtlarını saklar; güncel teknik sözleşme değildir.
