# Smart Nutrition — Web

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

## Danışan kaydı

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
kurulumuyla `https://localhost:7099` hedeflenir. Vite geliştirme sunucusu kayıt
ve bu iki doğrulama API yolunu ilgili hedefe proxy eder. Sentetik bir
hesabı `/kayit` ekranıyla oluşturup Mailpit'teki kodla doğrulayabilirsiniz.
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
bağlıdır; sıfırlama formu hâlâ istek/e-posta üretmeyen sunumdur.
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
