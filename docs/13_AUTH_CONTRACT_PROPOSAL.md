# 13 — Auth ve profil sözleşmesi önerisi

**Tarih:** 27.10.2026 · **İlk öneri temeli:** DOCS-V1 / `6351089` · **Güncel inceleme temeli:** `main` / `bedce49`.

**Durum: KISMEN ONAYLI.** 27.10.2026 tarihinde kullanıcı W2-C1–C7 için
“İki tarafın ortak onayı var; uygula” diyerek Uğur–Mert ortak onayını teyit etti.
W2 ad/alan/HTTP kuralları `04/05/06`ya, güvenlik ve hazırlık durumu `11/12`ye
işlenir; normatif kaynaklar bunlardır. Diğer A1–A8 adaylarının onayı bu kayıttan
türetilmez; aşağıdaki tarihsel öneriler çalışan API sözleşmesi sayılmaz.

**Güncel karar farkı — 27.10.2026:** Bu önerinin temeli `6351089`dur; sonradan
kayıt/e-posta doğrulama ve JWT giriş görevleri kullanıcı tarafından ayrıca
onaylanmış, `04/05/06/11/12`ye işlenmiştir. Mevcut giriş 15 dakikalık **JWT** ve
`200 { accessToken, tokenType: "Bearer", expiresAt }` döndürür; hatalı/bulunmayan,
doğrulanmamış veya Admin hesap aynı `401`i alır. Aşağıdaki opaque bearer/ayrı `403`
ve refresh/cookie içeren yanıt önerileri mevcut giriş sözleşmesi değildir.
E-posta doğrulaması artık 30 dakika ve `resend-verification` yoluyla uygulanmıştır;
eski 24 saat/`email-verification-requests` önerileri geçerli kaynak sayılmaz.
Mevcut hız limitleri ve teslim sınırları `06`dadır. W2 web cookie/CSRF/iptal
ayrıca ortak onaylıdır. Profil düzenleme, mobil refresh/iptal, MFA ve sıfırlama
önerileri henüz onaylanmış/uygulanmış sayılmaz;
bu not A1–A8'in tamamına veya iki geliştiricinin ayrı onayına eşdeğer değildir.

**Sonraki kendi hesap görevi — 27.10.2026:** Kullanıcının açık talimatıyla
`GET /api/v1/auth/me`, düz `CurrentUserResponse` içinde yalnız `id`, nullable
`displayName`, `email`, `role`, `isEmailVerified` döndürür. JWT sahibi User ve
varsa kendi ClientProfile'ı sorgulanır; profil yoksa ad null'dır. Bu sözleşme
`04/05/06/11/12`de kayıtlıdır. Aşağıdaki eski `GET /me` ve iç içe profil kökü
önerileri bu endpointin yanıtı değildir; profil düzenleme/uzman profili önerileri
açık kalır. Hesap okumasının kapanması tüm A3 veya A1–A8 paketinin onayı değildir.

Dayanaklar: [kanonik adlar](04_NAMING_CONVENTIONS.md),
[veri sözlüğü](05_DATA_DICTIONARY.md), [HTTP sözleşmesi](06_API_CONTRACT.md),
[geliştirmeye hazırlık](12_TEAM_PLAN_AND_DECISIONS.md) ve
[mevcut backend hazırlığı](../backend/README.md).

## Sıradaki web giriş dilimi — 27.10.2026, onay bekleyen seçim

**İnceleme temeli: `main` / `bedce49`.** Oturumsuz web e-posta doğrulama ve
yeniden gönderim tamamlanmıştır. Gerçek web girişi hâlâ istemci saklama kararı
bekler; bu bölüm iki geliştiricinin onayı veya uygulama izni değildir.
Aşağıdaki seçimler mevcut kayıt, doğrulama, JWT login ve `GET /auth/me`
sözleşmelerini kendiliğinden değiştirmez.

| Seçim | İncelenecek somut kapsam | Sınır / sonraki etki |
|---|---|---|
| W1 — geliştirmede sınırlı JWT girişi | Mevcut `LoginUserRequest` → `LoginUserResponse` kullanılır. Access token yalnız açık sayfanın JavaScript belleğinde tutulur; localStorage, sessionStorage, IndexedDB, URL veya cookie'ye yazılmaz. Yalnız mevcut `GET /auth/me` ile beş alanlı kendi hesap özeti okunur. Yenileme/tarayıcı kapanışı, `expiresAt` veya `401` belleği ve hesap görünümünü temizler; tekrar giriş gerekir | Yeni API alanı/endpointi/modeli yoktur. Refresh çağrısı, sunucu logout/iptali, sağlık kaydı veya uzman/admin paneli erişimi eklenmez. Yerel kapatma yalnız bu sayfanın belleğini temizler; verilmiş JWT sunucuda iptal edilmiş sayılmaz. Bu geçici dilim yalnız geliştirmede sentetik hesaplarla doğrulanır; üretim girişi/yayın onayı değildir |
| W2 — önce üretim oturumu sözleşmesi | HttpOnly cookie/CSRF, sunucu oturum kaydı, süre uzatma ve iptal tasarımı; mevcut 15 dakikalık JWT kararı korunarak ayrıntılandırılır. Mobilin mevcut giriş gövdesi/yanıtı ve web taşımasının etkileri birlikte onaylanır | Cookie'nin yalnız istemcide seçilmesi yeterli değildir; backend ve ortak `04/05/06/11/12` etkileri tek onaylı değişiklikte ele alınır. Eski opaque token veya geniş login yanıtı mevcut API yerine uygulanamaz. Mobil refresh/iptal ayrı açık dilimdir |

**Önerilen ürün yönü W2'dir.** Microsoft'un web uygulamaları için sunucuda token
ve HttpOnly cookie yönlendirmesi ile OWASP'ın oturum kimliğini JavaScript'in
erişebildiği kalıcı depolamaya yazmama uyarısı bu yönü destekler.
[Microsoft: JWT ve güvenli web istemcisi](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/configure-jwt-bearer-authentication?view=aspnetcore-10.0#use-cookies),
[OWASP: istemci depolaması](https://cheatsheetseries.owasp.org/cheatsheets/HTML5_Security_Cheat_Sheet.html#local-storage).
Bu kaynaklar projeye yeni kimlik sağlayıcısı/paket veya başka JWT sözleşmesi
seçildiği anlamına gelmez. W1 yalnız ayrıca onaylanırsa geçici geliştirme adımıdır;
bellekte tutmak XSS koruması veya token iptali sağlamaz. W2 seçimi de alt şema
onayının yerine geçmez.

Her iki seçimde parola gönderimden sonra temizlenir; girişteki genel `401`,
doğrulanmamış hesap/Admin ayrımı sızdırmadan gösterilir. Kimlik/rol JWT'yi
istemcide çözümleyerek atanmaz; kaynak yetkisi sunucudadır. Onay sonrası kabul
kontrolleri: yanlış giriş ve `429`, `GET /auth/me` sahipliği/null ad, süre/`401`
sonrası temizlik, eşzamanlı istek ve sayfadan ayrılmada eski yanıtların reddi,
kalıcı depolama ve loglara secret yazılmaması. W2 için cookie/CSRF, refresh
yarışı/tekrar kullanım ve sunucuda iptal testleri ayrıca zorunludur.

**Yön seçimi:** Uğur, 27.10.2026 tarihinde “Önce HttpOnly cookie, CSRF ve sunucuda
oturum iptali sözleşmesini tamamla” seçeneğini seçti. W1 uygulanmayacaktır.
Aşağıdaki W2 ayrıntıları ilk talimatla inceleme önerisi olarak hazırlanmıştı;
sonraki açık kullanıcı teyidi W2-C1–C7 ortak onayını kaydetmiştir.
Bu teyit web giriş/oturum uygulamasını ve ilgili kanonik sözleşme değişikliğini
yetkilendirir; diğer Auth önerilerini onaylamaz.

## Önerinin 6351089 temelindeki durumu ve farkları (tarihsel)

- Mert'in `6351089` commitinde `POST /api/v1/auth/register` uygulanmıştır.
  Zorunlu girdiler `email`, `password`, `displayName`; isteğe bağlı `role`dur.
  Yalnız danışan oluşturur. Başarılı yanıt **`201 { id }`** olup `id`, User UUID'sidir.
- `RegisterAsync`, User ve ClientProfile'ı tek SaveChanges transaction'ında
  kaydeder; profilin ayrı UUID'si ve User bağlantısı korunur. `PrepareAsync`
  hesap kaydetmeyen yardımcı olarak durur. Kayıt yanıtı profil gövdesi taşımaz.
- Kayıtta `birthDate`/`heightCm` alınmaz; profilde null kalır. Bu alanları isteğe
  eklemek mevcut API'de desteklenmeyen alan hatasıdır.
- `User.IsEmailVerified` ve `is_email_verified` migration'ı eklenmiş, başlangıç
  false seçilmiştir. Alan entity JSON'una veya kayıt yanıtına çıkmaz.
- `appsettings.json` kayıt politikası **8–128 Unicode kod noktası**, en az bir
  farklı karakter ve dört karmaşıklık bayrağı false olacak şekilde yapılandırılmıştır.
  Unicode skaler sayımı ve bozuk UTF-16 reddi kodda vardır.
- Giriş/refresh/logout, `/me`, e-posta gönderimi/doğrulama ve MFA bu committe yoktur.
  Kullanıcının bildirdiği sıradaki çalışma Mert'in e-posta doğrulamasıdır.
- Mobil kayıt ekranında henüz ad alanı yok. Web ve mobil formlar önizlemedir.
- `06` kayıt/`me` yanıt kökünü, token/cookie ayrımını ve güvenlik gövdelerini açık
  bırakır. `backend/README.md` uygulanmış kayıt kararlarını anlatır; `04/05/06`
  bu committe güncellenmemiştir. Kodun varlığı ortak belge onayının kaydı değildir.
- Ürün kararı diyetisyenin mobil/web başvurusunu içerir. Mevcut danışan kayıt
  hazırlığı bu başvuru akışının tamamlandığı veya kaldırıldığı anlamına gelmez.

## 6351089 oturumundaki çakışmayı önleme sınırı (tarihsel)

Kullanıcının ilettiği çalışma bilgisi doğrultusunda kayıt ve e-posta doğrulaması
Mert'in devam eden işidir. Bu, `12`deki genel Auth liderliğini kalıcı değiştiren
bir ürün kararı değildir; aynı dosyaya eşzamanlı yazmayı önleyen görev sınırıdır.

| Alan | Bu oturumdaki sınır |
|---|---|
| `backend/src/SmartNutrition.Api/Features/Auth/` | Mert'in kayıt/doğrulama çalışmasıyla çakışabilecek Controller, User, DTO ve service dosyaları değiştirilmez |
| Backend `Data/`, migration/snapshot, `Program.cs`, ayarlar, Auth testleri ve `backend/README.md` | Mert'in görevi aynı altyapıya dokunabildiği için bu oturumda değiştirilmez; paralel migration üretilmez |
| `mobile/` | Mert'in alanı; bu belge yalnız gereken istemci etkisini bildirir |
| `apps/web/` | Uğur'un bağımsız alanı; gerçek Auth bağlantısı ilgili ortak yanıt/güvenlik kararıyla eşleştirildikten sonra ele alınır |
| `docs/13_AUTH_CONTRACT_PROPOSAL.md` | Bu oturumun tek değişiklik dosyası; güncel kodla farkları ve henüz açık önerileri kaydeder |
| `docs/04`, `05`, `06` | Ortak sözleşmeler; iki tarafın açık onayı olmadan güncellenmez |

Yeni işe başlamadan `upstream/main` alınır, değişen dosyalar ve DTO'lar yeniden
karşılaştırılır. Bir feature'ın farklı branch'te olması aynı dosyaya paralel
yazma riskini çözmez; dosya sahipliği de kontrol edilir. E-posta doğrulaması
henüz main'e gelmediyse endpoint/token şeması veya uygulama varmış gibi varsayılmaz.

| Önceki öneriyle fark | Güncel kod | Bu revizyondaki karşılık |
|---|---|---|
| Kayıt yanıtını profil kökü yapmak | `201 { id }` | Kayıt yanıtı korunur; eski geniş profil kökü önerisi mevcut `GET /auth/me` beş alanlı yanıtına uygulanmaz |
| Yeni `emailVerifiedAt` alanı | Saklanan `isEmailVerified` boolean | Paralel alan önerisi çıkarıldı; güncel `GET /auth/me` bu boolean'ı kendi hesap DTO'sunda sunar |
| Kayıtta isteğe bağlı doğum tarihi/boy | Bu girdiler kabul edilmiyor | Kayıt gövdesine eklenmez; gelecekteki profil düzenlemesi ayrı ele alınır |
| Minimum 15 parola ve eski UTF-16 sayımını düzeltme | Minimum 8; skaler sayım zaten uygulanmış | 15 yalnız ayrı politika değişikliği adayıdır; kodda yeniden sayım işi açılmaz |
| Kayıtta rol/alan doğrulamasına `422` | Girdi/rol hatası `400`; parola hatası `422` | Mevcut hata ayrımı korunur |

## Onaya sunulan kararlar

| Kod | Önerilen karar | Gerekçe ve etkisi |
|---|---|---|
| A1 | İlk çalışan kayıt dilimi yalnız danışan; hesap başına tek rol | Mevcut hazırlıkla uyumludur. Çoklu rol ve diyetisyen başvurusu ayrı akış olarak tasarlanır; public kayıt Admin veya doğrulanmış uzman oluşturmaz |
| A2 | Uygulanmış `email`, `password`, `displayName`, isteğe bağlı `role` kayıt gövdesini ortak belgelere geçir; doğum/boy kayıt gövdesine eklenmesin | Yeni danışanın User ve ClientProfile kaydı zaten atomiktir; değişiklik önerisi mevcut API'yi genişletmez |
| A3 | Kayıt için `201 { id }` korunur. Eski geniş `GET/PATCH /me` kökü önerisinden hesap okuması ayrılmış, `GET /auth/me` düz beş alanla onaylanmıştır; geniş profil/düzenleme önerisi açık kalır | Mobil ve web onaylı kendi hesap DTO'sunu kullanır; kayıt/hesap yanıtındaki User UUID'si ClientProfile UUID'si sanılmaz |
| A4 | W2 önerisi: webde HttpOnly cookie; mevcut mobil/API JWT girişi aynen korunur | Aşağıdaki W2 HTTP/taşıma tablosu esas alınır. Eski opaque token ve `useCookies` seçimi tarihsel öneridir; web yeni bir JWT yanıtı tüketmez |
| A5 | W2 önerisi: web oturumu sunucuda izlenir ve iptal edilir; mobil refresh/iptal ayrı açık dilimdir | Web çıkışı mevcut stateless JWT'leri iptal etmiş sayılmaz. Mobil refresh/token ailesi için bu görevden onay çıkarılmaz |
| A6 | Uygulanmış 8–128 skaler politikası esas alınsın; minimumu 15 yapma önerisi ayrı değerlendirilip ancak iki taraf onaylarsa değiştirilsin | Aynı anda farklı istemci/parola kuralları üretilmez; mevcut hash ve uygulanmış Unicode sayımı korunur |
| A7 | E-posta doğrulanmadan uygulama oturumu verilmez; doğrulama ve reset tokenları tek kullanımlık | Doğrulama bir oturum veya paylaşım onayı sayılmaz. Başarılı kayıttan sonra doğrulama akışı açılır |
| A8 | Admin MFA için TOTP + tek kullanımlık kurtarma kodları; hazır olana kadar Admin oturumu kapalı | Zorunlu MFA, geçici bir parola giriş yolu ile atlanmaz. Kurulum/kurtarma gövdeleri ayrıca onaylanır |

**Kaynak ile ürün önerisinin ayrımı:** Microsoft'un cookie/antiforgery
bileşenlerinin kullanılması yeni Identity endpointleri veya User tablo takımı
ekleme kararı değildir. W2 onaylı JWT sözleşmesini değiştirmez; yalnız web
oturumu için aşağıdaki ek kaynak/şema adaylarını sunar.

## A1–A3: Kayıt, profil ve rol davranışı

Tüm yollar mevcut `/api/v1` tabanını kullanır. Aşağıdaki tablolar **önerilen**
HTTP tamamlamalarıdır; mevcut yol adları korunur.

| İşlem | Önerilen girdiler ve yanıt | Kurallar |
|---|---|---|
| `POST /auth/register` | Mevcut JSON: `email`, `password`, `displayName`; isteğe bağlı `role`. Mevcut `201 { id }` | `role` gönderilmezse `client`; yalnız `client` kabul edilir. `birthDate`/`heightCm` kayıt girdisi değildir. Oturum/token üretmez |
| Önceki `GET /me` önerisi | Yerine güncel `GET /auth/me` beş alanlı düz yanıtı `06`da onaylıdır | Eski yol/iç içe kök uygulanmaz; yalnız JWT sahibinin kendi hesabı okunur |
| `PATCH /me` | `displayName`, `birthDate`, `heightCm`; `200`: güncel güvenli profil kökü | Danışan kendi alanlarını düzenler. Gönderilmeyen korunur; nullable alan açık null ile temizlenir. Boş PATCH `400` |

Geniş profil görünümü/düzenlemesi için geçmiş öneri olan kök ve alan listesi
(mevcut `GET /auth/me` yanıtını genişletmez; yeni uygulama için ayrıca onay gerekir):

| JSON anahtarı | Alanlar / anlam |
|---|---|
| `user` | Mevcut `id`, `email`, `role`, `createdAt`, `updatedAt`; saklanan `isEmailVerified: boolean` bilgisinin yalnız kendi `/me` DTO'sunda açılması **öneri**dir |
| `clientProfile` | Kendi profili varsa mevcut `id`, `userId`, `displayName`, `birthDate`, `heightCm`; yoksa null |
| `dietitianProfile` | Kendi uzman profili varsa mevcut `id`, `userId`, `displayName`, `isVerified`; yoksa null. `licenseInfo` şeması ve özel belgeler bu güvenli yanıta dahil edilmez |

Yeni danışan kaydında `User` ve `ClientProfile` aynı transaction içinde kaydedilir;
iki UUID sunucuda ayrı üretilir. Bu davranış `6351089`da uygulanmıştır. Profil
kaydı başarısızsa yarım hesap bırakılmaz. Mevcut profilsiz hesaplara sentetik
profil veya varsayılan doğrulama atanmaz; mevcut migration'ın false başlangıcı
korunur. User hesabı ve ClientProfile kimliği birbirinin yerine kullanılmaz.

Mevcut `displayName` doğrulaması boş/yalnız boşluk girdisini reddeder; bu belgede
yeni uzunluk veya kırpma davranışı kesinleştirilmez. Gelecekteki profil düzenlemesi
için `birthDate` date-only, `heightCm` pozitif decimal/cm veya null'dır; klinik boy
aralığı, yaş sınırı, hassasiyet ve günlük saat dilimi ayrıca ortak değerlendirilir.

E-posta için mevcut invariant normalizasyon ve PostgreSQL benzersiz indeksi
korunur. Ön kontrolden sonra yarışla oluşan `ux_users_email` ihlali de `409 conflict`
olur. Bu mevcut durum kodu hesap varlığı hakkında bir sinyal taşıyabilir;
mesaj genel tutulur ve kayıt hız sınırına alınır. Bu davranış değiştirilmek
istenirse `06`daki başarı/çakışma davranışı birlikte yeniden onaylanmalıdır.

`role`, `isVerified`, `isEmailVerified`, kimlikler veya `passwordHash` profil
güncellemesinden değiştirilemez. Mevcut public kayıtta `dietitian`/`admin` rolü,
tanımsız JSON alanı/biçimi ve boş girdi `400`; parola politikası ihlali `422`dir.
Ayrı başvuru akışı onaylanmadan
diyetisyen rolüne geçiş veya başvuru endpointi uygulanmaz.

## W2 — onaylı web cookie, CSRF ve sunucuda iptal kararının inceleme kaydı

**W2-C1–C7 ortak onayı kullanıcı tarafından 27.10.2026'da teyit edilmiştir.**
Bu bölüm kararın inceleme kaydıdır; güncel kanonik kaynak `04/05/06`dır.
Bu bölüm, aşağıdaki tarihsel A4–A5'in `useCookies`, opaque bearer,
geniş login yanıtı ve mobil refresh tasarımını web uygulaması için devre dışı
bırakır. Yeni yol/tip adları yalnız bu bölümün inceleme adaylarıdır.

### W2-C1 — mevcut JWT ile uyumluluk ve HTTP

Mevcut `POST /api/v1/auth/login`, `LoginUserRequest` ve
`200 LoginUserResponse { accessToken, tokenType: "Bearer", expiresAt }` korunur;
15 dakikalık JWT, claim'ler ve hata davranışı değişmez. Bu yola cookie,
`useCookies` parametresi veya nullable token yanıtı eklenmez. Web oturum açma
işlemi bu JWT yolunu çağırıp dönen tokenı saklamaz. Ayrı kaynak bir ekran alias'ı
değil, sunucuda yaşayan cookie oturumunun oluşturulması/silinmesidir.

| Method + route adayı | Girdi / kimlik | Başarı / davranış |
|---|---|---|
| `GET /api/v1/auth/csrf` | Gövde/query yok; o anki geçerli cookie kimliği veya anonim bağlam | `200 CsrfTokenResponse { requestToken: string }`; ASP.NET Core antiforgery cookie'si hazırlanır. Yanıt yalnız request tokenıdır; User/oturum/JWT bilgisi içermez |
| `POST /api/v1/auth/web-session` | Mevcut `LoginUserRequest { email, password }`; JSON, CSRF cookie + `X-CSRF-TOKEN`, izinli `Origin`. Bearer kabul edilmez | Auth istisnası olarak `200 CurrentUserResponse`; tam mevcut beş alan, nullable ad. Yeni oturum DB'ye commit edildikten sonra korumalı HttpOnly cookie atanır; JWT/refresh token/oturum ID'si JSON'a çıkmaz. `Location` üretilmez |
| `GET /api/v1/auth/me` | Mevcut JWT **veya** W2 cookie; gövde/query yok | `200 CurrentUserResponse` şeması aynen korunur. Cookie desteği yalnız açık ortak onaydan sonra mevcut JWT-only yetkilendirmesine eklenir |
| `DELETE /api/v1/auth/web-session` | Gövde/query yok; CSRF cookie + `X-CSRF-TOKEN`, izinli `Origin`; yalnız mevcut tarayıcı cookie oturumu | DB'de o oturum iptal edildikten sonra `204`, boş gövde; auth ve CSRF cookie'leri aynı ad/path/özelliklerle temizlenir. Geçersiz/bitmiş/zaten iptal edilmiş ya da olmayan oturum, CSRF/Origin geçerliyse yine `204`; başka oturumlar etkilenmez |

`CurrentUserResponse` bu öneride de yalnız `id`, `displayName`, `email`, `role`,
`isEmailVerified` taşır; User/ClientProfile UUID ayrımı korunur. Yeni profil,
uzman durumu veya session wrapper DTO'su türetilmez. Webde hesap okumasına rol
nedeniyle yeni sağlık verisi eklenmez; Admin MFA engeli ve uzman/kategori/onay
kontrolleri korunur. Login'de olmayan hesap, yanlış parola, doğrulanmamış hesap
ve Admin aynı genel `401 unauthenticated` sonucunu alır.

Cookie ile `Authorization` aynı W2/hesap isteğinde bulunursa `400 invalid_request`
olur; birinin başarısızlığında diğerine düşülmez. Yalnız bearer içeren W2
oluşturma/silme isteği `400`dür. Geçerli cookie ile ikinci oluşturma `409 conflict`
olur; hesap değiştirmek için önce çıkış gerekir. Bozuk/geçersiz cookie bir kimlik
değildir; yeni anonim CSRF alınıp geçerli parola ile yeniden giriş yapılabilir.
Mevcut JWT yolunun gövde/yanıtı ve onaylı kayıt/verify/resend işlemleri bu seçimi
kullanmaz; bu işlemler cookie oturumu oluşturamaz veya uzatamaz.

Tüm Auth yanıtları `Cache-Control: no-store` taşır. Ortak `error`/`requestId`
zarfı kullanılır; cookie API'si HTML veya `302` giriş yönlendirmesi üretmez.
JWT `401` için mevcut `WWW-Authenticate: Bearer` korunur; cookie `401`i token,
hesap durumu veya giriş URL'si açmaz. JSON yazmada yanlış içerik `415`, ek/eksik
alan ve query/gövde ihlali `400`, boyut aşımı `413`, hız sınırı `429`, beklenmeyen
DB/altyapı hatası genel `500`dür. Geçersiz CSRF `400 invalid_request`, eksik/yanlış
Origin `403 forbidden` olur; ayrıntılı CSRF/kimlik hata metni döndürülmez.

### W2-C2 — cookie ve korumalı bilet

ASP.NET Core `AddCookie` ve Data Protection kullanılır; yeni şifreleme/imza
protokolü veya Identity tablo/endpoint takımı tasarlanmaz. Cookie biletinde tek
`sub` User UUID'si, tek `role` kanonik rol, tek `sid` AuthSession UUID'si ve
framework zaman bilgileri bulunur. `sid` yeni bir JWT claim'i değildir; mevcut
JWT yapısı korunur. E-posta, ad, sağlık değeri ve access/refresh token içermez. Rol ve oturum
referansı korumalı bilette bulunmasıyla güncel sunucu kontrolünden muaf olmaz.
Cookie principal'ında ad kimliği `sub` User UUID'si, rol kimliği `role` olur;
antiforgery aynı User kimliğine bağlanır. Eksik/tekrarlı veya bozuk `sub`/`sid`,
boş UUID ve izinli olmayan rol için kimlik kabul edilmez.

| Cookie adayı | Özellikler | İçerik / sınır |
|---|---|---|
| `__Host-smart-nutrition-session` | `Secure`, `HttpOnly`, `SameSite=Strict`, `Path=/`; Domain yok | Data Protection ile korunan authentication ticket. Kalıcı “beni hatırla” seçimi yoktur; tarayıcı cookie'sinde `Expires`/`Max-Age` bulunmaz. Bilet ve DB süreleri yine zorunludur |
| `__Host-smart-nutrition-csrf` | `Secure`, `HttpOnly`, `SameSite=Strict`, `Path=/`; Domain yok | Framework antiforgery cookie'si; request tokenı ayrı JSON'dan alınır ve yalnız sayfa belleğinde tutulur |

HTTP üzerinden cookie akışı açılmaz; yerel web/API aynı HTTPS origin üzerinden
proxy edilir ve güvenilir geliştirme sertifikası kullanılır. `Secure` kaldırma,
sertifika kontrolünü atlama veya `SameSite=None` kestirmesi yoktur. Anahtar halkası
Git dışında, uygulama kimliğine kısıtlı ve diskte korunan kalıcı depoda tutulur;
çok API örneği aynı uygulama adı/anahtar halkasını kullanır. Üretim sağlayıcısı,
anahtar koruma ve dağıtım ayrıntıları `11/12` yayın kapısında ayrıca doğrulanır;
geçersiz koruma/anahtar yapılandırmasında cookie oturumu açılamaz.

Bu framework tercihi ve her istekte kimlik kontrolü için
[Microsoft: cookie authentication](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/cookie?view=aspnetcore-10.0)
ve anahtar halkası için
[Microsoft: Data Protection yapılandırması](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/configuration/overview?view=aspnetcore-10.0)
esas alınır. Yukarıdaki adlar/süreler ise bu projeye özel onay adaylarıdır.

### W2-C3 — CSRF, Origin ve tarayıcı kimliği

ASP.NET Core antiforgery servisi açıkça kaydedilip JSON endpointlerinde
`IAntiforgery` ile doğrulanır; yalnız `AddControllers` veya SameSite yeterli
kabul edilmez. Request tokenı `GET /auth/csrf` ile o anki cookie + kullanıcı
bağlamına bağlı üretilir. Girişten sonra yeni kimlik için tekrar alınır; çıkış,
`401` veya hesap değişiminde bellekteki eski değer atılır. Request tokenı
yetkilendirme kimliği değildir ve cookie'nin yerine geçmez.

Web session POST/DELETE ve ileride cookie ile kimlik doğrulayan bütün
POST/PUT/PATCH/DELETE işlemleri, iş kuralı çalışmadan CSRF kontrolünden geçer.
Bu yazmalarda `Origin`, yapılandırılmış tek web origin'iyle scheme/host/port
olarak tam eşleşmelidir; yok/null/farklı origin reddedilir. `GET /auth/csrf`te
varsa Origin aynı kontrolü geçer; `Sec-Fetch-Site: cross-site` istekleri reddedilir.
GET'lerde ürün verisi değiştirilmez. Kimlik cookie'si kullanmayan mevcut
oturumsuz API işlemleri cookie yetkisi kazanmaz; mobil bearer'a bu tarayıcı
başlıkları zorunlu tutulmaz.

Web/API aynı origin'dedir; wildcard origin veya başka origin'e credential CORS
açılmaz. Başka origin ihtiyacı ayrı onay gerektirir. Aynı tarayıcıdaki sekmeler
tek cookie hesabını paylaşır; sekme başına farklı hesap vaat edilmez. Başka
sekmede hesap/oturum değişirse eski CSRF ile yazma reddedilir. İstemci mevcut
işlemi otomatik tekrarlamaz; yeni CSRF/hesap bağlamını okuyup kullanıcıya tekrar
gönderim olanağı verir.
[Microsoft: antiforgery ve çoklu sekme](https://learn.microsoft.com/en-us/aspnet/core/security/anti-request-forgery?view=aspnetcore-10.0).

### W2-C4 — sunucu oturumunun veri adayı

Yeni kavram adayı **`AuthSession`**, tablo adayı **`auth_sessions`**tir. Yalnız
web cookie oturumunu izler; `User`, `ClientProfile` veya doğrulama tokenı için
eşanlamlı entity değildir. İstemciye serileştirilmez. Ortak onayla `04/05`e işlenmiştir.

| Alan adayı | Tip / DB karşılığı | Bütünlük |
|---|---|---|
| `id` | `uuid`, `id`; PK | Sunucunun oluşturduğu oturum referansı; User/profil UUID'si değildir. Tek başına bearer secret veya geçerli cookie değildir |
| `userId` | `uuid`, `user_id`; zorunlu FK → `User.id` | Bir User'ın birden çok tarayıcı/cihaz oturumu olabilir; User başına unique yapılmaz. FK silmesi `NO ACTION`; hesap silme ayrı `11` akışında oturumları ayrıca ele alır |
| `createdAt` | `instant`, `created_at`; zorunlu | UTC ilk giriş zamanı; yenilemeyle değişmez |
| `lastSeenAt` | `instant`, `last_seen_at`; zorunlu | Son başarılı yetkili istek; ilk değer createdAt, geriye gitmez |
| `idleExpiresAt` | `instant`, `idle_expires_at`; zorunlu | Hareketsizlik sonu; başlangıçta createdAt + 30 dakika |
| `absoluteExpiresAt` | `instant`, `absolute_expires_at`; zorunlu | createdAt + 8 saat; hiçbir işlem uzatamaz |
| `revokedAt` | `instant?`, `revoked_at` | Başlangıç null; iptalden sonra tekrar null yapılamaz |

Sıra `createdAt <= lastSeenAt < idleExpiresAt <= absoluteExpiresAt` olur;
revokedAt varsa createdAt'ten önce olamaz. `user_id` ve süreye göre temizlik
indeksleri önerilir. Cookie bileti `AuthSession.id` referansını korumalı olarak
taşır; cookie/bilet/JWT/parola veya Data Protection anahtarı DB satırına
kopyalanmaz. Yeni düz metin token/hash sütunu gerekmemesinin nedeni kimlik
doğrulamasının framework'ün korumalı biletiyle yapılmasıdır; çıplak UUID kabul
eden bir kimlik yolu eklenmez. User'a session/refresh sütunu eklenmez.

Önerilen yalnız oturum satırı saklama sınırı: iptal veya süre bitişinden sonra
en geç 24 saatte temizlenmesi; kullanıcı/sağlık kaydı bu temizlikten etkilenmez.
Bu süre de ortak onay adayıdır. `AuditEvent` veya sağlık verisinin saklama
süresi bu 24 saatten türetilmez; `11`deki ayrı politika geçerlidir.

### W2-C5 — süre, eşzamanlılık ve iptal

Cookie ile her yetkili istekte korumalı bilet, oturum satırı ve User birlikte
denetlenir: oturum o User'a ait, revokedAt null, `now < idleExpiresAt` ve
`now < absoluteExpiresAt`, hesap var/doğrulanmış ve güncel rol biletteki
`client`/`dietitian` rolüyle aynı olmalıdır. Eşitlik anında süre bitmiştir.
Admin kabul edilmez. Aktif oturum sonucu süreçler arasında önbelleğe alınmaz;
DB kontrolü atlanmaz. DB erişim hatası genel `500`dür ve erişim kapalı kalır;
önceki başarılı kontrol veya bilet tek başına yetki vermez.

Başarılı yetkili istek idleExpiresAt'yi `min(now + 30 dakika, absoluteExpiresAt)`
değerine ilerletebilir. Sağlık kontrolü, statik dosya, CSRF alma, başarısız/yetkisiz
istek ve otomatik oturum-yaşatma polling'i süre uzatmaz. Bilet yenilense de aynı
oturum/createdAt/absoluteExpiresAt korunur; biletin geçerliliği DB sınırını aşamaz.
Tarayıcının oturum geri yüklemesi bu sunucu sürelerini kaldırmaz. Web için ayrı
JWT refresh, refresh tokenı veya `/auth/refresh` çağrısı eklenmez.

Oturum uzatma koşullu atomik DB güncellemesidir: iptal edilmemiş ve süresi
bitmemiş satırı ilerletir, eski istek lastSeenAt/idleExpiresAt'yi geri alamaz.
Çıkış `revokedAt`yi commit eder; yarışan yenileme bunu silemez veya yeni oturum
oluşturamaz. Login, User satırını transaction boyunca kilitleyip doğrulamada
kullanılan passwordHash/doğrulama/rol durumunun hâlâ aynı olduğunu denetleyerek
yeni satırı oluşturur. İlgili güvenlik değişimleri de önce aynı User satırını
kilitler; böylece iptal işleminin arkasından eski parola kontrolüyle yeni oturum
açılamaz. Yarışta geçersiz giriş genel `401` alır ve cookie üretemez.
Parola doğrulaması mevcut Identity/verifier ve ortak uygunluk kurallarını kullanır;
web yolu JWT üretim adımını çağırmaz. Aynı parolanın başarılı Identity rehash'i
gerçek parola değişikliği sayılmaz ve diğer oturumları iptal etmez.
İptalden önce yetkilendirilmiş bir istek tamamlanabilir; commit sonrası
başlayan yeni yetki kontrolleri eski cookie'yi reddeder. Önceden dönen veri veya
indirme bu işlemle geri alınmış sayılmaz.

Şifre değişikliği/sıfırlama, e-posta doğrulamasının kaldırılması veya rol değişimi
uygulandığında ilgili User'ın bütün web oturumları aynı DB transaction'ında
iptal edilir. Bu gelecekteki yazma yollarının kabul şartıdır; sıfırlama/rol
değiştirme endpointinin bu görevde onaylandığı anlamına gelmez. Doğrulama/rol
değişikliği ayrıca her istekteki User kontrolünde de reddedilir. Hesap silme,
User FK ve audit saklaması `11`in ayrı silme akışında birlikte çözülür.

**İptal sınırı açık:** W2 çıkışı ve bu yeni web oturum tablosu, mevcut stateless
15 dakikalık JWT'leri iptal etmez. Mobil/API refresh, token ailesi ve anlık JWT
iptali hâlâ ayrı ortak sözleşmedir. Bu fark kapatılmadan bütün platformlarda
oturum iptali tamamlandı veya gerçek yayın hazır denmez.

### W2-C6 — istemci, limit ve güvenli hata davranışı

Web `credentials: same-origin` kullanır; auth cookie'sini JavaScript'te okuyamaz.
Yalnız CurrentUserResponse ve CSRF request tokenı geçici sayfa belleğindedir;
kalıcı depolama/URL/loga yazılmaz. Sayfa yenilenince `GET /auth/me` ile hesap
yeniden okunur. `401` hesap/CSRF/korunan UI verisini temizler ve girişe döner;
sunucu geçersiz auth cookie'sini temizler. JWT parse ederek rol/yetki atanmaz.

Parola bütün giriş denemelerinden sonra temizlenir. Çıkışta hassas UI hemen
kaldırılır; yalnız `204` sunucu çıkışı olarak gösterilir. Ağ/`500` hatasında
“Çıkış sunucuda doğrulanamadı; tekrar deneyin” mesajı verilir; HttpOnly cookie
istemcide silinmiş veya oturum iptal edilmiş gibi davranılmaz. Geç yanıtlar,
sayfadan ayrılma veya çıkış sonrasında eski hesabı UI'ye geri koyamaz. Yerel
iptal devam eden sunucu işlemini geri almış sayılmaz.

W2 login ile mevcut JWT login aynı IP sayacını paylaşır: onaylı başlangıç limiti
dakikada 10 giriş denemesi, yapılandırılabilir. İki yolu dönüşümlü kullanmak
limiti aşamaz. W2 login gövdesi 4096 byte; DELETE/GET gövdesizdir. CSRF alma için
ayrı önerilen sınır IP başına dakikada 30 istektir; aşım ortak `429`dur. Logout
başka hesap aramaz; CSRF/Origin doğrulamasından sonra yalnız mevcut cookie
referansını işler. Çok örnekli IP sayacı/güvenilir proxy yapılandırması yayın
öncesi tamamlanır; keyfi X-Forwarded-For güvenilir kabul edilmez.

Cookie, Authorization, CSRF başlığı, parola ve ham yanıtlar loglanmaz. Mevcut
`AuditEvent` kavramıyla başarılı web oturumu oluşturma/iptal olayları önerilir:
actorUserId o User, resourceType `AuthSession`, resourceId ilgili oturum UUID'si;
metadata yalnız `reason: logout | password_changed | role_changed | email_unverified`
gibi bu kapsamdaki neden kodunu içerir. Oluşturmada metadata null'dır. Anonim
başarısız giriş için sahte actor/User üretilmez. Audit'in kalıcı şema, saklama ve
aktarım onayı ayrı `11` kapısıdır; tamamlanmadan üretim audit'i hazır denmez.

### W2-C7 — ortak onay ve uygulama kapısı

| Etki alanı | Onay sonrası tek dilimde yapılacaklar |
|---|---|
| `04/05/06` | AuthSession/CsrfTokenResponse adları, yalnız sunucu alanları, yeni iki kaynak/üç HTTP işlemi ve `GET /auth/me` cookie kabulü; eski JWT taşıması aynen korunur |
| Backend | Aynı ASP.NET Core API içinde cookie/antiforgery, kaynak bazlı scheme seçimi, AuthSession migration'ı, transaction/iptal ve ortak giriş IP sayacı; User/profile veya sağlık migration'ı yok |
| Web | HTTPS proxy, CSRF alma/yenileme, gerçek cookie girişi/hesap özeti/çıkış ve hassas UI temizliği; panel/uzman doğrulama veya sağlık erişimi bu dilimden çıkarılmaz |
| Mobil — Mert | Mevcut JWT giriş/hesap testleri değişmeden geçmeli; yeni cookie/CSRF girdisi zorunlu olmaz. Mobil refresh/iptal için bu taslaktan DTO üretmez |
| `11/12/13` | Onay veren taraflar ve alt kararlar kaydedilir; üretim anahtar/audit/proxy/saklama kapıları ve mobil iptal sınırı görünür tutulur |

Planlanan W2 kontrolleri: 1) mevcut JWT kayıt/giriş/me regresyonu; 2) HTTPS cookie
bayrakları, JSON/JS depolarında token olmaması; 3) anonim/oturumlu CSRF ve yanlış
Origin/çoklu sekme; 4) değişmeden beş alanlı hesap yanıtı, profilsiz ad/null ve
Admin/rol engeli; 5) tam 30 dakika/8 saat sınırları, başarılı istekle sınırlı uzama;
6) logout/yenileme yarışı, tekrar logout ve cookie replay; 7) DB kesintisinde
kapalı erişim, çok API örneği ve anahtar sürekliliği; 8) geç istemci yanıtları,
iptal/ağ hatasında gerçek çıkış durumu; 9) iki login yolunun ortak IP sınırı;
10) User güvenlik değişimiyle bütün web oturumlarının atomik iptali ve secret'sız
log/audit. Bu liste öneri hazırlanırken kabul planıydı; tek başına gerçekleşmiş
test sonucu değildir. Uygulanan alt kapsamın doğrulaması backend/web README ve
görev raporunda ayrı belirtilir; üretim audit/yayın kontrolleri açık kalır.

Mevcut `bedce49` temeli ayrı doğrulanmıştır: geçici PostgreSQL 17 ve Mailpit
v1.32.0 ile **190 backend testi geçti, 0 atlandı**. Bu, mevcut JWT/e-posta/hesap
kodunun sonucudur; W2'nin uygulanmış veya doğrulanmış olduğunu göstermez.

**Onay sonrası uygulama:** `04/05/06/11/12` ve backend/web etkileri aynı
değişiklikte ele alınır. Mobil JWT yolu/DTO'su korunur; Mert entegrasyon öncesi
ortak `main`i eşitler. Mobil refresh/iptal, uzman profili ve Admin MFA açıktır.

## Tarihsel A4–A5 ile fark

İlk `6351089` önerisindeki zorunlu `useCookies` query parametresi, opaque bearer,
nullable tokenlı geniş login yanıtı ve mobil refresh ailesi W2'de kullanılmaz.
Güncel JWT yolu/yanıtı korunur; web oturumu ayrı kaynakta oluşturulup silinir.
Webde süre uzatma sunucudaki hareketsizlik penceresidir; refresh tokenı veya
ayrı refresh endpointi değildir. Önceki ayrıntılı öneri Git geçmişinde bulunur.

## A6–A8: Parola, e-posta ve yönetim güvenliği

Mevcut kayıt politikası 8–128 Unicode skaler değerdir; C# kodu artık `Rune` ile
sayar ve bozuk UTF-16'yı reddeder. Mobil/web, entegrasyonda aynı sayımı kullanır.
Mevcut options değerleri `RequiredLength=8`, `MaximumLength=128`,
`RequiredUniqueChars=1`, dört karmaşıklık bayrağı `false`tur. Parola
kırpılmaz/normalleştirilmez veya sessizce kısaltılmaz. Yapıştırma ve parola
yöneticileri desteklenir. Bu oturum mevcut politikayı değiştirmez.

**Ayrı güvenlik değerlendirmesi önerisi:** MFA kullanmayan hesaplarda minimumu
15'e çıkarmak, uzunluğu öne çıkaran rehberle uyumludur; bu, mevcut 8 sınırının
kendiliğinden değiştirilmesi veya istemcinin sunucudan farklı kural uygulaması
anlamına gelmez. Politika değişirse Mert'le birlikte doküman, sunucu ve istemciler
aynı karara taşınır. Yaygın/sızmış parola engelleme listesinin kaynağı/lisansı
uygulama öncesi seçilsin; parola bir dış servise düz metin gönderilmesin.
[OWASP: parola ve kimlik doğrulama](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).

Aşağıdaki e-posta maddeleri Mert'in devam eden işine iletilecek **önerilerdir**;
`6351089`da uygulanmış değildir. Doğrulama commitindeki gerçek alan/yol/süreler
görülüp ortak karar karşılaştırılmadan ayrı bir uygulama veya istemci DTO'su
hazırlanmaz.

| İşlem | Önerilen davranış |
|---|---|
| Kayıt sonrası | Hesap/profil kalıcı kaydedilir; doğrulama e-postası güvenilir yeniden denemeyle gönderilir. Yanıtın başarısı teslim edilmiş e-posta veya oturum anlamına gelmez |
| `POST /auth/verify-email` | Mevcut taslak sözleşmedeki `{ token }`; 24 saat ömür önerisi; doğru amaç/hesap ve kullanılmamış token atomik tüketilir, mevcut `isEmailVerified` sunucuda true yapılır; `204`. Geçersiz/süresi dolmuş/tüketilmiş token `422` |
| **Yeni öneri:** `POST /auth/email-verification-requests` | `{ email }`; tekrar doğrulama e-postası isteği. Hesap yok/doğrulanmış/bekliyor ayrımı göstermeyen `202`; yeni token eskisini geçersiz kılar |
| `POST /auth/password-reset-requests` | Mevcut `{ email }`; hesap varlığını açıklamayan `202`; token 30 dakika ömürlü ve yalnız parola sıfırlama amaçlı |
| `POST /auth/reset-password` | Mevcut `{ token, password }`; tokenı atomik tüketir, hash'i günceller ve tüm oturumları iptal eder; `204`. Otomatik giriş yapmaz; geçersiz token/parola `422` |
| Giriş | Yanlış hesap/parola için aynı `401` mesajı; bulunmayan hesapta da parola hash doğrulamasına eşdeğer maliyet. Doğru parola ancak doğrulanmamış e-posta için `403 forbidden`, oturum yok |
| Admin | TOTP kurulum/doğrulama/kurtarma gövdeleri ve güvenli saklama onaylanıp uygulanana kadar login/refresh üzerinden yönetim oturumu verilemez |

Önerilen başlangıç hız sınırı: login/kayıt için IP başına 5 dakikada 20 istek;
login için ayrıca normalize hesap anahtarı başına 15 dakikada 10 başarısız deneme.
IP sınırı aşımında `429 rate_limited` ve `Retry-After`; kalıcı hesap kilidi yok.
Reset/tekrar doğrulama e-postası hesap başına saatte 3, IP başına saatte 20 ile
sınırlandırılsın. Hesaba özgü e-posta cooldown'unda dış yanıt aynı `202` kalsın;
hesap varlığına bağlı farklı durum kodu üretilmesin. Bu sayılar da onay adayıdır.
Çoklu backend örneğinde hız sınırı ve iptal durumu ortak kaynaktan uygulanır.

E-posta tokenları bağlantı/log/analitik yoluyla sızmayacak biçimde işlenmeli;
görüntüleme otomatik doğrulama veya otomatik reset yapmamalıdır. Gönderici
sağlayıcısı, transaction sonrası güvenilir gönderim, doğrulama bağlantısı ve
mobil deep-link/canlı host seçimi ayrıca kapanmadan e-posta akışı hazır sayılmaz.

## Onay sonrası dosya ve ekip etkisi

| Alan | Gereken değişiklik |
|---|---|
| `04/05/06` | Önce uygulanmış kayıt gövdesi, minimal `201 { id }`, `isEmailVerified` ve hata ayrımını iki tarafın onayıyla eşitle. Gelecekteki profil/oturum/CSRF ve önerilen iki ek yolu ayrı kararla işle |
| Backend — görev bazında | Kayıt ve devam eden e-posta doğrulama işinde Mert'in dosyalarına paralel yazma. Oturum/rehash/iptal/reset/rate limit işleri için başlamadan dosya lideri belirle; açık DietitianProfile/MFA şemalarını tahminle kapatma |
| Mobil — Mert | Kayıtta ad alanı; aynı güvenli profil/oturum alanları; e-posta doğrulama; Android/iOS güvenli saklama seçimi ve testleri; tek refresh; logout/reset sonrası hassas cache temizliği |
| Web — Uğur | Cookie/CSRF ve ortak `/me`; gerçek rol kontrolüne göre yönlendirme. Danışan hesabına diyetisyen paneli açma; doğrulanmamış uzmanı danışan verisine geçirme |
| `02/07/08/11/12` | Kabul edilen akış, güvenlik kapıları, mobil/web davranışı ve iki tarafın onayını kaydet |

Diyetisyen başvurusunun belge/lisans gövdesi, doğrulama ve tek rolden diyetisyene
geçişte varsa kişisel danışan verisinin devamı ayrı ürün/şema kararıdır.
Bu karar ve `DietitianProfile` olmadan gerçek web uzman girişi tamamlanmış
sayılmaz. MFA ve başvuru, ilk sürüm gerekliliklerinden çıkarılmamıştır.

## Uygulama sırası ve kabul kapıları

1. Uğur ve Mert A1–A8 için kabul/düzeltme kaydını verir; kalan güvenlik saklama,
   e-posta teslimi, uzman başvurusu ve MFA alt şemalarını ilgili uygulamadan önce
   onaylar. İki taraf onaylamadan bu belge uygulama kaynağına dönüşmez.
2. İlgili kararlar tek sözleşme değişikliğinde `04/05/06` ve etkilenen istemci
   tanımlarına işlenir; iki geliştirici aynı `main` sürümüne eşitlenir.
3. İlk çalışan dilim: danışan kaydı + e-posta doğrulama + giriş/refresh/logout +
   kendi profili + parola sıfırlama. Gerçek sağlık verisi/yayın `11` kapısına bağlıdır.
4. Sonraki dilim: onaylı uzman başvurusu/doğrulama ve gerçek web uzman oturumu;
   Admin yönetiminden önce MFA akışları. Sağlık verisi için kategori/onay
   sözleşmesi ayrıca kapanır; ilk Auth dilimi tek başına sağlık erişimi vermez.

Planlanan doğrulamalar (bu görevde çalıştırılmış test sonucu değildir):

- Mobil/web aynı JSON anahtarlarını ve UUID/null ayrımını karşılıklı parse eder.
- Eşzamanlı aynı e-postada yalnız bir hesap/profil oluşur; profil hatası rollback
  yapar. Boşluk, Unicode, farklı harf boyutu ve aksan davranışları doğrulanır.
- Parola/hash/token yanıt veya loga çıkmaz; mevcut parola için rehash gerektiğinde
  doğrulamadan sonra güvenle güncellenir. Emoji ve bozuk UTF-16 sınırları test edilir.
- Yanlış hesap/parola aynı güvenli hatayı döndürür; public Admin/uzman rolü ve
  istemciden `isVerified`/`isEmailVerified` atama girişimleri reddedilir.
- Webde CSRF/Origin, cookie bayrakları, dar CORS, yetkisiz tarayıcı istekleri ve
  localStorage/sessionStorage içine token yazılmaması doğrulanır.
- Refresh yarışı/tekrar kullanım, süresi dolma, logout ve parola reseti eski access
  tokenı da geçersiz kılar; süre testleri sabit saatle deterministik çalışır.
- E-posta tokenı amaç/hesap değiştiremez; tek kullanımlılık ve güvenilir gönderim
  yeniden denemeleri gerçek test ortamında doğrulanır.
- Admin MFA'sız ve doğrulanmamış uzman sağlık verisine erişemez; danışanın kendi
  profil/veri erişimi diyetisyen ilişkisinin varlığına bağlanmaz.

## Onay kaydı

| Taraf | A1–A8 kararı | Tarih / gerekli düzeltmeler |
|---|---|---|
| Uğur | Bekliyor | — |
| Mert | Bekliyor | — |

W2 için ayrı kayıt:

| Alt karar | Uğur | Mert |
|---|---|---|
| W2 yönü: önce cookie/CSRF/sunucuda iptal sözleşmesini hazırlama | 27.10.2026 kullanıcı seçimi | Ayrı kayıt yok |
| W2-C1–C7: HTTP, yeni ad/alan, cookie, süre, iptal ve saklama | 27.10.2026 kullanıcı ortak onayı teyit etti | 27.10.2026 kullanıcı ortak onayı teyit etti |

İlk hazırlama talebi uygulama onayı değildi; sonraki açık kullanıcı teyidi yalnız
W2-C1–C7'yi kapatmıştır. Diğer öneriler ve üretim yayın kapıları açık kalır.
