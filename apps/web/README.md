# Smart Nutrition — Web

Uğur'un web alanı için React/TypeScript + Vite başlangıcı. Giriş, şifre sıfırlama
arayüzleri ve yalnız geliştirme ortamında açılan diyetisyen paneli önizlemesi.
**Backend/API, gerçek Auth, hesap/oturum veya sağlık verisi entegrasyonu içermez.**

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
bağlantısı bulunmaz. Bu ayrım gerçek bir oturum/yetki sistemi değildir. Mert'in
`6351089` commit'ine kadar backend ve mobil güncellemeleri yerel projeye
alınmıştır. Backend ve mobil dosyaları bu web görevi kapsamında değiştirilmemiştir.

## Yapı

- `src/features/auth/`: giriş/sıfırlama sunumu, yerel biçim/boş alan kontrolleri.
- `src/features/workspace/`: panel navigasyonu, genel bakış ve veri bekleyen alanlar.
- `src/features/clients/`: danışan listesi/detayı, kapalı sözleşme alanlarının
  TypeScript karşılıkları, sentetik örnekler, kayıt sunumu ve önizleme durumları.
- `src/core/components/`: kullanılan ortak marka/ikon ve boş durum bileşeni.
- `src/core/theme/`: tek merkezde başlangıç tokenları, sistem/açık/koyu görünüm.
- `src/test/`, `*.test.tsx`: formların istek/oturum üretmemesi, üretim önizleme
  sınırı, erişilebilir form geri bildirimi, sayfa geçişi ve tema davranışları.

## Ortak sözleşme ve devam sınırı

`docs/04`, `05`, `06` değiştirilmemiştir. Yeni endpoint, sözleşme dışı domain
modeli, oturum DTO'su, paylaşım kategorisi veya açık şemadan kesin mock
oluşturulmamıştır. Danışan liste girdisi yalnız `id` ve `displayName` içerir;
doğum tarihi, boy, User veya Dashboard kök DTO'su varsayılmaz. Öğün/su/ölçüm/aktivite/tahlil
tipleri yalnız tanımlı alanları kullanır; fixture'lar üretim derlemesine dahil
edilmez. Bilinmeyen danışan kimliğine mevcut bir örneğin verisi atanmaz;
kayıt, öğün kalemi ve tahlil sonucu sahiplik bağlantıları görüntüleme öncesinde eşleştirilir.
Bu istemci kontrolleri gerçek kaynak/yetki denetimi olarak sunulmaz.
E-posta biçimi ve
boş şifre yerel olarak kontrol edilir; açık parola politikası yerine minimum
uzunluk/karmaşıklık kuralı seçilmez. Form geçerli olsa da istek, hesap kontrolü,
e-posta veya token üretilmez; başarılı giriş/sıfırlama taklidi yapılmaz.
Şifre gönderimde ve sayfa geçişinde temizlenir; saklanmaz veya loglanmaz.
`isLoading` / `errorMessage` yalnız test edilebilir sunum girdileridir; yapay
gecikme veya sahte ağ yanıtı yoktur.

Tema varsayılan olarak sistemi izler; elle seçilen tercih yalnız mevcut sayfa
oturumunda tutulur. Kalıcı saklama tasarımı seçilmemiştir. `tokens.css` içindeki
başlangıç marka rengi `#386a5e`, 8/16/24/32 boşlukları ve 16px köşe değeri mobil
`AppTokens` ile eşleşir. Koyu tema karşılıkları ve sistem fontu tasarım önerisidir;
nihai ortak tema/ekran onayı sayılmaz. Uzak font, analitik veya medya isteği yoktur.

Backend altyapısı PostgreSQL bağlantısı, sağlık kontrolleri ve geliştirme
OpenAPI/Swagger görünümünü ve User/ClientProfile kaydını içerir. `6351089` ile
danışan kayıt endpointi `201 { id }` yanıtıyla hazırdır; giriş/oturum ve sağlık
kayıtlarını okuyan endpointler henüz yoktur. Ortak Auth önerisi ayrı PR'dadır;
incelemeye hazır olması sözleşme onayı değildir.
Web bu altyapıya sahte bir giriş isteği göndermez. Sonraki adım Auth/profil
sözleşmesini iki tarafla doğrulamak ve ilgili endpointler hazır olduğunda
ilk gerçek giriş entegrasyonunu ayrı görevde yapmaktır.
Admin MFA, başvuru/doğrulama ve açık DTO'lara bağlı program/görev/yorum ekranları
bu başlangıca dahil değildir. Gerçek veri veya yayın için `docs/11` kapısı geçerlidir.
