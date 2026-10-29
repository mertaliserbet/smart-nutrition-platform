# 14 — 29 Ekim sunumu: sıradaki sözleşme kararları

**Tarih:** 29.10.2026 · **Temel:** ortak `main` / `8705f1f`.
**Durum: B1–B3 ORTAK ONAYLI.** Kullanıcı 29.10.2026 tarihinde
“Ortak onay var devam et.” diyerek Uğur–Mert onayını teyit etti.
Bu dosya karar kaydıdır; normatif ad/veri/HTTP kaynakları `04/05/06`dır.
İlişki/paylaşım ve program paketleri bu onayın kapsamı dışındadır.

## Hedef ve mevcut uygulama sınırı

Ön raporun 29 Ekim adımı: e-posta doğrulamalı kimlik, diyetisyen başvurusu ve
Admin onayı, arama/davet ve karşılıklı onay, gerçek danışan listesi/detayı,
webden program oluşturma/atama ve mobilde atanmış programı okuma.

Bu görev **yalnız Uğur'un web/Auth ve ilgili backend alanıdır**. Mevcut
backend/web kaydı, doğrulama ve W2 oturumu korunur. Flutter kaynakları
değiştirilmez; mobil entegrasyon Mert'in alanıdır. Backend değişikliklerinin
mobil etkisi belge ve API sözleşmesi üzerinden raporlanır.

## Onaylı paket: uzman başvurusu ve güvenli Admin onayı

### B1 — hesap ve başvuru

- Bu ilk dilimde hesap başına tek rol. Mevcut danışan hesabı uzman hesabına
  otomatik çevrilmez; aynı e-postayla ikinci hesap oluşturulmaz.
- Mevcut `POST /auth/register` yalnız danışan olmaya devam eder.
- **Yeni öneri:** `POST /api/v1/dietitians/apply`, oturumsuz JSON:
  `{ email, password, displayName, licenseInfo }`. Dördü zorunlu string;
  `licenseInfo`, uzmanın Admin'e sunduğu mesleki kayıt/belge açıklamasıdır.
  Bu dilimde dosya yükleme veya otomatik meslek doğrulama yoktur.
- Parola mevcut 8–128 Unicode politikasıyla aynen işlenir. Ad 1–120,
  lisans açıklaması 1–2000 Unicode kod noktası; dış boşluklar kırpılır.
- User (`dietitian`, e-postası doğrulanmamış) ve DietitianProfile
  (`isVerified: false`, `licenseInfo: string`) tek transaction'da oluşur.
  Yanıt mevcut kayıt biçiminde `201 { id }` (User UUID); mükerrer `409`,
  doğrulama `422`, biçim/ek alan `400`. İstek gövdesi en fazla 16 KiB.
- Mevcut e-posta doğrulama, login ve W2 kullanılır. Başvuru/giriş yalnız
  hesap özeti erişimidir; doğrulanmamış uzman danışan verisi okuyamaz.
- `CurrentUserResponse` beş alanı korunur; diyetisyen adı DietitianProfile'dan
  okunur. Profil yoksa mevcut `null` davranışı korunur.
- Başvuru takibi için **yeni öneri:** `GET /api/v1/dietitians/me`, yalnız
  oturum sahibi diyetisyen: `{ id, displayName, isVerified }`.
  Lisans açıklaması halka açık arama sonucuna veya mevcut auth/me'ye eklenmez.
- Login ile aynı yapılandırılabilir IP limit altyapısı kullanılır; başvuru
  başlangıcı dakikada 5/IP. E-posta tesliminin bellek kuyruğu sınırı korunur.

### B2 — Admin MFA ve ilk kurulum

- Mevcut `/auth/login` ve `/auth/web-session` Admin'e kapalı kalır.
- Admin hesabı genel kayıt endpointinden açılamaz. İlk Admin ve TOTP kurulumu
  yalnız sunucuda çalıştırılan yerel yönetim komutuyla hazırlanır; başlangıç
  parolası/kurtarma bilgileri Git, seed, log veya varsayılan ayarda bulunmaz.
- MFA yöntemi: standart TOTP, 6 hane, 30 saniye; saat penceresi ±1 adım.
  Aynı doğrulama adımı tekrar kullanılamaz. Standart kütüphane kullanılır;
  yeni kriptografik algoritma yazılmaz. TOTP sırrı Data Protection ile
  korunur; 10 adet tek kullanımlık kurtarma kodunun yalnız hash'i saklanır.
- **Yeni öneri:** `POST /api/v1/auth/admin-web-session`, JSON
  `{ email, password, mfaCode }`; `mfaCode` TOTP veya kurtarma kodudur.
  Yanıt mevcut beş alanlı `CurrentUserResponse`; cookie/CSRF/Origin,
  süre ve sunucuda iptal W2 ile aynıdır. Ayrı MFA'sız Admin oturumu yoktur.
- Eksik/yanlış parola, MFA veya uygun olmayan hesap aynı `401`;
  biçim `400`, gövde 4096 byte, login ile ortak IP sayacı.
- Mevcut CSRF, auth/me ve web logout Admin'i yalnız yeni MFA ile açılmış
  cookie oturumuyla kabul eder; bearer Admin yasağı korunur. MFA kanıtı
  sunucu oturumunda tutulur; istemcinin rol veya isVerified girdisine güvenilmez.
- User'a önerilen yalnız sunucu alanları: nullable `totpSecretProtected`
  (string), nullable `lastUsedTotpStep` (64 bit integer),
  `mfaRecoveryCodeHashes` (başlangıçta boş string listesi; PostgreSQL text[]).
  AuthSession'a `isMfaVerified: boolean` (varsayılan false) eklenir;
  client/dietitian oturumları false kalır. Alanlar hiçbir User/hesap API
  yanıtına açılmaz. TOTP adımı ve recovery tüketimi User satır kilidiyle
  oturum oluşturma transaction'ına dahil edilir; MFA tüketimi hata halinde
  geri alınır. Uygulama öncesi `04/05/06/11`e birlikte işlenir.
- MFA kayıp/yeniden kurulum bu dilimde yerel yönetim komutudur; public
  e-posta veya şifre sıfırlama ile MFA atlanmaz. Gerçek yayın hazırlığı ayrıdır.

### B3 — inceleme ve karar

- **Yeni öneri:** `GET /api/v1/admin/dietitians?isVerified=false`;
  mevcut pagination zarfı `{ items, totalCount }`. Yalnız MFA'lı Admin.
  Item: `{ id, displayName, licenseInfo, isVerified }`; sağlık verisi yoktur.
- **Yeni öneri:** `POST /api/v1/admin/dietitians/{dietitianId}/verify`,
  gövdesiz; `200 { id, displayName, isVerified: true }`. Zaten doğrulanmış
  profilde aynı yanıt; bilinmeyen profilde `404`. E-postası doğrulanmamış
  hesap `409`. Admin/User/uzman satırı ve yetki güncel DB'den kontrol edilir.
- Public `GET /dietitians` yalnız doğrulanmış ve e-postası doğrulanmış
  uzmanları mevcut `id`/`displayName` alanlarıyla listeler; `licenseInfo`
  veya başvuru özel bilgisi paylaşılmaz.
- Ret, yeniden başvuru ve doğrulama geri alma ayrı dilimdir; `false` hem
  bekleyen hem reddedilen anlamında kullanılmaz. Bu pakette ret düğmesi yoktur.
- Onay audit'i için mevcut `AuditEvent` ad ve alanları korunur: `id`,
  `actorUserId`, `action`, `resourceType`, `resourceId`, `createdAt`,
  nullable `metadata`. Bu dilimde `action: dietitian_verified`,
  `resourceType: DietitianProfile`, `resourceId: dietitianId`, `metadata: null`.
  Mesleki açıklama/parola/token/sağlık değeri yazılmaz. Onay ve olay aynı
  transaction'da kaydedilir; zaten doğrulanmış profil ikinci olay oluşturmaz.
- Web: ayrı uzman başvuru formu, başvuru durumu; ayrı MFA'lı Admin giriş ve
  başvuru listesi/onay ekranı. Gerçek uzman paneline geçiş yalnız DB'de
  doğrulanmış uzman yetkisiyle yapılır.

## Sonraki iki paket; bu öneriyle henüz kesinleştirilmiyor

1. **İlişki/paylaşım:** mevcut `DietitianClientRelationship` yolları,
   arama/davet kodunun biçimi/ömrü, kategori kodları ve varsayılan kapalı
   izinler; karşılıklı onay ve tek aktif ilişki için transaction/DB indeksi.
2. **Program/mobil:** mevcut `NutritionPlan` yolları; items gün/miktar,
   alternatif/sürüm ve geçiş; web atama ve mobil salt okunur görüntüleme.
   Mobil tokenın güvenli saklanması/refresh/iptal ayrıca kararlaştırılır.

B1–B3 onayı bu iki paketin ayrıntılarını onaylamaz. Sonraki paketler kendi
somut HTTP/veri önerileri ve iki tarafın onayı olmadan uygulanmaz.

## Kabul ve sahiplik

**Uygulama doğrulaması — 29.10.2026:** Backend `dotnet build ... --no-restore`
0 uyarı/hata; `dotnet test ... --no-restore` geçici PostgreSQL/Mailpit ile
231 geçti, 0 atlandı. Yerel Admin kurulum/yenileme, MFA tekrar kullanımı,
eşzamanlı recovery tüketimi, başvuru/onay rollback ve audit doğrulandı.
Web typecheck/lint/build ve 105 test başarılı. Başvuru ve Admin giriş ekranı
tarayıcıda görsel olarak kontrol edildi; gerçek tarayıcı oturumuyla uçtan uca
onay testi yapıldığı iddia edilmez. Flutter kaynaklarında fark yoktur.

- Kullanıcı B1–B3 için Uğur–Mert ortak onayını 29.10.2026 tarihinde teyit etti.
- Lider: Uğur; backend Auth/uzman/Admin ve web. Mobil kaynaklarına yazılmaz;
  Mert için entegrasyon notu belgelenir. Aynı fiziksel checkout'a eşzamanlı yazılmaz.
- `04/05/06/11/12` ile backend/web etkileri aynı uygulama değişikliğinde ele alınır.
- Test: atomik/mükerrer başvuru, doğrulama öncesi login reddi; MFA'sız Admin
  reddi, TOTP tekrar/recovery tüketimi; CSRF/Origin; yetkisiz onay/arama,
  e-posta doğrulanmamış uzman ve audit rollback; web istek/hata/iptal durumları.
- **Ortak onay kaydı:** Kullanıcının açık teyidi: “Ortak onay var devam et.”
  Bu teyit yalnız sunulan B1–B3 paketine uygulanır; diğer açık şemalara yayılmaz.
