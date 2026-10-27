# 01 — Proje kapsamı ve ürün vizyonu

**Sürüm:** DOCS-V1 · **Durum:** `12_TEAM_PLAN_AND_DECISIONS.md` içindeki 22 karar doğrultusunda ürün kapsamı onaylı; ayrıntılı şema, uygulama ve yayın takvimi kararları açık. Eski fitness projesinden hiçbir kod, şema veya ekran devralınmaz.

## Ürün tanımı

Diyetisyen–danışan ilişkisinin merkezde olduğu, beslenme verisi takibini ve kanıt düzeyi açık AI destekli analizleri birleştiren **sıfırdan geliştirilecek** mobil + web + API sistemi. Danışan diyetisyensiz de günlük kayıt tutabilir, kişisel hedef ve beslenme programını oluşturabilir. Diyetisyenle bağlandığında yalnız izin verdiği kategorilerdeki veriler paylaşılır; tahliller ayrıca açık onay gerektirir.

Danışanın en fazla bir aktif diyetisyeni ve kişisel/atanmış programlar toplamında en fazla bir aktif beslenme programı olur; ilişki ve program sürüm geçmişi korunur. Ürün metnindeki “plan/program” aynı kanonik `NutritionPlan` kavramıdır. Gerçek tüketim `MealLog` olarak serbestçe kaydedilir; program tavsiyesiyle karıştırılmaz.

### Mobil, web, backend ve AI sınırları

| Bileşen | Onaylı teknoloji ve sorumluluk |
|---|---|
| Mobil | **Flutter/Dart**; danışanın günlük kayıt, kişisel/atanmış program, hedef, görev, yorum/cevap, paylaşım ve gelişim deneyimi; kamera/galeri, tahlil girişi ve izinli sağlık platformu entegrasyonu. Diyetisyen mobil üzerinden de başvurabilir; bu, ilk sürümde mobil yönetim paneli taahhüdü değildir |
| Web | **React/TypeScript**; diyetisyenin danışan takibi, program yönetimi, yorumlar, görevler, analiz/grafikler ve PDF raporları; Admin'in ayrı operasyon ekranları. **İlk sürüm yönetim paneli webdedir** |
| Backend ve veri | **ASP.NET Core/C# + PostgreSQL**; mobil/web için ortak versiyonlu API, kimlik/güvenli oturum, kaynak ve kategori bazlı yetki, tek aktif kuralları, geçmiş, onay/rıza, kaynak/tekilleştirme ve audit. İş kuralları sunucudadır; istemciler DB'ye doğrudan bağlanmaz |
| AI | İhtiyaç olduğunda **Python/FastAPI**; uygun hazır model/API'lerle fotoğraftan besin/kalori/makro tahmini ve açıklayıcı tahlil değerlendirmesi. Özel model eğitimi veya doğruluk oranı taahhüdü yoktur; model/veri/sağlayıcı seçimi ve validasyon açıktır. Manuel kayıt AI başarısına bağlı değildir |

Mert mobil ve ilgili API'lerden; Uğur web, Auth ve ilgili API'lerden sorumludur; AI ortaktır. 27.10.2026 kullanıcı kararıyla ortak uzak depo `mertaliserbet/smart-nutrition-platform`, ortak çalışma dalı `main`dir; kullanıcı açıkça istemedikçe yeni dal veya PR açılmaz. İki geliştirici kendi yerel checkout'unda çalışır ve aynı dosyaya paralel yazmaz. Ortak sözleşmeler iki tarafın onayını gerektirir. Ayrıntılı Git akışı ve görev/modül liderliği `12`de izlenir. Kavram adları `04`, alan/tip/ilişkiler `05`, HTTP/JSON karşılıkları `06` ile belirlenir; bu kapsam belgesi yeni model veya endpoint tanımlamaz.

## Kullanıcılar ve temel değer önerisi

- **Danışan (`Client`)**: öğün, su, ölçüm, aktivite ve tahlil kayıtlarını yönetir; kişisel hedef/programını oluşturur, atanmış programını ve gelişimini görür. Kişisel kalori/makro/su önerilerini düzenleyebilir; diyetisyen programı/hedefleri kendisine salt okunurdur. Gerçek tüketimini programdan bağımsız kaydeder ve karşılaştırır; AI/OCR çıktılarını kontrol edip onaylar, öğün yorumlarına cevap verir, atanan görevlerini izler ve kategori paylaşım izinlerini yönetir. Görev durumunu değiştirme yetkileri ile yorum düzenleme/silme ayrıntıları ortak sözleşmede açıktır.
- **Diyetisyen (`Dietitian`)**: mobil veya web üzerinden başvurur, Admin tarafından doğrulanır. Aktif ilişkili ve erişim izni olan danışanını izler; kendi atadığı programı düzenler, öğün alternatifleri ve sürüm geçmişiyle yönetir; yorum/cevap, görev/son tarih, grafik, program uyumu ve izinli PDF raporlarıyla takip yapar. Klinik kararı kendisi verir; uygulama tanı/tedavi üretmez.
- **Yönetici (`Admin`)**: uzman doğrulama, kullanıcılar, şikâyetler, besin kataloğu, Audit Log (`AuditEvent`) ve sistem durumunu yönetir. Özel sağlık verilerine varsayılan erişimi yoktur; MFA zorunludur.

## Özellikler ve aşamalar

**İlk sürüm koşulları:** Yönetim paneli webde olur; öğün yorumları, cevaplar ve bildirimler ilk sürümde bulunur (`12`, karar 2 ve 7). **MVP önceliği** mevcut temel ürün döngüsünü gösterir: danışan manuel kayıt tutar → diyetisyen izinli veriyi görür → program atar → danışan mobilde görür. Bu öncelik tüm onaylı özelliklerin aynı sürümde tamamlanacağı taahhüdü değildir.

**Onaylı / takvimi açık** özellik kapsamdan çıkarılmış veya yalnız araştırma önerisi değildir; sprint/yayın sırası ayrıca planlanır. **Sonraki sürüm** ve **opsiyonel araştırma** olarak belirtilenler ilk sürüm koşulu sayılmaz. Teknik ayrıntının açık olması onaylı ürün kararını geri almaz.

| Başlık | Onaylı kapsam | Aşama / açık karar |
|---|---|---|
| Hesap (19) | E-posta/şifre, e-posta doğrulama, şifre sıfırlama, profil ve güvenli oturum; Admin MFA | **MVP önceliği**; kayıt/e-posta doğrulama, 15 dakikalık JWT login ve `GET /auth/me` kendi hesap özeti `06/12`de onaylı. Refresh/logout/iptal, cookie/istemci saklama, profil düzenleme/uzman profili ve MFA ayrıntıları açık |
| Uzman ve ilişki (1–3) | Mobil/web başvuru, Admin doğrulaması; diyetisyen arama ve davet kodu, karşılıklı onay; en fazla bir aktif diyetisyen, geçmiş korunur | **İlk sürüm:** yönetim paneli webde. Başvuru belgeleri ve davet kodunun teknik yapısı açık; çoklu aktif diyetisyen mevcut kapsamda yok |
| Beslenme programı (4–6) | Kişisel veya diyetisyen tarafından atanan `NutritionPlan`; toplamda tek aktif program; öğün alternatifleri ve sürüm geçmişi. Diyetisyen programını yalnız yetkili diyetisyen düzenler; gerçek tüketim serbestçe kaydedilip karşılaştırılır | Temel oluşturma/atama/görüntüleme **MVP önceliği**; alternatif/sürüm yapısı, program geçişi ve uyum hesabı ayrıntıları açık |
| Öğün | Manuel öğün/besin ve miktar girişi, kalori/makro, düzeltme/silme; plan dışında tüketim de kaydedilir | **MVP önceliği**; gram/adet dönüşümü ayrıntısı açık. Barkod önceki bir geliştirme önerisidir, teslimi onaylanmış kapsam değildir |
| Besin kaynağı ve tarif (10) | Hibrit besin veritabanı, uygun hazır modeller/API'ler ve özel tarifler (`Recipe`); kaynak/lisans ve belirsizlik izlenir | **Onaylı / takvimi açık**; sağlayıcı, katalog birleştirme, tarif bileşen/porsiyon/görünürlük ayrıntıları açık |
| Görsel AI (9) | Fotoğraf/kamera veya galeriden besin tanıma; porsiyon, kalori ve makro **tahminini** kullanıcı kontrol eder, gerektiğinde düzeltir ve onaylar; başarısızlıkta manuel kayıt sürer | Fotoğraf akışı **MVP önceliği**; sürekli kamera/video analizi **sonraki sürüm/araştırma**. Model performansı ve gelişmiş porsiyon kestirimi taahhüt edilmez |
| Su ve kişisel hedefler (14) | Manuel su kaydı/günlük toplam; kişisel kalori/makro/su önerileri düzenlenebilir, diyetisyen hedefleri danışana salt okunur | Temel su/hedef takibi **MVP önceliği**; öneri hesabı ve programsız hedeflerin saklanması açık. Kişiselleştirilmiş su hatırlatmaları önceki öneridir; görev hatırlatmalarıyla aynı kapsam sayılmaz |
| Ölçüm (15) | Kilo ve vücut ölçümleri; kaynak, zaman, geçmiş ve grafikler; gereksiz ölçüm zorunluluğu yok | Temel ölçüm takibi **MVP önceliği**; vücut kompozisyon cihaz entegrasyonları ayrıca değerlendirilir |
| Aktivite (13) | Manuel yürüyüş/koşu vb.; Health Connect/HealthKit ile izinli adım, mesafe, egzersiz, süre, aktif kalori ve nabız; kaynak ve tekilleştirme | Manuel kayıt **MVP önceliği**; platform senkronizasyonu onaylı sonraki geliştirme aşamasıdır, yayın takvimi açık. Tüm akıllı saatlerin doğrudan desteği garanti değildir |
| Diyetisyen ve görevler (16) | İzinli danışan listesi/kayıt izleme, `ClientTask` atama, son tarih, durum ve isteğe bağlı hatırlatmalar | Danışan izleme **MVP önceliği**; görevler **onaylı / takvimi açık**. Durum geçişleri, son tarih ve hatırlatma ayrıntıları açık |
| İletişim ve bildirim (7) | Öğün yorumları, cevaplar, bunlara ilişkin bildirimler ve sistem içi kritik olay bildirimleri; ilişki/paylaşım yetkileri geçerli | **İlk sürüm koşulu**; ayrı sohbet **sonraki sürümde**. Push/e-posta veya başka teslim kanalı, anlık iletişim altyapısı ve moderasyon açık |
| Paylaşım (8) | Kategori bazlı `DataSharingPermission`, tahliller için ayrıca açık onay/`ConsentRecord`; izin geri çekilince diyetisyenin yeni erişimi kesilir | Tüm ilgili akışların **temel yetki koşulu**; kategori ve onay kapsam kodları açık. Aktif ilişki tek başına tüm veriyi açmaz |
| Laboratuvar (11–12) | `LabReport`/`LabResult` için manuel değer, birim, tarih ve laboratuvar referansı; açıklayıcı `LabInsight`. Ardından kullanıcı onaylı PDF/fotoğraf OCR | Manuel giriş/referans karşılaştırması **MVP önceliği**; OCR onaylı sonraki geliştirme aşaması, yayın takvimi açık. Doğrulanabilir ML **opsiyonel araştırma**; tanı/tedavi yok |
| Gelişim ve raporlama (17) | Günlük/haftalık trendler, diyetisyen analiz/grafikleri, program uyumu ve izinli PDF raporları | Temel trendler **MVP önceliği**; gelişmiş analiz/PDF raporları **onaylı / takvimi açık**. Uyum yöntemi ve rapor içeriği açık; kişiselleştirilmiş öngörüler önceki araştırma önerisidir |
| Admin (18) | Doğrulama, kullanıcılar, şikâyetler, besin kataloğu, Audit Log ve sistem durumu; sağlık verisine varsayılan erişim yok | **İlk sürüm:** panel webde. İdari süreç ve ekranların ayrıntılı teslim sırası açık; yönetim yetkisi sağlık kaydı yetkisi değildir |
| Tasarım (22) | Premium, erişilebilir UI/UX; mobil/web ortak tasarım tokenları ve **açık/koyu tema** | İki tema ve ortak görsel dil onaylıdır; renk, font, token değerleri ve ekran tasarımları açık |

**MVP** mutlak teslim taahhüdü değildir; 2 kişilik kapasite ve dönem süresi için aşama aşama doğrulanacak kapsamdır.

Önceki belgede geçen randevu, ücretlendirme, barkod, vücut kompozisyon entegrasyonları, kişiselleştirilmiş su hatırlatmaları ve öngörüler bu 22 kararla ayrıca onaylanmış teslimler değildir; sonraki kapsam değerlendirmesinde öneri/açık karar olarak korunur. Ayrı sohbet ve sürekli kamera analizi ise açıkça sonraki aşamaya bırakılmıştır. Gerçek kullanıcıya açılma veya mağaza yayını, MVP demosundan ayrı olarak `11_SECURITY_AND_RELEASE.md` kapısını gerektirir.

## Ürün ilkeleri

1. Beslenme ve diyetisyen merkezde; antrenör, spor salonu, egzersiz programı yok. Aktivite bilgisi beslenme ve sağlık takibine yardımcı veri.
2. Görsel kalori ve makro değerleri **yaklaşık**; kayda geçmeden kullanıcı doğrulaması gerekir.
3. Laboratuvar sonuçlarında “iyisin/kötüsün” veya hastalık tanısı yerine ölçüm, birim, laboratuvar aralığı, zaman ve açıklama verilir. Hekim/diyetisyen görüşü gerektiği vurgulanır.
4. Sağlık verilerine erişim aktif ilişki, kategori bazlı kullanıcı izni, tahlillerde ayrıca açık onay, en az ayrıcalık ve denetim izleri ile sağlanır. İlişki/izin bitince diyetisyenin yeni erişimi kesilir; danışanın kendi verisine erişimi diyetisyen bağlantısına bağlı değildir. Admin sağlık verisini varsayılan göremez.
5. Mobil ve web, aynı sözleşmeli API üzerinden çalışır; rol, kaynak sahipliği ve tek aktif kuralları her işlemde sunucuda uygulanır. `04/05/06` ad, veri ve entegrasyon sözleşmeleridir; açık şema parçaları uydurulmaz.
6. Tasarım; hızlı, okunaklı, erişilebilir, güven veren ve ürün olarak pazarlanabilir olmalı; ortak tokenlarla açık/koyu tema desteklenir.
7. Kişisel ve diyetisyen programı aynı kavramı kullanır; toplamda tek aktif program vardır. Geçmiş ilişki/sürümleri korumak eski diyetisyene erişim veya süresiz veri saklama hakkı vermez.
8. AI/OCR, kullanıcının kontrol ve onayının yerine geçmez. Manuel kayıt kullanılabilir kalır; kaynak, tarih, birim, tahmin ve bilinmeyen değerler görünürdür. Aktivite/cihaz verisi çift sayılmaz.
9. Gerçek sağlık verisi seed/test/log içinde kullanılmaz; demo sentetik veriyle hazırlanır. Veri indirme/silme, saklama, üçüncü taraf aktarımı, audit ve gerçek yayın koşulları `11`e göre tamamlanır.

## MVP başarı kriterleri (hedef; doğrulanacak)

- Danışan kendi öğününü kaydedebilir, düzeltebilir ve günlük toplamını görebilir.
- Danışan diyetisyen bağlantısı olmadan kendi hedef/programını oluşturabilir; atanmış programı/hedefleri değiştirmeden gerçek tüketimini kaydedip karşılaştırabilir.
- Diyetisyen arama/bağlantı akışında karşılıklı onay ve en fazla bir aktif ilişki korunur; diyetisyen yalnız izinli danışan verisini görür ve yetkili program ataması yapar. Kişisel/atanmış programlar toplamında ikinci aktif program oluşmaz.
- İlk sürüm web yönetim paneli ve öğün yorum/cevap/bildirim akışı çalışır; kanal seçimi gerekli teknik onayla tamamlanır.
- Fotoğraf analizi tahmin ve belirsizlik sunar; kullanıcı kontrol/onayı olmadan kayıt oluşmaz. OCR aşamasında da doğrulanmamış çıkarım kalıcı tahlil/değerlendirmeye dönüşmez.
- Lab verileri doğru birim/referans olmadan klinik bayrak üretmez.
- Kullanıcılar başka danışanın özel sağlık verisine erişemez; kategori izni/tahlil onayı geri çekildiğinde diyetisyenin yeni erişimi kesilir. Admin yönetim oturumu MFA gerektirir ve varsayılan sağlık verisi erişimi sağlamaz.
- En az bir mobil-web-backend uçtan uca test akışı çalışır.
- Aşamaya dahil edilen sürüm/alternatif, görev, cihaz senkronizasyonu ve PDF raporları kendi veri bütünlüğü, izin ve kaynak koşullarıyla doğrulanır; onaylı kapsamı veya belgeyi güncellemek bu özelliklerin uygulanıp test edildiği anlamına gelmez.

## Kesinleşmesi gerekenler

Tek aktif diyetisyen/program, kişisel program, uzmanı Admin'in doğrulaması, kategori paylaşımı/tahlil açık onayı, teknoloji seçimi ve açık/koyu tema **onaylıdır**. Açık olanlar bu kararların uygulanma ayrıntılarıdır:

- Onaylı özelliklerin sprint/yayın takvimi; ilk sürüm koşulları korunarak kapasite planı. Android/iOS ilk önceliği, ülke/dil kapsamı ve ücretli model.
- Başvuru belgeleri/doğrulama süreci, davet kodu yapısı, çoklu rol/profil; kişisel/atanmış program geçişi ve ilişki bittikten sonraki program davranışı.
- Program sürüm/alternatif ve tarif bileşen yapıları, kişisel makro/programsız hedef alanları, güvenli öneri hesabı ve program uyum yöntemi; yorum/cevap moderasyonu, görev durum/son tarih/hatırlatma ve bildirim kanalları.
- Paylaşım kategorileri, tahlil açık onayının kapsamı/kanıtı, Auth refresh/logout/iptal, cookie/istemci saklama ve MFA yöntemi, saklama/silme/audit; gizlilik ve gerçek yayın için `11`deki kontroller. Onaylı 15 dakikalık JWT access kararı açık seçim sayılmaz.
- Hibrit katalog sağlayıcıları/lisansları, hazır model/API ve veri validasyonu; tahlil test kodları, birim dönüşümleri, OCR taslağı/onay kaydı ve opsiyonel ML'nin bilimsel koşulları.
- Health Connect/HealthKit cihaz/OS desteği ve veri şemaları, aktif/toplam enerji ayrımı, manuel/cihaz örtüşmesi ve tekilleştirme; sayısal hassasiyet, saat dilimi, PDF içeriği ve dosya erişimi.
- Renk paleti, font, token değerleri, navigasyon ve ekran onayı; dağıtım sağlayıcısı, paket sürümleri ve maliyet.

Karar kaydı `12`de, ayrıntılı şema ve HTTP açıkları `04/05/06`da izlenir. Ürün kapsamının onaylanması bu açıkları kendiliğinden kapatmaz; ortak sözleşme değişiklikleri iki geliştiricinin onayıyla ele alınır.
