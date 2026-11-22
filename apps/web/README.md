# Smart Nutrition — Web

## 1. Amaç ve güncel özellikler

React/TypeScript uygulaması diyetisyen çalışma alanı ve ayrı Admin panelidir. Kaynak inceleme tabanı **22.11.2026 / `4f160b3`**; bu belge görevinde tarayıcı, servis, test veya DB çalıştırılmadı.

| Bölüm | Gerçek API'ye bağlı davranış |
|---|---|
| Giriş/hesap | W2 HTTPS cookie/CSRF, uzman başvuru durumu, hesap özeti ve sunucuda çıkış |
| Uzman/Admin | Yeni uzman başvurusu, e-posta doğrulama, ayrı MFA Admin girişi ve uzman onayı |
| Bağlantı/danışan | Davet kodu, kabul/red/sonlandırma, gerçek aktif danışan listesi/kimlik detayı |
| Program | Oluşturma, kendi atadığını düzenleme, açık etkinleştirme/arşivleme, değişmez sürümler |
| Öğün/ölçüm | Kategori izniyle salt okunur öğün ve ölçüm/grafik; öğün yorumu/tek düzey yanıt |
| Görev | Gerçek atama/düzenleme/iptal, durum/tamamlama, son tarih ve sürüm geçmişi |
| Su | Bağımsız water_logs izniyle gün kayıt/toplamı, en çok 31 günlük grafik/tablo |
| Karşılaştırma | Açık program sürümü/gün seçimi, bilinen toplam/eksik besin ve koşullu kcal farkı |
| Parola sıfırlama | Gerçek talep, Mailpit bağlantısındaki fragment kodu, yeni parola ve eski oturumların iptali |

Aktif rotalar App.tsx'tedir: /giris, /sifremi-unuttum, /eposta-dogrulama, /hesabim, /uzman-basvurusu, /uzman/basvuru-durumu, /yonetici-giris, /yonetim/uzmanlar ve /calisma-alani altı. /kayit → /giris yönlenir; eski RegistrationPage dosyası aktif danışan web kaydı değildir.

Çalışma alanı /calisma-alani, /danisanlar, /danisanlar/:clientId ve /baglantilar yollarını sunar. Doğrulanmamış uzman başvuru takibine gider; normal danışanın uzman profili yoksa web çalışma alanı açılmaz. client temel rolünü koruyan onaylı çift profilli uzman desteklenir.

**/onizleme/** yalnız Development'ta sentetik WorkspacePreview'dır. Laboratuvar/aktivite örnek listeleri gerçek uzman sağlık paylaşımı değildir. Demo verisi gerçek API hatasında yedek sonuç olarak gösterilmez. Tarif, bildirim teslimi, PDF, genel uyum yöntemi ve geniş Admin/audit operasyonları henüz tamamlanmamıştır.

## 2. Gereksinimler ve kurulum

Komutlar aksi belirtilmedikçe **apps/web/** içindedir.

- Node.js engine kısıtı `^20.19.0 || >=22.12.0`; npm ve package-lock kullanılır.
- React 19 / TypeScript 6 / Router 7 / Vite 8; Vitest/Testing Library/oxlint ve Playwright bağımlılıkları manifesttedir.
- Çalışan backend/PostgreSQL ve SMTP için [backend README](../../backend/README.md).
- Cookie akışı için aynı HTTPS origin, güvenilir localhost sertifikası ve backend W2 ayarları.

```powershell
npm ci --include=optional
```

Paket/sürüm veya ikinci panel eklenmez. UI tokenları src/core/theme, gerçek özellikler src/features, gerçek tarayıcı testleri e2e altındadır.

## 3. Çalıştırma komutları

Bütün bileşenler için repo kökünden:

```powershell
.\start.ps1
```

Yalnız web için HTTPS ayarları hazırlandıktan sonra apps/web/ içinde:

```powershell
npm run dev
```

Geliştirme web origin'i https://localhost:5173, API HTTPS portu 7099'dur. start.ps1 yeni paket/sır/migration kurmaz, başkasının portundaki süreci kapatmaz. HTTPS eksikse Vite'ın sınırlı anonim HTTP proxy seçeneği gerçek W2 oturum kurulumu sayılmaz.

`npm run build` TypeScript kontrolü ve üretim paketini oluşturur. `npm run preview` yalnız paketi yerel incelemek içindir; kaynakta preview sunucusu geliştirme API proxy'sini kurmaz. Üretim reverse proxy/HTTPS/host yapılandırması ayrı dağıtım işidir.

## 4. Geliştirme ortamı ve güvenlik

### Web oturumu (W2)

Backend HTTPS profili, Auth:WebSession:Origin=`https://localhost:5173` ve Git dışında kalıcı/korumalı KeyRingPath ile çalışmalıdır. Anahtar koruması Windows'ta DPAPI, diğer platformlarda özel anahtarlı koruma sertifikasıdır; [backend ayarları](../../backend/README.md#web-oturumu-ve-https).

Sertifika mevcutsa onun PEM/özel anahtar çifti kullanılır. **Yalnız ilk kurulumda**, Git dışındaki dizinde güvenilir geliştirme sertifikasını hazırlama örneği:

```powershell
New-Item -ItemType Directory -Path "$env:LOCALAPPDATA/SmartNutrition" -Force | Out-Null
dotnet dev-certs https --trust
dotnet dev-certs https --export-path "$env:LOCALAPPDATA/SmartNutrition/dev-cert.pem" --format Pem --no-password
```

Mevcut sertifika/anahtar dosyalarının üzerine rutin kurulumda yazılmaz. Geliştirme anahtarı özel dosyadır; erişimi kendi hesabınıza kısıtlayın, Git'e veya cihaza taşımayın. Ardından aynı terminalde:

```powershell
$env:SMART_NUTRITION_HTTPS_CERT = "$env:LOCALAPPDATA/SmartNutrition/dev-cert.pem"
$env:SMART_NUTRITION_HTTPS_KEY = "$env:LOCALAPPDATA/SmartNutrition/dev-cert.key"
$env:NODE_EXTRA_CA_CERTS = $env:SMART_NUTRITION_HTTPS_CERT
npm run dev
```

İki sertifika yolu birlikte verilir; vite.config.ts PEM'leri okur ve secure=true ile API'ye proxy yapar. NODE_EXTRA_CA_CERTS zaten kullanılıyorsa gereken mevcut CA'ları da kapsayan güven kümesi korunmalıdır. TLS kontrolünü kapatma, HTTP'ye düşme, Secure/SameSite gevşetme veya credential CORS açma yoktur. Android Chrome güveni ayrıca [kök README](../../README.md#android-chrome-için-yerel-https)'de anlatılır.

Web JWT login/refresh'i çağırmaz. CSRF ve hesap yalnız bellektedir; cookie HttpOnly/Secure/SameSite=Strict'tir. Cookie yazmaları tam Origin + oturuma bağlı X-CSRF-TOKEN ister. Giriş sonrası yeni CSRF alınır; hesap/CSRF değişiminde yazma otomatik tekrarlanmaz.

Backend her istekte hesabı/oturumu denetler; idle 30 dakika, absolute 8 saattir. Oturumu yaşatma polling'i yoktur. Çıkışta hassas görünüm temizlenir; yalnız sunucunun 204 yanıtı doğrulanmış çıkıştır. Ağ/500 sonucunda sunucuda iptal garantisi verilmez.

### Admin ve uzman yetkisi

Admin ayrı /yonetici-giris formunda parola + TOTP/kurtarma koduyla girer; kurulum/MFA yenileme [backend rehberindedir](../../backend/README.md#admin-kurulumu-ve-mfa). MFA, danışan sağlık verisine erişim yetkisi değildir. Parola reseti Admin MFA'yı kaldırmaz.

Development + uygun loopback SMTP:1025 + Auth:AdminEmailCode:Enabled koşulunda “E-posta ile kod gönder” Mailpit seçeneği vardır; üretim MFA alternatifi değildir. Genel 202 teslim/giriş garantisi sayılmaz. U6 test ortamı bu seçeneği kapatır; TOTP/recovery güvenlik testleri backend paketinde ayrı kapsamdadır.

Uzman onayı, aktif ilişki ve kategori izni backend'de kontrol edilir. Program/öğün/ölçüm/görev/su izinleri bağımsızdır; web danışan adına izin açmaz. Program–tüketim iki ilgili izni birlikte ister. Kişisel su hedefi water_logs iznine dahil değildir.

### Form, veri ve reset davranışı

Danışan/hesap/gün/sürüm/filtre değişince eski içerik ve sayılar kaldırılır, geç yanıtlar elenir. 401/403/404, yetkili boş liste, null/sıfır ve ağ/DB hatası farklı sunulur. Görevde 409 taslağı korur, güncel sürümle açık yeniden başlatma ister; otomatik overwrite yoktur. Görev/su görünür sekmede 30 saniye/fokus/elle yeniler; bu, bildirim veya WebSocket değildir.

Reset /sifremi-unuttum üzerinden çalışır. Bağlantıdaki #token fragment'i yalnız belleğe alınır ve URL/history replace ile temizlenir; query/bozuk/tekrarlı token kabul edilmez. Kalıcı depo/router state/log/analitik veya referrer'a taşınmaz. Yenilemede bağlantının yeniden açılması/yeni talep gerekir; POST otomatik tekrarlanmaz. 204 sonrası /giris'e dönülür, otomatik giriş yoktur.

## 5. Testler ve doğrulama

### Statik analiz ve React DOM

```powershell
npm run typecheck
npm run lint
npm test
npm run build
```

typecheck/build tsc, lint oxlint, test Vitest kullanır. React DOM ve DTO testleri gerçek tarayıcı değildir. Kaynakta ihtiyaç halinde daha sınırlı worker ile kullanılan komut da vardır:

```powershell
node node_modules/vitest/vitest.mjs run --maxWorkers=2
```

Üç opt-in canlı React DOM testi ayrı eski ortamları bekler; standart test koşusu bunları çalıştırmış sayılmaz:

| Test | Gerekli ayrı ortam |
|---|---|
| ClientTaskPanel.live.test.tsx | SNP_TASK_WEB_LIVE=1, SNP_TASK_WEB_ORIGIN=https://localhost:7443, SNP_TASK_WEB_CA ve SNP_TASK_WEB_PSQL |
| BodyMeasurementPanel.live.test.tsx | SNP_MEASUREMENT_WEB_LIVE=1, SNP_SHARING_CONTAINER ve SNP_MEASUREMENT_WEB_CA; https://localhost:7101 |
| MealLogComments.live.test.tsx | SNP_COMMENT_WEB_LIVE=1, SNP_SHARING_CONTAINER ve SNP_COMMENT_WEB_CA; https://localhost:7101 |

Bu ortamlar U6 ile aynı değildir; source'taki değişken/sabitler doğrulanmadan opt-in açılmaz. Test atlanması başarı kanıtı değildir.

### U5/U6 gerçek Edge HTTPS testleri

Kaynaklar `playwright.config.ts`, `tsconfig.e2e.json`, `e2e/Start-TestServers.ps1` ve `e2e/regression.e2e.ts`dir. Kurulu Microsoft Edge, PowerShell 7/Windows, Docker, restore edilmiş/derlenmiş backend, npm paketleri ve **önceden güvenilir/geçerli localhost geliştirme sertifikası** gerekir. Playwright MS Edge kanalını kullanır; yeni tarayıcı kurulumu bu rehberin önkoşulu değildir.

Önce [backend'in izole test ortamı](../../backend/README.md#ayrı-geçici-postgresqlmailpit-ortamı) hazırlanır. Beklenen kaynaklar:

| Kaynak | Sabit test hedefi |
|---|---|
| PostgreSQL | nutrition-u6-postgres, U6 etiketi, 127.0.0.1:55586/nutrition_u6_test, nutrition_test |
| Mailpit | nutrition-u6-mailpit, U6 etiketi, HTTP 58028 / SMTP 51028 |
| API / web | https://localhost:7099 / https://localhost:5446 |

Uygulama volume'u kullanılmaz. **Yalnız bu yeni test DB'sine** backend kurulumundaki güncel-hedef EF komutu uygulanmış ve API DLL'i build edilmiş olmalıdır. Uygulama API'si 7099'u kullanıyorsa bu testle aynı anda çalışmaz; betik portu kullanan başka süreci kapatmaz.

**Ayrı test PowerShell terminalinde**, apps/web/ içinden:

```powershell
$nutritionU6Artifacts = Join-Path $env:TEMP ('nutrition-u6-' + [guid]::NewGuid().ToString('N'))
pwsh -NoProfile -File ./e2e/Start-TestServers.ps1 -Artifacts $nutritionU6Artifacts
```

Betik çağıran süreçte environment ayarlar; ayrı pwsh süreci API/Vite çocuklarına bu ayarları geçirirken ana terminalin API/JWT ayarlarını değiştirmemesini sağlar. Betik yeni Git dışı klasörde özel TLS kopyaları/test key ring ve PID/yol/başlangıç zamanı sahiplik kaydı oluşturur. Ana geliştirme sertifikasını/güven deposunu değiştirmez.

Başlatma çıktısı servis hazırlığı kanıtı değildir. API/web hazır olmadan teste geçmeyin; güvenilir sertifikayla şu kontroller başarılı olmalıdır:

```powershell
Invoke-WebRequest https://localhost:7099/health/ready
Invoke-WebRequest https://localhost:5446/giris
```

Ardından aynı test terminalinde:

```powershell
$env:SNP_E2E_TEST_ENV = 'nutrition_u6_test'
$env:SNP_E2E_RESULTS = Join-Path $nutritionU6Artifacts 'results'
$env:NODE_EXTRA_CA_CERTS = Join-Path $nutritionU6Artifacts 'localhost.pem'
npm run test:e2e
```

Komut önce ayrı E2E TypeScript kontrolünü, sonra gerçek Edge testlerini çalıştırır. ignoreHTTPSErrors=false, Secure cookie/tam Origin/CSRF/normal limitler korunur; retries=0, tek worker, trace/video/screenshot ve kalıcı Auth storage kapalıdır. Sonuç dizini mutlak ve Git dışında olmalıdır.

Senaryolar gerçek giriş/aktif danışan/görev/geçmiş, bağımsız su izni/geri çekme, CSRF/yabancı Origin, reset e-postası/URL temizliği/eski kimliklerin iptali, yenileme/klavye/iki tema/dar ekran ve sunucu oturum süresi davranışlarını kapsar. Danışan adımları API olabilir; Flutter veya fiziksel sağlık testi değildir. Onay/expiry hazırlığı yalnız U6 etiketli DB'deki yeni sentetik UUID/e-postalara sınırlı SQL kullanır; gerçek Admin inceleme UI provası yerine geçmez.

Test başarısız olsa da yalnız sahip olunan API/web/test anahtarlarını durdurun:

```powershell
pwsh -NoProfile -File ./e2e/Start-TestServers.ps1 -Artifacts $nutritionU6Artifacts -Stop
```

-Stop PID/yol/başlangıç zamanı, klasör işareti ve anahtar hash'ini doğrular; uyuşmazlıkta dosya/süreç korunur. npm test sonucunu cleanup komutunun çıkış koduyla karıştırmayın. Sonra yalnız kendi oluşturduğunuz U6 konteynerlerini ID/etiket doğrulamasıyla backend rehberine göre kapatın; test terminalini kapatarak E2E environment'ını bırakın.

Bu dokümantasyon görevinde test/build/lint/E2E veya bu kurulum komutları çalıştırılmadı. Geçmiş U5/U6 sonuçları [12](../../docs/12_TEAM_PLAN_AND_DECISIONS.md)'de tarih/commit/kapsamla verilir; README güncel başarı sayısı iddia etmez.

## 6. Bilinen sınırlamalar

- Mevcut danışan hesabıyla uzman başvuru API'si/eskiden hazırlanmış mobil widget vardır; aktif mobil Profile/AuthGate navigasyonu başvuruya erişmiyor. Webdeki mobil Profil yönlendirme metni çalışır uçtan uca başvuru garantisi değildir.
- Backend'de yeni ölçüm izni oluşturma/açma Development şartına bağlıdır; üretim açılım kararı ayrıca gereklidir.
- Laboratuvar/aktivite önizlemeleri, tarif/katalog/AI/OCR, bildirim teslimi/PDF ve geniş Admin operasyonları gerçek tamamlanmış ekranlar değildir.
- Fiziksel Android/iOS sağlık aktarımı, üretim SMTP/proxy/ortak limit/anahtar/audit ve kapsamlı erişilebilirlik ayrıca doğrulanır.
- Vite preview yerel API'li dağıtım ortamı değildir; üretim hosting/reverse proxy bu görevde seçilmez.

## 7. İlgili güncel dokümantasyon

[Kök kurulum](../../README.md) · [Ürün](../../docs/01_PROJECT_SCOPE.md) · [Mimari](../../docs/03_SYSTEM_ARCHITECTURE.md) · [Adlar](../../docs/04_NAMING_CONVENTIONS.md) · [Veri](../../docs/05_DATA_DICTIONARY.md) · [HTTP/DTO](../../docs/06_API_CONTRACT.md) · [Gerçek web ekranları](../../docs/08_WEB_SPEC.md) · [Tasarım](../../docs/09_DESIGN_SYSTEM.md) · [Güvenlik](../../docs/11_SECURITY_AND_RELEASE.md) · [Durum/açık kararlar](../../docs/12_TEAM_PLAN_AND_DECISIONS.md) · [Sağlık aktarımı](../../docs/20_HEALTH_DATA_SYNC_CONTRACT.md)

Su veri/API/güvenlik kuralları 05/06/11'dedir; arşivlenen 21 aktif sözleşme değildir. Tarihsel U1–U6 teslimleri [mevcut arşivde](../../docs/archive/README.md) korunur. Görev/Git/yazma sınırları [AGENTS.md](../../AGENTS.md)'ye tabidir.
