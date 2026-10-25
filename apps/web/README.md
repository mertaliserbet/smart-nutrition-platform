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
istekleri arasında gezinilebilir; arama, veri gelene kadar devre dışıdır.
Bu görünümler veri alınmış ve listeniz boşmuş gibi davranmaz. Sayaçlardaki `—`
değeri bilinmeyendir; gerçek sıfır veya sağlık özeti değildir.

`npm run build` sonrasında `npm run preview` üretim çıktısını yerelde gösterir.
Üretim derlemesinde `/onizleme/*` yolları kapalıdır; giriş ekranında önizleme
bağlantısı bulunmaz. Bu ayrım gerçek bir oturum/yetki sistemi değildir. Mert'in
henüz gönderilmemiş backend çalışmasına bu görevde müdahale edilmemiştir.

## Yapı

- `src/features/auth/`: giriş/sıfırlama sunumu, yerel biçim/boş alan kontrolleri.
- `src/features/workspace/`: panel navigasyonu, genel bakış ve veri bekleyen alanlar.
- `src/core/components/`: kullanılan ortak marka/ikon ve boş durum bileşeni.
- `src/core/theme/`: tek merkezde başlangıç tokenları, sistem/açık/koyu görünüm.
- `src/test/`, `*.test.tsx`: formların istek/oturum üretmemesi, üretim önizleme
  sınırı, erişilebilir form geri bildirimi, sayfa geçişi ve tema davranışları.

## Ortak sözleşme ve devam sınırı

`docs/04`, `05`, `06` değiştirilmemiştir. Yeni endpoint, domain modeli, oturum
DTO'su, paylaşım kategorisi veya kesin mock oluşturulmamıştır. E-posta biçimi ve
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

Sonraki adım: Mert'in backend commit'i geldikten sonra Auth/profil sözleşmesini
iki tarafla doğrulamak ve ilk gerçek giriş entegrasyonunu ayrı görevde yapmak.
Admin MFA, başvuru/doğrulama ve açık DTO'lara bağlı program/görev/yorum ekranları
bu başlangıca dahil değildir. Gerçek veri veya yayın için `docs/11` kapısı geçerlidir.
