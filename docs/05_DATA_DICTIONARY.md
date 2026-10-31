# 05 — Ortak veri sözlüğü (domain schema)

## 29.10.2026 N1–N3 onaylı program verisi

`16` N1–N3 ortak onayı kullanıcı tarafından teyit edildi. Programın aşağıdaki
şeması ve kuralları eski miktar/gün/alternatif/sürüm açık notlarının yerini alır.

- NutritionPlan id/clientId/dietitianId?/title/status/startDate/endDate?/
  dailyCaloriesTargetKcal?/dailyWaterTargetMl?/createdAt alanlarına ek
  `versionNumber: integer` tutar; ilk değer 1. Yanıt ayrıca güncel
  `versionId: uuid` taşır; sürüm satırından türetilir, ikinci FK oluşturulmaz.
- Güncel items `jsonb` dizisidir; 1–100 kalem. Her kalemde sunucunun ürettiği
  id/nutritionPlanId UUID'leri, dayOfWeek: integer? (ISO 1–7; null her gün),
  mealType: mevcut MealType, description: string (kırpılmış 1–2000 Unicode
  kod noktası), recommendedQuantity: string? (kırpılmış 1–200; boş null),
  sortOrder: integer (>=0, aynı sürümde tek), recipeId: uuid? (ilk dilimde
  yalnız null), alternativeGroupId: uuid? bulunur. Grup yerel UUID'dir;
  en az iki üye aynı gün ve mealType'a ait olur; ayrı tablo/FK değildir.
- title kırpılmış 1–120; PostgreSQL text. Tarihler date ve endDate >= startDate.
  Hedefler nullable pozitif decimal/numeric, kcal ve mL; otomatik hesap veya
  yuvarlama yoktur. Status draft/active/archived; aktiflik tarihten bağımsızdır.
- Yeni NutritionPlanVersion: id: uuid, nutritionPlanId: uuid FK,
  versionNumber: integer (>0), recordedByUserId: uuid FK User, createdAt:
  instant, snapshot: jsonb object. Snapshot yalnız title/tarihler/hedefler/items
  içerir; sunucu modeli SnapshotJson özelliğini snapshot sütununa eşler.
  recordedByUserId yanıtta açılmaz. (nutritionPlanId,versionNumber) unique.
- Program→ClientProfile/nullable DietitianProfile ve sürüm→User/Program FK'leri
  NO ACTION. Programda status=active için clientId kısmi unique indeksi vardır.
  Sürüm içerikleri uygulamada sonradan değiştirilemez; her geçerli PATCH yeni
  satır ve yeni item UUID'leri oluşturur. Önceki JSONB içeriği değişmez.
- Program güncel içerik ve sürüm ekleme aynı transaction'da; User →
  ClientProfile → program kilit sırasıyla kaydedilir. İzin geri çekme ve
  ilişki bitişi aynı ClientProfile kilidini kullanır. Yeni yazma commit'inden
  önce aktif ilişki/izin yeniden kontrol edilir. Zamanlar UTC mikro saniyedir.
- Aktif ilişki bitince yalnız o diyetisyenin bu danışana atanmış active
  programı aynı transaction'da archived olur; kişisel programa dokunulmaz,
  sahiplik/geçmiş korunur. Danışan kendi tüm program/geçmişini okumaya devam
  eder. Genel sahipler arası replace akışı bu dilimin dışındadır.

HTTP DTO, null/atlanmış alan ve erişim ayrıntıları `06`daki N1–N3 bölümündedir.

## 29.10.2026 R1–R3 onaylı ilişki/paylaşım verisi

`15` R1–R3 ortak onayı kullanıcı tarafından teyit edildi. Mevcut
DietitianClientRelationship alan/tipleri korunur; pending/active/rejected/ended
değerleri aynıdır. ClientProfile ve DietitianProfile FK'leri NO ACTION.
PostgreSQL'de clientId için status=active kısmi unique; aynı clientId/dietitianId
çifti için status=pending kısmi unique indeks uygulanır. Geçmiş silinmez.

DietitianProfile'a nullable invitationCodeHash (SHA-256/64 hex) ve
invitationCodeExpiresAt (instant) eklenir. İlk alan unique indekslidir;
ham 80 bit/16 Base32 kod saklanmaz. Yeni üretim eskisini iptal eder; kod
pending ilişki ekleme transaction'ında tek kullanımlık tüketilir. Süre 24 saat.

DataSharingPermission mevcut id/relationshipId/category/isGranted/
consentRecordId/createdAt/updatedAt alanlarıyla uygulanır. Tek kategori
`nutrition_plans`, consentRecordId daima null (DB check); diğer kategoriler
ve rıza tür/politikası bu dilimin dışındadır. Aynı ilişki/kategori unique,
relationshipId FK/NO ACTION. İzin yoksa kapalıdır; ilişki kabulü izin üretmez.
Yalnız ilişkinin danışanı aktif ilişkide oluşturur/günceller. Geçmiş ilişki
ve mevcut audit/rıza kayıtları silinmez. Tam izin değişiklik audit'i ve sağlık
saklama/politika kapıları `11`e göre ayrıca tamamlanır.

Mutasyonlar User ardından ClientProfile satır kilidini kullanır; aktif ilişki
ve izin denetimleri transaction içinde güncel kalır. Geri çekme/sonlandırma
yeni program erişimini kapatır. Danışanın kendi program erişimi ilişkisizdir.
Bu dilimde dönen yeni ilişki/izin zamanları PostgreSQL mikro saniye hassasiyetiyle
aynı UTC anına normalize edilir; ilk ve tekrar yanıtları aynı kalır. Bu kural
decimal sağlık ölçümlerine hassasiyet/yuvarlama seçimi getirmez.

## 29.10.2026 B1–B3 onaylı veri güncellemesi

Kullanıcı `14` B1–B3 için ortak onayı teyit etti. Aşağıdaki alanlar, eski
başvuru/MFA açık notlarının bu dilimdeki yerini alır; diğer şemalar açık kalır.

| Model / alan | Onaylı tip ve kalıcı karşılık |
|---|---|
| `DietitianProfile` | Mevcut id/userId/displayName/isVerified; `licenseInfo: string` zorunlu. displayName kırpılmış 1–120, licenseInfo 1–2000 Unicode kod noktası; PostgreSQL text, DB check. userId unique/FK, NO ACTION; isVerified başlangıç false |
| `User.totpSecretProtected` | string?, text; User UUID'sine bağlı Data Protection purpose ile şifreli Base32 TOTP anahtarı |
| `User.lastUsedTotpStep` | 64 bit integer?, bigint; başarılı TOTP adımı monoton ilerler |
| `User.mfaRecoveryCodeHashes` | list<string>, text[]; boş başlangıç; kurulumda 10 kodun SHA-256 hash'i; tüketilen çıkarılır |
| `AuthSession.isMfaVerified` | boolean, is_mfa_verified; varsayılan false. Admin cookie'si için true gerekir; normal kullanıcı oturumunda false |
| `AuditEvent` | Mevcut alanlar; metadata fiziksel JSONB, bu onay olayında null. action dietitian_verified, resourceType DietitianProfile, resourceId uzman profil UUID'si; actorUserId MFA'lı Admin |

Başvuru User(role=dietitian, isEmailVerified=false) ve profili tek transaction'da
oluşturur; ClientProfile oluşturmaz. Bu dilimde tek rol vardır; mevcut danışan
hesabı değiştirilmez. auth/me'de diyetisyen adı kendi DietitianProfile'ından,
danışan adı ClientProfile'dan gelir; profil yoksa null kalır. Admin beş alanlı
yanıtı yalnız geçerli MFA cookie oturumuyla alabilir; MFA alanları seçilmez.

TOTP/kurtarma tüketimi ve oturum ekleme User satır kilidi + tek transaction;
oturum başarısızsa tüketim geri alınır. Admin onayı, hedef User/profil kilidi
ve AuditEvent aynı transaction'dadır; tekrar onay ikinci audit olayı oluşturmaz.
Admin'in sağlık verisi erişimi açılmaz. Kayıt/JWT mobil gövdeleri değişmez.

> Kanonik model adları: `04_NAMING_CONVENTIONS.md`. Bu belge alan/tip/ilişki otoritesidir. **Taslak sözleşme**; açık parçalar için migration hazırlamadan önce ekip onayı al. Karar temeli: `12_TEAM_PLAN_AND_DECISIONS.md` içindeki 22 onaylı karar. Kayıt, e-posta doğrulama, JWT girişi ve kendi hesap özetinin 27.10.2026 tarihli onaylı ayrıntıları `04/06/11/12` ile birlikte güncellenmiştir; diğer açık şemalar kesinleşmiş sayılmaz.

Mevcut geçerli alanlar korunur; kişisel program için `NutritionPlan.dietitianId` nullable yapılır. Yeni asgari alanlar aşağıda tanımlanır. Henüz kesinleşmemiş alt kayıt adları, enum değerleri ve saklama tercihleri **AÇIK** veya **ÖNERİ** olarak ayrılır; bunlar uygulama için onaylanmış kabul edilmez. Bir domain ilişkisi tanımlanması her ilişki için ayrı tablo/model oluşturulmasını gerektirmez.

## Genel kurallar

- Tüm ilişkili sağlık kayıtları `clientId` ile kendi verisine bağlanır.
- Silme ve veri saklama süresi KVKK tasarımına göre kararlaştırılır; sağlık verisi için varsayılan herkes görür yaklaşımı **yok**.
- Sayısal ölçümler `decimal` karşılığı hassas tip; kesin olmayan kalori ve makro alanları tahmin bayrağı/analiz kaynağıyla ilişkilidir.
- Ölçümlerde `null` bilinmiyor demektir; `0` ölçülmüş gerçek sıfırdır. Eksik laboratuvar aralığı için sıfır yazılmaz. Opsiyonel ilişkilerde null, bağlantının bulunmadığını ifade edebilir; kişisel programın boş `dietitianId`si gibi istisnaların anlamı ilgili modelde belirtilir.
- Tablo adı `snake_case` çoğul: `meal_logs`, `lab_reports` vb.; backend property PascalCase; JSON camelCase.

### Tip, nullability ve birim gösterimi

Tablolarda `alan: tip?` nullable, `alan: tip` zorunludur. `?` JSON anahtarının parçası değildir. Bir alanın domain'de zorunlu olması istemcinin onu göndermesini gerektirmez: kimlik, sahiplik, hesaplanan bayrak ve audit alanları sunucu tarafından atanabilir. PATCH'te alanın gönderilmemesi ile açıkça `null` gönderilmesinin farkı `06`da tanımlanmalıdır.

| Tip | Anlam / eşleme |
|---|---|
| `uuid` | İç kayıt/FK kimliği; PostgreSQL `uuid`, JSON UUID string. `externalRecordId` dış sistemin string kimliğidir; UUID olması beklenmez |
| `instant` | UTC an; PostgreSQL `timestamptz`, JSON ofseti açık ISO 8601. `createdAt`, `updatedAt` dahil tüm `...At` alanları bu tiptedir |
| `date` | Saat dilimsiz takvim günü; PostgreSQL `date`, JSON `YYYY-MM-DD` |
| `decimal` | Kesin ondalık ölçüm; PostgreSQL `numeric`, JSON number. Hassasiyet, ölçek ve yuvarlama henüz seçilmemiştir; bilinmeyen değer sıfıra çevrilmez |
| `integer` | Tam sayı; sıralama/adet gibi anlamlar için. `dayOfWeek` gün numaralama standardı **AÇIK**tır |
| `string`, `boolean` | Metin ve true/false. Zorunlu ad/açıklama alanları boş veya yalnız boşluk olamaz; uzunluk sınırları ayrıca onaylanır |
| `object`, `list<T>` | Mantıksal nesne/koleksiyon; fiziksel tablo veya JSON/JSONB saklama seçimi değildir |
| `UserRole`, `MealType`, `RelationshipStatus`, `NutritionPlanStatus`, `FoodAnalysisStatus`, `LabFlag`, `RecordSource` | `04`teki mevcut string enumlar ve değerleri aynen korunur; yeni enum değeri eklenmez |
| `AÇIK` | Alanın adı korunur, tipi veya biçimi henüz kesinleşmemiştir; kod/DTO/migration için varsayılan tip seçilmez |

`heightCm`, `weightKg`, `waistCm` ve bilinen porsiyon/servis gramı pozitiftir; enerji, makro, mesafe ve süre negatif olamaz. `amountMl` pozitiftir; `bodyFatPercent` biliniyorsa 0–100 aralığındadır. Laboratuvar değerlerine genel bir pozitiflik kuralı uygulanmaz; analit/birim kuralları ayrıca doğrulanır. Sayılar sonlu olmalıdır; keyfî klinik alt/üst sınır uydurulmaz.

## Kullanıcı ve ilişki

| Entity | Temel alanlar | Not / kısıt |
|---|---|---|
| `User` | `id: uuid`, `email: string`, `passwordHash: string`, `role: UserRole`, `isEmailVerified: boolean`, `emailVerificationTokenHash: string?`, `emailVerificationExpiresAt: instant?`, `emailVerificationLastSentAt: instant?`, `createdAt: instant`, `updatedAt: instant` | E-posta harf duyarsız unique; yeni kayıt yalnız `client`, doğrulama başlangıcı `false`. Parola hash'i ve token metadata'sı API yanıtlarına çıkmaz. `isEmailVerified` yalnız onaylı kendi hesap DTO'sunda açılır; entity JSON'u gizli kalır. W2 web oturumu aşağıda onaylıdır; şifre sıfırlama, mobil oturum ve Admin MFA kayıtları **AÇIK**tır |
| `ClientProfile` | `id: uuid`, `userId: uuid`, `displayName: string`, `birthDate: date?`, `heightCm: decimal?` | `userId` → User ve unique; boy cm. Yaş/kişisel veri hassas ele alınır; doğum tarihi şimdilik isteğe bağlıdır |
| `DietitianProfile` | `id: uuid`, `userId: uuid`, `displayName: string`, `licenseInfo: AÇIK?`, `isVerified: boolean` | `userId` → User ve unique; uzmanı Admin doğrular. Mobil/web başvuru, belge biçimi ve doğrulama geçmişinin yapısı **AÇIK**tır; `isVerified` istemcinin kendi değiştireceği bir alan değildir |
| `DietitianClientRelationship` | `id: uuid`, `clientId: uuid`, `dietitianId: uuid`, `status: RelationshipStatus`, `requestedAt: instant`, `respondedAt: instant?`, `endedAt: instant?` | `clientId` → ClientProfile, `dietitianId` → DietitianProfile; danışan başına en fazla bir aktif ilişki. Karşılıklı onay gerekir; arama/davet kodu onayın yerine geçmez |

### Onaylı kayıt ve e-posta doğrulama bütünlüğü

- Kayıtta User ile ClientProfile farklı UUID'lerle tek transaction içinde oluşturulur; `ClientProfile.userId` güvenilir User kimliğinden atanır ve unique zorunlu FK'dir. `displayName` zorunlu/boş olamaz; `birthDate` ve `heightCm` kayıt sırasında alınmaz, null kalır. Çoklu rol/profil ve diğer profil uçları bu kararla kapanmaz.
- E-posta dış boşlukları kırpılır, Identity `UpperInvariantLookupNormalizer` kullanılır; PostgreSQL harf duyarsız, aksanı ayırt eden ICU collation ve unique indeks ile yarışan mükerrer kayıtları da reddeder. Parola kırpılmaz/normalize edilmez; Identity `PasswordHasher<User>` kullanılır. İlk sürüm politika ayrıntıları `06/11`dedir.
- Token, kriptografik rastgele 32 byte'tan üretilen 43 karakter Base64URL değeridir (256 bit). Yalnız SHA-256 hash'i saklanır: `emailVerificationTokenHash`, PostgreSQL `varchar(64)`, 64 büyük harfli hexadecimal karakter ve null olmayan değerler için unique indeks. Ham token DB'ye, API yanıtına veya log/audit'e yazılmaz.
- Hesap başına tek güncel token vardır. `emailVerificationExpiresAt` ve `emailVerificationLastSentAt` nullable UTC `timestamptz` alanlarıdır. İlk üretim öncesi üç metadata alanı null'dır. Hash doluysa süre sonu ve son gönderim zamanı dolu olmak zorundadır; hash yoksa süre sonu da null'dır. Son gönderim zamanı, SMTP'den önce atomik ayrılan **gönderim denemesi** zamanıdır; teslim kanıtı değildir.
- Geçerlilik token üretiminden itibaren **30 dakika**dır; `now < emailVerificationExpiresAt` gerekir. Doğrulama, hash eşleşmesi + doğrulanmamış hesap + süre kontrolü ile tek atomik DB işleminde `isEmailVerified = true` yapar, hash ve süre sonunu temizler, `updatedAt`yi günceller. Son gönderim zamanı kalabilir. Eşzamanlı iki doğrulama birden başarılı olamaz.
- Yeniden gönderim yeni token/hash üretir ve önceki tokenı geçersiz kılar. Aynı hesaba gönderim denemeleri arasında varsayılan 60 saniye gerekir; bu sınır DB'de atomik uygulanır ve yapılandırılabilir. Doğrulanmış/bulunmayan hesap için token üretilmez. SMTP hatası hesabı silmez veya doğrulamaz; kullanıcı yeniden gönderim isteyebilir.
- Token için ayrı tablo veya düz metin outbox oluşturulmaz. Mevcut arka plan kuyruğu yalnız e-posta adreslerini bellekte tutar; yeniden başlatmada kalıcı teslim garantisi yoktur. SMTP/TLS ve hata davranışı `06/11`, yerel Mailpit kurulumu `backend/README.md` içindedir.

### Giriş ve JWT — kalıcı model sınırı

- Giriş mevcut User e-postası/Identity hash'i/doğrulama bayrağı/rolünü kullanır; User/ClientProfile ilişkisi ve alanları değişmez. `isEmailVerified = false` veya `role = admin` için access token üretilmez. Login yeni profil oluşturmaz veya kullanıcı kimliğini istemciden almaz.
- `LoginUserResponse.accessToken: string`, `tokenType: string` (sabit `Bearer`), `expiresAt: instant`, `refreshToken: string`, `refreshTokenExpiresAt: instant` yalnız HTTP yanıt alanlarıdır; User sütunları değildir. JWT DB'ye saklanmaz. 31.10.2026 refresh görevi aşağıdaki ayrı hash geçmişini ekler; 15 dakikalık JWT'nin şekli/süresi değişmez.

### Mobil refresh hash geçmişi — 31.10.2026

Kullanıcının refresh/iptal göreviyle eklenen `RefreshToken` (`refresh_tokens`)
yalnız sunucu içindir; entity JSON'u API yanıtı değildir.

| Alan | Tip | Kural |
|---|---|---|
| `id` | uuid | Sunucu üretir; token değildir |
| `userId` | uuid | User FK, NoAction; otomatik kullanıcı/profil silinmez |
| `role` | UserRole | Giriş anındaki `client`/`dietitian`; Admin DB check'iyle de dışlanır |
| `familyId` | uuid | Her girişte yeni aile; rotasyonda aynı kalır |
| `tokenHash` | string(64) | 256 bit ham refresh tokenın SHA-256 büyük harf hex hash'i; unique, JSON'a çıkmaz |
| `createdAt` | instant | Bu tokenın UTC üretimi |
| `expiresAt` | instant | Ailenin mutlak UTC bitişi; varsayılan giriş+30 gün, rotasyon uzatmaz |
| `consumedAt` | instant? | Başarılı rotasyonda atomik tüketim |
| `revokedAt` | instant? | Logout/tekrar kullanım/geçersiz hesapta aile iptali |

Bir ailede tüketilmemiş/iptal edilmemiş en fazla bir token, kısmi unique indeksle
korunur. User satır kilidi login/refresh/logout yarışlarını serileştirir.
Tüketilmiş hash'ler aile süresi dolana kadar korunur; erken silme replay tespitini
bozar. On dakikada bir yalnız mutlak süresi bitmiş kayıtlar temizlenir.
Ham token/parola/access JWT veya web cookie bu tabloda tutulmaz.
`Auth:RefreshTokens:LifetimeDays` 1–365 (varsayılan 30); HTTP IP limiti
`RequestsPerMinute` >0 (varsayılan 30), refresh ve logout için ayrı sayaçtır.
Gelecekteki parola/güvenlik yazmaları aynı User kilidi altında refresh ailelerini
de iptal etmelidir; otomatik access JWT iptali bu modelden türetilmez.
- JWT `sub`, User UUID'sidir. Sonraki iş modülleri `clientId`yi güvenilir User → ClientProfile ilişkisinden çözer; token içindeki rol tek başına uzman doğrulaması, aktif ilişki veya veri paylaşım izni sağlamaz.
- Identity `SuccessRehashNeeded` sonucunda yalnız başarılı ve girişe uygun hesabın `passwordHash`/`updatedAt` alanları güncellenebilir. Güncelleme önceki hash/doğrulama/rol koşuluyla atomiktir; yarışta başka bir parola değişikliği ezilmez ve token verilmez. Yanlış parola, doğrulanmamış hesap ve Admin için hash değiştirilmez.

### Kendi hesap özeti — mevcut veriden salt okunur DTO

`CurrentUserResponse` ayrı bir kalıcı model değildir; migration veya User/ClientProfile
alan değişikliği gerektirmez. `GET /api/v1/auth/me` yalnız aşağıdaki alanları seçer:

| Alan | Tip / nullability | Kaynak |
|---|---|---|
| `id` | `uuid`, zorunlu | Doğrulanmış JWT veya W2 cookie `sub` ile bulunan `User.id`; ClientProfile UUID'si değildir |
| `displayName` | `string?`, anahtar daima bulunur | O User'ın opsiyonel ClientProfile ilişkisindeki mevcut ad; profil yoksa null. Zorunlu profil adı alanının kendisi nullable yapılmaz |
| `email` | `string`, zorunlu | User'ın DB'deki güncel e-postası |
| `role` | `UserRole`, zorunlu | User'ın DB'deki güncel kanonik rolü |
| `isEmailVerified` | `boolean`, zorunlu | User'ın sunucu tarafından tutulan doğrulama durumu |

Hesap ID'si, tek ve geçerli `sub` claim'inden çözülür; istemci girdisi veya profil ID'si
ile başka hesap seçilemez. User ve varsa kendi ClientProfile'ı tek salt okunur
projeksiyonla sorgulanır. Hash/token/sağlık/profilin diğer alanları seçilmez; entity
serileştirilmez. Profilsiz `client`/`dietitian` için aynı DTO ve null ad kullanılır;
DietitianProfile veya yapay ad/varsayılan profil üretilmez.

Bu işlemde hesap hâlâ bulunmalı, e-postası doğrulanmış olmalı ve güncel rolü tokenın
izinli `client`/`dietitian` rolüyle eşleşmelidir; aksi durumda `06`daki ortak `401`
uygulanır. Admin MFA engeli korunur. Bu kontrol yalnız kendi hesap okumasının
güvencesidir; diğer endpointler için genel anlık oturum iptali anlamına gelmez.

### Onaylı web oturumu — AuthSession (27.10.2026)

W2-C1–C7 ortak onayı kullanıcı tarafından teyit edilmiştir. Bu sunucu kaydı
`auth_sessions` tablosunda tutulur; HTTP yanıtı değildir.

| Alan | Tip / sütun | Bütünlük |
|---|---|---|
| `id` | `uuid`, `id` | Sunucunun ürettiği PK; çıplak UUID kimlik doğrulama sırrı değildir |
| `userId` | `uuid`, `user_id` | Zorunlu FK → User.id; unique değildir, birden çok cihaz desteklenir; silme NO ACTION |
| `createdAt` | `instant`, `created_at` | İlk giriş UTC anı; değişmez |
| `lastSeenAt` | `instant`, `last_seen_at` | İlk değer createdAt; başarılı yetkili istekte geriye gitmeden ilerler |
| `idleExpiresAt` | `instant`, `idle_expires_at` | Başlangıç createdAt + 30 dakika; başarılı yetkili istekte en fazla now + 30 dakika |
| `absoluteExpiresAt` | `instant`, `absolute_expires_at` | Değişmez createdAt + 8 saat; idle bu sınırı aşmaz |
| `revokedAt` | `instant?`, `revoked_at` | Başlangıç null; iptal sonrası yeniden null olamaz; createdAt'ten önce olamaz |

DB kısıtı: `createdAt <= lastSeenAt < idleExpiresAt <= absoluteExpiresAt`.
`user_id`, `idle_expires_at`, `revoked_at` indekslenir. Cookie bileti/ham cookie,
JWT, parola, refresh token veya Data Protection anahtarı bu tabloda saklanmaz;
User'a yeni oturum/refresh alanı eklenmez. Etkin bitiş idle/absolute sürelerinin
erken olanıdır; eşitlik anında geçersizdir. İptal veya süre bitişinden en geç
24 saat sonra yalnız oturum satırı temizlenir. Normal çalışmada 10 dakikalık
temizlik 23 saat 50 dakika eşiğini kullanır; DB kesintisindeki gecikme izlenir.
Sağlık/audit saklama süresi buradan türetilmez.

Her cookie kimlik kontrolü oturum ve güncel doğrulanmış User/rolünü DB'den okur.
Süre uzatma ve iptal koşullu atomik işlemlerdir; eski istek süreyi geri alamaz
ve iptali silemez. Login User satırını kilitleyip doğrulanan hash/rol/doğrulama
durumunu yeniden kontrol eder. Gelecekteki parola/rol/doğrulama değişimleri
aynı User kilidi ve transaction içinde bütün web oturumlarını iptal etmelidir;
mevcut stateless JWT'lerin iptali bu kaydın kapsamına girmez.

## Beslenme ve günlük takip

| Entity | Temel alanlar | Not / kısıt |
|---|---|---|
| `FoodItem` | `id: uuid`, `name: string`, `servingBasisGrams: decimal`, `caloriesKcal: decimal`, `proteinGrams: decimal`, `carbsGrams: decimal`, `fatGrams: decimal`, `dataSource: string` | Enerji kcal, makrolar gram; hepsi aynı `servingBasisGrams` temeline aittir. Hibrit katalog kaynağı/kanıtı korunur; sağlayıcı ve lisans seçimi **AÇIK**tır |
| `MealLog` | `id: uuid`, `clientId: uuid`, `mealType: MealType`, `consumedAt: instant`, `note: string?`, `source: RecordSource`, `foodAnalysisId: uuid?`, `createdAt: instant` | Bir öğünün kalemleri `MealLogItem`; plan dışı gerçek tüketim de kaydedilebilir |
| `MealLogItem` | `id: uuid`, `mealLogId: uuid`, `foodItemId: uuid?`, `recipeId: uuid?`, `displayName: string`, `quantityGrams: decimal?`, `caloriesKcal: decimal?`, `proteinGrams: decimal?`, `carbsGrams: decimal?`, `fatGrams: decimal?`, `isEstimated: boolean` | `recipeId` → Recipe yeni opsiyonel bağlantıdır. Değerler tüketilen kalemin toplamıdır; katalogdaki gram temeliyle karıştırılmaz. Katalog dışı giriş mümkündür; null porsiyon/besin değeri bilinmiyor demektir |
| `FoodAnalysis` | `id: uuid`, `clientId: uuid`, `status: FoodAnalysisStatus`, `createdAt: instant`, `completedAt: instant?`, `modelVersion: string?`, `suggestions: list<object>?`, `errorCode: string?` | Bir tahmin **otomatik kayıt değildir**. Öneri tipi aşağıda açıklanır; özel medya saklama politikası gerekir |
| `WaterLog` | `id: uuid`, `clientId: uuid`, `amountMl: decimal`, `consumedAt: instant`, `source: RecordSource` | Miktar mL; günlük toplam hesaplanır |
| `NutritionPlan` | `id: uuid`, `clientId: uuid`, `dietitianId: uuid?`, `title: string`, `status: NutritionPlanStatus`, `startDate: date`, `endDate: date?`, `dailyCaloriesTargetKcal: decimal?`, `dailyWaterTargetMl: decimal?`, `createdAt: instant`, `versionNumber: integer` | dietitianId null ise kişisel; toplamda tek active. Güncel sürümün versionId'si yanıta eklenir; items JSONB. N1–N3 sınırları yukarıdadır |
| `NutritionPlanItem` | `id: uuid`, `nutritionPlanId: uuid`, `dayOfWeek: integer?`, `mealType: MealType`, `description: string`, `recommendedQuantity: string?`, `sortOrder: integer`, `recipeId: uuid?`, `alternativeGroupId: uuid?` | Her satır tavsiyedir. ISO gün 1–7/null her gün, miktar serbest öneri metni; recipeId ilk dilimde yalnız null. Aynı gün/öğün bağlamında en az iki alternatif |
| `NutritionPlanVersion` | `id: uuid`, `nutritionPlanId: uuid`, `versionNumber: integer`, `recordedByUserId: uuid`, `createdAt: instant`, `snapshot: object` | Değişmeyen JSONB içerik; actor kimliği yalnız sunucudadır. Program/number unique; sürüm metadata ve snapshot DTO'ları `06`da |
| `BodyMeasurement` | `id: uuid`, `clientId: uuid`, `measuredAt: instant`, `weightKg: decimal?`, `waistCm: decimal?`, `bodyFatPercent: decimal?`, `source: RecordSource` | Kilo kg, bel cm, yağ oranı yüzde. En az bir ölçüm bulunur; istenmeyen ölçüm zorunlu yapılmaz; kaynak ve geçmiş korunur |
| `ActivityLog` | `id: uuid`, `clientId: uuid`, `activityType: string`, `startedAt: instant`, `durationMinutes: decimal?`, `distanceKm: decimal?`, `caloriesKcal: decimal?`, `source: RecordSource`, `externalRecordId: string?`, `wearableConnectionId: uuid?` | Süre dakika, mesafe km, enerji kcal. `wearableConnectionId` → WearableConnection yeni opsiyonel kaynak bağlantısıdır. Aktivite izleme, antrenman programı değildir |

### Kişisel program, hedefler ve sürüm ilişkileri

- `NutritionPlan.clientId` her iki program türünde de zorunludur ve programın danışanını belirler. Kişisel programda `dietitianId = null` olur; sahte diyetisyen kaydı/UUID'si oluşturulmaz. Kullanıcının diyetisyen ilişkisi bulunmaması program oluşturmayı engellemez.
- Diyetisyen programını yalnız sahibi olan yetkili diyetisyen düzenler; kişisel programı kendi danışanı düzenler. Diyetisyende aktif ilişki ve nutrition_plans izni gerekir. Aktif ilişki bitince o uzmanın active programı archived olur; dietitianId null yapılmaz ve eski uzmana erişim sağlamaz. Danışanın kendi geçmiş okuması sürer. Genel replace/geçiş akışı açıktır.
- `endDate` varsa `startDate`ten önce olamaz. Aktiflik `status = active` ile belirlenir; tarih aralığı tek aktif sınırını delmek için kullanılmaz. Aynı danışanın kişisel ve diyetisyen programları aynı anda aktif olamaz.
- Program hedefi ile gerçekleşen `MealLogItem`/`WaterLog` toplamları ayrı tutulur. Danışan gerçek tüketimini kaydederek programı veya diyetisyen hedefini değiştirmez. Kişisel kalori/makro/su önerileri düzenlenebilir; öneri hesaplama yöntemi ve programsız hedeflerin saklanacağı yer **AÇIK**tır. Kişisel program hedefleri mevcut nullable hedef alanlarını kullanabilir; makro hedeflerinin alan adları henüz kesinleşmemiştir.
- **Sürüm ilişkisi:** Bir `NutritionPlan`ın 1:N geçmiş sürümü bulunur; her sürüm o andaki başlık, tarih, hedef ve `NutritionPlanItem` içerik/alternatiflerini geri getirilebilir biçimde korur. Revizyon geçmiş sürümü değiştirmez. Her sürümün program bağlantısı, kararlı ayıracı, kaydeden `User` bağlantısı ve kayıt zamanı gerekir. Geçmiş sürümler ayrı aktif program sayılmaz; tüketim karşılaştırması doğru tarih/sürüme dayanmalıdır.
- **Öğün alternatifi ilişkisi:** Aynı programın aynı sürümü ve gün/öğün bağlamındaki `NutritionPlanItem` önerileri alternatif olabilir. Alternatifler birlikte zorunlu tüketim veya toplanacak ayrı öğünler gibi değerlendirilmez; başka danışanın/programın öğesi aynı gruba bağlanamaz. Kullanıcının bir alternatifi seçmesi programı düzenlemesi anlamına gelmez.
- N1–N3 ile ayrı NutritionPlanVersion tablosu ve değişmeyen JSONB snapshot onaylıdır. Öğeler ilgili snapshot içinde nutritionPlanId ve tarihsel item UUID'leriyle korunur; alternativeGroupId yereldir. Yalnız güncel içeriği yerinde değiştirip geçmiş kaydını atlamak onaylı değildir.

### Tarif, görev ve yorum ilişkileri

`04`te karşılığı bulunan üç yeni kavram için asgari alanlar aşağıdadır. Bunlar yeni endpoint veya enum listesi tanımlamaz.

| Kavram | Asgari alanlar | İlişki / bütünlük |
|---|---|---|
| `Recipe` | `id: uuid`, `userId: uuid`, `name: string`, `createdAt: instant` | `userId` → tarifi oluşturan User; bir kullanıcının N tarifi olabilir. Recipe 1:N bileşenden oluşur; FoodItem ile eşleşen bileşen ilgili besine bağlanır. Bileşen modeli/yapısı ve tarif görünürlüğü **AÇIK**tır |
| `ClientTask` | `id: uuid`, `clientId: uuid`, `dietitianId: uuid`, `description: string`, `status: string`, `createdAt: instant` | Görev bir danışana ve atayan diyetisyene bağlıdır; atama için aktif/yetkili ilişki gerekir. Durum değerleri ve kimin hangi geçişi yapacağı **AÇIK**tır; serbest rastgele durum değerleri kabul edilmez |
| `DataSharingPermission` | `id: uuid`, `relationshipId: uuid`, `category: string`, `isGranted: boolean`, `consentRecordId: uuid?`, `createdAt: instant`, `updatedAt: instant` | `relationshipId` → DietitianClientRelationship; danışan/diyetisyen bu ilişkiden türetilir, tekrar saklanmaz. Kategori listesi **AÇIK**tır. Aynı ilişki/kategori için tek güncel izin bulunur; değişiklikler audit/rıza geçmişini silmez |

- Tarif bileşenlerinin miktar/birim bilgisi ve pişmiş toplam/porsiyon temeli korunmadan hesaplanmış enerji/makro gösterilmez; kaynak ve belirsizlik görünür tutulur. Bilinen gram miktarı `decimal` ve pozitiftir; bilinmeyen miktar sıfır sayılmaz. Bileşenlerin gram/adet dönüşümü, katalog dışı bileşen yapısı ve tarifin daha sonra değişmesindeki sürümleme yöntemi **AÇIK**tır.
- `MealLogItem.recipeId` veya `NutritionPlanItem.recipeId` doluysa tarif mevcut ve ilgili kullanıcıya erişilebilir olmalıdır. Tarif/katalog değişikliği önceki tüketim değerlerini veya program geçmişini yeniden yazamaz; kayıttaki değerler tüketim anındaki veriyi korur. `foodItemId` ile `recipeId`nin birlikte kullanım kuralı **AÇIK**tır; aynı kalem iki kez hesaba katılmaz.
- Görevin son tarihi ve isteğe bağlı hatırlatma tercihi tutulmalıdır. **Alan önerileri:** `dueAt: instant?` ve `isReminderEnabled: boolean`; son tarihin yalnız gün mü kesin saat mi olduğu, zorunluluğu, varsayılan tercih ve hatırlatma zamanlaması **AÇIK**tır. Bunlar onaylanmadan son tarih için keyfî alan/tip veya görev enumu eklenmez. Görev geçmişi ilişki sona erince eski diyetisyene yeni erişim sağlamaz.
- **Yorum ilişkisi:** `MealLog` 1:N yorum, `User` 1:N yazdığı yorum; cevap aynı öğünün bir yorumuna bağlıdır. Yazar danışanın kendisi veya o öğüne erişmeye yetkili diyetisyen olmalıdır. Başka öğüne/başka danışana cevap bağlantısı ve döngü kurulamaz. Diyetisyenin yorum yetkisi güncel ilişki/paylaşım kontrollerinden bağımsız değildir; bu yapı sohbet özelliği değildir.
- **Yorum için asgari alan önerisi:** `id: uuid`, `mealLogId: uuid`, `authorUserId: uuid`, `text: string`, `createdAt: instant`, `parentCommentId: uuid?` (null ise kök yorum). Kanonik yorum model adı `04`te yoktur; ayrı yorum/cevap modelleri, cevap derinliği, düzenleme/silme ve moderasyon kuralları **AÇIK**tır. Bu öneri henüz onaylı payload değildir.
- İlk sürüm yorum/cevap bildirimleri ile görev hatırlatmaları ilgili kayıt ve alıcıyla ilişkilendirilmelidir; bildirimde sağlık içeriği gösterimi paylaşım iznini aşamaz. Bildirim modeli, saklama ve teslim kanalı açık olduğundan yeni notification entity'si tanımlanmaz.

## Laboratuvar ve cihaz

| Entity | Temel alanlar | Not / kısıt |
|---|---|---|
| `LabReport` | `id: uuid`, `clientId: uuid`, `collectedAt: instant`, `labName: string?`, `note: string?`, `createdAt: instant` | Kullanıcının tek analiz/rapor oturumu; manuel/OCR giriş aynı kavramı kullanır |
| `LabResult` | `id: uuid`, `labReportId: uuid`, `testCode: string?`, `testName: string`, `value: decimal`, `unit: string`, `referenceLow: decimal?`, `referenceHigh: decimal?`, `flag: LabFlag` | Rapordaki birim/aralık esastır; sunucu hesaplar, `unknown` olabilir |
| `LabInsight` | `id: uuid`, `labReportId: uuid`, `createdAt: instant`, `summary: string`, `method: string`, `modelVersion: string?`, `limitations: AÇIK` | Sınırlılık açıklaması zorunludur; metin/liste biçimi ve method değerleri **AÇIK**tır. Kaynak/açıklanabilirlik korunur; klinik tanı içermez |
| `WearableConnection` | `id: uuid`, `clientId: uuid`, `provider: string`, `status: string`, `lastSyncedAt: instant?` | Provider/durum değerleri **AÇIK**tır; token/secrets API yanıtına çıkmaz, ayrı platform izni gerekir |
| `ConsentRecord` | `id: uuid`, `userId: uuid`, `consentType: string`, `granted: boolean`, `policyVersion: string`, `recordedAt: instant`, `withdrawnAt: instant?` | `userId` → User; izin/rıza geçmişi ve geri çekilme. Mevcut `granted` adı korunur; onay türü kodları henüz belirlenmemiştir |
| `AuditEvent` | `id: uuid`, `actorUserId: uuid`, `action: string`, `resourceType: string`, `resourceId: uuid`, `createdAt: instant`, `metadata: object?` | `actorUserId` → User; sağlık değeri/password/token loglanmaz. Kaynak türü/id çifti ilgili kaydı işaret eder; metadata ayrıntıları **AÇIK**tır |

### Paylaşım ve tahlil bütünlüğü

- `ClientProfile` → User üzerinden rıza sahibi belirlenir. `DataSharingPermission` erişim kapsamını, `ConsentRecord` rıza/izin geçmişini temsil eder; aynı kayıt veya birbirinin yerine kullanılan boolean değildir.
- Bir kategorinin diyetisyene açılması için ilgili ilişki `active`, güncel kategori izni `isGranted = true` olmalıdır. İzin kaydı yoksa diyetisyene erişim yoktur. İlişki bitince veya izin geri çekilince mevcut kayıtlar/PDF raporları dahil diyetisyenin yeni erişimi kesilir; geçmiş kayıt saklamak erişim hakkı vermez. Danışanın kendi verisine erişimi diyetisyen ilişkisine bağlı değildir.
- Tahlil kategorisi izni veriliyorsa ayrıca `consentRecordId` dolu ve ilgili danışanın User kaydına ait olmalıdır; açık onayın türü/kapsamı tahlil paylaşımıyla eşleşmeli, `granted = true`, `withdrawnAt = null` olmalıdır. Yalnız genel gizlilik kabulü veya cihaz izni yeterli değildir. Kapsam/kategori kodları onaylanmadan uydurulmaz.
- `ConsentRecord.withdrawnAt` varsa `recordedAt`ten önce olamaz; geri çekilmiş rıza yeni erişimde kullanılamaz. Rıza değişiminde geçmiş kabulün politika sürümü ve zamanı korunur. `DataSharingPermission` veya rızanın eski halinin cache'te kalması erişimi sürdürmez.
- `LabReport` en az bir `LabResult` içerir. Referans sınırları biliniyorsa aynı analit/birim için anlamlı olmalı; ikisi de varsa `referenceLow <= referenceHigh` sağlanmalıdır. Eksik/uyumsuz birim/aralıkta `flag = unknown`; sıfır referans uydurulmaz. Tek taraflı aralıkların güvenli değerlendirme kuralı **AÇIK**tır.
- OCR, kullanıcı doğrulamasından önce değerlendirmeye alınan kesin `LabResult` üretmez. Taslak OCR değeri, orijinal birim/referans/tarih ve kullanıcı onayının nasıl saklanacağı **AÇIK**tır; doğrulanmış veriyle karıştırılamaz. Trendler yalnız aynı analit ve aynı/doğrulanmış dönüştürülmüş birimle karşılaştırılır. `LabInsight` tanı/tedavi değildir; ML kullanımı opsiyonel ve validasyona bağlıdır.

### Aktivite, platform kaynağı ve tekilleştirme

- `ActivityLog.wearableConnectionId` doluysa bağlantının `clientId`si aktivite sahibine eşit olmalıdır. `source = wearable` olan içe aktarımda bu bağlantı zorunludur; sağlayıcı buradan belirlenir. Manuel girişte platform bağlantısı ve dış kimlik zorunlu değildir; `source` gerçeği yansıtır.
- İçe aktarılan kaydın kararlı dış kimliği varsa `externalRecordId` korunur; aynı danışan + sağlayıcı + dış aktivite kimliği tekrar aktarımda ikinci kayıt oluşturmaz. Bağlantının yeniden kurulması bu kuralı bozmaz. Sağlayıcı kararlı kimlik vermiyorsa kaynak anahtarı üretme politikası **AÇIK**tır; sahte UUID ile tekilleştirme tamamlandı sayılmaz.
- Manuel/cihaz örtüşmesini belirleme yöntemi **AÇIK**tır; yalnız dış ID kontrolü manuel kaydın aynı aktivite olduğunu kanıtlamaz. Örtüşen veriler günlük toplamlarda çift sayılmaz; otomatik birleştirme/silme eşiği uydurulmaz. İzin geri alındığında yeni senkronizasyon durur; silme/saklama ayrı politikadır.
- Health Connect/HealthKit kapsamındaki mesafe km, süre dakika, enerji kcal olarak açık birimle normalleştirilir; orijinal kaynak korunur. `ActivityLog.caloriesKcal` alanının aktif/toplam enerji anlamı mevcut sözleşmede kesinleşmemiştir; aktif kaloriyle sessizce eşitlenmez.

| Ek sağlık verisi | Gerekli mantıksal ilişki / tip | Açık ayrıntı |
|---|---|---|
| Adım sayısı | ClientProfile'a ait 1:N kaynak kayıt; `integer`, birim adım; kayıt zaman/aralığı ve varsa WearableConnection bağlantısı | Kanonik model/alan adı, zaman aralığı ve gün bazlı agregasyon |
| Nabız | ClientProfile'a ait 1:N kaynak ölçüm; `decimal`, birim atım/dakika; ölçüm zamanı ve varsa WearableConnection bağlantısı | Kanonik model/alan adı; tek ölçüm/seri ve aktiviteyle opsiyonel eşleme |
| Aktif kalori | ClientProfile'a ait kaynak kayıt; `decimal`, birim kcal; aktivite veya zaman aralığı bağlamı | Alan/model adı; aktivite kaydı ile günlük toplamın ayrımı |

Bu verilerin tamamı zorla `ActivityLog` veya `BodyMeasurement` içine yerleştirilmez. Manuel giriş imkânı korunur; eksik ölçüm sıfır olmaz. Bağımsız kayıt mı mevcut modele bağlantı mı gerekeceği onaylanmadan genel amaçlı karmaşık bir ölçüm tablosu tasarlanmaz.

## İlişki ve bütünlük kuralları

- `User` 1:0..1 `ClientProfile` **veya** `DietitianProfile` (rol modeli netleştirilecek); `DietitianClientRelationship` üzerinde kullanıcı ID yerine profil ID kullanılır.
- `ClientProfile` 1:N `MealLog`, `WaterLog`, `LabReport`, `ActivityLog`, `BodyMeasurement`.
- `ClientProfile` 1:N `NutritionPlan`, `ClientTask`, `DietitianClientRelationship`, `WearableConnection`; `DietitianProfile` 1:N atadığı ClientTask ve diyetisyen programı. Kişisel programın DietitianProfile bağlantısı yoktur.
- `MealLog` 1:N `MealLogItem`; `LabReport` 1:N `LabResult`; `NutritionPlan` 1:N `NutritionPlanItem`.
- `FoodAnalysis` bağımsız rapordur; isteğe bağlı `MealLog.foodAnalysisId` ilişkisi vardır. İki kaydın danışanı aynı olmalıdır; analiz başka danışanın öğününe bağlanamaz. Katalog/tarif referansı olmayan manuel `MealLogItem` geçerlidir.
- `LabResult.flag` referans aralığına güvenilebiliyorsa hesaplanır; aralık yoksa/uyumsuzsa `unknown`.
- `ActivityLog.externalRecordId` ve bağlantının provider'ı üzerinden kaynak özelinde tekrar içe alma engellenir; kaynak bağlantısı aynı danışana ait olmalıdır.
- Diyetisyen programı ve görev atamasında ilgili diyetisyenle danışan arasında yetkili/aktif ilişki olmalı; bu şart kişisel program oluşturmak için aranmaz. Diyetisyenin görev/yorum/rapor erişimlerinde de güncel ilişki ve kategori izinleri kontrol edilir.
- **Tek aktif diyetisyen:** Her `clientId` için `status = active` olan ilişki sayısı en fazla 1'dir. Kabul işlemi diğer aktif ilişkiyle yarıştığında da kural korunur. `active` ilişki karşılıklı onaylanmış olmalı (`respondedAt` dolu, `endedAt` boş); `ended` için `endedAt` doludur. Olay sırası `requestedAt <= respondedAt <= endedAt` olacak şekilde mevcut zamanlara uygulanır; diğer durum geçiş ayrıntıları **AÇIK**tır. Geçmiş ilişki silinerek veya profil kimliği değiştirilerek sınır aşılmaz.
- **Tek aktif program:** Her `clientId` için `status = active` olan NutritionPlan sayısı en fazla 1'dir; `dietitianId`ye göre ayrı ayrı sayılmaz. Program değiştirmede eski aktif kaydın durum değişimi ve yeni kaydın aktifleşmesi tutarlı/atomik olmalıdır. Aynı anda iki aktivasyon sınırı aşamaz; tarihleri farklı iki `active` kayıt da kabul edilmez.
- Bu iki tekillik yalnız UI kontrolüyle sağlanmaz; backend ve PostgreSQL tarafında eşzamanlı işlemlerde de korunur. Kısmi unique indeks/transaction gibi mekanizmanın ayrıntısı uygulama kararıdır; burada migration/SQL üretilmez.
- FK bağlantılarında danışanın özel alt kayıt/program/analizleri başka danışanın özel kayıtlarına bağlanamaz. Ortak katalog/tarif bağlantısı için ilgili kaynağa erişim yetkisi ayrıca kontrol edilir; bunların görünürlüğü özel sağlık kaydı sahipliğiyle karıştırılmaz. Tarihçe koruma kararı otomatik cascade silme veya süresiz saklama anlamına gelmez; silme/anonymizasyon/FK davranışı veri koruma tasarımında netleşir.

## Hesaplanan / saklanan alan ayrımı

Günlük kalori, makro ve su toplamları `MealLogItem`/`WaterLog` kayıtlarından hesaplanabilir. Agregasyon performans için tutulacaksa tutarlılık/yeniden hesaplama politikası gerekir. Bilinmeyen besin değerleri tam toplam varmış gibi sıfır sayılmaz; eksiklik görünür olmalıdır. Grafikler ve PDF raporları aynı yetkili kaynak verilerden üretilir; bunlar için otomatik yeni entity veya sağlık verisi kopyası gerekmez. Program uyum hesabı, tarih/sürüm eşleştirmesi ve günlük saat dilimi politikası **AÇIK**tır.

`FoodAnalysis.suggestions` için `06`daki mevcut örnek; `displayName: string`, `quantityGrams: decimal?`, `caloriesKcal: decimal?`, `confidence: decimal` (0–1) içerir. Kalori/porsiyon belirsizliği korunur. Onaylı makro tahmini için aynı `proteinGrams`/`carbsGrams`/`fatGrams` adları nullable decimal/gram olarak kullanılmalıdır; `06`daki öneri şeması bunları henüz içermemektedir. Analiz düzeyindeki `limitations` dönüşü `06`da vardır; saklanacak mı üretilecek mi olduğu ve `10` ile iç içelik uyumu **AÇIK**tır. Kullanıcı düzeltip ayrıca onaylamadan MealLog oluşturulmaz.

## `06_API_CONTRACT.md` ile uyumsuzluklar (bu görevde değiştirilmedi)

- Plan oluşturma/düzenleme/aktif etme işlemleri yalnız diyetisyen için anlatılır; kişisel NutritionPlan sahipliği, nullable `dietitianId` ve danışanın kendi programını düzenlemesi API'ye yansıtılmalıdır. Mevcut endpointler bu dosyada değiştirilmez veya yeni alternatif rota üretilmez.
- `Recipe`, `ClientTask`, `DataSharingPermission` ve yeni `recipeId`/`wearableConnectionId` bağlantılarının request/response karşılıkları yoktur. Sürüm/alternatif, yorum/cevap, son tarih/hatırlatma ve tahlil açık onayı için de payload/yetki kuralları tamamlanmalıdır.
- Mevcut enum değerleri korunmuştur; görev durumları, paylaşım kategorileri ve provider değerleri henüz belirlenmemiştir. Bunlar serbest string olarak istemcilerde ayrı ayrı uydurulamaz. API null/eksik alan ve PATCH davranışı netleştirilmelidir.
- Aktivite sağlayıcı kimliği, tekilleştirme, adım/nabız ve aktif enerji ayrımı mevcut API örneklerinde tanımlı değildir. Lab OCR taslağı/kullanıcı onayı, güvenli birim dönüşümü ve LabInsight yanıt ayrıntıları da eksiktir.
- Fotoğraf analizi önerilerinde makrolar eksiktir; `limitations` biçim/konumu belgeler arasında netleştirilmelidir. E-posta doğrulama, şifre sıfırlama ve Admin MFA'nın HTTP ayrıntıları bu veri sözlüğüyle belirlenmez.

## Onay bekleyen şema kararları

Tek aktif diyetisyen/program, kişisel program, program sürüm geçmişi ve öğün alternatifleri **onaylı gereksinimlerdir**; yeniden açık ürün kararı sayılmaz. Açık kalanlar:

- Sürüm/alternatif/yorum alt kayıtlarının kanonik adları, alanları ve saklama biçimi; tüketim–program sürümü eşleştirmesi. Öğün kayıtlarının kendi sürümleme ihtiyacı ayrıca açıktır.
- Tarif bileşenleri, toplam/porsiyon temeli, görünürlük ve değişiklik geçmişi; kişisel makro hedef alanları, programsız hedeflerin yeri ve öneri hesaplama yöntemi.
- Görev son tarihinin gün/saat anlamı ve nullability'si, durum geçişleri, hatırlatma tercihleri; yorum/cevap moderasyonu ve bildirim teslim modeli.
- Paylaşım kategorileri, rıza tür/kapsam kodları, davet/başvuru doğrulama kayıtları, çoklu rol/profil ve doğum tarihi zorunluluğu.
- Nabız/adım/aktif enerji veri yapıları, platform/cihaz desteği ve manuel/cihaz örtüşme politikası; günlük zaman dilimi ve yeniden senkronizasyon anahtarları.
- Besin sağlayıcısı/lisans, test kod standardı, birim dönüşümleri, OCR onay kaydı, AI modeli/veri validasyonu; `licenseInfo`, `recommendedQuantity` ve `LabInsight.limitations` biçimleri.
- Mobil güvenli saklama/istemci refresh entegrasyonu ve mobil MFA, sayısal hassasiyet/yuvarlama, metin sınırları, veri/fotoğraf/PDF saklama-silme ve anonimleştirme; geçmişi koruyan FK davranışları. Backend refresh hash/iptal modeli 31.10.2026 bölümündedir; gerçek yayın için `11_SECURITY_AND_RELEASE.md` kapısı geçerlidir.

Sonraki ortak sözleşme adımı; açık alt kayıt adlarını `04`te, şema ayrıntılarını burada ve HTTP karşılıklarını `06`da iki geliştiricinin onayıyla eşgüdümlü tamamlamaktır. Kayıt/e-posta doğrulamasının kapanmış alanları bu açık listeye dahil değildir.
