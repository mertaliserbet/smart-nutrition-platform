# 12 — Güncel sorumluluklar, özellik durumu ve açık kararlar

Kaynak incelemesi: **22.11.2026**, yerel kod tabanı **`4f160b3`**. Güncel uygulama ile geçmiş teslim beyanları ayrılmıştır. Bu belge güncellemesinde servis/test/cihaz çalıştırılmadı, uygulama DB'sine bağlanılmadı. Özellik için “kod mevcut”, “geçmişte test edildiği raporlanmış” ve “yeni ortamda doğrulanmış” farklı kanıtlardır.

## Görev sahipliği ve çalışma ilkeleri

Mert ağırlıklı Flutter/mobil, Uğur ağırlıklı React/web geliştirir. **Backend/API/DB/migration/test/entegrasyonu ikisi de üstlenebilir**, önceki geliştiricinin modülü kalıcı özel alan değildir. Sorumluluk güncel görev ve izinli dosyalara göre belirlenir. AI ortaktır; her işte tek değişiklik sorumlusu atanır.

Güncel yazma/Git/koordinasyon kurallarının tek kaynağı [AGENTS.md](../AGENTS.md)'dir. Aynı checkout'a iki oturum yazmaz; aynı dosya/özellik ve özellikle AppDbContext, migration, snapshot ve ortak sözleşmede koordinasyonsuz paralel yazma olmaz. Görev devrinde dosya listesi, mevcut diff, bağımlılık ve doğrulama sınırı paylaşılır.

Mert'in yerel main, Uğur'un fork/feature branch → ortak main PR modeli korunur; kullanıcı talimatı olmadan Git işlemi veya belge değişikliği yapılmaz. Eski plandaki kalıcı “backend/docs yalnız Uğur” ve herkese zorunlu feature branch hükümleri geçerli çalışma kuralı değildir. M1–M6/U1–U6 tarihsel görev kimlikleridir; yeni işe başlamanın zorunlu şartı değildir.

Sözleşme değişikliği diğer geliştiriciye method/route/DTO, profil/yetki, hata, migration, istemci etkisi ve test durumu ile aktarılır. Önceki API'yi kullanan istemciyle uyum kontrol edilmeden yeni kategori/açılım entegrasyonu tamamlandı sayılmaz. Bayrak kapatmak eski istemciye dönüşü tek başına güvenli yapmaz; bilinmeyen kategori satırları da değerlendirilir.

## Uygulama ve doğrulama matrisi

| Alan | Mevcut kod | Test/kanıt düzeyi ve eksik doğrulama |
|---|---|---|
| Hesap/e-posta/JWT/refresh/W2/Admin MFA | ASP.NET Core, Flutter ve React temel oturum akışları mevcut | Auth/PostgreSQL/Mailpit ve istemci testleri var; tarihsel U5/U6 regresyon raporu mevcut. Üretim teslim/anahtar/proxy ve mobil platform doğrulaması ayrı |
| Parola sıfırlama | Backend, React fragment bağlantısı ve Flutter manuel kod formları mevcut; Admin MFA korunuyor | U5/U6 geçmiş raporu; M5 testleri/live probe kodu 4f160b3'te mevcut, bu görevde koşulmadı |
| Uzman/ilişki/izin | Aynı hesapla başvurunun backend desteği, onay, arama/davet, kabul/red/sonlandırma ve beş kategori mevcut | API/istemci testleri var; mobil Profil başvuru/durum ve onaylı panel geçişi geliştirilip doğrulanmadı. Yeni ortamın açılım/DB sürümü kontrol edilmedi |
| Program/sürüm | Backend ve React oluşturma/düzenleme/aktivasyon/arşiv/geçmiş; mobil aktif program okuma | Sahiplik/tek aktif/snapshot testleri var. Tam kişisel mobil editör veya genel atomik replace yok |
| Öğün ve yorum | Manuel CRUD, uzman okuma, mobil/web yorum ve tek düzey yanıt | API/DOM/widget testleri var; bildirim teslimi ve yorum düzenleme/silme/moderasyon yok |
| Su | Manuel CRUD/toplam, uzman su liste/toplam/geçmişi, Flutter beşinci kategori | API/React/mobil testleri var; WaterLogsEnabled kaynak varsayılanı false, gerçek ortam açılımı doğrulanmadı |
| Ölçüm/gelişim | Kilo/bel/kalça/göğüs/yağ CRUD, mobil ve web grafik | API/istemci testleri var; yeni izin oluşturma/açma Development şartına bağlı |
| Kişisel hedef | Beş nullable hedef, GET/PATCH upsert ve mobil düzenleme/gösterim | API/widget testleri var; otomatik öneri hesabı ve kişisel hedefin uzman paylaşımı yok |
| Günlük program–tüketim | Seçilen sürüm/gün, bilinen toplam/eksik değer ve kontrollü kcal farkı; mobil/web görünüm | API/istemci testleri var; genel uyum yüzdesi ve geçmiş aktivasyon çizelgesi yok |
| Görev | Backend, React atama/takip, Flutter liste/durum/geçmiş ve kategori | Snapshot/sürüm/yetki testleri, U6 web/API raporu ve mobil live probe var; hatırlatma gönderimi yok |
| Sağlık platformu ve API | Native okuma, açık ön plan upsert, bağlantı/receipt/özet ve manuel aktivite API'si | Sentetik reader/sync/API testleri ve probe dosyaları var. Fiziksel Android/HealthKit, gerçek sensör/native ID ve OS kapsamı bu incelemede doğrulanmadı |
| Manuel aktivite mobil formu | Ana sayfa hızlı işlem hâlâ önizleme | API varlığı UI teslimi değildir; gerçek manuel form/gelişmiş aktivite geçmişi eksik |
| Besin kataloğu/tarif/AI yemek | Onaylı kapsam, çalışan entity/servis/controller yok | Sağlayıcı/lisans/model/dosya/onay tasarımı ve uygulama gerekli |
| Manuel tahlil/OCR/LabInsight | Onaylı kapsam; mobil/web tahlil önizlemesi gerçek kayıt değil | Henüz DB/API yok; manuel temel → onaylı OCR; bilimsel ML opsiyonel |
| Bildirim/PDF/geniş Admin/Audit | Onaylı kapsam; yalnız uzman onayı audit'i ve uzman Admin ekranı mevcut | Teslim/dosya/moderasyon/operasyon şemaları ve uygulama açık |
| Tasarım | İki tema ve başlangıç tokenları kaynakta var | Nihai marka, tam erişilebilirlik ve bütün platform/görsel doğrulama ayrıca gerekli |

### Geçmiş test raporlarının sınırı

20.11.2026 tarihli U5/U6 kaydı, kod commit'i `1573fdd` ile gelen backend/React/gerçek Edge HTTPS doğrulamalarını raporlar; ortak main'e alınma commit'i `f4fcd50`dır. Ayrıntı ve komutlar [tarihsel koordinasyon kaydında](archive/2026-11-22/PARALLEL_WORK_PLAN_2026-11-19.md) korunur. React DOM, API/PostgreSQL ve gerçek Edge testleri ayrı kapsamlardır; danışan adımları API olabilir, Flutter/Health Connect/HealthKit cihaz testi değildir.

21.11.2026 `4f160b3` M5/M6 commit'i mobil reset, API/widget testleri ve live/device probe kaynakları içerir. Commit başlığı veya probe varlığı tek başına başarılı koşu kanıtı değildir; kullanılabilir komut/ortam/çıktı bulunmadan bütün mobil regresyon “doğrulandı” sayılmaz.

Geçmiş sayımlar README'ye güncel sonuç olarak taşınmamıştır. Bu görevde build/lint/unit/integration/E2E veya migration komutu çalıştırılmadı. Doküman/bağlantı kontrolleri uygulama testlerinin yerine geçmez.

## Kesinleşmiş 22 kararın korunması

Bu kayıt ürün kararlarını korur; ayrıntı kendi ana belgesindedir. Son kullanıcı talimatıyla 21'in kişi bazlı sahiplik yorumu güncellenmiştir.

| No | Korunan karar | Ana kaynak |
|---|---|---|
| 1 | Tek aktif diyetisyen ve ilişki geçmişi | 01, 05/06 |
| 2 | Mobil/web başvuru ve aynı hesapta çift profil; Admin doğrulama, Flutter V1 danışan kullanımı ve uzman yönetimi web | 01, 07/08 |
| 3 | Arama/davet ve karşılıklı onay | 01, 06 |
| 4 | Tek aktif program, alternatifler ve sürüm geçmişi | 01, 05/06 |
| 5 | Diyetisyensiz kişisel hedef/program | 01, 06 |
| 6 | Atanmış programı yalnız yetkili uzman düzenler; tüketim serbest | 01, 06 |
| 7 | İlk sürüm öğün yorum/cevap/bildirim; sohbet sonraki sürüm | 01 |
| 8 | Kategori izni ve tahlilde ayrıca açık onay | 11 |
| 9 | Fotoğraf/galeri tahmini ve kullanıcı onayı; sürekli video sonraki aşama | 10 |
| 10 | Hibrit besin kaynağı, uygun hazır model/API ve özel tarif | 10 |
| 11 | Önce manuel tahlil, ardından kullanıcı onaylı PDF/fotoğraf OCR | 10 |
| 12 | Referans karşılaştırması, doğrulanabilir ML opsiyonel, tanı/tedavi yok | 10 |
| 13 | Health Connect/HealthKit ve kaynak/tekilleştirme | 20 |
| 14 | Düzenlenebilir kişisel kalori/makro/su; uzman hedefi salt okunur | 01, 06 |
| 15 | Kilo/vücut ölçümleri, kaynak/geçmiş/grafik | 01, 07/08 |
| 16 | Görev/son tarih/durum ve isteğe bağlı hatırlatma tercihi | 01, 06 |
| 17 | Yetkili analiz/grafik, program uyumu ve PDF raporları | 01 |
| 18 | Admin doğrulama/kullanıcı/şikâyet/katalog/audit/sistem; varsayılan sağlık engeli | 01, 11 |
| 19 | E-posta/şifre/doğrulama/reset/güvenli oturum ve zorunlu Admin MFA | 06, 11 |
| 20 | Flutter, React, ASP.NET Core, PostgreSQL; gerektiğinde Python/FastAPI | 03 |
| 21 | Mobil/web ağırlıkları, backend ve ortak işlerde görev bazlı sorumluluk | AGENTS.md, bu belgenin ilk bölümü |
| 22 | Ortak premium UI/UX ve açık/koyu tema | 09 |

Sonraki ortak onaylı paketlerin güncel sonucu 04/05/06'da yer alır: kayıt/doğrulama/JWT/me/W2, uzman/MFA ve çift profil, ilişki/paylaşım, program sürümleri, refresh/reset güvenlik sürümü, manuel kayıtlar/hedefler, yorum, ölçüm, günlük karşılaştırma, görev, sağlık aktarımı ve su paylaşımı. Önceki proposal onayı, bütün gelecekteki şemaları onaylamaz.

## Kesinleşmiş çift profil ve mobil yönlendirme kararı

- Kullanıcı mobilde danışan olarak kayıt olur ve daha sonra mevcut hesabıyla diyetisyen başvurusu yapabilir. Tek User altında ClientProfile ve DietitianProfile birlikte bulunur; ikinci hesap oluşturulmaz. Mevcut backend başvuruda onaysız uzman profili oluşturur; Admin onayı uzman yetkisini açar. Başvuru/onay danışan profilini, öğünleri, ölçümleri, diğer kişisel kayıtları veya temel hesap rolünü değiştirmez.
- **Flutter V1 yalnız danışan kullanımına yöneliktir.** Onaylı diyetisyen mobilde kendi danışan özelliklerini kullanmaya devam eder; mobil diyetisyen yönetim paneli geliştirilmez.
- Mobil **Profil**, mevcut hesapla başvuru girişini ve güncel başvuru/onay durumunu gösterir. Onaylı diyetisyende **“Diyetisyen Paneline Git”** seçeneği bulunur.
- Bu seçenek güvenilir HTTPS web adresindeki çalışma alanını harici tarayıcıda açar. Web oturumu yoksa aynı e-posta/şifreyle ayrıca giriş yapılır; mobil JWT/refresh token web adresine, URL'ye veya tarayıcıya aktarılmaz. Yeni oturum aktarımı tanımlanmaz.
- Aynı kullanıcı, onaylı diyetisyen profiliyle web çalışma alanına erişir; yeni hesap gerekmez. Bekleyen/onaysız kullanıcı erişemez. Mevcut backend başvuru ve yetkilendirmesi ile [04](04_NAMING_CONVENTIONS.md)/[05](05_DATA_DICTIONARY.md)/[06](06_API_CONTRACT.md) sözleşmeleri korunur.

**Uygulama durumu:** karar kesindir; mobil Profil başvuru erişimi, durum gösterimi ve onaylı panel seçeneği geliştirilip doğrulanmış değildir. Ayrıntılı hedef davranış [01](01_PROJECT_SCOPE.md), mobil kaynak durumu [07](07_MOBILE_SPEC.md), web oturumu/erişimi [08](08_WEB_SPEC.md)'dedir.

## Açık kararlar ve somut uyuşmazlıklar

| Konu | Doğrulanan sınır / gereken karar |
|---|---|
| Mobil Profil akışının uygulanması | Ürün kararı kesindir; uygulama eksiktir. API ve eski DietitianAccountPage mevcut; aktif AuthGate /dietitian-account yolunu WebPanelPage'e çeviriyor, ProfilePage'de başvuru bağlantısı yok. React başvuru metni kullanıcıyı mobil Profil'e yönlendiriyor. Profil başvuru/durum ve onaylı panel geçişi ayrı kod görevi ve uygulama doğrulaması gerektirir; mevcut UI tamamlanmış sayılmaz |
| Ölçüm izninin üretim açılımı | CategoryEnabled body_measurements için hem Development hem flag istiyor. Üretimde yeni POST/PATCH true açılamıyor; mevcut izin okuması/geri çekmesi farklıdır. Kısıt kendi başına kaldırılmadı; üretim kapsamı ortak karar ister |
| İstek doğrulama ortaklığı | Eski controller'lar yalnız query anahtarlarını/pozitif sayfayı kontrol ederken yeniler tekrar/100 üst sınırını da denetler; register gibi eski uçlarda query guard'ı yok. Global katı kural varsayılmadı, yeni kod/limit kararı verilmedi |
| Hedef/program geçişi | Programsız hedef saklama ve içerik sürümleri kapandı; güvenli otomatik öneri, program makro hedefleri, genel atomik replace ve sahiplikler arası geçiş açık |
| Gün ve uyum | Su/karşılaştırma/sağlık için somut gün sınırı var; tüm uygulamanın kayıtlı danışan saat dilimi, geçmiş aktivasyon çizelgesi ve genel uyum formülü yok |
| Cihaz kapsamı | Gerçek Android/iOS izin/sensör/cihaz/OS testi, kararlı native ID ve destek listesi gerekli. Otomatik arka plan sync ve native silme delta entegrasyonu uygulanmış değil; eksik pencere silme sayılmaz |
| Uzman yaşam döngüsü/profil | Mesleki açıklama ve onay mevcut; belge yükleme, doğrulama ölçütleri, ret/yeniden başvuru/geri alma, genel profil düzenleme ve mobil MFA açık |
| Tarif/katalog/AI | Kaynak/lisans/öncelik, tarif bileşen/porsiyon/görünürlük/geçmiş, model/validasyon, dosya ve kullanıcı onayı kanıtı açık; 10 |
| Laboratuvar/OCR | Test kodu/birim dönüşümü/referans doğrulama, tam CRUD/alt kayıt/OCR taslak ve onay, LabInsight biçimi/eski sonuç davranışı açık |
| İletişim ve PDF | Yorum düzenleme/silme/moderasyon, bildirim/hatırlatma kanalı/teslimi, rapor DTO/dosya yetkisi ve PDF endpointi açık |
| Güvenlik ve yayın | Retention/silme/yedekten silme/veri hakları/ConsentRecord kanıtı, üretim SMTP/kalıcı teslim, ortak limit/proxy/anahtar/audit/izleme ve dağıtım açık; mevcut parola politikasının güçlendirilmesi/sızmış parola listesi kaynağı ayrı değerlendirme önerisi, mevcut kuralı değiştirmez; 11 |
| Sayısal ve istemci politikaları | Genel precision/yuvarlama, eski endpointlere ortak metin/pagination/idempotency politikası, kalıcı tema tercihi/nihai marka, ülke-dil/ücretli model açık |

Kod–onaylı ürün kararı farkları bu belgede bulgudur; kapsamdan çıkarma veya yeni davranış onayı değildir. Bağımsız izinli işler ilerleyebilir; çelişkili şema varsayılarak üretilmez.

## Belge birleştirme ve devir

Aktif ana belge sayısı 12'dir. 02'nin ürün akışları 01'e, yetkileri 06/11'e; 21'in su veri/API/güvenlik kuralları 05/06/11'e; paralel planın geçerli çalışma ilkeleri bu belgeye aktarılmıştır. 13–19'un onaylı ad/şema/HTTP kuralları 04/05/06/11'dedir; eski teklif seçenekleri güncel teknik sözleşme değildir.

Tüm 22 özgün docs belgesi ve önceki kök README [arşivde](archive/README.md) korunur. Arşivdeki test/teslim/PR ve hazırlık notları kendi tarihlerini anlatır; güncel uygulama durumu olarak kullanılmaz. Kalan ürün gereksinimleri aktif ana belgelerde korunmuştur.

Sonraki önerilen tek adım: mobil Profil'de aynı hesapla başvuru, durum gösterimi ve onaylı diyetisyenin web paneline geçişi için ayrı, dosya kapsamı belirli bir kod görevi açılması.
