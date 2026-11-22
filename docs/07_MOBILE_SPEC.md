# 07 — Gerçek Flutter ekranları ve mobil davranış

İnceleme tabanı 22.11.2026 / `4f160b3`. Mevcut uygulama açıklamaları kaynak koddan doğrulanmıştır; fiziksel Android/iOS veya yeni test koşusu sonucu değildir. Kesinleşmiş ancak geliştirmesi kalan Profil akışı ayrıca işaretlenmiştir. Ürün kapsamı [01](01_PROJECT_SCOPE.md), HTTP sözleşmesi [06](06_API_CONTRACT.md), sağlık aktarımı [20](20_HEALTH_DATA_SYNC_CONTRACT.md)'dedir.

## Uygulama girişi ve navigasyon

`mobile/lib/main.dart` SmartNutritionApp'i açar. Mevcut AuthGate doğrulanmış oturum olmadan özel ekran açmaz; başlangıç/deep-link yolları aynı kontrolden geçer. Normal mobil danışan deneyimi client temel rolündedir; aynı hesapla uzman başvurusu bu rolü değiştirmez. Mevcut kod diğer temel rolleri web paneline yönlendirir; eski diyetisyen mobil widget dosyalarının bulunması onların aktif yönetim paneli olduğu anlamına gelmez.

| Yol/ekran | Kaynaktaki davranış |
|---|---|
| /, /register, /email-verification | Giriş, gerçek kayıt ve e-posta doğrulama/yeniden gönderim |
| /forgot-password | Gerçek reset talebi ve manuel kodla yeni parola/tekrar formu |
| Ana Sayfa | API'den günlük tüketim/enerji/makro, su, aktif program veya kişisel hedef ve son öğünler |
| /nutrition — Beslenme | Kendi aktif programını ve öğün önerilerini salt okunur gösterme; sürümle günlük tüketim karşılaştırması |
| Öğün geçmişi/detayı/formu | Manuel oluşturma/düzenleme/silme, kalemler, miktar ve nullable besin değerleri; yorum/cevap |
| Su formu/özeti | Gerçek su kaydı, günlük toplam, düzeltme/silme |
| /progress — İlerleme | Kilo/bel/kalça/göğüs/yağ kayıtları, liste/detay/düzeltme/silme ve grafik |
| /personal-nutrition-targets | Kalori/protein/karbonhidrat/yağ/su hedeflerini girme veya temizleme |
| /dietitians, /client-connections | Doğrulanmış uzman arama, istek, ilişki durumu/sonlandırma ve beş bağımsız kategori izni |
| /client-tasks | Gerçek görev listesi/detay/sürüm geçmişi, danışanın izinli durum/hatırlatma tercihi |
| /device-health | Destek/izin durumları, açık ön plan okuması, ayrı sunucuya aktarım onayı/tercihi ve backend özeti |
| /profile | Hesap adı/e-postası ve ilgili ekranlara bağlantılar; başvuru/durum/panel seçeneği henüz yok, tam profil/gizlilik düzenleme ekranı değildir |
| /dietitian-account | Harici HTTPS web girişine (/giris) yönlendirme; mobil token URL'ye eklenmez, mevcut hesapla başvuru ekranını açmaz |

MainShell sekmeleri Ana Sayfa, Beslenme, İlerleme ve Profil'dir. Sekme/hesap/lifecycle değişimlerinde güncel veri yeniden okunur; eski hesaptan geç yanıtların görünmesi engellenir. Ana sayfa gün sınırında yenilenir; bütün veri için arka plan sürekli senkronizasyon taahhüdü yoktur.

## Kesinleşmiş çift profil ve Profil akışı

**Durum: onaylı gereksinim; Flutter geliştirmesi ve uygulama doğrulaması tamamlanmadı.** ProfilePage'de başvuru bağlantısı yoktur; eski DietitianAccountPage dosyası aktif /dietitian-account yolunda açılmaz. Mevcut genel web giriş bağlantısı aşağıdaki Profil akışının teslimi değildir.

- Kullanıcı mobilde danışan olarak kayıt olur, daha sonra aynı User hesabıyla diyetisyen başvurusu yapabilir. Başvuruda onaysız DietitianProfile oluşması mevcut backend davranışıdır; Admin onayından sonra onaylı uzman yetkisi açılır. ClientProfile, öğünler, ölçümler ve diğer kişisel kayıtlar korunur; ikinci hesap oluşturulmaz.
- Flutter V1 yalnız danışan deneyimidir. Onaylı diyetisyen kendi danışan özelliklerini kullanmaya devam eder; mobil diyetisyen yönetim paneli geliştirilmez.
- **Profil** mevcut hesapla başvuru girişini ve güncel başvuru/onay durumunu gösterir. Yalnız onaylı diyetisyende **“Diyetisyen Paneline Git”** seçeneği bulunur; bekleyen veya onaylanmamış kullanıcı çalışma alanına erişemez.
- Panel seçeneği güvenilir, yapılandırılmış HTTPS web adresindeki diyetisyen çalışma alanını harici tarayıcıda açar. Geçerli web oturumu kullanılabilir; web oturumu yoksa kullanıcı aynı e-posta ve şifresiyle ayrıca giriş yapar. Mobil JWT/refresh token web adresine, URL'ye veya tarayıcıya aktarılmaz; yeni bir oturum aktarım mekanizması tanımlanmaz.

Başvuru ve uzman yetkisi mevcut [06](06_API_CONTRACT.md) kurallarına tabidir. Web davranışı [08](08_WEB_SPEC.md), geliştirme/kanıt durumu [12](12_TEAM_PLAN_AND_DECISIONS.md)'dedir.

## Gerçek işlev ve önizleme ayrımı

Ana sayfanın hızlı işlemlerinde Öğün ekle ve Su ekle gerçek API kullanır. **Aktivite ekle ve Tahlil ekle önizleme açar, kayıt oluşturmaz.** Manuel aktivite API'sinin bulunması mobil manuel aktivite formunun tamamlandığı anlamına gelmez. Fotoğraftan besin, laboratuvar/OCR, bildirim teslimi, tarif/katalog ve tam kişisel program editörü henüz bağlı mobil akışlar değildir.

Kaynakta dashboard_demo_data gibi sentetik yardımcı dosyalar vardır; dosya varlığı gerçek ekranda kullanıldığını kanıtlamaz. Gerçek veri yükleme hatasında sentetik kayda veya sahte başarıya dönülmez. Hedefin programdan mı kişisel tercihten mi geldiği ayrılır; atanmış hedefler düzenlenmez.

## Oturum ve parola sıfırlama

AuthSession başlangıçta güvenli refresh deposunu okur, oturumu yeniler ve auth/me ile hesabı doğrular. Access token/hesap bellektedir; yalnız refresh token, mutlak bitiş ve rotationPending işareti API origin'ine ayrılmış şifreli kayıtta tutulur. Android/iOS dışındaki kalıcı depo kullanımı engellenir. Android resetOnError/migrateOnAlgorithmChange kapalı; iOS Keychain unlocked_this_device ve synchronizable=false kullanır.

Eşzamanlı yenileme tek koordinatörden yürür; ağ/saklama belirsizliği güvenli oturum durumu olarak gösterilir. Hesap değişiminde Navigator ve hassas ekranlar kaldırılır; dönüşte süre ve hesap kontrol edilir. Normal logout ile parola resetinin iptal farkı [06](06_API_CONTRACT.md)'dadır.

ForgotPasswordPage aynı backend akışını kullanır: talep için email, tüketim için token/password; tekrar alanı istemcidedir. Kod elle girilir, parola kırpılmaz, POST otomatik tekrarlanmaz. 204 sonrası normal girişe dönülür; otomatik login/deep-link tüketimi yoktur. Hata, limit ve sonucu bilinmeyen ağ durumu başarı sayılmaz.

## Sağlık platformu ekranı

DeviceHealthReader yalnız izinli native okumayı; HealthSyncService HTTP aktarımı/tekrar denemeyi yürütür. Desteklenmiyor, kurulum/güncelleme gerekiyor, izin reddi, veri yok ve hata ayrı durumlardır. İzin istemek kendi başına okuma/aktarım yapmaz.

Aktarım yalnız açık ön plan eylemi ve ayrı onayla başlar. Hesap/lifecycle/izin değişiminde bekleyen okuma ve kuyruk belleği bırakılır. Kalıcı sağlık önbelleği/disk kuyruğu veya otomatik arka plan upload yoktur. Eksik okuma ve iOS boş sonuç silme kanıtı değildir; mevcut mobil akış açık upsert kullanır, native silme delta'sı otomatik üretmez. Backend'in delete desteği mobil silme entegrasyonu sayılmaz.

Android manifestte okuma izinleri, iOS HealthKit entitlement ve açıklaması vardır. Fiziksel sensör/saat, gerçek native ID, OS sürümü, iOS/macOS imzalama ve mağaza kapsamı ayrıca doğrulanır. Kaynak başlık/birim/tekilleştirme ve API sınırları için yalnız [20](20_HEALTH_DATA_SYNC_CONTRACT.md) esas alınır.

## Yapılandırma ve doğrulama sınırı

API_BASE_URL release'te geçerli HTTPS origin olmalıdır; debug varsayılanı localhost:7099'dur. Kod yalnız debug loopback için HTTP'ye sınırlı izin verir; ortak yerel çalışma HTTPS kullanır. API_DEV_CERT_BASE64 yalnız debug'da açık geliştirme sertifikasına güven ekler, hostname/süre/TLS kontrolünü kapatmaz. WEB_BASE_URL HTTPS web origin'idir; release'te ayrıca ayarlanır.

Kurulum [kök README](../README.md)'dedir. Unit/widget testleri ile live/device probe dosyaları ayrı kanıtlardır. `mobile/test/mobile_quality_device_probe.dart` veya `device_health_live_probe.dart` bulunması çalıştırıldıkları anlamına gelmez. M5/M6 commit başlığı da tek başına cihaz test sonucu değildir. Güncel kanıt ve eksikler [12](12_TEAM_PLAN_AND_DECISIONS.md)'dedir.
