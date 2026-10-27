# Smart Nutrition — Mobil

Flutter/Dart başlangıç uygulaması; Android ve iOS proje dosyaları içerir.
Ana Sayfa'da örnek verili Dashboard; Beslenme, İlerleme ve Profil sekmelerinde
boş durum ekranlarını içerir.
Giriş/kayıt, şifre sıfırlama ve e-posta doğrulama bilgilendirme ekranları içerir.
Gerçek veri, API entegrasyonu, çalışan kimlik doğrulama veya özellik iş mantığı içermez.

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

## Yapı

- `lib/main.dart`: giriş noktası.
- `lib/app.dart`: uygulama kökü ve tema bağlantısı.
- `lib/core/theme/`: başlangıç tokenları ve Material 3 açık/koyu temalar.
- `lib/core/widgets/empty_state.dart`: sekmelerin ortak, duyarlı boş durum görünümü.
- `lib/features/navigation/`: Material 3 alt navigasyon ve sekme durumunu koruyan ana yapı.
- `lib/features/auth/`: kimlik ekranları, temel form doğrulaması ve ortak form görünümleri.
- `lib/features/home/`: Dashboard düzeni, günlük göstergeler, program/öğün kartları
  ve merkezi `dashboard_demo_data.dart` örnekleri.
- `lib/features/nutrition/`, `progress/`, `profile/`: diğer sekmelerin ekran iskeletleri.
- `test/app_test.dart`: açılış, tema, sekme geçişleri, geri tuşu ve büyük metin testleri.
- `test/dashboard_test.dart`: demo işaretleri, hedef göstergeleri, diyetisyen
  bağlantısı olan/olmayan örnekler, erişilebilirlik etiketleri ve duyarlı Dashboard testleri.
- `test/auth_test.dart`: form doğrulama, şifre görünürlüğü, ekran geçişleri,
  yüklenme/hata durumları ve klavye/büyük metin kontrolleri.

Yalnız Flutter SDK kullanılır; test ve analiz için standart `flutter_test` ve
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

Debug derlemede Dashboard açılışı korunur; uygulama çubuğundaki **Kimlik ekranları
(önizleme)** düğmesi Giriş Yap ekranını açar. Geri dönmek mevcut sekme durumunu
korur. Debug dışı derlemeler Giriş Yap ekranıyla açılır; çalışan Auth henüz yoktur.
Geçerli form gönderimi bile hesap, token veya oturum oluşturmaz; hiçbir e-posta
göndermez ve Dashboard'a başarılı giriş geçişi yapmaz. E-posta doğrulama sayfası
yalnız açıkça seçilen bir bilgilendirme ekranıdır; kayıt sonrası başarı simülasyonu değildir.

Formlar e-posta biçimi, boş alan ve şifre eşleşmesini yerel olarak kontrol eder;
şifreler kırpılmaz, saklanmaz veya loglanmaz. Kayıt/profil gövdesi, rol seçimi,
şifre politikası ve hukuki onay metinleri ortak karar bekler; bu görevde
kesinleştirilmemiştir. `isLoading` ve `errorMessage` yalnız sunum girdileridir;
zamanlayıcı, sahte istek veya gecikmeli giriş simülasyonu yoktur. Şifre alanları
sayfa kapandığında serbest bırakılır; başka kimlik ekranına giderken temizlenir.

Uygulama sistem temasını izler; kullanıcı tema tercihi veya kalıcı
saklama henüz uygulanmamıştır. Android/iOS `com.example` kimlikleri ve standart
ikonlar geliştirme yer tutucularıdır; mağaza kimliği, ikon ve yayın imzası ayrıca
kesinleştirilmelidir. Ortak veri/API sözleşmelerinden açık şema uygulanmamıştır.
## W2 web oturumu entegrasyon notu — 27.10.2026

Kullanıcının teyit ettiği Uğur–Mert ortak onayıyla web cookie/CSRF/iptal
sözleşmesi `docs/04/05/06/11/12`ye işlendi. Mobil `POST /auth/login` isteği,
15 dakikalık JWT yanıtı ve bearer `GET /auth/me` beş alanı değişmedi. Mobil
isteklere cookie/CSRF/Origin eklenmez; yeni web yollarından mobil refresh DTO'su
türetilmez. Mobil refresh/iptal/saklama hâlâ açık karardır. Mobil kaynak kodu
bu dilimde değişmedi; Mert entegrasyondan önce ortak main'i eşitlemelidir.
