# 11 — Güvenlik, KVKK, kalite ve gerçek yayın hazırlığı

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
| Kimlik | E-posta/şifre, e-posta doğrulama, şifre sıfırlama, güçlü parola hash, güvenli oturum/iptal ve rate limit; Admin MFA zorunlu. E-posta tokenı ve 15 dakikalık JWT access aşağıda onaylı; refresh/logout/iptal, cookie ve MFA yöntemi açık |
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
cookie/istemci saklama, MFA ve sıfırlama henüz sağlanmaz. Bu sınırlar korunmadan
tam güvenli oturum/yayın tamamlandı denmez; rol tek başına sağlık kaydı yetkisi değildir.

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
