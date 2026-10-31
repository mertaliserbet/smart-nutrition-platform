# 11 — Güvenlik, KVKK, kalite ve gerçek yayın hazırlığı

## 31.10.2026 mobil refresh/iptal güncellemesi

Kullanıcının backend göreviyle JWT login yanıtına refresh token ve mutlak
refresh bitişi eklendi. Önceki mobil refresh/iptal açık notları bu alt kapsam
için tarihseldir; güvenli mobil saklama/istemci entegrasyonu halen ayrıdır.
Web `AuthSession`, cookie/CSRF ve Admin MFA akışları değiştirilmez.

- 256 bit opak refresh tokenın yalnız SHA-256 hash'i PostgreSQL'dedir; ham sır,
  access JWT veya parola DB/log/audit'e yazılmaz. Yanıtlar no-store'dur.
- Varsayılan 30 gün mutlak aile süresi merkezi yapılandırılır; rotasyon aileyi
  uzatmaz. User satır kilidi ve transaction, tüketim+yeni hash üretimini,
  eşzamanlı tekrar ve logout yarışlarını korur. Bir aktif aile tokenı DB unique
  indeksiyle de sınırlıdır. Hata rollback'i eski tokenı tüketilmiş bırakmaz.
- Tüketilmiş ata token tekrarında bütün aile iptal edilir; bağımsız girişler
  korunur. Meşru ve çalıntı tokenın ilk kullanımını ayırma garantisi yoktur.
  İstemci refresh'i tek işlemde koordine etmeli; kayıp yanıtı eski tokenla
  otomatik tekrarlamamalıdır. Grace/replay kabulü bulunmaz.
- Her refresh güncel e-posta/rolü kontrol eder. Admin'e login/refresh ile
  bearer verilmez; rol/doğrulama değişimi aileyi kapatır. Gelecekte parola ve
  güvenlik yazmaları aynı User kilidi/transaction'ında refresh ailelerini de
  iptal etmelidir; parola sıfırlama bu görevle uygulanmış sayılmaz.
- Logout refresh ailesini sunucuda iptal eder; **stateless access JWT'nin
  anlık iptali yoktur**. Daha önce verilen JWT kalan en fazla 15 dakikası
  boyunca geçerli olabilir; web session iptali veya JWT denylist'i türetilmez.
- Süresi dolmayan hash geçmişi silinmez; yalnız mutlak süresi bitmiş aile
  kayıtları periyodik temizlenir. Çok örnekli IP limiti/güvenilir proxy,
  anahtar işletimi, mobil güvenli saklama ve genel yayın kapıları açıktır.

## 29.10.2026 N1–N3 program erişimi ve geçmişi

`16` ortak onayıyla program API'sinde her işlemde User→profil, e-posta/rol,
uzman doğrulaması ve kaynak sahipliği kontrol edilir. Danışanın kendi
program/geçmiş okuması ilişkisizdir; atanmış programı yazamaz. Diyetisyen
aktif ilişki + açık nutrition_plans izniyle okur, yalnız kendi programını
yazar. Admin sağlık erişimi kazanmaz. Başka danışan veya başka programa ait
sürüm varlığı 404 ile gizlenir; izin kapalıysa 403. Yanıtlar no-store.

Yazma, izin geri çekme ve ilişki bitişi aynı ClientProfile kilidiyle
serileştirilir; program güncel içerik ve yeni snapshot tek transaction'dır.
Eski snapshot değişmez, recordedByUserId HTTP'de açılmaz. Aktif ilişki bitince
yalnız o uzmanın active atanmış programı aynı işlemde arşivlenir; rollback
testi hem ilişkiyi hem programı korur. Tek active DB indeksiyle de korunur.
Cookie yazması CSRF/Origin ister; istemci yazmayı otomatik tekrarlamaz.

Webde izin/yetki kaybında program içerikleri/form/geçmiş kaldırılır; temel
danışan kimliği ayrı kalabilir. Sayfa/istek değişiminde eski sağlık verisi
gizlenir, geç yanıt ve iptal edilmiş yazma başarı göstermez. Program hedefi
otomatik doldurulmaz; alternatifler gerçek tüketim/toplam değildir.
POST/PATCH 128 KiB; sırlar ve program gövdeleri uygulama loguna yazılmaz.

250 backend testi gerçek geçici PostgreSQL/Mailpit'te atlamasız, 128 web testi
başarılıdır. Bu doğrulama kalıcı sağlık verisi kullanma veya yayın onayı
değildir. Tam erişim/izin audit'i, saklama/silme/aktarım politikası ve diğer
sağlık kategorilerinin rıza gereksinimleri aşağıdaki yayın kapısında kalır.

## 29.10.2026 R1–R3 erişim güncellemesi

`15` ortak onayıyla doğrulanmış uzman/aktif ilişki/ilk kategori için backend
denetimi uygulanır. Invitation code, oturum veya veri erişimi değildir;
tek kullanımlık pending talep başlatır. Ham kod yalnız üretim yanıtında ve
geçici web belleğindedir. Hash/expiry sunucuda; rotasyon/tüketim/expiry ve
rollback test edilir. Hesap + bağlantı IP limitleri süreç içindedir.

JWT/cookie kaynakları karıştırılmaz; cookie yazması W2 CSRF/Origin ister.
User/profil kimlikleri ayrıdır ve her istekte güncel DB rol/doğrulama kontrol
edilir. Kabul/sonlandırma/izin mutasyonları ClientProfile kilidiyle yarışları
serileştirir; tek active/pending çift DB indeksleriyle de korunur.

nutrition_plans izni otomatik verilmez; yalnız danışan açıp kapatır.
Tahlil ve diğer sağlık kategorileri bu onayla açılmaz. ConsentRecord hukuki
metin/tür/politika kanıtı, tam izin audit'i ve saklama/silme/yayın kapıları
açık kalır. Temel danışan listesi/detayı yalnız aktif ilişkiyle id/ad taşır;
sağlık değeri, toplam veya varsayılan sıfır sunmaz. Admin kaynaklara erişmez.

## 29.10.2026 B1–B3 güvenlik güncellemesi

Kullanıcı ortak onayıyla uzman başvurusu ve Admin MFA/onay dilimi açılmıştır.
Eski MFA/başvuru açık notları yalnız bu dilim için tarihsel durumdur; üretim
kapıları, sağlık paylaşımı, ret/geri alma ve diğer açıklar korunur.

- Admin JWT veya normal web girişiyle kabul edilmez. Yeni MFA cookie'si,
  User satır kilidi altında TOTP/recovery tüketimi + AuthSession commit'iyle
  verilir. Her okumada DB'de isMfaVerified ve güncel rol/doğrulama/süre/iptal
  kontrol edilir. CSRF/Origin/HTTPS ve W2 cookie korumaları aynıdır.
- TOTP için Otp.NET 1.4.1 kullanılır; 6 hane/30 saniye/±1 adım, tek kullanım.
  Secret User UUID'sine bağlı Data Protection ile korunur. Kurtarma kodları
  128 bit kriptografik rastgele, yalnız SHA-256 hash, atomik tek kullanımdır.
- Yerel ilk Admin/MFA yenilemesi HTTP açmadan çalışır. Girdi parolası ve
  tek seferlik enrollment/kurtarma dosyası Git dışında tutulur. Çıktı mevcut
  dosyanın üzerine yazılmaz; Windows'ta yalnız mevcut kullanıcı ACL'i,
  Unix'te 0600 kullanılır. Sırlar console/log/API'ye yazılmaz. Dosyalar
  güvenli aktarımdan sonra işletmen tarafından kaldırılır. Key ring yedeği ve
  üretim rotasyon/kurtarma operasyonu yayın kapısının parçasıdır.
- licenseInfo özel mesleki açıklamadır; public arama/auth/me'ye açılmaz.
  Başvuru e-posta doğrulaması veya Admin uzman doğrulaması değildir.
- Onay ve secret/sağlık değeri içermeyen AuditEvent tek transaction'dadır;
  audit yazılamazsa onay da geri alınır. Admin sağlık içeriklerine erişmez.
- Manuel kurulum, standart uzmanın klinik yeterliliğini otomatik doğrulamaz;
  onayı yetkili Admin verir. Gerçek kullanıcı/yayın için bu belge geçerlidir.

**Bu doküman hukuki görüş değildir.** Gerçek kullanıcı verisi işlemeye ve Türkiye/Google Play dağıtımına geçmeden önce yetkin hukuk, sağlık ve mağaza politikası incelemesi gerekir. Laboratuvar ve sağlık verisi özel nitelikli kişisel veri olabilir.

## Veri koruma tasarım ilkeleri
- Veri envanteri: hangi veriler (beslenme, tahlil, ölçüm, cihaz), amaç, hukuki dayanak, saklama süresi, erişen rol, üçüncü taraf, yurt dışı aktarım.
- Aydınlatma metni ile **açık rıza gerekebilen işlemleri** birbirinden ayır; rıza gerekip gerekmediği hukuken değerlendirilir, tüm süreçleri tek checkbox ile çözme.
- **Varsayılan gizlilik:** doğrulanmış diyetisyen yalnız aktif ilişkili ve kategori bazında izinli danışan verisini görür; tahliller ayrıca geri çekilmemiş açık onay gerektirir. Admin sağlık içeriğini varsayılan göremez. Danışanın kendi verisine erişimi diyetisyen ilişkisine bağlı değildir.
- Rıza/izin geçmişi (`ConsentRecord`), kategori erişimi (`DataSharingPermission`) ve cihaz/OS izni birbirinin yerine geçmez. İlişki/izin/onay geri çekilince cache, analiz, dosya ve PDF dahil diyetisyenin yeni erişimi kesilir; kendi verisini okuyan danışan engellenmez.
- Hesap silme, veri indirme / silme talepleri, yedekten silme ve saklama süreleri yayından önce netleşir.
- Kullanıcı fotoğrafı/tahlili AI/üçüncü tarafa aktarılıyorsa sağlayıcı, yer, sözleşme, retention ve yasal dayanak incelenir.
- Sırlar `.env` vb. yerel konfigürasyonda; git'e secret, gerçek laboratuvar sonucu veya gerçek hesap dökümü eklenmez.

## Teknik güvenlik kontrolü
| Kontrol | Kabul yönü |
|---|---|
| Kimlik | E-posta/şifre, e-posta doğrulama, şifre sıfırlama, güçlü parola hash, güvenli oturum/iptal ve rate limit; Admin MFA zorunlu. E-posta tokenı, 15 dakikalık JWT ve W2 web cookie/CSRF/iptal onaylı; mobil refresh/iptal ve MFA açık |
| Yetki | Her endpointin kendi rol/kaynak kuralı; danışan kendi kaydı, diyetisyen doğrulanmış uzman + aktif ilişki + kategori izni ve tahlilde ayrı açık onay. Kişisel program için ilişki aranmaz |
| Sağlık verisi | TLS, aktarım/depoda güvenlik, en az ayrıcalık, audit |
| İstemci | güvenli token saklama; ekran/log/cache ile veri sızıntısını sınırlama |
| Dosyalar | MIME/limit/zararlı içerik taraması, private storage, süreli erişim |
| Hata/log | PII/sağlık değeri/token sızmaması, request ID |
| AI/OCR | Amaçla uyumlu aktarım izni, minimum veri, model sınırı; tahmin/OCR tamamlanması kullanıcı onayı sayılmaz, onaysız kalıcı sağlık kaydı oluşmaz |
| Cihaz API'leri | açık izin, veri kapsamı, geri çekme, dedup |

Özel sağlık verisi sunan rol, listelerin totalCount/özetleri ve rapor dosyaları dahil kaynak kapsamını kontrol eder. Sahiplik/flag/rol gibi sunucu alanları istemci girdisiyle değiştirilemez. Başvuru/rol seçimi uzman doğrulaması değildir; Admin MFA tamamlanmadan yönetim oturumu verilmez. Gizli doğrulama/MFA/refresh bilgileri profil yanıtına veya audit metadata'sına konmaz.

### Kayıt ve e-posta doğrulama güvenliği — 27.10.2026

- Onaylı kayıt: yalnız danışan, zorunlu `email`/`password`/`displayName`, `201 { id }`; User/ClientProfile atomik oluşturulur. Başlangıçta e-posta doğrulanmamıştır; otomatik giriş/token/cookie verilmez. İlk sürüm parola politikası 8–128 Unicode kod noktası, boşluk destekli ve karakter türü zorunluluğu olmadan merkezi yapılandırılır. Parola kırpılmaz/normalize edilmez; Identity PasswordHasher kullanılır.
- E-posta tokenı kriptografik rastgele 256 bittir; 30 dakika geçerlidir ve tek kullanımlıktır. Yalnız SHA-256 hash'i DB'de tutulur. Ham token yalnız geçici işlem belleğinde ve SMTP ile iletilen e-posta içeriğinde bulunur; API yanıtına, request-body loguna, SMTP protokol loguna, audit'e veya DB hata ayrıntısına yazılmaz. İstek DTO'ları loglarda destructure edilmez; EF hassas veri loglaması/Npgsql hata detayı kapalı tutulur.
- Doğrulama ve tüketme tek atomik DB güncellemesidir; eşzamanlı tekrar, geçersiz, süresi dolmuş veya önceki gönderimden kalan token aynı `422` olur. Yeni gönderim eski tokenı geçersiz kılar. Bu akış parola sıfırlama veya oturum açma yetkisi vermez.
- Yeniden gönderim geçerli e-posta için hesap varlığı/doğrulanmışlık/gönderim aralığından bağımsız gövdesiz `202` döner. Hesap sorgusu ve SMTP arka plandadır. Varsayılan hesap başına 60 saniye DB kontrolü ve bağlantı IP'si başına 5 istek/dakika HTTP sınırı uygulanır; IP aşımında `429`. SMTP hata mesajı veya alıcı bilgisi loglanmaz. Kayıttaki mevcut mükerrer e-posta `409` sözleşmesi korunur; yeniden gönderim kuralıyla karıştırılmaz.
- SMTP host/port/gönderen ve kimlik bilgileri environment/User Secrets üzerinden yönetilir. TLS zorunludur (`StartTls`/`SslOnConnect`); `None` yalnız Development + loopback SMTP için kabul edilir. Yerel Mailpit SMTP/UI portları yalnız localhost'a açılır, dış iletim yapılandırılmaz; sentetik test e-postaları kullanılır. Üretim sağlayıcısı ve TLS/secret dağıtımı ayrıca hazırlanır.
- Mevcut sınırlı bellek kuyruğu kalıcı teslim sağlamaz. SMTP hatası/kuyruk doluluğu/yeniden başlatma durumunda hesap doğrulanmamış kalır; yeniden gönderim gerekir. Üretim teslim dayanıklılığı, çok API örneğinde ortak IP limitleri ve güvenilir proxy ayarları yayın öncesi ayrıca değerlendirilir. Mobil/web doğrulama ekranı/deep-link akışı bu backend adımında uygulanmamıştır.

## Geliştirme ve gerçek veri kapıları
### Onaylı web cookie güvenliği — 27.10.2026

Kullanıcı W2-C1–C7 ortak onayını teyit etti. `06`daki ayrı web oturumu
ASP.NET Core Cookie Authentication/Data Protection, HttpOnly/Secure/Strict
host cookie, oturuma bağlı antiforgery ve tam HTTPS Origin kontrolü kullanır.
Korunan bilet yalnız User/rol/oturum referansı taşır; JWT/refresh/PII taşımaz.
30 dakika hareketsizlik ve 8 saat mutlak sınır DB'de her istekte doğrulanır;
başarılı hesap okuması dışında oturum uzatılmaz. DB kesintisi kapalı erişimdir.
Çıkış DB iptalinden sonra 204'tür; istemci ağ hatasını tamamlanmış çıkış saymaz.
Parola ve CSRF yalnız geçici bellektedir; cookie/Authorization/CSRF/ham yanıt
loglanmaz. Yeni oturum aynı hesapta da önceki CSRF'yi geçersiz kılar.

`Auth:WebSession:Origin` ve Git dışındaki `KeyRingPath` yapılandırılır.
Windows'ta anahtarlar uygulama Windows hesabının DPAPI korumasını kullanır;
diğer ortamlarda özel anahtarı bulunan koruma sertifikası gerekir. Kalıcı dizin
uygulama kimliğine kısıtlanır. Çok API örneği aynı uygulama adı/anahtar halkasını
kullanmalıdır. Web ayarı yoksa JWT altyapısı çalışabilir, web oturumu açılamaz;
yanlış HTTPS/anahtar ayarı başlangıçta reddedilir. Dev sertifikası kontrolü atlanmaz.
Üretim anahtar dağıtımı/koruma/rotasyon, ortak rate limit/güvenilir proxy,
audit kalıcı şema/teslim ve kesinti sonrası temizlik izleme yayın kapılarıdır.
Mevcut AuditEvent için önerilen web oturum olayları, audit şeması açık olduğu
için tamamlanmış üretim audit'i olarak sunulmaz. Web oturum satırı en geç
24 saatte temizlenir; sağlık/audit saklaması ayrı kalır. Yeni parola/rol/doğrulama
yazmaları User kilidi + aynı transaction'da bütün web oturumlarını iptal etmelidir.
Web çıkışı stateless JWT'yi iptal etmez; mobil refresh/iptal ve Admin MFA açıktır.


**Giriş/JWT güncellemesi — 27.10.2026:** `06`daki onaylı giriş yanıtı yalnız
`accessToken`, sabit `tokenType: Bearer` ve UTC `expiresAt` içerir. Mevcut Identity
hash'i doğrulanır; bulunmayan hesapta da eşdeğer parola doğrulama işi yapılır.
Yanlış parola, olmayan kullanıcı, doğrulanmamış e-posta ve MFA'sız Admin aynı
genel `401` yanıtını alır. Admin'e token üretimi ve Admin claim'inin middleware'de
kabulü kapalıdır. Başarılı hesapta `SuccessRehashNeeded` güvenle güncellenir.

JWT imzası `HS256`, anahtar en az 32 kriptografik rastgele byte'ın Base64
karşılığıdır; anahtar/issuer/audience yalnız environment/User Secrets'tan alınır.
Eksik/hatalı ayar fail-closed başlangıç hatasıdır. Middleware imza/algoritma/tür,
issuer/audience ve zamanı doğrular; sıfır clock skew ile 15 dakikalık süre uzamaz.
Token yalnız User UUID'si/rol ve gerekli standart claim'leri taşır; sağlık verisi,
ad/e-posta, hash ve secret içermez. Parola, ham token, Authorization başlığı ve
giriş yanıtı loglanmaz; JWT framework hata ayrıntıları yanıta/loga taşınmaz.

Login varsayılan IP sınırı dakikada 10 istek ve gövde sınırı 4096 byte'tır.
Üretimde HTTPS, güvenilir proxy, ortak çok örnekli limit ve anahtar saklama/rotasyonu
ayrıca yapılandırılır. Mevcut access token stateless'tir; anlık iptal/refresh/logout,
mobil istemci saklama, MFA ve sıfırlama henüz sağlanmaz. Web cookie/CSRF/iptal
ayrı W2 dilimidir. Bu sınırlar korunmadan
tam güvenli oturum/yayın tamamlandı denmez; rol tek başına sağlık kaydı yetkisi değildir.

**Kendi hesap okuması — 27.10.2026:** `GET /api/v1/auth/me` doğrulanmış
JWT bearer veya W2 web cookie ile erişilir; ikisi birlikte kabul edilmez.
User UUID'si tek `sub` claim'inden çözülür; istemciden
userId alınmaz. Güncel User ve opsiyonel kendi ClientProfile'ından yalnız `id`,
nullable `displayName`, `email`, `role`, `isEmailVerified` seçilir; entity/hash/token
ve diğer profil/sağlık verileri serileştirilmez. Profil yoksa ad null'dır. Yanıt
`Cache-Control: no-store` kullanır; yanıt içeriği veya hassas hesap verisi loglanmaz.
Silinmiş hesap, artık doğrulanmamış e-posta veya tokenla uyuşmayan güncel rol için
ortak `401` kullanılır; Admin MFA engeli korunur. Bu hesap projeksiyonu User/profil verisi
yazmaz; W2 cookie modunda yalnız AuthSession idle süresi uzar. Diğer kaynaklar için anlık JWT iptali anlamına gelmez.

Ürün/teknoloji kararları onaylıdır; Auth/profil ve kategori/onay DTO'ları dahil teknik bağımlılıklar `12`nin hazırlık tablosundadır. İlgili şema kapanmadan gerçek yetki/oturum entegrasyonu tamamlandı sayılmaz. Sentetik tasarım/bağımsız altyapı çalışması gerçek sağlık verisi toplama veya yayın izni değildir.

Silme/retention, yedekten silme, rıza kanıtı, üçüncü taraf aktarımı, dosya erişimi ve istisnai Admin erişiminin uygulama ayrıntıları açıktır; süre, sağlayıcı, izin kodu veya hukuki dayanak bu belgeyle kendiliğinden seçilmez. Gerçek veri/yayın için aşağıdaki kapılar ayrıca tamamlanır.

## Test stratejisi
1. Domain unit test: kalori toplamı/bilinmeyen ölçüm, birimler, referans aralığı, tek aktif ilişki/program, alternatif/sürüm ve kişisel/atanmış düzenleme kuralları.
2. API integration/contract test: `04/05/06` sözleşmesi, 401/403/404, izole danışan verisi, giriş/çıkış.
3. Mobil/web E2E: danışan diyetisyensiz manuel öğün/su ve kişisel program → karşılıklı onay/kategori paylaşımı → diyetisyen izinli kaydı görür → kendi programını atar → mobil salt okunur görür. İlk sürüm yorum/cevap/bildirim akışı da doğrulanır; açık durum geçişi uydurulmaz.
4. AI/OCR: model versiyonu, hata/belirsizlik, kontrol/düzeltme/onay, manuel fallback ve onaysız kaydın oluşmaması; provider seçilmeden performans sonucu bildirilmez.
5. Güvenlik: farklı client ID/FK denemeleri, aktif ilişki/kategori/tahlil onayı geri çekme, cache/PDF erişim kesilmesi, yetkisiz liste sayıları, Admin MFA ve varsayılan sağlık erişiminin yokluğu; dosya sınırları/rate limit. İki eşzamanlı ilişki kabulü/program aktivasyonunda tekillik ve `409` kontrol edilir.
6. UX: her iki tema, erişilebilirlik, küçük ekran, zayıf internet, izin reddi ve çevrimdışı hata yönetimi; kişisel/atanmış düzenleme farkı, unknown/boş/izin kapalı durumları.
7. Cihaz/veri geçmişi: tekrar aktarım ve manuel/cihaz örtüşmesi çift sayılmaz; kaynak/bağlantı aynı danışana aittir. Tarif/katalog değişikliği eski tüketimi, program revizyonu eski sürümü değiştirmez. İlgili veri politikası önce onaylanır.

Bu liste test gereksinimidir; gerçekleşmiş sonuç değildir. Dokümantasyon görevinde uygulama test/build/lint yoksa çalıştırılmadığı açık raporlanır; dosya/bağlantı ve `git diff --check` doğrulaması uygulama testinin yerine geçmez.

## Yayın öncesi kalite kapıları
- [ ] Gerçek veri işleme ve pazara çıkış için KVKK/veri sorumlusu/yurt dışı aktarım değerlendirmesi tamam.
- [ ] Kullanıcı sözleşmeleri, gizlilik/aydınlatma, izinler ve gerekli açık rıza akışları hazır.
- [ ] Play Console sağlık politikaları, veri güvenliği beyanı ve izin gerekçeleri kontrol edildi.
- [ ] Uygulamanın sağlık iddiaları ve olası tıbbi cihaz mevzuatı riski uzmanla değerlendirildi.
- [ ] Erişim kontrolü, hesap silme, veri saklama, audit ve hata izleme test edildi.
- [ ] E-posta doğrulama/sıfırlama ve oturum iptali; zorunlu Admin MFA; kategori/tahlil onayı geri çekme ve PDF/cache erişimi gerçek ortamda doğrulandı.
- [ ] AI sonuçları kesinlik iddiası taşımıyor; açıklama ve onay akışları doğru.
- [ ] İmzalı release, paket kimliği, ikon, mağaza görselleri, çökme izleme ve destek kanalı hazır.
- [ ] İstemci/servis dağıtımı için gerçek ortam konfigürasyonu, secret yönetimi, yedekleme/geri yükleme ve izleme hazır.
- [ ] Açık/koyu tema, erişilebilirlik, salt okunur atanmış program ve onay/izin reddi durumları doğrulandı; seçilen platform/mağaza kapsamı ve desteklenen cihazlar açıkça belirlendi.

**MVP demo ile canlı yayın farklı aşamalardır.** Demo için sentetik veri kullanılabilir; gerçek kullanıcıya açma ancak bu kapılar tamamlandıktan sonra düşünülür.
