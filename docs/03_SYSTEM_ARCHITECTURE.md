# 03 — Sistem mimarisi ve repository yapısı

Kaynak inceleme tabanı: 22.11.2026, yerel kod commit'i `4f160b3`. Bu belge çalışan süreç veya veritabanı incelemesi değildir; klasörler, bağımlılık dosyaları, yapılandırma ve kaynak koddan doğrulanmıştır.

## Gerçek bileşenler

| Katman | Mevcut uygulama |
|---|---|
| Mobil | `mobile/`: Flutter/Dart, Material 3, `flutter_secure_storage`, `health`, `url_launcher` |
| Web | `apps/web/`: React 19, TypeScript 6, React Router 7, Vite 8; Vitest/Testing Library, oxlint ve Playwright |
| API | `backend/src/SmartNutrition.Api/`: .NET 10 / ASP.NET Core, EF Core 10, Npgsql, Identity PasswordHasher, JWT, Cookie Authentication/Data Protection, MailKit ve Otp.NET |
| Veri | PostgreSQL 17; EF migration'ları ve `AppDbContextModelSnapshot` kaynakta mevcut |
| Yerel e-posta | Compose içinde Mailpit; üretim teslim sağlayıcısı değildir |
| AI | Ayrı servis, model veya inference entegrasyonu yok. İhtiyaç halinde Python/FastAPI onaylı teknoloji; [10](10_AI_SPEC.md) |

Tam sürüm kaynakları `backend/global.json`, API csproj, `apps/web/package.json`/lockfile ve `mobile/pubspec.yaml`/lockfile'dır. Flutter için Dart SDK kısıtı `^3.12.2`, health paketi `13.3.2`dir; sürüm yükseltme kararı bu belgeyle verilmez.

```text
smart-nutrition-platform/
├── AGENTS.md
├── README.md
├── start.ps1
├── setup-local-https.ps1
├── tools/android-browser-https.mjs
├── .vscode/settings.json
├── docs/                         # 12 aktif ana belge + archive/
├── backend/
│   ├── SmartNutrition.Backend.slnx
│   ├── global.json
│   ├── compose.yaml
│   ├── src/SmartNutrition.Api/
│   │   ├── Features/             # Auth, Dietitians, Relationships, NutritionPlans,
│   │   │                         # MealLogs, WaterLogs, PersonalNutritionTargets,
│   │   │                         # BodyMeasurements, ClientTasks, HealthData
│   │   ├── Data/                 # AppDbContext + Migrations/
│   │   ├── Models/
│   │   ├── Infrastructure/
│   │   └── Health/
│   └── tests/SmartNutrition.Api.Tests/
├── apps/web/
│   ├── src/core/                 # theme, components
│   ├── src/features/             # auth, dietitians, relationships, clients,
│   │                             # nutritionPlans, clientTasks, workspace
│   └── e2e/
└── mobile/
    ├── lib/core/                 # network, theme, widgets
    ├── lib/features/             # auth, navigation, home, nutrition, water,
    │                             # body_measurements, personal_nutrition_targets,
    │                             # dietitians, client_tasks, health, progress, profile
    ├── android/
    ├── ios/
    └── test/
```

`apps/mobile`, `services/api` ve `services/ai` mevcut klasörler değildir; eski öneri yapı, gerçek repo yerine kullanılmaz.

## İstek ve veri akışı

Mobil ve web aynı `/api/v1` API'sini kullanır; doğrudan DB bağlantısı yoktur. Controller'lar HTTP/şekil kontrollerini, feature servisleri iş kurallarını ve transaction'ları yürütür. EF eşlemeleri entity/feature altında, migration ve snapshot Data altındadır. Gereksiz repository/katman ekleme zorunluluğu yoktur.

Mobil bearer ve güvenli refresh deposu, web ise aynı HTTPS origin üzerinden cookie/CSRF kullanır. Kaynak/profil/ilişki/kategori kontrolü sunucudadır. Kimlik taşıma ve endpoint kuralları [06](06_API_CONTRACT.md), güvenlik ve üretim koşulları [11](11_SECURITY_AND_RELEASE.md) içindedir.

Sağlık senkronizasyonunda User → ClientProfile kilitleri, sürümler ve batch receipt kullanılır. Özetler/sayfalı izinli okumalar tutarlı snapshot'larla alınır. Günlük toplamlar kalıcı ayrı sağlık tabloları değildir. Veri modeli [05](05_DATA_DICTIONARY.md), aktarım politikası [20](20_HEALTH_DATA_SYNC_CONTRACT.md) içindedir.

## Yapılandırma ve yerel geliştirme

Kurulum/başlatma komutlarının ana kaynağı [kök README](../README.md)'dir. Alt [backend](../backend/README.md), [web](../apps/web/README.md) ve [mobil](../mobile/README.md) README'lerinde ayrıntılı komutlar vardır; tarihli teslim notları güncel özellik durumu için kullanılmaz.

- API launch profilleri HTTP 5052 ve HTTPS 7099; Vite varsayılan 5173'tür. Cookie akışı HTTPS gerektirir. Vite proxy hedefleri `apps/web/vite.config.ts` içindedir; mobil-only yolların tamamı web proxy'sinde bulunmaz.
- Compose API'yi çalıştırmaz: PostgreSQL `127.0.0.1:5433`, Mailpit SMTP 1025/UI 8025 sunar. Parola dışarıdan gelir; kalıcı volume korunur.
- ConnectionStrings:DefaultConnection ve JWT issuer/audience/SigningKeyBase64 repo dışında ayarlanır. Web için Auth:WebSession:Origin ve KeyRingPath gerekir. Başlangıçta otomatik EnsureCreated/Migrate yoktur.
- Genel paylaşım ayarları varsayılan false'tur. Kaynaktaki Development override'ı yalnız MealLogsEnabled ve ClientTasksEnabled değerlerini true yapar; BodyMeasurementsEnabled ve WaterLogsEnabled için aynı varsayım yapılamaz. Gerçek ortamın secrets/environment override'ları bu incelemede okunmadı.
- `start.ps1` aynı terminalde API, web ve uygun Android emülatörü/Flutter alt süreçlerini yönetir. Eksik bağımlılık/paket/ayar veya migration'ı otomatik kurmaz. Başkasının portundaki süreci kapatmaz; Ctrl+C kendi süreçlerini ve kendisinin başlattığı servisleri temizler.
- API `/health/live` DB'ye ihtiyaç duymaz; `/health/ready` PostgreSQL'i kontrol eder. `/openapi/v1.json` ve `/swagger` yalnız Development ortamında açılır.

## Android tarayıcı için yerel HTTPS

Flutter'ın API geliştirme sertifikasına güvenmesi Android Chrome'un web sertifikasına güvendiği anlamına gelmez. `setup-local-https.ps1`, PowerShell 7.5+ ile yalnız test AVD'si için yerel CA ve localhost sunucu sertifikası hazırlar; kullanım komutu kök README'dedir.

CA özel anahtarı CurrentUser DPAPI ile korunur; dosyalar `LOCALAPPDATA/SmartNutrition/browser-https` altında kullanıcı/SYSTEM erişimiyle tutulur. Yalnız açık CA emülatör Download klasörüne kopyalanır ve Android'in standart CA yükleme ekranında kullanıcı tarafından kurulur. CA iki yıl, sunucu sertifikası 180 gün geçerlidir; son yedi günde sunucu sertifikası yenilenir. CA değişiminde Android güven onayı yeniden gerekir.

CA dosyaları varsa akış Android Chrome localhost:5173 → adb reverse 5173:5174 → loopback HTTPS geçidi → sertifikası doğrulanan Vite 5173 → API 7099'dur. Web origin'i değişmez; API tüneli 7099:7099 kalır. CA yoksa doğrudan web tüneli kullanılır; bu, tarayıcı güvenini sağlamaz. Farklı hedefe bağlı tüneller otomatik değiştirilmez.

Windows güven deposuna CA eklenmez, kişisel/fiziksel cihaza kurulum yapılmaz, özel anahtar cihaza kopyalanmaz. HTTP'ye düşme, sertifika uyarısını atlama veya TLS doğrulamasını kapatma yoktur. Geri almada yalnız test AVD'sindeki Smart Nutrition Local Development CA kaldırılır; bütün sertifikalar veya AVD verisi silinmez. Bu akış üretim sertifika altyapısı değildir.

## Planlanan mimari parçalar

AI/OCR, dosya depolama/tarama, kalıcı bildirim/e-posta teslimi, PDF üretimi, dağıtım sağlayıcısı, ortak rate limit ve üretim izleme ayrıca geliştirilir. Queue, WebSocket, yeni bulut sağlayıcısı veya genel job modeli mevcutmuş gibi kabul edilmez. Gerçek veri/yayın kapıları [11](11_SECURITY_AND_RELEASE.md), açık kararlar [12](12_TEAM_PLAN_AND_DECISIONS.md) içindedir.
