# Smart Nutrition — Mobil

## 1. Amaç ve güncel özellikler

Flutter uygulaması danışanın kişisel beslenme takibi ve izinli diyetisyen ilişkisi içindir. Kaynak inceleme tabanı **22.11.2026 / `4f160b3`**; bu belge güncellemesinde Flutter/cihaz/test çalıştırılmadı.

| Alan | Aktif uygulama |
|---|---|
| Auth | Gerçek kayıt, e-posta doğrulama/yeniden gönderim, JWT login/me, güvenli refresh saklama/rotasyon ve çıkış |
| Parola sıfırlama (M5) | Email talebi, e-postadaki standalone kod, yeni parola/tekrar ve başarı sonrası girişe dönüş |
| Öğün/su | Manuel CRUD, geçmiş/detay, nullable enerji/makro ve gerçek günlük su toplamı |
| Hedef/ölçüm | Beş kişisel günlük hedef, kilo/bel/kalça/göğüs/yağ kayıtları ve grafik |
| Program/yorum | Aktif kişisel/atanmış programı salt okunur görme, seçilen sürümle günlük tüketim karşılaştırması, öğün yorumu/tek düzey cevap |
| İlişki/paylaşım (M4) | Uzman arama, istek/ilişki sonlandırma, beş bağımsız kategori izni ve sayfalama |
| Görev (M2) | Liste/detay/geçmiş, danışanın izinli durum değişikliği ve hatırlatma tercihi |
| Sağlık (M1/M3) | Health Connect/HealthKit uygunluk/izin/okuma, ayrı açık ön plan HTTP aktarımı, bağlantı durumu ve backend gün özeti |
| Mobil kontrol (M6) | Unit/widget ve live/device probe kaynakları; varlıkları başarılı koşu/cihaz kanıtı değildir |

MainShell sekmeleri Ana Sayfa, Beslenme, İlerleme ve Profil'dir. Dashboard öğün/su/hedef/program için gerçek API okur. Hızlı işlemlerde **Öğün ekle/Su ekle gerçek**, **Aktivite ekle/Tahlil ekle önizlemedir**; bu iki önizleme kayıt oluşturmaz. Manuel aktivite API'sinin bulunması mobil formun tamamlandığı anlamına gelmez.

Beş kategori `nutrition_plans`, `meal_logs`, `body_measurements`, `client_tasks`, `water_logs` olarak ayrı yönetilir; biri diğerini açmaz. Uzman/Admin danışan adına izin veremez. Backend açılım bayrağı ile danışanın açık izni farklıdır; kapalı rollout'ta yeni izin yazması reddedilebilir.

Tam kişisel program editörü, profil düzenleme, AI/katalog/tarif/tahlil/OCR, bildirim/hatırlatma teslimi ve PDF mobil teslimi henüz yoktur. Atanmış program/hedef salt okunurdur. Kayıt yok, bilinmeyen değer, sıfır, erişim kapalı ve ağ hatası farklı gösterilir.

## 2. Gereksinimler ve kurulum

Komutlar aksi belirtilmedikçe **mobile/** içindedir.

- Flutter ve Dart; pubspec SDK kısıtı `^3.12.2`dir. Önceki oluşturma ortamı Flutter 3.44.6/Dart 3.12.2 olarak kaydedilmiştir; kurulu SDK bu görevde çalıştırılarak doğrulanmadı.
- Android SDK/emülatör veya uygun cihaz; Gradle'da Java/Kotlin hedefi 17, minSdk 26'dır. compile/target SDK Flutter ayarından gelir.
- iOS derleme/çalıştırma için macOS/Xcode, uygun imzalama/provisioning; kaynak deployment target 15.0'dır. Bu değer HealthKit'in her cihazda doğrulandığı anlamına gelmez.
- Gerçek API/DB/SMTP için [backend kurulumu](../backend/README.md), web yönlendirmesi için [web kurulumu](../apps/web/README.md).

```powershell
flutter pub get
flutter devices
```

pubspec'te health 13.3.2, flutter_secure_storage ^11.2.0 ve url_launcher ^6.3.3 vardır. Paket/sürüm seçimleri bu README ile değiştirilmez.

### Android/iOS yapılandırması

Android main manifest INTERNET ve yalnız okuma amaçlı adım/mesafe/egzersiz/aktif kalori/nabız izinlerini içerir. HealthPermissionsActivity ve permission-usage alias'ı native izin açıklamasını sağlar. allowBackup/fullBackupContent kapalıdır; data_extraction_rules shared preferences bulut yedek/cihaz transferini dışlar.

Debug network security config yalnız tanımlı loopback/emülatör adreslerine cleartext izni taşır; release ağı HTTPS gerektirir. Ortak geliştirme akışı HTTPS'tir; geçersiz sertifikayı kabul eden callback/TLS atlama kullanılmaz.

iOS Runner.entitlements HealthKit yetkisini, Info.plist NSHealthShareUsageDescription açıklamasını içerir; API sağlık platformuna yazmaz. Xcode HealthKit/signing ve gerçek cihaz yetkileri ayrıca doğrulanmalıdır. iOS boş okuma, okuma izni verildiği/reddedildiği veya kaydın silindiği kanıtı değildir.

## 3. Çalıştırma komutları

### Ortak başlatıcı

Ön koşullar hazırken **repo kökünden**:

```powershell
.\start.ps1
```

Betik Docker/API/web ve desteklenen Android emülatörünü/Flutter'ı aynı terminalde yönetir; npm/pub paketlerini, sırları veya migration'ı kurmaz. Uygun çalışan emülatörü seçer; yoksa SDK'da tek AVD'yi soğuk başlatabilir. Birden fazla AVD'de önce istenen emülatör açılır. Kullanıcı verisini silmez, farklı hedefli mevcut adb tünelini değiştirmez. Ctrl+C yalnız kendi süreç/tünel/başlattığı servisleri temizler; önceden çalışan emülatör/servisler korunur.

### API_BASE_URL, WEB_BASE_URL ve HTTPS

| Define | Kaynaktaki anlam |
|---|---|
| API_BASE_URL | API origin'i; debug varsayılanı https://localhost:7099; path/query/fragment/kimlik bilgisi kabul edilmez |
| WEB_BASE_URL | Harici web origin'i; debug varsayılanı https://localhost:5173; yalnız HTTPS |
| API_DEV_CERT_BASE64 | Yalnız debug'da açık geliştirme sertifikasına ek güven; release'te kullanılmaz |

Release API ve web origin'leri açıkça yapılandırılmalıdır; geliştirme hostu veya üretim URL'si uydurulmaz. Mobil JWT/refresh, web bağlantısına veya dönüş URL'sine eklenmez. Sertifika ek güveni normal chain/hostname/expiry doğrulamasını kapatmaz.

Başlatıcıyı kullanmadan manuel Android emülatör çalıştırmada önce cihazı/tüneli inceleyin:

```powershell
adb devices
adb -s emulator-5580 reverse --list
```

emulator-5580 yerine kendi test cihazı kimliği kullanılır. API tüneli yoksa ve başka işe ait çakışan tünel bulunmuyorsa:

```powershell
adb -s emulator-5580 reverse tcp:7099 tcp:7099
$nutritionPublicCert = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:LOCALAPPDATA/SmartNutrition/dev-cert.pem"))
flutter run -d emulator-5580 --dart-define=API_BASE_URL=https://localhost:7099 --dart-define=WEB_BASE_URL=https://localhost:5173 --dart-define=API_DEV_CERT_BASE64=$nutritionPublicCert
Remove-Variable nutritionPublicCert
```

API ve web önceden çalışıyor olmalı, PEM gerçek sunucu sertifikasıyla uyuşmalıdır. Yalnız **açık** sertifika aktarılır; özel anahtar cihaza/git'e taşınmaz. Fiziksel cihazda localhost bilgisayarı göstermez; ona uygun yetkili HTTPS origin ve OS güveni ayrıca hazırlanır.

Release yapılandırma örneği; example.com adresleri gerçek dağıtım origin'leriyle değiştirilir:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com --dart-define=WEB_BASE_URL=https://web.example.com
```

Bu derleme mağaza yayını değildir: mevcut Android release ayarı hâlâ debug signing kullanır; paket kimlikleri/ikonlar ve yayın imzası ayrıca hazırlanmalıdır.

### Android tarayıcı ve Türkçe klavye

Flutter API sertifika güveni Android Chrome'a aktarılmaz. Harici web paneli için [kök README Android HTTPS adımları](../README.md#android-chrome-için-yerel-https) uygulanır. Yalnız test AVD'sinde PowerShell 7.5+ ile kökten `./setup-local-https.ps1 -EmulatorId emulator-5580` kullanılır; yalnız açık CA Android'in standart ekranında kurulur. Windows'a/kişisel cihaza CA ekleme veya sertifika uyarısını atlama yoktur. Yerel CA geçidi, tüneller ve geri alma [03](../docs/03_SYSTEM_ARCHITECTURE.md)'tedir.

Unicode giriş için Gboard → Languages altında Türkçe (Türkiye)/Türkçe-Q ekleyin; fiziksel klavyede AT Translated Set 2 keyboard ve qwerty2 için Turkish seçin. Ekran klavyesi açık olabilir. `adb shell input text` Unicode/IME testi değildir. Başlatıcı bu AVD tercihlerini sıfırlamaz.

## 4. Geliştirme ortamı ve güvenlik

### Auth ve güvenli token

Debug dahil özel ekranlar AuthGate'ten geçer; sahte oturum/giriş atlama yoktur. client rolü danışan MainShell'ini açar; diğer rol web paneline yönlendirilir. JWT claim'i istemcide çözülerek kaynak yetkisi verilmez; login/refresh sonrası geçerli beş alanlı auth/me gerekir.

Access token ve hesap bellektedir; yalnız refresh token, mutlak bitiş ve rotationPending tek güvenli kayıtta saklanır. Kayıt API origin'ine ayrılmıştır; Android/iOS dışı düz metin/web fallback yoktur. iOS unlocked_this_device, synchronizable=false; Android resetOnError/migrateOnAlgorithmChange=false kullanır.

Refresh tek Future ile koordine edilir. İstekten önce rotationPending saklanır; gönderim sonrası yanıt kaybında eski token otomatik tekrar kullanılmaz. Geçici ağ/depo hatası geçerli oturum süresini uzatmaz. Lifecycle/hesap/çıkışta Navigator ve eski yanıtlar yeni oturumu geri getiremez.

Logout refresh ailesini sunucuda iptal etmeye çalışır, yerel bellek/güvenli kayıt temizliğini yönetir; sunucu iptali veya depo temizliği doğrulanamazsa başarı iddia edilmez. Normal logout access JWT'nin kalan süresini tek başına bitirmez; parola reseti credentialsVersion ile eski kimlikleri ayrıca iptal eder. Detay [06](../docs/06_API_CONTRACT.md)'dadır.

### Kayıt, e-posta ve reset

Kayıt displayName/email/password gönderir; parola tekrarı ve rol istemciden API'ye taşınmaz. 201 hesap oluşturmadır, SMTP teslimi veya oturum değildir; doğrulama ekranına geçilir. Parola 8–128 Unicode kod noktasıdır, kırpılmaz/normalize edilmez; girişte yeni kayıt karmaşıklığı uygulanmaz.

E-posta doğrulama standalone kodla yapılır; yalnız 204 başarıdır. Yeniden gönderim 202 hesap varlığını veya teslimi açıklamaz. Yerel cooldown sunucu limitinin yerine geçmez; POST otomatik tekrarlanmaz. Reset de email talebi + elle kod/yeni parola kullanır; tekrar yalnız istemcidedir. Başarılı 204 sonrası girişe dönülür, otomatik login yapılmaz. Mobil reset deep-link tüketimi yoktur.

Parola/token/ham yanıt loglanmaz; cookie/CSRF mobil bearer akışına eklenmez. Ağ kesintisinde işlemin sunucuda başarısız olduğu varsayılmaz. Form/sayfa değişiminde sırlar temizlenir.

### Sağlık aktarımı

Native okuma, açık sunucuya aktarım onayı ve bağlantı active/revoked tercihi ayrıdır. İzin istemek veya ekran açmak tek başına okuma/upload yapmaz. Ön plandaki açık eylem upsert batch'i hazırlar; kalıcı sağlık cache'i/disk kuyruğu/otomatik arka plan sync yoktur.

Hesap, lifecycle veya izin değişiminde bekleyen okuma/aktarım bırakılır. Eksik pencere, boş sonuç veya izin reddi native silme delta'sı sayılmaz. Backend receipt/özet başarısı native fiziksel ölçüm doğruluğunu kanıtlamaz. Birim/kararlı kaynak kimliği/idempotency/örtüşme için [20](../docs/20_HEALTH_DATA_SYNC_CONTRACT.md) esas alınır.

## 5. Testler ve doğrulama

```powershell
flutter analyze
flutter test
```

Bu komutlar unit/widget paketini doğrular; ayrı `*_probe.dart` dosyalarının tamamını veya fiziksel cihazı çalıştırmış sayılmaz. Hedefli örnekler:

```powershell
flutter test test/password_reset_api_test.dart test/password_reset_widget_test.dart
flutter test test/device_health_reader_test.dart test/health_data_api_test.dart test/health_sync_service_test.dart test/health_sync_widget_test.dart
```

| Kaynak | Gerçek kapsam / koşul |
|---|---|
| auth/session/refresh, kayıt/doğrulama/reset, öğün/su/hedef/ölçüm/program/yorum/görev testleri | Unit/widget/DTO; native platform veya çalışan API kanıtı değildir |
| health_sync_live_probe.dart | M3 sentetik HTTP/HTTPS/izole DB; SNP_HEALTH_LIVE ve kendine özgü m3_verify_… ortamı; fiziksel health okuma testi değildir |
| password_reset_live_probe.dart | SNP_RESET_LIVE ve m5_verify_… test DB'si; Mailpit/API oturum iptali |
| client_task_live_probe.dart | SNP_TASK_LIVE ve m6_verify_… test DB'si; görev API provası |
| device_health_live_probe.dart, mobile_quality_device_probe.dart | Ayrı cihaz hedefi/define/hesap/ortam gerektirir; dosya veya commit başlığı başarılı koşu değildir |

Live probe'ların sabit port, konteyner ve test DB kontrolleri kendi kaynaklarından okunur; uygulama DB'siyle veya U6 web ortamıyla doğrudan aynı olduğu varsayılmaz. Ortam hazır değilse opt-in açılmaz; komut/başarılı sonuç uydurulmaz. Yalnız sentetik hesap kullanılır.

Fiziksel Android sağlık aktarımı ve iOS/HealthKit bu görevde doğrulanmadı. Gerçek sensör/native ID/izin/OS, Keychain/Keystore, iki tema, küçük ekran/klavye ve yayın imzalama ayrıca test edilmelidir. Geçmiş sonuçlar [12](../docs/12_TEAM_PLAN_AND_DECISIONS.md)'de tarih/kapsamla ayrılır; burada yeni başarı/sayım verilmez.

## 6. Bilinen sınırlamalar

**Mevcut danışanla uzman başvurusu erişimi tamamlanmış değildir.** DietitianApi.applyExisting ve DietitianAccountPage vardır; AuthGate /dietitian-account yolunu WebPanelPage'e yönlendirir, ProfilePage'de başvuru bağlantısı yoktur. Eski widget/API'nin varlığı erişilebilir kullanıcı akışı değildir. Web formundaki “mobil Profil'den başvur” metni bu engeli gidermiyor; kod düzeltmesi ayrı görevdir.

Tam profil/gizlilik düzenleme, kişisel program editörü, manuel aktivite formu, AI/tahlil/OCR ve bildirim teslimi tamamlanmış değildir. HealthKit fiziksel testi, gerçek Android aktarımı, nihai marka/erişilebilirlik ve mağaza kimliği/ikon/release signing açık kalır. Bunlar onaylı kapsamdan çıkarılmamıştır.

## 7. İlgili güncel dokümantasyon

[Kök kurulum](../README.md) · [Ürün](../docs/01_PROJECT_SCOPE.md) · [Adlar](../docs/04_NAMING_CONVENTIONS.md) · [Veri](../docs/05_DATA_DICTIONARY.md) · [HTTP/DTO](../docs/06_API_CONTRACT.md) · [Mobil ekranlar](../docs/07_MOBILE_SPEC.md) · [Tasarım](../docs/09_DESIGN_SYSTEM.md) · [Güvenlik](../docs/11_SECURITY_AND_RELEASE.md) · [Durum/açık kararlar](../docs/12_TEAM_PLAN_AND_DECISIONS.md) · [Sağlık aktarımı](../docs/20_HEALTH_DATA_SYNC_CONTRACT.md)

Önceki M/U görevleri tarihsel kimliklerdir; güncel işlem/yazma yetkisi [AGENTS.md](../AGENTS.md)'dedir. Eski teslim bilgileri [mevcut arşivde](../docs/archive/README.md) korunur.
