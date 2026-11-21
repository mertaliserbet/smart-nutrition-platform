# Smart Nutrition — Web

## 20.11.2026 — U6 gerçek HTTPS tarayıcı regresyonu

`npm run test:e2e`, Playwright Test 1.65.1 ve kurulu Microsoft Edge ile gerçek
tarayıcıyı çalıştırır; React DOM testlerinden ayrıdır. U6 sırasında test
bağımlılığı kullanıcı tarafından ayrıca açıkça onaylandı. Dört senaryo:

- Uzman girişi → aktif danışan → son tarihli görev atama → danışan API'sinden
  tamamlama → webde durum/geçmiş; bağımsız su izni/okuma/geri çekme, CSRF/Origin,
  sayfa yenileme, profil menüsü klavyesi ve sunucuda çıkış.
- Gerçek Mailpit e-postasının React bağlantısı → URL temizliği → reset → yeni
  parolayla giriş; eski parola/web cookie/access/refresh ve tekrar token reddi.
- Normal danışanın web giriş reddi, onaysız uzman sınırı, 390 px ekran,
  açık/koyu sistem teması ve doğrulama hatasında klavye odağı.
- Süresi dolan sunucu oturumunda danışan listesinin kaldırılması ve eski cookie reddi.

Yalnız ayrı, sentetik test ortamında çalıştırın. Sabit uçlar: PostgreSQL 17
`127.0.0.1:55586/nutrition_u6_test` (`nutrition_test`), Mailpit HTTP 58028/SMTP
51028, test API `https://localhost:7099`, Vite `https://localhost:5446`.
Uygulama servisi 7099'u kullanıyorsa betik durur; başka süreci kapatmaz.
Kurulu/geçerli ve zaten güvenilir localhost ASP.NET geliştirme sertifikası
gereklidir. TLS doğrulaması, Secure cookie, CSRF, tam Origin ve normal limitler
korunur; `ignoreHTTPSErrors=false`. Test CA güveni Node'a yalnız PEM ile verilir.

Önce repo kökünden yalnız bu test konteynerlerini oluşturun (uygulama volume'u yok):

```powershell
docker run --rm -d --name nutrition-u6-postgres --label smart-nutrition.test=U6 --tmpfs /var/lib/postgresql/data -p 127.0.0.1:55586:5432 -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_USER=nutrition_test -e POSTGRES_DB=nutrition_u6_test postgres:17
docker run --rm -d --name nutrition-u6-mailpit --label smart-nutrition.test=U6 -p 127.0.0.1:58028:8025 -p 127.0.0.1:51028:1025 axllent/mailpit:v1.32.0
$env:ConnectionStrings__DefaultConnection = 'Host=127.0.0.1;Port=55586;Database=nutrition_u6_test;Username=nutrition_test;Pooling=true'
Push-Location backend
dotnet build SmartNutrition.Backend.slnx --no-restore
dotnet ef database update --project src/SmartNutrition.Api --no-build
Pop-Location
Push-Location apps/web
$u6Artifacts = Join-Path $env:TEMP ('nutrition-u6-' + [guid]::NewGuid().ToString('N'))
./e2e/Start-TestServers.ps1 -Artifacts $u6Artifacts
$env:SNP_E2E_TEST_ENV = 'nutrition_u6_test'
$env:SNP_E2E_RESULTS = Join-Path $u6Artifacts 'results'
$env:NODE_EXTRA_CA_CERTS = Join-Path $u6Artifacts 'localhost.pem'
npm run test:e2e
./e2e/Start-TestServers.ps1 -Artifacts $u6Artifacts -Stop
Pop-Location
```

Betik test JWT/SMTP/paylaşım ayarlarını yalnız çocuk süreçlere verir. İşaretli
test klasörü Git dışında olmalıdır; özel anahtar kopyaları/hash'leri ve süreç
PID/yol/başlangıç zamanı kaydıyla sahiplik doğrulanır. `-Stop` yalnız eşleşen
süreçleri, değişmemiş anahtar kopyalarını ve kendi test key ring'ini temizler;
asıl geliştirme sertifikası/deposu değiştirilmez. Son olarak konteynerlerin U6
etiketlerini `docker inspect` ile doğrulayıp yalnız `nutrition-u6-postgres` ve
`nutrition-u6-mailpit` adlarını `docker stop` ile kapatın; `--rm`/tmpfs veriyi kaldırır.
Trace/video/screenshot ve kalıcı Auth storage kullanılmaz. Danışan işlemleri
gerçek API ile yapılır; Flutter testi değildir. Başlangıç sentetik hesapları API
ile kaydolur/e-postası doğrulanır; uzman onayı ve oturum süresi yalnız etiketli
test DB'sindeki yeni UUID/e-posta eşleşmesine sınırlı SQL ile hazırlanır.

U6 sonuçları: dört Edge/HTTPS testi başarılı; React DOM 349 başarılı/3 eski
opt-in canlı DOM testi atlandı. Bu üçü SNP_TASK_WEB_LIVE, SNP_MEASUREMENT_WEB_LIVE,
SNP_COMMENT_WEB_LIVE için eski sabit ayrı ortamları bekler; silinmedi. Tam backend
ve migration sonuçları koordinasyon kaydındadır. Bu testler üretim yayını veya
fiziksel Flutter/Health Connect/HealthKit onayı değildir.

## 20.11.2026 — U5 gerçek parola sıfırlama

Girişteki **Şifremi unuttum** mevcut `/sifremi-unuttum` sayfasını açar. E-posta
formu gerçek `POST /api/v1/auth/password-reset-requests { email }` yolundadır;
202 mesajı hesap varlığını veya teslimi açıklamaz. Mailpit e-postasındaki
`<Auth:WebSession:Origin>/sifremi-unuttum#token=<kod>` aynı sayfada yeni parola
formunu açar. Vite iki kanonik reset yolunu mevcut backend'e proxy eder.
Yerel başlatıcıdaki güvenilir Origin `https://localhost:5173` ile eşleşmelidir;
uygulama hesabı veya ayarlar bu U5 görevinde değiştirilmedi.

Token yalnız sayfa belleğinde tutulur, URL/history replace ile temizlenir.
Query/bozuk/tekrarlı token reddedilir. Yenileme sonrası e-postadaki bağlantıyı
yeniden açın veya yeni bağlantı isteyin. Local/session storage, router state,
log/analitik kullanımı yoktur; no-referrer ve credentials omit/no-store vardır.
Şifre ve tekrarı kırpılmaz; 8–128 Unicode kod noktası politikası uygulanır.
Yalnız `{ token, password }` gönderilir; 204 sonrası `/giris`, otomatik giriş yok.
Route'a bağlı hesap/çalışma alanı belleği sayfadan ayrılmada kalkar. Backend eski
web/access/refresh kimliklerini iptal eder. Admin yeni parolayla da MFA ekranından
girmelidir; MFA kurulumu/kurtarma kodları değişmez.

Doğrulama: `node node_modules/vitest/vitest.mjs run --maxWorkers=2`,
`npm run build`, `npm run lint`. PasswordResetPage testleri talep/ortak başarı,
422/429/ağ/sunucu hataları, Unicode/eşleşme, double-submit, StrictMode, URL/history,
yenileme ve geç yanıtları sınar. Gerçek Mailpit/PostgreSQL ve kimlik iptali
`backend/tests/SmartNutrition.Api.Tests/PasswordResetWebIntegrationTests.cs`
içindedir. React DOM/API testleri fiziksel tarayıcı veya Flutter testi değildir.
Bu kayıt aşağıdaki eski reset sunum/açık bağımlılık notlarının yerini alır.

## 19.11.2026 — U4 gerçek su takibi

Danışan çalışma alanındaki WaterLogPanel gerçek uzman su liste/toplam/geçmiş
yollarına bağlıdır. Gün seçimi, 10'lu kayıt listesi, mL/saat/kaynak ve 31 güne
kadar IANA/DST sınırlarıyla günlük SVG grafik + tablo kullanılır; paket eklenmedi.
Mevcut WaterLogList mikro-saniye/offset sırasını korur. Kişisel hedef API'si
çağrılmaz, izin açma/yazma işlemi sunulmaz. İzin/ilişki reddi, hata ve boş
başarılı gün farklıdır; hata 0 gösterilmez. Oturum/danışan/tarih değişiminde
geç yanıtlar elenir, no-store ve görünür sekme yenilemesi kullanılır.

API ve Flutter M4 açılımı [21 teslim notunda](../../docs/21_WATER_LOG_SHARING_CONTRACT.md).
WaterLogsEnabled mobil beş kategori uyumu doğrulanana kadar false kalır.
React testleri `node node_modules/vitest/vitest.mjs run --maxWorkers=2`;
`npm run build` ve `npm run lint` ile doğrulanır. Testler sentetik DTO'lu
React DOM testidir; API/PostgreSQL uçtan uca akışı backend testlerindedir.
Flutter veya fiziksel tarayıcı görsel provası yapılmış sayılmaz.

## 19.11.2026 — U2 gerçek görev yönetimi

Gerçek danışan detayındaki **Danışan görevleri** bölümü U1 API'sini kullanır:
`GET/POST /api/v1/client-tasks`, `GET/PATCH /{clientTaskId}`,
`GET /{clientTaskId}/versions`. Vite HTTPS proxy'sine aynı kök eklendi.
Görev/versiyon sayfaları 10 kayıttır; yanıtlar kanonik DTO ve danışan/uzman/
görev sahipliğiyle doğrulanır. Cookie same-origin, no-store ve X-Profile-Context
korunur; yazmada mevcut CSRF kullanılır. JWT/taslak kalıcı depolanmaz.

Yeni görev doğrudan atanır. Uzman yalnız açık görevi düzenler veya onayla
iptal eder; danışan adına tamamlama ve hatırlatma tercihi yazma yoktur.
Son tarih cihazın yerel saatinden UTC'ye çevrilir; aynı kalan sunucu zamanının
mikrosaniyeleri korunur. Kapanmış görev salt okunur, completed zamanı U1'in
terminal sürüm zamanıdır. 409 taslağı korur; güncel görev okunur, kayıt otomatik
tekrarlanmaz. İzin/ilişki kaybında yalnız görev içeriği/formları kaldırılır.
Görünür sekmede 30 sn/fokus/elle yenileme vardır; gizli sekme veri göstermez
ve yeni okuma yapmaz. Ağda sonucu belirsiz yazma yeniden gönderilmeden önce
liste kontrol edilir. Formu kapatırken kaydedilmemiş değişiklik uyarısı vardır.

U1 davranışı ve `04/05/06` değişmedi; backend'de yalnız entegrasyon testi
eklendi. ClientTasksEnabled varsayılan false kalır; M2 mobil kategori/izin
uyumu doğrulanmadan ortak ortamda açılmaz. Web uzmanı danışan adına izin
oluşturmaz. Bildirim teslim altyapısı yoktur. Flutter M2 ortak main'dedir
(d14576f); bu U2 oturumunda Flutter üzerinden doğrulama yapılmadı.

Doğrulama: `node node_modules/vitest/vitest.mjs run --maxWorkers=2` ile
282 başarılı / 3 opt-in canlı test atlandı (29 görev testi dahil).
`npm run build` ve `npm run lint` başarılı/uyarısız. Ayrı PostgreSQL 17.11'de
ilgili API testleri 49/49, backend build 0 uyarı/hata. Uygulama DB'si kullanılmadı.

Görev canlı testi ayrıca gerçek React DOM + HTTPS/cookie/CSRF API ile
çalıştırıldı; tarayıcı görsel testi veya Flutter testi değildir. Ayrı geçici
PostgreSQL'i 127.0.0.1:55582 / nutrition_u2_test / nutrition_test ve yalnız bu
DB'ye bağlı HTTPS API'yi https://localhost:7443 olarak hazırlayın. API'nin test
ortamında ClientTasksEnabled=true, güvenli web oturumu ve JWT ayarları olmalı;
test sertifikası güveni yalnız bu sunucuya verilir. Yeni sentetik hesapların
doğrulanmışlığı psql ile yalnız bu test DB'sinde ayarlanır; uygulama verileri
seed edilmez/değiştirilmez. Gerekli test ortam değişkenleri:

- `SNP_TASK_WEB_LIVE=1`
- `SNP_TASK_WEB_ORIGIN=https://localhost:7443`
- `SNP_TASK_WEB_CA`: test HTTPS sertifikasının PEM dosyası
- `SNP_TASK_WEB_PSQL`: test PostgreSQL psql.exe dosyasının tam yolu

Ardından `node node_modules/vitest/vitest.mjs run
src/features/clientTasks/ClientTaskPanel.live.test.tsx --maxWorkers=1`.
Gerçek akış: webden atama→danışan bearer oturumuyla tamamlama→webde 409 ve
güncel durum/geçmiş, ayrıca düzenleme/iptal, izin geri çekme ve ilişki sonu.

## 18.11.2026 — Seçilen program sürümüyle günlük tüketim karşılaştırması

Gerçek danışan detayında bir programın **Program ve tüketimi karşılaştır**
düğmesini açın; güncel veya geçmiş sürüm ve takvim günü seçin. Programın bu
sürümdeki tarih aralığı içinde bir gün gerekir. Planlanan öneriler/alternatifler
ile tüm kayıtlardan hesaplanan öğün türü özetleri yan yana görünür. Günlük
kalori farkı backend'den gelir; eksik besin değerleri ve tahmini kalem sayıları
ayrıca belirtilir. Kayıt yokluğu tüketim yapılmadığı anlamına gelmez.

Gün sınırları tarayıcının saat dilimine göre oluşturulur ve iki offset
gösterilir. Bu seçim danışanın saat dilimi veya o gün aktif olan program
sürümü iddiası değildir. Manuel yenileme ve görünür sekmeye/odağa dönüş yeni
yetkili okuma yapar. Program ve öğün paylaşım izinlerinin **ikisi** gerekir;
403/404 yalnız karşılaştırmayı kapatır. Mevcut bağımsız program/öğün ekranları
kendi yetkileriyle çalışır. `04/05/06` ve onaylı `19` K1–K4 aynı sözleşmedir;
Flutter ekranı bu teslimin dışındadır. Yeni ortam bayrağı veya migration yoktur.

## 18.11.2026 — Gerçek danışan ölçümleri

Gerçek danışan detayındaki Vücut ölçümleri bölümü mevcut diyetisyen ölçüm
API'sine bağlıdır. Kilo/bel/kalça/göğüs/yağ oranı/not, kaynak ve zaman salt
okunur; null değerler Bilinmiyor, gerçek sıfır birimiyle gösterilir.
Sunucudan 10'lu sayfalama, açık UTC tarih filtresi ve elle/fokusa dönüşte
yenileme vardır. İzin/bağlantı kaybı, boş sonuç ve hata ayrıdır; önceki sağlık
verisi ve sayılar istek/oturum/danışan değişince gizlenir. Geç yanıtlar gösterilmez.
Program/öğün izinleri ölçüm açmaz. Sentetik önizleme gerçek panelden ayrı kalır.
Mobilde ölçüm izni uyarlaması doğrulanana kadar backend BodyMeasurementsEnabled
varsayılan false kalır; bu web ekranı danışan yerine izin oluşturmaz.

## 07.11.2026 — Giriş ve gerçek panel deneyimi

Başarılı hesap girişinden sonra `GET /dietitians/me` ile güncel uzman profili
kontrol edilir. `role=client` kalan çift profilli hesaplar dahil, onaylı uzmanlar
`/calisma-alani` genel bakışına; bekleyen başvurular başvuru durumuna yönlenir.
Uzman profili olmayan danışan için giriş ve kayıt mobil uygulamadadır. Profil kontrolü
başarısız olduğunda oluşturulmuş oturum korunur ve hesap ekranından yeniden
kontrol/çıkış yapılabilir. Çalışma alanı girişte onayı tekrar sunucudan doğrular.

Gerçek diyetisyen paneli mevcut tasarım tokenlarıyla genel bakış, danışan
listesi/detayı, programlar ve bağlantı/davet düzenini kullanır. Genel bakışta
aktif danışan ve bekleyen istek sayıları mevcut API yanıtlarından gelir;
yükleme/hata durumunda bilinmeyen sayılar `—` kalır. Sağlık önizlemeleri
gerçek panele taşınmaz. Responsive menü, klavye odağı ve iki tema desteklenir.

Yönetici girişi `/yonetici-giris`, panel `/yonetim/uzmanlar` (`/yonetim`
yönlendirir) adresindedir. MFA'lı oturum ve mevcut `isVerified` filtresiyle
bekleyen/onaylı başvurular görüntülenir; onaylı satırda tekrar onay düğmesi
yoktur. Yönetici çıkışı onaylandıktan sonra yönetici girişine dönülür.

Bu web düzeltmeleri API/DTO, backend, mobil veya migration değiştirmez.
Veritabanı migration uygulaması ve yerel Admin kurulumu `backend/README.md`
adımlarına göre ayrıca yapılır; web tarayıcısından bu işlemler çalıştırılmaz.

## 17.11.2026 — Web oturumu ve diyetisyen başvurusu

`/uzman-basvurusu` yeni diyetisyen hesabı açar. Mevcut danışan hesabıyla başvuru,
mobil uygulamanın Profil ekranından yapılır. Onaylı çift profilli hesap webde
diyetisyen çalışma alanına erişebilir. Panelin sağ üstündeki avatardan **Hesabım**
ve **Çıkış yap** açılır. Sunucu çıkışı doğruladığında ilgili giriş ekranına dönülür.

## Gerçek program oluşturma ve atama — N1–N3

Doğrulanmış uzman `/calisma-alani/danisanlar/{clientId}` detayında
nutrition_plans izni varsa gerçek programları okur. “Yeni program oluştur”
boş hedeflerle taslak açar; gün, öğün, miktar ve en az iki aynı gün/öğün
alternatifi girilebilir. Taslak kaydetme otomatik atama değildir; “Programı
etkinleştir” açık atamadır. İkinci active 409'u gösterir ve taslağı korur.
Kendi programını düzenleme yeni sürüm kaydeder; geçmiş salt okunur açılır.
Arşivleme açık işlemdir. Kişisel/başka uzmanın programında yazma düğmesi yoktur.

İzin kaybolunca içerik/form/geçmiş kaldırılır; temel danışan adı kalabilir.
İstek değişimi eski veriyi gizler, okumalar ve sayfadan ayrılınca yazma yanıtı
iptal edilir. Yazma otomatik tekrarlanmaz; ağ hatasında yeniden kontrol istenir.
HTTPS proxy'ye `/api/v1/nutrition-plans` eklendi; yerel W2 kurulumu aynıdır.
Yeni paket yoktur. Flutter değişmedi; sözleşme ve sunum sırası `docs/16`dadır.

**Doğrulama:** 128 web testi; typecheck, lint ve production build geçti.
Bileşen testleri doğru gövde/CSRF, açık aktivasyon, 409, salt okunurluk,
alternatif doğrulama, eski snapshot, yetki kaybı ve iptal davranışını kapsar.
Backend'in 250 testi gerçek geçici PostgreSQL/Mailpit'te ayrıca geçti;
tam canlı tarayıcı/mobil ortak sunum provası henüz yapılmadı.

## Gerçek diyetisyen çalışma alanı — R1–R3

`/hesabim` ve doğrulanmış başvuru durumundan `/calisma-alani` açılır.
Sunucudan auth/me ve dietitians/me kontrol edilmeden özel kaynak okunmaz;
doğrulanmamış uzman başvuru durumuna döner. `/calisma-alani/danisanlar`
gerçek aktif danışanları adla arar/sıralar/sayfalar; detay yalnız izinli
temel adı/kimliği gösterir. Sağlık kartları veya sahte hedef/toplam eklenmez.

`/calisma-alani/baglantilar`, gerçek pending/active/rejected/ended listesini,
kabul/red/sonlandırma ve davet kodu üretimini kullanır. API'nin ilişki DTO'su
bekleyen talepte ad taşımadığından danışan profil kimliği gösterilir; isim
uydurulmaz. Kabul edilen danışanın adı aktif danışan listesinde görünür.
Davet kodu yalnız geçici sayfa belleğindedir; depolama/URL/loga yazılmaz.
Cookie yazmalarında girişte yakalanan CSRF kullanılır; geçersiz bağlamda
özel görünüm kaldırılır ve yazma otomatik tekrarlanmaz. Sayfa/filtre değişimi
eski veriyi hemen gizler ve önceki okumayı iptal eder.

Eski `/onizleme` geliştirme alanı ayrı sentetik görünüm olarak kalır. Program
oluşturma/atama sonraki N1–N3 diliminde eklendi; diğer sağlık kayıtları açık. Mobil danışan
talebi/izin ekranları Mert'in alanıdır; backend sözleşmeleri `04/05/06`dadır.

R1–R3 sonrası typecheck/lint ve 115 web testi başarılıdır; tüm backend
entegrasyonları geçici PostgreSQL/Mailpit'te ayrıca doğrulanmıştır.

## Uzman başvurusu ve MFA'lı yönetim — 29.10.2026

B1–B3 ortak onayıyla aşağıdaki yollar gerçek backend'e bağlıdır:

| Yol | İşlev |
|---|---|
| `/uzman-basvurusu` | Yalnız diyetisyen hesabı/başvurusu; mesleki açıklama ve mevcut 8–128 Unicode parola politikası. Başarı 201; otomatik giriş veya uzman onayı yok |
| `/uzman/basvuru-durumu` | Giriş yapan diyetisyenin güncel Admin doğrulaması; yalnız manuel yenileme |
| `/yonetici-giris` | Ayrı CSRF korumalı admin-web-session yolu; parola + TOTP veya tek kullanımlık kurtarma kodu |
| `/yonetim/uzmanlar` | MFA Admin'e başvuru listesi, mesleki açıklama, sayfalama ve uzman onayı; sağlık verisi yok |

`/hesabim`, sunucunun MFA cookie'siyle onayladığı Admin hesabını da beş alanla
gösterir; çıkış mevcut W2 yolunu kullanır. Normal giriş Admin'e oturum vermez.
Giriş ekranı uzman başvurusu ve yönetici girişine bağlantı içerir. Token/MFA
kodu/mesleki açıklama JS depolama/URL/loga yazılmaz; parola/MFA gönderimde
temizlenir. Geç yanıtlar sayfadan ayrıldıktan sonra veri gösteremez. Başarısız
CSRF/yetki yanıtı özel başvuru listesini kaldırır; yazma otomatik tekrarlanmaz.

HTTPS sertifikası/proxy kurulumu aşağıdaki W2 adımlarıyla aynıdır. Yeni
dietitians ve admin/dietitians API yolları HTTPS backend'e proxy edilir.
Admin yerel kurulum ve MFA yenileme komutu `backend/README.md`dedir.
Uzman onayı tek başına sağlık verisi yetkisi değildir; gerçek danışan bağlantısı
R1–R3, program modülü N1–N3 ile ayrıca eklendi. Flutter değişmedi.

Uğur'un web alanı için React/TypeScript + Vite uygulaması. Danışan kaydı, e-posta doğrulama ve
yeniden kod isteme mevcut backend API'sine bağlıdır. Giriş/şifre sıfırlama
arayüzleri ve yalnız geliştirme ortamında açılan diyetisyen paneli önizlemesi de bulunur.
W2 ortak onayıyla gerçek web cookie girişi, hesap özeti ve sunucuda çıkış bağlıdır.
Sağlık verisi ve gerçek uzman/Admin paneli entegrasyonu henüz tamamlanmamıştır.

## Çalıştırma

Node.js 20.19+ veya 22.12+ gerekir. Kurulum ve kontroller `apps/web/` içinde:

```sh
npm ci
npm run dev
npm run typecheck
npm run lint
npm test
npm run build
```

## Web oturumu (W2)

`/giris` formu CSRF aldıktan sonra `POST /api/v1/auth/web-session` çağırır.
Parola kırpılmaz; gönderimde temizlenir. Başarılı giriş `/hesabim` ekranını açar;
danışan/diyetisyen rolü panel erişimi yerine yalnız hesap özeti gösterir.
Hesap ekranı sayfa açılışında CSRF, ardından `GET /api/v1/auth/me` okur;
adı olmayan hesap **Belirtilmemiş** görünür. JWT login yolu webden çağrılmaz.

Cookie Secure/HttpOnly/SameSite=Strict'tir; JS tarafından okunmaz. Hesap/CSRF
yalnız sayfa belleğindedir; kalıcı depolama, URL veya loga yazılmaz. Arka planda
oturum yaşatma polling'i yoktur. Çıkışta hesap bilgileri hemen kaldırılır;
CSRF ile `DELETE /api/v1/auth/web-session` yalnız 204 dönerse girişe geçilir.
Ağ/500 hatası sunucuda doğrulanmamış çıkış olarak görünür; kullanıcı tekrar
denerken hesap bağlamı yeniden okunur. Farklı hesaba geçen sekmede otomatik
çıkış yapılmaz. 400/403'te eski CSRF atılır; yazma otomatik tekrarlanmaz.
Sayfadan ayrılma isteği iptal eder, geç yanıt görünümü geri getiremez.

Bu akış HTTPS gerektirir. Backend `https://localhost:7099` HTTPS profili ve
`Auth__WebSession__Origin=https://localhost:5173` ile yapılandırılır; anahtar
koruması ve dizin izinleri için `backend/README.md` izlenir. Güvenilir .NET
geliştirme sertifikasını Git dışındaki özel bir dizine PEM olarak aktarın:

```powershell
dotnet dev-certs https --trust
dotnet dev-certs https --export-path "$env:LOCALAPPDATA/SmartNutrition/dev-cert.pem" --format Pem --no-password
$env:SMART_NUTRITION_HTTPS_CERT = "$env:LOCALAPPDATA/SmartNutrition/dev-cert.pem"
$env:SMART_NUTRITION_HTTPS_KEY = "$env:LOCALAPPDATA/SmartNutrition/dev-cert.key"
$env:NODE_EXTRA_CA_CERTS = $env:SMART_NUTRITION_HTTPS_CERT
npm run dev
```

Üst dizini önce oluşturun ve yalnız geliştirme hesabının erişimini sağlayın.
PEM özel anahtarı kaynak depoya taşınmaz. Vite her iki yol birlikte verilince
`https://localhost:5173` üzerinde çalışır; API sertifikasını normal doğrular
(`secure:true`), kontrolü kapatmaz. HTTPS modunda kayıt, doğrulama ve yeniden
kod isteme de doğrudan `https://localhost:7099` adresine gider; API'nin HTTP →
HTTPS yönlendirmesi `redirect:error` kullanan bu istekleri kesmez. HTTP önizleme,
backend'in yalnız `http` profiliyle görsel/kayıt/e-posta yollarını destekler;
cookie oturumu HTTP'de açılmaz. Üretimde aynı HTTPS origin altında
API proxy'si gerekir; Vite preview API proxy'si sağlamaz.

## Danışan web kaydı — 28.10.2026 arşivi

17.11.2026 itibarıyla danışan kaydı mobil uygulamada yapılır. Eski `/kayit`
adresi web girişine yönlendirir. Aşağıdaki açıklamalar önceki uygulamaya aittir.

Girişteki **Danışan hesabı oluştur** bağlantısı `/kayit` ekranını açar. Form,
`POST /api/v1/auth/register` yoluna yalnız `displayName`, `email`, `password`
gönderir; yalnız danışan kaydı desteklenir. Ad/e-posta kırpılır; parola aynen
korunur. Parola uzunluğu onaylı 8–128 Unicode kod noktası kuralıyla kontrol
edilir; sunucu doğrulaması geçerliliğini korur. Yalnız `201 { id }` başarıdır.
Ardından e-posta doğrulama ekranına bağlantı gösterilir; otomatik giriş yapılmaz
ve e-posta teslimi kesinleşmiş sayılmaz.

Parola gönderim başında temizlenir; form işlem sürerken tekrar gönderilemez.
409/422/diğer HTTP hataları ve sonucu belirsiz ağ hataları güvenli metinle
gösterilir; sunucu gövdesi kullanıcıya yansıtılmaz. İstek cookie/Authorization
taşımaz; kayıt bilgileri kalıcı depolama, URL veya loga yazılmaz. Sayfadan
ayrılınca istek iptal edilir; iptal sunucudaki kaydı geri almaz. Alanlar geri
dönüşte boştur. Geliştirme proxy'si kayıt yolunu HTTP modunda `http://127.0.0.1:5052`,
HTTPS modunda `https://localhost:7099` API'sine iletir. Üretimde aynı origin HTTPS
altında API yönlendirmesi gerekir.

Bu dilimde `npm run typecheck`, `npm run lint`, `npm test` (**95 test**) ve
`npm run build` başarılıdır. Kayıt testleri sentetik fetch yanıtlarıyla başarı,
parola sınırları, HTTP/ağ hataları, çift gönderim ve iptal davranışını doğrular.

28.10.2026 uçtan uca doğrulamada geçici PostgreSQL 17 ve Mailpit v1.32.0 ile
`dotnet build SmartNutrition.Backend.slnx --no-restore` (0 uyarı/hata) ve
`dotnet test SmartNutrition.Backend.slnx --no-restore` (**214 geçti, 0 atlandı**)
başarılıdır. Güvenilir HTTPS Vite/Kestrel üzerinde tarayıcıyla sentetik kayıt,
doğrulanmamış hesabın giriş reddi, gerçek SMTP e-postası, yeniden gönderim,
eski/kullanılmış kodun reddi, yeni kodla doğrulama, giriş, hesap yenileme ve
çıkış sonrası korunan hesap yolunun girişe dönmesi doğrulanmıştır. Bu test,
HTTPS geliştirme proxy'sindeki `307` yönlendirme hatasını ortaya çıkarmış ve
yukarıdaki doğrudan HTTPS hedefiyle giderildiğini doğrulamıştır. Yalnız geçici
veritabanı/posta kutusu ve sentetik hesap kullanılmıştır; üretim yayın kapısı
`docs/11` kapsamında ayrıca geçerlidir.

## E-posta doğrulama akışı

W2 doğrulaması: `npm run typecheck`, `npm run lint`, `npm test` (**72 test**) ve
`npm run build` başarılıdır. Gerçek HTTPS Vite/API proxy ve sentetik hesapla
giriş–hesap yenileme–çıkış tarayıcıda da doğrulanmıştır.

### Doğrulama kodu

Giriş ekranındaki **E-postamı doğrula** bağlantısı `/eposta-dogrulama` ekranını açar.
E-postadaki 43 karakterlik tek kullanımlık kod elle yapıştırılır; URL'den kod
alınmaz ve sayfa açılışında doğrulama isteği gönderilmez. Yalnız kullanıcının
gönderimiyle `POST /api/v1/auth/verify-email` çağrılır. Sadece `204` doğrulama
başarısıdır; `422` geçersiz/süresi dolmuş kod, diğer hatalar ve ağ kesintisi
güvenli mesajlarla gösterilir. Gönderilen kod hemen alandan temizlenir.

**Yeni kod iste**, `POST /api/v1/auth/resend-verification` yoluna yalnız `email`
gönderir. `202` hesap varlığını veya e-posta teslimini doğrulamaz; uygun hesap
için gönderimin işleme alınabileceğini bildirir. Yeni kod eskisini geçersiz
kılabileceğinden alandaki kod temizlenir. `429` sonrası kullanıcı bekleyip yeniden
deneyebilir; sunucunun yapılandırılabilir sınırları istemcide sabit bir sayaçla taklit edilmez.

Bu iki işlem oturumsuzdur; istekler cookie/Authorization içermez, önbelleğe
alınmaz ve yönlendirme takip etmez. Kod ve e-posta kalıcı istemci depolamasına,
URL'ye veya loga yazılmaz. Devam eden işlem tekrar gönderimi engeller; sayfadan
ayrılınca istemci isteği iptal edilir. İptal sunucudaki işlemi geri almaz.
Doğrulama otomatik giriş, uzman doğrulaması veya panel erişimi sağlamaz.

Yerel geliştirmede backend'i `backend/README.md` adımlarıyla PostgreSQL,
Mailpit ve JWT yapılandırmasıyla HTTP kullanımında `http://127.0.0.1:5052`
üzerinde (`http` profili) çalıştırın. HTTPS kullanımında yukarıdaki W2
kurulumuyla `https://localhost:7099` hedeflenir. Vite geliştirme sunucusu bu iki
doğrulama API yolunu ilgili hedefe proxy eder. Sentetik bir diyetisyen hesabı
için `/uzman-basvurusu` formunu ve Mailpit'teki doğrulama kodunu kullanın.
Backend kapalıysa ekran bağlantı/işlem
hatası gösterir. `npm run preview` API proxy'si sağlamaz; dağıtımda aynı origin
altındaki bu API yolları backend'e yönlendirilmelidir. Üretime yayın `docs/11`
koşullarını ayrıca gerektirir.

## Panel önizlemesi

`http://127.0.0.1:5173` giriş ekranını açar. Geliştirme sunucusundaki **Panel
tasarımını incele** bağlantısı `/onizleme` alanına gider. Danışanlar ve bağlantı
istekleri arasında gezinilebilir. Danışanlar bölümü altı sentetik danışanla
Türkçe arama ve A–Z/Z–A sıralama sunar. Kayıt bağlantıları danışan detayındaki
salt okunur öğün, su, ölçüm, aktivite ve tahlil örneklerini açar. Arama/sıralama URL'de korunur;
detay ekranından listeye dönüşte arama geri gelir.

Danışan detayındaki **Aktiviteler** bağlantısı `?kayit=aktiviteler` görünümünü
açar. Aktivite türü, başlangıç zamanı, kaynak, süre (dk), mesafe (km) ve enerji
(kcal) yalnız kayıttaki değerlerle gösterilir; en yeni başlangıç önce gelir.
`activityType` sözleşmedeki serbest metindir, yeni aktivite enumu tanımlanmaz.
Örnekler manuel kaynaklıdır; cihaz/senkronizasyon veya provider DTO'su üretilmez.
Enerji aktif/toplam kalori olarak yorumlanmaz; adım/nabız, günlük toplam,
hedef veya egzersiz programı eklenmez.

**Tahliller** bağlantısı `?kayit=tahliller` görünümünü açar. `LabReport`/`LabResult`
alanlarıyla laboratuvar, örnek alma zamanı, not, test/değer/birim, varsa test kodu
ve alt/üst referanslar gösterilir. Raporlar en yeni örnek alma anı önce olacak
şekilde sıralanır. Rapor–danışan ve sonuç–rapor bağlantıları eşleştirilir.
Gerçek sıfır referans korunur; eksik sınır **Bilinmiyor** olarak kalır. İstemci
`flag` hesaplamaz: kayıttaki `unknown` korunur; birim eksik, referans eksik veya
ters ise değerlendirme gösterilmez. Sentetik analit ve aralıklar klinik eşik
değildir. Bu salt okunur görünüm tanı, LabInsight, OCR, grafik, dosya yükleme veya
PDF raporu üretmez. Gerçek diyetisyen erişimi kategori iznine ek olarak tahlil
açık onayının sunucuda doğrulanmasını gerektirir; UI senaryosu bu yetkiyi vermez.

Liste ve detay ekranlarındaki **Önizleme senaryosu** seçimi; örnek kayıt,
bağlantısız, boş, paylaşım kapalı, yükleniyor ve hata görünümlerini açar.
Bu seçenekler UI durumlarıdır; sunucu enumu veya izin/kategori kodu değildir.
Paylaşım kapalı görünümünde kayıtlar, sayıları ve değerleri DOM'dan kaldırılır.
Bu davranış sunucu yetkilendirmesinin yerine geçmez. Örnek görünümüne dönmek
ağ isteği veya yeniden yetkilendirme yapmaz.

Genel bakış sayaçlarındaki `—` değeri bilinmeyendir; gerçek sıfır veya sağlık
özeti değildir. Kayıtlardaki `null` değerler **Bilinmiyor**, gerçek `0` değerler
birimleriyle gösterilir. Tarihler UTC kaynak anıyla `<time>` içinde tutulur,
tarayıcının yerel saati ve saat dilimiyle sunulur. Günlük toplam, hedef, uyum
veya klinik değerlendirme hesaplanmaz; günlük saat dilimi politikası seçilmez.

`npm run build` sonrasında `npm run preview` üretim çıktısını yerelde gösterir.
Üretim derlemesinde `/onizleme/*` yolları kapalıdır; giriş ekranında önizleme
bağlantısı bulunmaz. Bu ayrım gerçek bir oturum/yetki sistemi değildir.
Backend ve mobil dosyaları bu web görevi kapsamında değiştirilmemiştir.

## Yapı

- `src/features/auth/`: ortak Auth düzeni, giriş/sıfırlama sunumu, e-posta
  doğrulama/yeniden gönderim ekranı ve oturumsuz API çağrıları.
- `src/features/workspace/`: panel navigasyonu, genel bakış ve veri bekleyen alanlar.
- `src/features/clients/`: danışan listesi/detayı, kapalı sözleşme alanlarının
  TypeScript karşılıkları, sentetik örnekler, kayıt sunumu ve önizleme durumları.
- `src/core/components/`: kullanılan ortak marka/ikon ve boş durum bileşeni.
- `src/core/theme/`: tek merkezde başlangıç tokenları, sistem/açık/koyu görünüm.
- `src/test/`, `*.test.tsx`: giriş/sıfırlama sunum sınırı, doğrulama HTTP
  gövdeleri/durumları, gizlilik/iptal/tekrar gönderim, üretim önizleme sınırı,
  erişilebilir form geri bildirimi, sayfa geçişi ve tema davranışları.

## Ortak sözleşme ve devam sınırı

`docs/04/05/06` W2 ortak onayıyla güncellenmiştir. AuthSession yalnız sunucuda,
CsrfTokenResponse yalnız CSRF yanıtında kullanılır. Paylaşım kategorisi veya
açık şemadan kesin mock oluşturulmamıştır. Danışan liste girdisi yalnız `id` ve `displayName` içerir;
doğum tarihi, boy, User veya Dashboard kök DTO'su varsayılmaz. Öğün/su/ölçüm/aktivite/tahlil
tipleri yalnız tanımlı alanları kullanır; fixture'lar üretim derlemesine dahil
edilmez. Bilinmeyen danışan kimliğine mevcut bir örneğin verisi atanmaz;
kayıt, öğün kalemi ve tahlil sonucu sahiplik bağlantıları görüntüleme öncesinde eşleştirilir.
Bu istemci kontrolleri gerçek kaynak/yetki denetimi olarak sunulmaz.
Giriş/sıfırlama formlarında e-posta biçimi ve boş şifre yerel olarak kontrol
edilir; kayıt parola politikası girişte uygulanmaz. Giriş gerçek W2 API'sine
bağlıdır; sıfırlama U5 ile mevcut gerçek request/reset API'lerine bağlıdır.
Şifre gönderimde ve sayfa geçişinde temizlenir; saklanmaz veya loglanmaz.
`isLoading` / `errorMessage` yalnız test edilebilir sunum girdileridir; yapay
gecikme veya sahte ağ yanıtı yoktur.

Tema varsayılan olarak sistemi izler; elle seçilen tercih yalnız mevcut sayfa
oturumunda tutulur. Kalıcı saklama tasarımı seçilmemiştir. `tokens.css` içindeki
başlangıç marka rengi `#386a5e`, 8/16/24/32 boşlukları ve 16px köşe değeri mobil
`AppTokens` ile eşleşir. Koyu tema karşılıkları ve sistem fontu tasarım önerisidir;
nihai ortak tema/ekran onayı sayılmaz. Uzak font, analitik veya medya isteği yoktur.

Backend altyapısı PostgreSQL bağlantısı, sağlık kontrolleri ve geliştirme
OpenAPI/Swagger görünümünü ve User/ClientProfile kaydını içerir. `6f808ff`
seviyesinde kayıt, e-posta doğrulama/yeniden gönderim, 15 dakikalık JWT login ve
`GET /auth/me` hesap özeti hazırdır. Web, e-posta doğrulama/yeniden gönderime
ek olarak W2 cookie/CSRF/hesap/çıkış işlemlerini kullanır. Ortak Auth önerisinin tamamı
onaylanmış sayılmaz. W2 web cookie/CSRF/iptal ortak onayı ayrıca kayıtlıdır;
mobil refresh/iptal/saklama, sıfırlama ve uzman/Admin giriş kapıları açık kalır.
Admin MFA, başvuru/doğrulama ve açık DTO'lara bağlı program/görev/yorum ekranları
bu başlangıca dahil değildir. Gerçek veri veya yayın için `docs/11` kapısı geçerlidir.
