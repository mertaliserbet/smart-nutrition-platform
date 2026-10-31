# Smart Nutrition — Mobil

Flutter/Dart başlangıç uygulaması; Android ve iOS proje dosyaları içerir.
Ana Sayfa'da örnek verili Dashboard; Beslenme, İlerleme ve Profil sekmelerinde
boş durum ekranlarını içerir.
Giriş/kayıt, şifre sıfırlama ve e-posta doğrulama ekranları içerir.
Kayıt formu gerçek `POST /api/v1/auth/register` endpointini kullanır.
E-posta doğrulama ve yeniden gönderim mevcut Auth API'sine bağlıdır.
Giriş ve kendi hesap doğrulaması mevcut JWT API'sine bağlıdır. Parola sıfırlama
ve sağlık kayıtları henüz API'ye bağlı değildir; kayıt/e-posta doğrulaması
tek başına oturum oluşturmaz.

## Çalıştırma ve kontrol

Oluşturma ortamı: Flutter 3.44.6 (stable), Dart 3.12.2.
Komutları `mobile/` içinde çalıştırın:

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

`flutter run` için bağlı Android/iOS cihazı veya emülatör gerekir; iOS derleme ve
çalıştırma için macOS/Xcode gerekir.

## Kayıt API bağlantısı

API origin'i `lib/core/network/api_config.dart` üzerinden merkezî olarak seçilir.
`API_BASE_URL` yalnız scheme/host/port içerir; `/api/v1`, query veya kimlik bilgisi
eklenmez. Endpoint yolu mevcut sözleşmeye göre istemci tarafından eklenir.

Debug varsayılanı `https://localhost:7099`dur. Backend HTTP 5052 isteklerini
HTTPS'e yönlendirir; `10.0.2.2:5052` kayıt için uygun varsayılan değildir.
Kökteki `start.ps1`, açık Android emülatörünü bulduğunda `adb reverse`
ile 7099 portunu host'a bağlar ve mevcut açık geliştirme sertifikasını yalnız
debug derlemesine `API_DEV_CERT_BASE64` olarak aktarır. Özel anahtar aktarılmaz.
Sertifika zinciri, süre ve host adı doğrulamaları korunur; sertifika Git'e konmaz.
Backend, PostgreSQL ve SMTP ortamı backend README'sine göre ayrıca çalışmalıdır.
Gerçek cihazlarda erişilebilir ve sertifikası güvenilir HTTPS origin'i verilir.

Release/profile için `API_BASE_URL` açıkça verilmelidir ve HTTPS zorunludur:

```sh
flutter run --release --dart-define=API_BASE_URL=https://api.example.com
```

HTTP yalnız debug'da localhost/loopback ve Android emülatör alias'ına açıktır.
Android ağ güvenlik istisnası yalnız debug manifestindedir; diğer HTTP hostları
ve release HTTP kullanımı reddedilir. HTTPS sertifika/host doğrulaması kapatılmaz;
yerel HTTPS sertifikası cihaz tarafından güvenilmeli ve host adıyla eşleşmelidir.
`API_DEV_CERT_BASE64` yalnız debug'da, bu açık sertifikaya uygulama kapsamında
güven ekler; release/profile derlemeleri bu parametreyi kullanmaz.
Yeni ağ paketi yoktur; Dart `HttpClient` kullanılır.

## Giriş ve geçici mobil oturum

`POST /api/v1/auth/login` yalnız `{ email, password }` gönderir. E-posta kırpılır;
parola Unicode/boşluklarıyla korunur, kayıt parola politikası girişe uygulanmaz.
Yalnız `200 { accessToken, tokenType: "Bearer", expiresAt }` kabul edilir.
JWT claim'leri çözümlenerek yetki verilmez; token ile gövdesiz/query'siz
`GET /api/v1/auth/me` çağrılır. Beş alanlı geçerli `200 CurrentUserResponse`,
doğrulanmış e-posta ve izinli `client`/`dietitian` rolü olmadan Auth Gate açılmaz.
Admin bearer ile kabul edilmez; MFA destekli web girişi gerekir.

Token ve hesap özeti yalnız `AuthSession` belleğindedir; uygulama yeniden
başlatıldığında giriş gerekir. Token/parola/ham yanıt loglanmaz. Cookie, CSRF,
refresh, disk saklama veya sahte giriş eklenmez. İstek sırasında alanlar,
gönderim ve geri dönüş kilitlenir; parola istek başlarken formdan temizlenir.
Yanlış parola/olmayan hesap/doğrulanmamış e-posta/Admin aynı `401` olduğu için
istemci kesin hata nedeni veya hesap varlığı iddia etmez.

Oturum açıldığında Dashboard gösterilir. Oturum geçişleri tüm Navigator
geçmişini yeniler; çıkış/expiry/`401` sonrasında alt sayfa veya geri tuşuyla
korumalı ekranlara dönülmez. Route argümanları oturum oluşturamaz. `expiresAt`
anında zamanlayıcı temizler; uygulamaya dönüşte önce süre kontrol edilir,
ardından `/auth/me` yeniden okunur. Bu okumadaki `401`, gövde tamamlanmadan
oturumu siler; geçersiz hesap yanıtı da erişimi kapatır. Geçici ağ/5xx hatası
geçerli tokenın süresini uzatmaz ve yeni doğrulama başarısı sayılmaz.
Eski login/me yanıtı veya `401` yeni oturumu değiştiremez.

AppBar'daki **Çıkış yap** tokenı, hesap özetini ve navigasyonu yerel olarak
temizler. Mevcut stateless JWT için sunucuda iptal endpointi yoktur; çıkarılan
JWT kendi 15 dakikalık süresi bitene kadar sunucuda geçerli kalabilir.
Güvenli kalıcı saklama ve refresh/iptal sonraki ayrı oturum yönetimi
kapsamıdır. Yeni yetkili API işlemleri mevcut
`401` invalidasyonunu kullanmalıdır; mevcut yetkili mobil okuma `/auth/me`dir.

## E-posta doğrulama

Mevcut backend e-postası URL yerine 30 dakika geçerli, tek kullanımlık
43 karakterlik Base64URL kod içerir. Webde olduğu gibi mobilde de bu kod girilir;
tanımlı App Link/deep-link/callback sözleşmesi olmadığından URL yakalama eklenmez.
Kayıttan aktarılan e-posta ekranda görünür. Doğrudan açılışta yeniden gönderim
için e-posta girilebilir; kodun hangi hesaba ait olduğunu sunucu belirler.

`POST /api/v1/auth/verify-email` yalnız `{ token }` gönderir; yalnız boş `204`
doğrulamayı tamamlar. Kod istek başlarken alandan temizlenir, saklanmaz/loglanmaz.
Başarıdan sonra girişe dönüş navigasyon geçmişini temizler; oturum oluşturmaz.
Webde doğrulama yapan kullanıcı da girişe dönebilir; istemci doğrulama durumunu
varsaymaz ve oturum açılmış kabul etmez.

`POST /api/v1/auth/resend-verification` yalnız `{ email }` gönderir. Boş `202`,
hesap varlığı veya SMTP teslimi kanıtı değildir; genel bilgilendirme gösterilir.
İstek sürerken eşzamanlı doğrulama/yeniden gönderim ve geri dönüş engellenir.
Kayıt sonrası ve `202` sonrası yerel 60 saniye beklenir; sunucunun hesap/IP
sınırları her zaman geçerlidir. `429 rate_limited` yanıtında varsa `Retry-After`
(saniye veya HTTP tarihi) kullanılır; mevcut backend bu başlığı göndermediği
için yokluğunda 60 saniye beklenir. Yeniden gönderim otomatik tekrarlanmaz.
Geçersiz/süresi dolmuş/kullanılmış kod, bağlantı ve sunucu hataları güvenli
Türkçe mesajlarla gösterilir. Bağlantı kaybında sunucudaki sonuç varsayılmaz.

## Yapı

- `lib/main.dart`: giriş noktası.
- `lib/app.dart`: uygulama kökü ve tema bağlantısı.
- `lib/core/theme/`: başlangıç tokenları ve Material 3 açık/koyu temalar.
- `lib/core/network/api_config.dart`: API origin'i ve geliştirme/HTTPS sınırları.
- `lib/core/network/json_api.dart`: sınırlı JSON POST ve yetkili GET taşıması;
  bearer yalnız aynı API origin'ine gider, yönlendirme/cookie/otomatik tekrar yoktur.
- `lib/core/widgets/empty_state.dart`: sekmelerin ortak, duyarlı boş durum görünümü.
- `lib/features/navigation/`: Material 3 alt navigasyon ve sekme durumunu koruyan ana yapı.
- `lib/features/auth/`: kimlik ekranları, temel form doğrulaması ve ortak form görünümleri.
  `auth_gate.dart`, yalnız API ile doğrulanmış bellek oturumunda korumalı
  ekranları açar; oturumsuz korumalı yollar girişe döner.
  `registration_api.dart`, kayıt JSON'unu ve güvenli API hata eşlemesini yönetir.
  `email_verification_api.dart`, doğrulama/yeniden gönderim sözleşmesini yönetir.
  `login_api.dart`, onaylı login/me DTO'larını; `auth_session.dart`, geçici
  oturumu, expiry/401 temizliğini ve geç yanıtların elenmesini yönetir.
- `lib/features/home/`: Dashboard düzeni, günlük göstergeler, program/öğün kartları
  ve merkezi `dashboard_demo_data.dart` örnekleri.
- `lib/features/nutrition/`, `progress/`, `profile/`: diğer sekmelerin ekran iskeletleri.
- `test/auth_gate_test.dart`: girişsiz açılış, korumalı başlangıç/yönlendirme
  istekleri ve API doğrulaması olmadan oturum açılmaması testleri.
- `test/login_api_test.dart`: loopback HTTP ile login/me JSON ve bearer
  sözleşmesi, bozuk yanıtlar, Admin engeli, güvenli hata ve bağlantı testleri.
- `test/login_test.dart`: login+me sırası, loading/tekrar engeli, expiry/resume,
  çıkış/401/navigasyon temizliği, geç yanıt ve yeniden başlatma testleri.
- `test/app_test.dart`: ana navigasyonun bağımsız widget olarak tema, sekme
  geçişleri, geri tuşu ve büyük metin testleri.
- `test/dashboard_test.dart`: demo işaretleri, hedef göstergeleri, diyetisyen
  bağlantısı olan/olmayan örnekler, erişilebilirlik etiketleri ve duyarlı Dashboard testleri.
- `test/auth_test.dart`: form doğrulama, şifre görünürlüğü, ekran geçişleri,
  yüklenme/hata durumları ve klavye/büyük metin kontrolleri.
- `test/registration_api_test.dart`: ayrı loopback HTTP sunucusuyla gövde/status,
  hata zarfı, bağlantı kesintisi, timeout ve yönlendirme kontrolleri. Bu test
  sunucusu gerçek ASP.NET Core/PostgreSQL entegrasyonu yerine geçmez.
- `test/registration_test.dart`: bekleme/tekrar gönderim engeli, başarılı kayıt,
  hata ve geç yanıtların widget testleri. Kontrollü yanıtlar yalnız testtedir.
- `test/email_verification_api_test.dart`: gerçek loopback HTTP ile istek alanları,
  kesin durum kodları, güvenli hatalar, Retry-After, timeout ve bağlantı kontrolleri.
- `test/email_verification_test.dart`: kod/e-posta doğrulama, bekleme ve istek
  engelleri, güvenli girişe dönüş, hata, tema ve küçük ekran widget testleri.
- `test/device_registration_probe.dart`: isteğe bağlı terminal cihaz kontrolü;
  mevcut `LiveWidgetController` ile gerçek uygulama/UI ve HTTP istemcisini
  Android'de çalıştırır. Yeni paket kullanmaz, `flutter test` ile otomatik
  çalışmaz. `flutter run -t test/device_registration_probe.dart -d <cihaz>` için
  `API_BASE_URL`, açık sertifikanın `API_DEV_CERT_BASE64` değeri ve benzersiz
  `E2E_EMAIL=e2e-<rastgele>@example.test` verilir. Gerçek test hesabı/e-posta
  oluşturur; kayıt, mükerrer e-posta, geçersiz form ve bağlantı kesintisini
  denetler. Parolayı bellekte üretir; yalnız güvenli `E2E_RESULT` özeti yazar.

Yalnız Flutter SDK kullanılır; test ve analiz için standart `flutter_test` ve
`flutter_lints` bulunur. Yeni özellik klasörleri ihtiyaç olduğunda eklenir.

## Açık tasarım ve yayın kararları

`docs/09` ve `docs/12` uyarınca renk, font ve kesin token değerleri henüz onaylı
değildir. `AppTokens` başlangıç değerlerini tek yerde tutar; marka rengi, boşluk
ve köşe değerleri nihai ortak tasarım kararı sayılmaz. Yüzey/metin renkleri ve
tipografi Material 3 `ColorScheme` / `TextTheme` rollerini kullanır. Mobil/web
eşlemesi tasarım onayında yapılmalıdır; web kodu bu görevde değiştirilmemiştir.

Sekmeler arasında geçişte ekranlar korunur; geri tuşu diğer sekmelerden Ana Sayfa'ya
döner. Ana Sayfa'daki yönlendirme Beslenme sekmesini açar; kayıt işlemi başlatmaz.
Dashboard'daki değerler, hedefler ve sabit örnek gün gerçek kullanıcı verisi veya
kişisel öneri değildir. Hızlı işlemler yalnız kapatılabilir demo önizlemeleri açar;
kayıt veya sayaç değişikliği yapmaz. Demo yapıları API DTO'su veya açık şemalar
için kesin mock değildir; veri sözleşmesi yerine kullanılmaz.

Debug dahil tüm derlemeler Auth Gate üzerinden açılır. Dashboard ve diğer
korumalı ekranlar yalnız gerçek login + `/auth/me` doğrulamasından sonra açılır.
Önizleme/giriş atlama düğmesi yoktur. Kontrollü API yanıtları yalnız testlerde
kullanılır; üretim koduna sahte oturum veya giriş atlama seçeneği eklenmemiştir.
Geçerli kayıt formu yalnız `displayName`, `email`, `password` gönderir;
şifre tekrarı veya rol gönderilmez. İstek sürerken alanlar, gönderim ve geri
dönüş kilitlenir. Yalnız `201 { id: UUID }` sonrasında kayıt rotası e-posta
doğrulama ekranıyla değiştirilir; girilen e-posta aktarılır, şifreler temizlenir.
Bu yanıt hesap oluşturmayı doğrular; SMTP teslimi veya oturum açma kanıtı değildir.
Kayıttan doğrulamaya bağımsız önizleme kısayolu kaldırılmıştır; giriş ekranındaki
genel doğrulama bilgisi oturumsuz erişilebilir kalır.

Kayıt formu Ad Soyad (`displayName`), e-posta, şifre ve şifre tekrarı içerir.
Zorunlu alanlar, e-posta biçimi ve şifre eşleşmesi yerel olarak kontrol edilir;
kayıt parolası onaylı `06` sözleşmesine göre 8–128 Unicode kod noktasıdır.
Boşluklar korunur; karakter türü zorunluluğu eklenmez. Giriş formuna kayıt
parola sınırı uygulanmaz. Şifreler kırpılmaz, saklanmaz veya loglanmaz.
KVKK aydınlatma alanı, onaylı metin/URL henüz bulunmadığını açıkça belirtir;
zorunlu hukuki onay veya rıza kaydı oluşturmaz.
API `error.code` ve `requestId` zarfı okunur; sunucu mesajı/details veya
istisna ayrıntıları kullanıcıya ya da loga taşınmaz. 409/400/422/429/5xx ve
bağlantı hataları Türkçe gösterilir. İstek toplam 20 saniyede sonlandırılır;
yönlendirme veya otomatik tekrar yoktur. Bağlantı kesintisinde sonucun
doğrulanamadığı belirtilir; kayıt oluşmadığı varsayılmaz.
`isLoading` ve `errorMessage` sunum girdileri korunur; gerçek istek durumu
ekran tarafından yönetilir. Sahte kayıt veya giriş simülasyonu yoktur. Şifre alanları
sayfa kapandığında serbest bırakılır; başka kimlik ekranına giderken temizlenir.

Uygulama sistem temasını izler; kullanıcı tema tercihi veya kalıcı
saklama henüz uygulanmamıştır. Android/iOS `com.example` kimlikleri ve standart
ikonlar geliştirme yer tutucularıdır; mağaza kimliği, ikon ve yayın imzası ayrıca
kesinleştirilmelidir. Ortak veri/API sözleşmelerinden açık şema uygulanmamıştır.
## W2 web oturumu entegrasyon notu — 27.10.2026

Kullanıcının teyit ettiği Uğur–Mert ortak onayıyla web cookie/CSRF/iptal
sözleşmesi `docs/04/05/06/11/12`ye işlendi. Mobil `POST /auth/login` isteği,
15 dakikalık JWT yanıtı ve bearer `GET /auth/me` beş alanı değişmedi. Mobil
isteklere cookie/CSRF/Origin eklenmez; yeni web yollarından mobil refresh DTO'su
türetilmez. Mobil refresh/iptal/saklama hâlâ açık karardır. Mobil kaynak kodu
bu dilimde değişmedi; Mert entegrasyondan önce ortak main'i eşitlemelidir.
