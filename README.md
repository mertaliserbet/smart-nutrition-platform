# Smart Nutrition Platform

**Yapay Zekâ Destekli Akıllı Beslenme ve Diyetisyen Platformu**

Diyetisyen odaklı, danışanlar için mobil uygulama ve diyetisyenler için web yönetim paneli sunması hedeflenen **sıfırdan geliştirilecek** ürün. Üniversite bitirme projesi olarak başlayacak; güvenlik, kullanılabilirlik ve dağıtım gereksinimleri karşılandığında mağazada yayımlanabilir ve ticari olarak sunulabilir bir temele sahip olması amaçlanır.

## Amaçlanan başlıca işlevler
- Danışan: öğün/besin, kalori/makro, su, kilo/ölçüm, aktivite ve tahlil takibi; kişisel hedef/program veya atanmış program. Kişisel öneriler düzenlenebilir, diyetisyen programı/hedefleri salt okunurdur; gerçek tüketim serbestçe kaydedilir.
- Diyetisyen: mobil/web başvuru ve Admin doğrulaması; arama/davet kodu ve karşılıklı onayla bağlantı. En fazla bir aktif diyetisyen ve kişisel/atanmış toplamında tek aktif `NutritionPlan`; geçmiş ve öğün alternatifleri korunur.
- Takip: izinli danışan yönetimi, öğün yorumları/cevaplar/bildirimler, görev/son tarih/durum ve isteğe bağlı hatırlatmalar, grafik/program uyumu/PDF raporları. Hibrit besin kataloğu ve özel tarifler desteklenir.
- Yapay zekâ: fotoğraf/galeriden **tahmini** kalori/makro; kullanıcı kontrol/onayı olmadan öğün oluşmaz. Tahlilde manuel giriş ve referans değerlendirmesinin ardından kullanıcı onaylı PDF/fotoğraf OCR; doğrulanabilir ML opsiyoneldir.
- Entegrasyon: ayrı izinle Health Connect/HealthKit üzerinden adım, mesafe, egzersiz, süre, aktif kalori ve nabız; manuel giriş, kaynak ve tekilleştirme.
- Güvenlik/deneyim: kategori bazlı paylaşım, tahlil için ayrıca açık onay, güvenli e-posta/şifre oturumu ve zorunlu Admin MFA; sağlık verisine varsayılan Admin erişimi yoktur. Premium UI/UX, ortak tokenlar ve açık/koyu tema.

İlk sürüm yönetim paneli webdedir; öğün yorumları, cevaplar ve bildirimler ilk sürüm koşuludur. Diğer onaylı özelliklerin takvimi, sonraya bırakılan sohbet/sürekli kamera ve opsiyonel araştırma ayrımı [proje kapsamında](docs/01_PROJECT_SCOPE.md) açıklanır; tüm özellikler aynı MVP'ye vaat edilmez.

> Sağlık uyarısı: Sistem teşhis koymaz, tedavi/ilaç önermez; görselden kalori hesabı kesin ölçüm değildir. Sağlık verileri özel niteliklidir ve korunmalıdır.

## Durum
`DOCS-V1` — **Uğur'un 29 Ekim web/Auth/backend dilimi tamamlandı.** Danışan Auth ve W2 web oturumu yanında B1–B3 uzman başvurusu/MFA Admin onayı, R1–R3 davet/karşılıklı onay/izinli danışan yönetimi ve N1–N3 program oluşturma/atama gerçek API'lere bağlıdır. Programlarda gün/miktar/alternatifler, değişmeyen sürüm geçmişi, tek aktif program ve ilişki bitince atanmışı arşivleme uygulanmıştır. Diğer sağlık kayıt ekranları ayrı sentetik önizlemedir. 250 backend testi gerçek geçici PostgreSQL/Mailpit'te atlamasız; 128 web testi, typecheck/lint ve production build başarılıdır. Bu durum canlı yayın veya tüm mobil aşamasının tamamlandığı anlamına gelmez.

**Sonraki tek adım:** Mert'in güncel ortak main'e göre mobil bağlantı/izin ve atanmış program okumasını bağlayıp sentetik hesaplarla ortak sunum provası. Flutter/Mert dosyaları bu çalışmada değiştirilmedi. Kararlar [12](docs/12_TEAM_PLAN_AND_DECISIONS.md), onaylı B/R/N dilimleri [14](docs/14_OCTOBER_PRESENTATION_CONTRACT_PROPOSAL.md), [15](docs/15_RELATIONSHIP_CONTRACT_PROPOSAL.md), [16](docs/16_NUTRITION_PLAN_CONTRACT_PROPOSAL.md) içinde izlenir; [16](docs/16_NUTRITION_PLAN_CONTRACT_PROPOSAL.md) sunum sırasını da içerir. Mevcut danışan register/JWT gövdeleri korunur; entegrasyondan önce iki taraf ortak main sürümünü çeker.

## Yerel geliştirme — tek terminal

VS Code'da **PowerShell 7** terminalini açıp proje kökünde çalıştırın:

```powershell
.\start.ps1
```

Windows PowerShell 5.1 kullanılıyorsa `pwsh -NoProfile -File .\start.ps1`
ile PowerShell 7 üzerinden çalıştırılabilir. Script yeni terminal/PowerShell
penceresi veya tarayıcı açmaz; servis loglarını `[Backend]`, `[Web]`, `[Mobil]`
ve `[Docker]` önekleriyle aynı terminalde gösterir.

**Bir defalık ön koşullar:** Docker Desktop'ın Linux motoru çalışmalı; .NET 10 SDK,
web'in desteklediği Node.js (20.19+ / 20.x veya 22.12+) ve mobil için Flutter
PATH içinde bulunmalıdır. Web paketlerini `apps/web` içinde `npm ci --include=optional`,
mobil paketlerini `mobile` içinde `flutter pub get` ile kurun.
[Backend kurulumu](backend/README.md) üzerinden mevcut `backend/.env`, PostgreSQL
bağlantısı, JWT, SMTP ve W2 web oturumu User Secrets/environment ayarlarını ve
gerekli migration'ları önceden hazırlayın. Script sır üretmez, mevcut ayarları
değiştirmez; npm/Flutter paket kurulumu veya migration uygulamaz. Backend,
`dotnet run` komutunun standart restore/derleme adımlarını kullanır.

[Web HTTPS kurulumundaki](apps/web/README.md#web-oturumu-w2) güvenilir geliştirme
sertifikası/özel anahtarı Git dışında hazır olmalıdır. Script mevcut
`SMART_NUTRITION_HTTPS_CERT` ve `SMART_NUTRITION_HTTPS_KEY` yollarını kullanır;
ikisi de verilmemişse `$env:LOCALAPPDATA/SmartNutrition/dev-cert.pem` ve
`dev-cert.key` dosyalarını arar. Sertifika güvenini otomatik değiştirmez.
`Auth:WebSession:Origin` mevcut web adresi `https://localhost:5173` ile eşleşmelidir.
Web alt sürecinde `NODE_EXTRA_CA_CERTS` verilmemişse bu PEM kullanılır;
mevcut bir değer verilmişse yerel API sertifikasına güveni de kapsamalıdır.

- Web: [Giriş](https://localhost:5173/giris), [Kayıt](https://localhost:5173/kayit),
  [E-posta doğrulama](https://localhost:5173/eposta-dogrulama).
- Backend: [Swagger](https://localhost:7099/swagger),
  [liveness](https://localhost:7099/health/live),
  [PostgreSQL readiness](https://localhost:7099/health/ready).
- Mailpit: [yerel posta kutusu](http://127.0.0.1:8025); PostgreSQL: `127.0.0.1:5433`.
- Mobil: önceden açtığınız desteklenen Android emülatörü otomatik seçilir;
  birden fazlaysa cihaz kimliğine göre ilk emülatör kullanılır. Emülatör/Flutter
  yoksa veya mobil çalıştırma başarısızsa uyarı verilir, backend/web açık kalır.
  Script emülatör açmaz ve grafik arayüzü kontrol etmez.
  Mobil API, `adb reverse tcp:7099 tcp:7099` üzerinden `https://localhost:7099`
  kullanır. Yalnız mevcut açık PEM sertifikası debug'a aktarılır; özel anahtar
  ve TLS doğrulamasını kapatan seçenek kullanılmaz. Script başka hedefe bağlı
  mevcut 7099 tünelini değiştirmez; kendi açtığı tüneli çıkışta kaldırır.

`Ctrl+C`, bu çalıştırmanın uygulama süreçlerini ve alt süreçlerini kapatır;
Flutter'a önce `q` gönderilir, kalan süreçler Windows Job Object ile sonlandırılır.
Yalnız scriptin başlattığı PostgreSQL/Mailpit servislerine `docker compose stop`
uygulanır. Önceden çalışan Docker servisleri ve emülatör kapatılmaz; container,
volume veya veritabanı verileri silinmez. Terminali zorla kapatmak yerine `Ctrl+C`
kullanın; zorla kapatmada Docker servisleri açık kalabilir.

5052/7099/5173 portları başka bir süreç tarafından kullanılıyorsa script
o süreci kapatmadan hata verir. Compose portları da başlamadan kontrol edilir;
zaten çalışan aynı Compose servisi yeniden kullanılır. Backend/web beklenmedik
şekilde kapanırsa bu çalıştırmanın servisleri temizlenir. Eksik ayar/bağımlılık
ve başarısız hazırlık kontrolleri terminalde bildirilir. Gerçek web akışları ve
mobil ekranların görsel kontrolü geliştirici tarafından elle yapılır.

## Mevcut repo düzeni
```text
smart-nutrition-platform/
├── AGENTS.md
├── README.md
├── docs/
├── apps/web/        # React + TypeScript
├── backend/         # ASP.NET Core / C#, PostgreSQL ve testler
└── mobile/          # Flutter / Dart; Mert'in alanı
```
Çalıştırma ve doğrulama adımları [web](apps/web/README.md), [backend](backend/README.md) ve [mobil](mobile/README.md) belgelerindedir. Ayrı AI servisi henüz yoktur; ihtiyaç olduğunda Python/FastAPI kullanılması onaylıdır. Yeni paketler/klasörler ihtiyaç oldukça eklenir; feature-based yapı korunur.

## İki geliştiricili çalışma
1. Her geliştirici önce kökteki [`AGENTS.md`](AGENTS.md) dosyasını okur.
2. **Aynı isimler** için [`docs/04_NAMING_CONVENTIONS.md`](docs/04_NAMING_CONVENTIONS.md), **aynı veri şeması** için [`docs/05_DATA_DICTIONARY.md`](docs/05_DATA_DICTIONARY.md), **aynı API** için [`docs/06_API_CONTRACT.md`](docs/06_API_CONTRACT.md) temel alınır.
3. Ortak uzak depo `mertaliserbet/smart-nutrition-platform`, entegrasyon dalı `main`dir. 29.10.2026 kullanıcı kararıyla **Mert doğrudan yerel `main` üzerinde çalışır**; açıkça istenmedikçe onun için yeni dal veya PR açılmaz. **Uğur güncel ortak `main`den görev dalı açar, kendi fork'una push eder ve ortak `main`e PR gönderir**; ortak `main`e doğrudan push yapmaz. Uzak depo adları URL üzerinden doğrulanır; Mert'in bu checkout'unda ortak depo `origin`, Uğur'un belgelenmiş düzeninde ortak depo `upstream`, fork `origin`dir. Ayrıntılı ve güncel kurallar [`AGENTS.md`](AGENTS.md) içindedir.
4. Görevler küçük commitlere bölünür; değişiklik özeti + test sonucu verilir. Görev ve push/PR öncesi ortak `main` kontrol edilir; aynı dosyaya paralel yazılmaz, force push yapılmaz. Ayrıntılar [`ekip planında`](docs/12_TEAM_PLAN_AND_DECISIONS.md) yer alır.
5. Sözleşme değişikliği iki geliştirici tarafından onaylanır ve tek ortak commit ile gerçekleştirilir. Mevcut PR'ları birleştirme/kapatma ve eski dalları silme ayrıca açık kullanıcı talimatı gerektirir.
6. Dal, commit/PR başlığı, dosya, klasör ve modül adlarında geliştirme aracının adı kullanılmaz; amaç ve proje kavramları esas alınır.

Mert mobil ve ilgili API'ler; Uğur web, Auth ve ilgili API'ler; AI ortak sorumluluğundadır. Ayrıntılı modül liderliği `12`de teyit edilir. `04/05/06`daki açık parçalar için her istemci ayrı DTO/endpoint üretmez; ilgili geliştirme öncesi ortak onay gerekir.

## Dokümantasyon
| Belge | Konu |
|---|---|
| [01](docs/01_PROJECT_SCOPE.md) | Ürün kapsamı ve özellik öncelikleri |
| [02](docs/02_ROLES_AND_WORKFLOWS.md) | Roller, kullanıcı akışları, diyetisyen süreçleri |
| [03](docs/03_SYSTEM_ARCHITECTURE.md) | Sistem bileşenleri, onaylı teknolojiler ve açık mimari ayrıntılar |
| [04](docs/04_NAMING_CONVENTIONS.md) | **Kanonik isimlendirme kuralları** |
| [05](docs/05_DATA_DICTIONARY.md) | **Entity ve alan sözlüğü** |
| [06](docs/06_API_CONTRACT.md) | **Ortak HTTP/JSON API sözleşmesi** |
| [07](docs/07_MOBILE_SPEC.md) | Danışan mobil uygulaması |
| [08](docs/08_WEB_SPEC.md) | Diyetisyen ve admin web paneli |
| [09](docs/09_DESIGN_SYSTEM.md) | Premium UI/UX kuralları |
| [10](docs/10_AI_SPEC.md) | Besin görseli ve laboratuvar analizi |
| [11](docs/11_SECURITY_AND_RELEASE.md) | KVKK, test, kalite ve yayın öncesi kontroller |
| [12](docs/12_TEAM_PLAN_AND_DECISIONS.md) | Görev sahipliği, yol haritası, karar kaydı |

**Geliştirme ilkesi:** Hedef gerçek ürün kalitesi olsa da tüm özelliklerin ilk sunuma yetiştiği varsayılmaz. MVP ve araştırma özellikleri ayrıdır.
