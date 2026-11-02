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

## Diyetisyen Bul — gerçek API bağlantısı

### Bağlantılarım ve beslenme programı paylaşımı

“Bağlantıları ve paylaşımı yönet” üzerinden aktif/kabul edilen, bekleyen,
reddedilen ve sonlandırılan ilişkiler sayfalı okunur. Ayrı accepted durumu yoktur:
danışanın başlattığı pending isteği hedef diyetisyen accept/reject eder.
Danışan yalnız kendi pending isteğini iptal veya active ilişkisini sonlandırır;
ikisi de mevcut gövdesiz `POST /dietitian-relationships/{id}/end` kullanır.
Aktif bağlantı bitince uzman erişimi kapanır; ilgili aktif atanmış program
sunucudaki mevcut N3 kuralıyla arşivlenir, danışanın kendi geçmişi korunur.

Bağlantı kabulü izin oluşturmaz. Active ilişki için mevcut
`GET /data-sharing-permissions?relationshipId=...&page=1&pageSize=10` okunur.
Kayıt yoksa paylaşım kapalıdır; okuma hatası kapalı izin gibi sunulmaz.
“Paylaşıma İzin Ver” ayrı onay diyaloğundan sonra ilk kayıtta POST ile yalnız
relationshipId/category=nutrition_plans/isGranted=true gönderir. Mevcut kayıtta
PATCH yalnız gerçek boolean isGranted gönderir; geri alma false değeridir.
Kimlik, rol, rıza kaydı veya yeni kategori atanmaz. Tahlil paylaşımı yoktur.

Her işlem JWT ve X-Profile-Context: client kullanır; POST/PATCH, 401 dahil
otomatik tekrarlanmaz. Yazma sırasında düğmeler kapalıdır. 403/404/409, bozuk
yanıt veya belirsiz ağ hatasında eski izin/ilişki eylemleri kaldırılır; yeniden
işlem için kullanıcı “Durumu yenile” seçer. Ekrandan çıkış ve oturum değişimi
geç yanıtları görünür yapmaz. `/client-connections` doğrudan rotası Auth Gate
ile korunur. Flutter dışında kod veya ortak sözleşme değişikliği gerekmemiştir.

İlgili API/widget testleri `dietitian_api_test.dart` ve
`dietitian_finder_test.dart` içindedir. İsteğe bağlı gerçek HTTPS probe'u artık
uzman kabulü/ret, danışan iptali, izin POST/PATCH, izin öncesi/sonrası uzman
program erişimi ve ilişki bitişini de sınar. Bu probe cihaz UI testi değildir.

### Arama ve istek gönderme

Üst çubuktaki **Diyetisyen Bul** simgesi veya Profil'deki aynı seçenek,
Auth Gate ile korunan `/dietitians` ekranını açar. Mevcut açık/koyu tema ve
alt sekmeler korunur. `GET /api/v1/dietitians?page=1&pageSize=10&query=...`
yalnız sunucunun onaylı uzman listesini kullanır; arama ve sayfalama desteklenir.
Public DTO yalnız `id/displayName` içerdiğinden profil görünümü ad ve onay
bilgisiyle sınırlıdır; biyografi, belge, iletişim bilgisi veya puan uydurulmaz.

`GET /api/v1/dietitian-relationships` ile active ve pending ayrı okunur;
bekleyenler sayfalanır. `POST` gövdesi yalnız `{dietitianId}` veya
`{invitationCode}` olur. Kod 16 Base32 karakteridir; kırpılır/büyük harfe çevrilir.
İlişki çağrıları mevcut doğrulanmış JWT ve `X-Profile-Context: client` kullanır;
clientId/userId/rol gönderilmez, cookie eklenmez. Başarı yalnız geçerli `201`
pending yanıtıdır; uzman kabulü ve veri paylaşım izni ayrı işlemlerdir.
İlişki DTO'sunda uzman adı yoktur; ekranda adı mevcut arama sonuçlarından
biliniyorsa gösterilir, bilinmiyorsa genel bağlantı durumu kullanılır.

Aktif ilişki veya bilinen aynı pending istek yeniden gönderilemez. Sunucudaki
409/422/429, ağ, TLS ve sunucu hataları Türkçe gösterilir. POST otomatik
tekrarlanmaz; belirsiz sonuç/çatışma sonrası bağlantıları yenilemek gerekir.
429 için Retry-After (yoksa bir dakika) beklenir ve kullanıcı yeniden kontrol
eder. GET 401 sonrası mevcut tek refresh akışıyla en fazla bir kez okunur;
geçersiz oturum Auth Gate'i kapatır. Çıkış/değişen hesap eski yanıtları reddeder.
Mevcut API_BASE_URL ve geliştirme sertifikası yapılandırması aynen kullanılır.

`flutter test` içindeki `dietitian_api_test.dart` gerçek loopback HTTP taşımasını,
`dietitian_finder_test.dart` ekran davranışlarını doğrular. İsteğe bağlı
`flutter test test/dietitian_live_probe.dart`, yalnız önceden hazırlanmış geçici
hesaplarla gerçek HTTPS akışını çalıştırır. Girdiler `SNP_LIVE_` önekli ORIGIN,
PASSWORD, CLIENT_A, CLIENT_B, QUERY, EXPERT_ID, EXPERT_EMAIL, INVITATION ortam
değişkenleridir; kurulum/temizlik çağırana aittir. Bu test cihaz UI testi değildir.

## Diyetisyen başvurusu için web yönlendirmesi

Profil → **Diyetisyen Olarak Başvur**, uygulama içindeki bilgilendirme ekranını
açar. **Web Sitesine Git**, `url_launcher` ile `LaunchMode.externalApplication`
kullanarak `/uzman-basvurusu` adresini varsayılan tarayıcıya gönderir;
**Adresi Kopyala** aynı adresi panoya yazar. Tarayıcı hatasında kopyalama seçeneği
korunur. Mobil form/belge yükleme veya yetki değişimi yoktur; e-posta doğrulaması
ve mevcut Admin onayı gerekir. Web akışı bağımsızdır, JWT/refresh/cookie/kimlik
URL veya header ile aktarılmaz. Webde yeni hesap başvurusu mükerrer e-postada
`409` verir; doğrulanmış danışan mevcut web hesabıyla giriş yapıp aynı User'a
başvurabilir. Admin onayı sonrası danışan verileri ve temel rol korunur.

Origin `lib/core/network/web_config.dart` içinde `WEB_BASE_URL` ile yönetilir.
Yalnız HTTPS scheme/host/port kabul edilir; path, query, fragment veya kimlik
bilgisi eklenemez. `/uzman-basvurusu` yolu kod tarafından sabit eklenir.
Debug varsayılanı mevcut Vite adresi `https://localhost:5173`dür. Release/profile
için gerçek web origin'i açıkça verilmelidir; eksik/hatalı adreste eylemler kapalıdır:

```sh
flutter run --dart-define=WEB_BASE_URL=https://localhost:5173
# Dağıtımda gerçek origin ile değiştirilecek örnek:
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com --dart-define=WEB_BASE_URL=https://web.example.com
```

Android emülatöründe localhost için `adb reverse tcp:5173 tcp:5173` gerekir.
Mevcut `start.ps1` API için 7099 tünelini kurar; tarayıcıdaki web bağlantısı için
5173 tüneli ayrıca kurulmalıdır. Alternatif `10.0.2.2` host'u seçilirse sertifikanın
o host/IP ile de eşleşmesi gerekir; localhost sertifikasını IP'ye yönlendirmek yetmez.
Vite mevcut HTTPS sertifikası ve backend proxy ayarlarıyla çalışmalıdır.
Harici tarayıcı, Dart `API_DEV_CERT_BASE64`/SecurityContext güvenini kullanmaz;
geliştirme HTTPS sertifikası tarayıcı tarafından güvenilmeli ve host adıyla eşleşmelidir.
Sertifika doğrulaması devre dışı bırakılmaz. Fiziksel cihazda localhost emülatör
tüneli yerine cihazdan erişilebilir, güvenilir sertifikalı HTTPS origin'i gerekir.

Widget testleri tarayıcı çağrısının dış modda, headersız ve sır içermeyen tam
adrese yapıldığını, pano davranışını, hata/çift gönderim/ayrılma durumlarını ve
çıkışta ekranın kaldırılmasını platform kanalı üzerinden denetler. Bu testler
gerçek cihazda varsayılan tarayıcı veya sertifika davranışı doğrulaması değildir.

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

## Giriş ve kalıcı mobil oturum

`POST /api/v1/auth/login` yalnız `{ email, password }` gönderir. E-posta kırpılır;
parola Unicode/boşluklarıyla korunur, kayıt parola politikası girişe uygulanmaz.
Yalnız `200 { accessToken, tokenType: "Bearer", expiresAt, refreshToken,
refreshTokenExpiresAt }` kabul edilir.
JWT claim'leri çözümlenerek yetki verilmez; token ile gövdesiz/query'siz
`GET /api/v1/auth/me` çağrılır. Beş alanlı geçerli `200 CurrentUserResponse`,
doğrulanmış e-posta ve izinli `client`/`dietitian` rolü olmadan Auth Gate açılmaz.
Admin bearer ile kabul edilmez; MFA destekli web girişi gerekir.

Access token ve hesap özeti yalnız `AuthSession` belleğindedir. Refresh token,
mutlak bitişi ve rotasyon durum işareti tek güvenli kayıtta tutulur. Oturum saklamada
[flutter_secure_storage 11.2.0](https://pub.dev/packages/flutter_secure_storage)
Android Keystore ile korunan RSA OAEP/AES-GCM ve iOS Keychain kullanır.
iOS kaydı `unlocked_this_device`, iCloud eşitlemesi kapalıdır. Android bulut
yedekleme ve cihaz aktarımına güvenli pref dosyalarının dahil edilmesi engellenir.
Kayıt API origin'ine göre ayrılır; geliştirme tokenı başka origin'e gönderilmez.
Android/iOS dışında bu depoda düz metin veya web fallback'i bulunmaz.
Token/parola/ham yanıt loglanmaz. Cookie/CSRF veya sahte giriş eklenmez. İstek sırasında alanlar,
gönderim ve geri dönüş kilitlenir; parola istek başlarken formdan temizlenir.
Yanlış parola/olmayan hesap/doğrulanmamış e-posta/Admin aynı `401` olduğu için
istemci kesin hata nedeni veya hesap varlığı iddia etmez.

Başlangıçta bekleme ekranı gösterilir; güvenli depodaki refresh ile
`POST /api/v1/auth/refresh` çağrılır, alınan yeni refresh kaydı saklanır ve
`/auth/me` doğrulandıktan sonra Dashboard açılır. `/me` geçici olarak başarısız
olursa alınan yeni token saklanır; erişim açılmaz, aynı access token ile yalnız
`/me` yeniden denenir. Token çiftinin kalıcı kısmı refresh'tir; access disk'e yazılmaz.

Yenileme tüm çağrılar için tek Future'da birleştirilir. Normal 15 dakikalık
access süresinin bitimine 30 saniye kala yenileme denenir; uygulamaya dönüşte
süre ve `/me` kontrol edilir. Access süresi dolduğunda veya `/me` `401` verdiğinde
korumalı UI kapatılır; refresh + yeni `/me` doğrulaması olmadan açılmaz.
Geçici ağ hatası geçerli access süresini uzatmaz. Oturum geçişlerinde Navigator
geçmişi yenilenir; çıkış sonrası geri/rota argümanıyla korumalı ekran açılamaz.
Eski login/refresh/me/401 yanıtları yeni oturumu veya çıkışı geri alamaz.

Refresh/logout yalnız `{ refreshToken }` gönderir; Authorization/cookie/query
eklenmez. Refresh gönderilmeden önce güvenli kayıtta `rotationPending` işaretlenir.
İstek gönderilmeden bağlantı kesildiği biliniyorsa veya açık `400/429` yanıtı
alındıysa bu işaret kaldırılır, kayıt silinmeden kullanıcı tekrar deneyebilir.
Gönderim sonrası bağlantı/yanıt kaybı veya belirsiz sunucu hatasında eski token
otomatik tekrar kullanılmaz; kayıt karantinada tutulur ve yeniden giriş gerekir.
Yenileme sırasında uygulamanın kapanması da aynı güvenli davranışı izler.
Bu, backend'in tekrar kullanımda tüm aileyi iptal etme sözleşmesi gereğidir.
Geçersiz/süresi dolmuş refresh `401`i veya geçersiz `/me` yanıtı yerel kaydı temizler.

AppBar'daki **Çıkış yap**, `/auth/logout` ile aile iptalini ister; sunucu/ağ
başarısız olsa da yerel bellek ve güvenli kayıt temizlenir. Sunucu çıkışı
doğrulanamadıysa bu bilgi giriş ekranında gösterilir. Güvenli native kayıt
silinmeden önce oturum kapalı işaretiyle üzerine yazılır; iki yöntem
de başarısızsa başarı iddia edilmez, depo temizlenene kadar erişim kapalı kalır.
Depo erişimi/kilit hatalarında kimlik verisi düz metin yedeğe taşınmaz.
Mevcut stateless access JWT sunucuda kendi kalan 15 dakikası boyunca geçerli
kalabilir. Yeni yetkili API işlemleri aynı oturum yenileme/401 akışını kullanmalıdır;
mevcut yetkili mobil okuma `/auth/me`dir. Korunan sağlık ekranlarının verileri
henüz API entegrasyonu değildir; mevcut demo/boş durum tasarımları korunur.

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
  `login_api.dart`, login/refresh/logout/me sözleşmesini; `auth_session.dart`,
  geri yükleme/tek yenileme/expiry/401/çıkışı yönetir. `refresh_token_store.dart`
  yalnız refresh kaydını güvenli tutar; `session_status_page.dart` bekleme/kurtarma ekranıdır.
- `lib/features/home/`: Dashboard düzeni, günlük göstergeler, program/öğün kartları
  ve merkezi `dashboard_demo_data.dart` örnekleri.
- `lib/features/nutrition/`, `progress/`, `profile/`: diğer sekmelerin ekran iskeletleri.
- `test/auth_gate_test.dart`: girişsiz açılış, korumalı başlangıç/yönlendirme
  istekleri ve API doğrulaması olmadan oturum açılmaması testleri.
- `test/login_api_test.dart`: loopback HTTP ile login/me JSON ve bearer
  sözleşmesi, bozuk yanıtlar, Admin engeli, güvenli hata ve bağlantı testleri.
- `test/login_test.dart`: login+me sırası, loading/tekrar engeli, expiry/resume,
  çıkış/401/navigasyon temizliği, geç yanıt ve yeniden başlatma testleri.
- `test/auth_session_test.dart`: geri yükleme/rotasyon, tek yenileme, ağ kesintisi,
  güvenli depo hataları, iptal/çıkış yarışları ve geç yanıt regresyonları.
- `test/refresh_token_store_test.dart`: kayıt biçimi/origin ayrımı, bozuk kayıt,
  native silme hatalarında güvenli davranış ve desteklenmeyen platform kontrolleri.
  Native Keystore/Keychain testlerde paketin mock platformuyla temsil edilir;
  bu testler fiziksel cihaz güvenli depolama veya iOS imzalı derleme testi değildir.
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

Flutter SDK ve güvenli depolama paketi kullanılır; test ve analiz için standart `flutter_test` ve
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

Uygulama sistem temasını izler; kullanıcı tema tercihinin kalıcı
saklanması henüz uygulanmamıştır. Android/iOS `com.example` kimlikleri ve standart
ikonlar geliştirme yer tutucularıdır; mağaza kimliği, ikon ve yayın imzası ayrıca
kesinleştirilmelidir. Ortak veri/API sözleşmelerinden açık şema uygulanmamıştır.
## W2 web oturumu entegrasyon notu — 27.10.2026

Kullanıcının teyit ettiği Uğur–Mert ortak onayıyla web cookie/CSRF/iptal
sözleşmesi `docs/04/05/06/11/12`ye işlendi. Mobil `POST /auth/login` isteği,
15 dakikalık JWT yanıtı ve bearer `GET /auth/me` beş alanı değişmedi. Mobil
isteklere cookie/CSRF/Origin eklenmez; yeni web yollarından mobil refresh DTO'su
türetilmez. Mobil refresh/iptal/saklama hâlâ açık karardır. Mobil kaynak kodu
bu dilimde değişmedi; Mert entegrasyondan önce ortak main'i eşitlemelidir.

Bu 27.10.2026 notu W2 tesliminin tarihsel durumudur. Mobil refresh/iptal ve
güvenli saklama, yukarıdaki güncel kalıcı oturum bölümünde uygulanmıştır.
