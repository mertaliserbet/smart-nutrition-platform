# 13 — Auth ve profil sözleşmesi önerisi

**Tarih:** 27.10.2026 · **Temel:** DOCS-V1, `main` / `80b9116`.

**Durum: ÖNERİ — Uğur ve Mert tarafından henüz onaylanmadı.** Bu belge mevcut
`04/05/06` sözleşmelerini değiştirmez. Aşağıdaki alanlar, süreler ve ek yollar
inceleme adaylarıdır; çalışan API, kesin mock, migration veya tamamlanmış Auth
olarak kullanılamaz. Her karar ayrı kabul edilebilir veya düzeltilebilir.

Dayanaklar: [kanonik adlar](04_NAMING_CONVENTIONS.md),
[veri sözlüğü](05_DATA_DICTIONARY.md), [HTTP sözleşmesi](06_API_CONTRACT.md),
[geliştirmeye hazırlık](12_TEAM_PLAN_AND_DECISIONS.md) ve
[mevcut backend hazırlığı](../backend/README.md).

## Mevcut durum ve çözülecek farklar

- Backend'de `User`, `ClientProfile`, EF eşlemeleri, Identity parola hash'i ve
  `UserRegistrationService` hazırlığı var. HTTP kayıt/giriş, kalıcı oturum,
  e-posta doğrulaması ve MFA yok.
- `PrepareAsync` hesap kaydetmez, profil oluşturmaz. `RegisterUserRequest`
  yalnız `email`, `password`, nullable `role` kabul eder; profil alanlarını
  reddeder. Mevcut hazırlık yalnız danışan rolünü kabul eder.
- `RegistrationPasswordPolicy` tüm değerler açıkça yapılandırılmadan kapalıdır.
  Testlerdeki sayılar ürün politikası olarak onaylanmamıştır.
- Mobil kayıt ekranında henüz ad alanı yok. Web ve mobil formlar önizlemedir.
- `06` kayıt/`me` yanıt kökünü, token/cookie ayrımını ve güvenlik gövdelerini açık
  bırakır. `12` bunları gerçek entegrasyonun giriş koşulu olarak tanımlar.
- Ürün kararı diyetisyenin mobil/web başvurusunu içerir. Mevcut danışan kayıt
  hazırlığı bu başvuru akışının tamamlandığı veya kaldırıldığı anlamına gelmez.

## Onaya sunulan kararlar

| Kod | Önerilen karar | Gerekçe ve etkisi |
|---|---|---|
| A1 | İlk çalışan kayıt dilimi yalnız danışan; hesap başına tek rol | Mevcut hazırlıkla uyumludur. Çoklu rol ve diyetisyen başvurusu ayrı akış olarak tasarlanır; public kayıt Admin veya doğrulanmış uzman oluşturmaz |
| A2 | Kayıtta `displayName` zorunlu; `birthDate` ve `heightCm` isteğe bağlı | `User` ve `ClientProfile` birlikte oluşturulabilir. Yaş/boy temel hesap açılışını gereksiz yere engellemez |
| A3 | Kayıt ve `GET/PATCH /me` aynı güvenli `{ user, clientProfile, dietitianProfile }` kökünü kullanır | Mobil ve web aynı JSON'u okur; hesap UUID'si ile profil UUID'si karışmaz |
| A4 | Webde HttpOnly cookie; mobilde kısa ömürlü opaque bearer + dönen refresh token | Tek backend ve mevcut ASP.NET Core güvenlik bileşenleri kullanılır. Mobil tokenı çözümlemez; web tokenı JavaScript depolarına yazmaz |
| A5 | Sunucuda izlenen, iptal edilebilir oturum ve tek kullanımlık refresh | Çıkış/parola sıfırlama ve eski refresh'in tekrar kullanımında erişim gerçekten kesilebilir |
| A6 | Parola 15–128 Unicode karakter; zorunlu büyük/küçük harf/rakam/sembol yok | Uzun parola ve parola yöneticileri desteklenir; mevcut hash altyapısı korunur |
| A7 | E-posta doğrulanmadan uygulama oturumu verilmez; doğrulama ve reset tokenları tek kullanımlık | Doğrulama bir oturum veya paylaşım onayı sayılmaz. Başarılı kayıttan sonra doğrulama akışı açılır |
| A8 | Admin MFA için TOTP + tek kullanımlık kurtarma kodları; hazır olana kadar Admin oturumu kapalı | Zorunlu MFA, geçici bir parola giriş yolu ile atlanmaz. Kurulum/kurtarma gövdeleri ayrıca onaylanır |

**Kaynak ile ürün önerisinin ayrımı:** Microsoft tarayıcı istemcilerinde cookie
önerir ve kendi bearer token seçeneğinin JWT olmadığını açıklar. Bu, mevcut
projeye otomatik Identity endpointleri veya yeni bir kullanıcı tablo takımı
ekleme kararı değildir. [Microsoft: Identity API ve cookie/bearer](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/identity-api-authorization?view=aspnetcore-10.0).

## A1–A3: Kayıt, profil ve rol davranışı

Tüm yollar mevcut `/api/v1` tabanını kullanır. Aşağıdaki tablolar **önerilen**
HTTP tamamlamalarıdır; mevcut yol adları korunur.

| İşlem | Önerilen girdiler ve yanıt | Kurallar |
|---|---|---|
| `POST /auth/register` | JSON: `email`, `password`, `displayName`; isteğe bağlı `role`, `birthDate`, `heightCm`. `201`: güvenli profil kökü | `role` gönderilmezse `client`; yalnız `client` kabul edilir. `birthDate`/`heightCm` gönderilmezse null. Oturum/token üretmez |
| `GET /me` | Gövdesiz; `200`: güvenli profil kökü | Kimlik doğrulama zorunlu; yalnız oturum sahibinin bilgisi |
| `PATCH /me` | `displayName`, `birthDate`, `heightCm`; `200`: güncel güvenli profil kökü | Danışan kendi alanlarını düzenler. Gönderilmeyen korunur; nullable alan açık null ile temizlenir. Boş PATCH `400` |

Önerilen güvenli profil kökü ve alan beyaz listesi:

| JSON anahtarı | Alanlar / anlam |
|---|---|
| `user` | Mevcut `id`, `email`, `role`, `createdAt`, `updatedAt`; **önerilen yeni alan** `emailVerifiedAt: instant?` |
| `clientProfile` | Kendi profili varsa mevcut `id`, `userId`, `displayName`, `birthDate`, `heightCm`; yoksa null |
| `dietitianProfile` | Kendi uzman profili varsa mevcut `id`, `userId`, `displayName`, `isVerified`; yoksa null. `licenseInfo` şeması ve özel belgeler bu güvenli yanıta dahil edilmez |

Yeni danışan kaydında `User` ve `ClientProfile` aynı transaction içinde kaydedilir;
iki UUID sunucuda ayrı üretilir. Profil kaydı başarısızsa yarım hesap bırakılmaz.
Mevcut profilsiz hesaplara sentetik profil veya varsayılan doğrulama atanmaz.
Eski hesaplarda `emailVerifiedAt` başlangıçta null olur; otomatik doğrulanmış sayılmaz.

Önerilen `displayName` sınırı: dış boşlukları kırpıldıktan sonra 1–100 Unicode
skaler değer. `birthDate` date-only, `heightCm` pozitif decimal/cm veya null'dır;
bu görevle klinik boy aralığı, yaş sınırı veya günlük saat dilimi seçilmez.
Hassasiyet/ileri tarih gibi genel veri kuralları ayrıca ortak değerlendirilir.

E-posta için mevcut invariant normalizasyon ve PostgreSQL benzersiz indeksi
korunur. Ön kontrolden sonra yarışla oluşan `ux_users_email` ihlali de `409 conflict`
olur. Bu mevcut durum kodu hesap varlığı hakkında bir sinyal taşıyabilir;
mesaj genel tutulur ve kayıt hız sınırına alınır. Bu davranış değiştirilmek
istenirse `06`daki başarı/çakışma davranışı birlikte yeniden onaylanmalıdır.

`role`, `isVerified`, `emailVerifiedAt`, kimlikler veya `passwordHash` profil
güncellemesinden değiştirilemez. Public kayıtta `dietitian`/`admin` rolü `422`,
tanımsız JSON alanı veya biçimi `400` olur. Ayrı başvuru akışı onaylanmadan
diyetisyen rolüne geçiş veya başvuru endpointi uygulanmaz.

## A4–A5: Oturum taşıma, süre ve iptal

**Önerilen taşıma seçimi:** login, refresh ve logout için açık `useCookies`
query parametresi zorunlu olsun. `true` web, `false` mobil bearer akışıdır;
eksik/geçersiz değer `400`dür. Kullanıcı rolü bu parametreden türetilmez.
Cookie ve bearer/refresh kimlik bilgisinin çelişkili birlikte gönderimi reddedilir.

| İşlem | Web (`useCookies=true`) | Mobil (`useCookies=false`) |
|---|---|---|
| `POST /auth/login` | JSON `email`, `password`; güvenli cookie ayarlanır; `200` ortak oturum kökü | Aynı JSON; `200` ortak oturum kökünde bearer/refresh değerleri |
| `POST /auth/refresh` | Gövdesiz; mevcut cookie ve CSRF doğrulanır; `200` | JSON `refreshToken`; atomik yenilemeden sonra `200` |
| `POST /auth/logout` | Gövdesiz; CSRF doğrulanır, oturum iptal edilir ve cookie temizlenir; `204` | JSON `refreshToken`; bağlı oturum ve token ailesi iptal edilir; `204`. Süresi bitmiş access token çıkışı engellemez |

Önerilen ortak oturum kökü bütün anahtarları iki istemcide de içerir:

| Alan | Web | Mobil |
|---|---|---|
| `tokenType: string?` | null | `Bearer` |
| `accessToken: string?` | null | opaque token |
| `refreshToken: string?` | null | tek kullanımlık rastgele token |
| `expiresAt: instant` | Cookie erişim penceresinin sonu | Access token sonu |
| `refreshExpiresAt: instant?` | null | Dönen refresh tokenın sonu |

Önerilen süreler ürün kararıdır; bir standart zorunluluğu olarak sunulmaz:

| Sınır | Öneri |
|---|---|
| Mobil access | 15 dakika |
| Mobil refresh hareketsizlik penceresi | 7 gün; başarılı refresh ile yenilenir |
| Mobil oturum mutlak üst sınırı | İlk girişten 30 gün; refresh bu sınırı uzatmaz |
| Web hareketsizlik penceresi | 30 dakika; geçerli sunucu isteğinde/refresh'te yenilenebilir |
| Web mutlak üst sınırı | İlk girişten 8 saat; tarayıcı kapansa da sunucu sınırı geçerlidir |

Web cookie için öneri: `__Host-smart-nutrition-session`, `Secure`, `HttpOnly`,
`SameSite=Lax`, `Path=/`, Domain olmadan. Web ve API aynı origin üzerinden
sunulsun; yerel geliştirmede proxy ve HTTPS kullanılsın. Üretim cookie
korumalarını kaldıran kalıcı bir geliştirme kestirmesi oluşturulmasın.

**Yeni yol önerisi:** `GET /auth/csrf` → `200 { requestToken: string }`;
ASP.NET Core antiforgery mekanizmasının cookie'siyle eşleşsin. Webin giriş dahil
durum değiştiren isteklerinde `X-CSRF-TOKEN` doğrulansın. Token JavaScript
belleğinde tutulsun; auth sırrı sayılmayan bu değer bearer oturumu yerine geçmez.
Origin kontrolü ve dar CORS listesi de uygulansın. SameSite tek başına CSRF
koruması olarak kabul edilmesin. [OWASP: CSRF önleme](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html).

Cookie ve mobil tokenlar aynı sunucu oturum kaydına bağlanır. Her yetkili istekte
oturumun iptal/süre durumu ve güncel kullanıcı rolü kontrol edilir; taşınan eski
rol veya süresi dolmamış access token, iptal edilmiş oturumu yeniden açamaz.
Rol, kategori, ilişki ve tahlil açık onayı sunucudaki kaynak kontrolünde ayrıca
değerlendirilir. Oturum açmak paylaşım izni oluşturmaz.

Refresh tek bir transaction içinde tüketilip yenisiyle değiştirilir. Tüketilmiş
bir refresh yeniden sunulursa o oturumun bütün token ailesi iptal edilir ve
`401 unauthenticated` döner. Mobil aynı anda yalnız bir refresh çalıştırır;
çoklu istekler aynı sonucu bekler. Ağ cevabı kaybolursa yeniden giriş gerekebilir;
bu ilk sürüm önerisinde süresiz tekrar kullanım aralığı yoktur. Çıkışın tekrarı
yeni oturum oluşturmaz; geçersiz/önceden iptal edilmiş logout girdisi de `204`dür.

İç güvenlik saklamasında gerekli bilgiler: oturum–User bağlantısı, oluşturulma,
hareketsizlik ve mutlak bitiş zamanları, iptal; refresh özeti ve tüketilme/yerine
geçme ilişkisi; e-posta tokenının amacı, özeti, sonu ve tüketilme zamanı.
Rastgele refresh/e-posta sırları en az 256 bit CSPRNG ile üretilsin, DB'de yalnız
tek yönlü özetleri tutulsun. Token/sağlık verisi loglanmasın.
[OWASP: oturum yönetimi](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html).

**Kapanmamış alt şema:** Bu bilgilerin entity/tablo adları, tam alanları,
eşzamanlılık indeksleri ve saklama/silme süreleri henüz kanonik değildir.
Uygulama/migration öncesinde `04/05` için ayrıca onaylanmış tasarıma dönüştürülür.
ASP.NET Core Identity'nin bütün varsayılan yolları `MapIdentityApi` ile açılarak
mevcut `/api/v1` sözleşmesi genişletilmez.

## A6–A8: Parola, e-posta ve yönetim güvenliği

Parola önerisi 15–128 Unicode skaler değerdir; mobil, web ve C# aynı sayımı
kullanır. Mevcut C# `Length`/`Distinct` kontrollerinin UTF-16 birimi sayması bu
öneri onaylanırsa uyarlanmalıdır. Parola kırpılmaz/normalleştirilmez, sessizce
kısaltılmaz; bozuk Unicode reddedilir. Parola yapıştırma ve yöneticiler desteklenir.
Mevcut options karşılıkları `RequiredLength=15`, `MaximumLength=128`,
`RequiredUniqueChars=1`, dört karmaşıklık bayrağı `false` olsun; eşsiz karakter
kısıtı eklenmesin. Yaygın/sızmış parola engelleme listesinin kaynağı/lisansı
uygulama öncesi seçilsin; parola bir dış servise düz metin gönderilmesin.
Bu başlangıç önerisi uzunluğu öne çıkaran rehberle uyumludur.
[OWASP: parola ve kimlik doğrulama](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).

| İşlem | Önerilen davranış |
|---|---|
| Kayıt sonrası | Hesap/profil kalıcı kaydedilir; doğrulama e-postası güvenilir yeniden denemeyle gönderilir. Yanıtın başarısı teslim edilmiş e-posta veya oturum anlamına gelmez |
| `POST /auth/verify-email` | Mevcut `{ token }`; 24 saat ömür; doğru amaç/hesap ve kullanılmamış token atomik tüketilir, `emailVerifiedAt` sunucuda yazılır; `204`. Geçersiz/süresi dolmuş/tüketilmiş token `422` |
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
| `04/05/06` | Onaylanan profil kökü, e-posta doğrulama alanı, oturum/CSRF şekli, yeni iki yol ve güvenlik saklama şemasını eşgüdümlü işle; mevcut User/profil adlarını ve UUID anlamlarını koru |
| Backend — Uğur | Request/response beyaz listeleri; atomik kayıt; parola politikası; Identity doğrulama/rehash; oturum/iptal; e-posta; rate limit ve sunucu yetkisi. Açık DietitianProfile/MFA şemalarına tahminî model ekleme |
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
  istemciden `isVerified`/`emailVerifiedAt` atama girişimleri reddedilir.
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

Bu önerinin hazırlanmasını istemek, önerilen alan/yol/politikaları veya iki
tarafın sözleşme onayını vermiş olmak değildir. Bu görev yalnız bu belgeyi ekler.
