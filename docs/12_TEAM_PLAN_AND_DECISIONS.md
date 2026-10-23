# 12 — Ekip görevleri, Codex koordinasyonu, yol haritası ve kararlar

**Repo:** `smart-nutrition-platform` · **Başlangıç:** 15.10.2026 · **Doküman sürümü:** `DOCS-V1` · **Karar güncellemesi:** 22.10.2026 · **Tutarlılık incelemesi:** 24.10.2026 · **Durum:** aşağıdaki 22 ürün, teknoloji ve çalışma kararı onaylı; ayrıntılı teknik kararlar açık.

Bu güncelleme mevcut temel ilkeleri korur; önceki açık kararların kesinleşen kısımlarını onaylı duruma taşır. Ürün kararının onaylanması, henüz uyarlanmamış veri şeması veya API tasarımının da onaylandığı anlamına gelmez. `04/05/06` kanonik ad, alan ve endpoint otoritesi olmaya devam eder; bu kararlarla çelişen veya eksik kalan sözleşmeler uygulama öncesinde ortak onayla güncellenmelidir. Bu dosya yeni entity, JSON alanı veya endpoint tanımlamaz.

## Görev dağılımı — onaylı sorumluluklar

| Geliştirici | Ana sorumluluk | Sahiplik sınırı |
|---|---|---|
| **Mert Ali** | **Mobil uygulama**, kamera/görsel işleme entegrasyonu ve ilgili API'ler | Danışan mobil akışları, mobil diyetisyen başvurusu, mobil ekran/servisler ve ilgili danışan endpointleri; mobil auth UI/entegrasyonu |
| **Uğur Çetin** | **Web uygulaması**, diyetisyen/admin paneli, **Auth** ve ilgili API'ler | Web ekran/servisleri; kimlik ve güvenli oturum backend'i; diyetisyen/plan/admin iş akışları ve ilgili endpointler |
| **Ortak** | Gıda görüntü analizi, kalori/porsiyon modeli, kan/vitamin-laboratuvar AI/ML, ortak sözleşmeler, entegrasyon ve güvenlik | Her ortak modül için tek PR lideri atanır; paralel çakışan kod yazılmaz |

**Onaylı sınır:** Auth backend lideri Uğur, mobil auth UI/entegrasyonu Mert'tir; JWT gibi uygulama ayrıntıları ayrıca kararlaştırılır. Mevcut ayrıntılı modül paylaşımı önerisi korunur: `meal-logs`, `water-logs`, `activity-logs` backend liderliği Mert; `dietitian-relationships` ve `nutrition-plans` backend liderliği Uğur. Bu önerinin görev bazlı sınırları, özellikle kişisel program gibi iki tarafı etkileyen akışlar, sprint planında teyit edilir. Ortak AI endpointlerinin lideri her sprintte belirlenir. İkisi aynı C# dosyalarını paralel düzenlemez.

## Kritik: aynı isimler için ekip protokolü

1. `docs/04_NAMING_CONVENTIONS.md` → tek kavram ve ad sözlüğü.
2. `docs/05_DATA_DICTIONARY.md` → entity/alan/tip sözleşmesi.
3. `docs/06_API_CONTRACT.md` → URI/DTO/JSON sözleşmesi.
4. **Contract owner = iki kişi birlikte**; hiçbir Codex tek başına bir adı değiştirip diğerinin kullandığını geçersiz kılamaz.
5. Yeni isim/alan/endpoint teklifi: **proposal → iki kişi onayı → 04+05+06 ve mevcut backend/istemci etkileri onaylı tek PR → main merge → ikisi de pull → entegrasyon**. Henüz kod olmayan bir alanda sözleşme önce tamamlanır; onaylı sözleşmeye göre ilk uygulama sonra yapılır. Böylece mevcut kodu etkileyen değişiklikte belge/kod birbirinden kopuk birleştirilmez.
6. Doküman uyuşmazlığında **ilgili çelişkili alan için kod/DTO üretimini durdur ve raporla**. Yetki verilen diğer belge düzeltmeleri sürdürülebilir; “çalışsın diye farklı endpoint ekleme” yasak. Korunan sözleşme dosyası kendiliğinden değiştirilmez.
7. PR açıklamasında açık alan: `Contract changed? Yes/No`; Yes ise kimin onayladığı ve etkilenen istemciler.
8. Aşağıdaki onaylı kararlar için yeni kavram/alan/endpoint gerekiyorsa önce mevcut `04/05/06` ile çakışma ve istemci etkisi raporlanır; ayrıntılı sözleşme iki tarafça onaylanmadan alternatif isim veya rota üretilmez.

## Git ve Codex akışı

- Varsayılan `main` korunur; task/feature branchlerde çalış: `feature/client-meal-logs`, `feature/dietitian-client-list`, `docs/contracts`, `fix/...`.
- Önce `git pull` ile main güncelle; görevin kapsamını ve ilgili dosya sahipliğini kontrol et.
- Codex'e **tek görev**, kısa ve test edilebilir hedef, değiştirilecek alan, kullanılacak belgeler ve `başka bir şey yapma` sınırı ver.
- Codex raporunu diğer geliştiriciyle paylaş; build/test ve contract etkisi incelensin; değişiklikleri küçük PR'larla birleştir. Ortak sözleşme değişikliklerinde iki tarafın onayı zorunludur.
- Aynı branch'i aynı anda farklı Codex oturumlarına yazdırma. Geniş refactor/taşıma ayrı onaylı görev.

## Önerilen geliştirme sırası (onaylı kararlar doğrultusunda)

Aşağıdaki sıra bir uygulama önerisidir; teslim tarihi veya tüm özelliklerin aynı MVP'ye sığacağı taahhüdü değildir. Karar 2 ve 7'deki ilk sürüm koşulları korunur; diğer onaylı özelliklerin sprint/yayın takvimi ayrıca planlanır.

1. **Sözleşme ve tasarım uyumlaması:** mevcut `04/05/06` uyarlamalarının doğrulanması; aşağıdaki hazırlık tablosundaki açık teknik parçaların iki tarafça onayı, onaylı DTO'larla mock örnekleri ve açık/koyu tema tasarım yönü. Eksik alan/enum için hayalî mock hazırlanmaz.
2. **Temel altyapı:** onaylı teknolojilerle ayrı uygulama iskeletleri, backend DB bağlantısı; e-posta doğrulama, şifre sıfırlama, güvenli oturum, Admin MFA ve rol testleri; diyetisyen başvuru/doğrulama akışı.
3. **Ana ürün döngüsü:** manuel öğün/su → API → izinli diyetisyen görünümü → plan atama → mobil plan ekranı; arama/davet kodu ve karşılıklı onay; kişisel hedef/program, tek aktif program, öğün alternatifleri ve sürüm geçmişi. İlk sürüm öğün yorumları, cevaplar ve bildirimleri bu akışla birlikte tamamlanır.
4. **Gelişim ve diyetisyen takibi:** ölçüm/aktivite kayıtları, kaynak ve geçmiş, grafikler; hedef/tüketim karşılaştırması, program uyumu, görev/son tarih/durum ve isteğe bağlı hatırlatmalar; izinli PDF raporları.
5. **AI fotoğraf:** görüntü upload → tahmin → kullanıcı düzeltmesi → öğün kaydı; kalori belirsizliği ve test raporu.
6. **Lab:** manuel veri girişi ve referans bazlı kurallar → rapor görünümü → kullanıcı onaylı PDF/fotoğraf OCR; yeterli veri ve doğrulama varsa opsiyonel ML araştırma prototipi.
7. **Entegrasyon:** Health Connect/HealthKit üzerinden onaylı veri türleri, ayrı izinler, manuel girişle tekilleştirme ve platform/cihaz testleri. Bildirimlerin teslim kanalı ve hatırlatma altyapısı teknik karara göre uygulanır; ilk sürüm bildirim gereksinimi ertelenmez.
8. **Kalite/yayın:** E2E, güvenlik, KVKK, performans, mağaza hazırlığı. Gerçek yayın ayrı kontrol kapısından geçer.

## Karar defteri

### Korunan temel kararlar

| Karar | Mevcut durum | Onay / sonraki işlem |
|---|---|---|
| Yeni repo/klasör adı `smart-nutrition-platform` | **ONAYLI** | Değiştirme |
| Eski fitness kod/dokümanlarının kullanılmaması | **ONAYLI** | Sıfırdan geliştirme |
| Ürün yönü: diyetisyen odaklı; mobil danışan + web uzman + backend | **ONAYLI** | Mobil diyetisyen başvurusu da desteklenir; ilk sürüm yönetim paneli webdedir. Aktivite kaydı beslenmeye destek içindir; antrenör/egzersiz programı kapsamı yoktur |
| Belgelerin `docs/` içinde, `AGENTS.md`/`README.md` kökte olması | **ONAYLI** | 12+2 belge |
| Codex ortak naming/data/API sözleşmesi | **ONAYLI PRENSİP** | Mevcut kanonik adlar korunur; bu güncelleme taslak şemaların tamamını onaylamaz. Uyarlamalar iki tarafın onayıyla yapılır |
| Gerçek kullanıcıya açılış/yayın | **KAPI** | `11_SECURITY_AND_RELEASE.md` tamamlanmalı |

### Kesinleşmiş 22 karar

Aşağıdaki kararların tamamı **ONAYLI**dır. “Program” mevcut kanonik kavram olan `NutritionPlan` anlamında kullanılır. Teknik ayrıntıların açık olması bu ürün kararlarını yeniden öneri durumuna düşürmez.

#### Kullanıcı ve diyetisyen sistemi (1–8)

| No | Onaylı karar | Uygulama kuralı |
|---|---|---|
| 1 | En fazla bir aktif diyetisyen; ilişki geçmişi korunur | Eşzamanlı birden çok aktif ilişkiye izin verilmez. İlişki sona erdiğinde diyetisyenin yeni sağlık verisi erişimi kesilir; geçmişin saklanması erişim hakkı vermez |
| 2 | Diyetisyen mobil veya web üzerinden başvurur; Admin doğrular | İlk sürüm diyetisyen/admin yönetim paneli webdedir. Başvuru ve doğrulama, danışan verisine erişim yetkisinden ayrı denetlenir |
| 3 | Diyetisyen arama ve davet koduyla bağlantı; karşılıklı onay | İki yöntem de desteklenir. Kodun kullanılması tek başına aktif ilişki veya sağlık verisi erişimi oluşturmaz |
| 4 | En fazla bir aktif beslenme programı; öğün alternatifleri ve sürüm geçmişi | Kişisel ve diyetisyen programları toplamında tek aktif program sınırı uygulanır. Önceki sürümler korunur; alternatif öğünler program içinde sunulur |
| 5 | Diyetisyensiz kullanıcı kendi hedef ve programını oluşturabilir | Kişisel program oluşturmak için diyetisyen ilişkisi gerekmez. `05`te nullable `dietitianId`, `06`da kişisel program yetkileri tanımlıdır; açık hedef/öğe/sürüm DTO ayrıntıları ayrıca tamamlanır |
| 6 | Diyetisyen programını yalnızca yetkili diyetisyen düzenler | Danışan atanmış programı değiştiremez; gerçek tüketimini serbestçe kaydeder. Planlanan ve tüketilen veriler karşılaştırılır; tüketim kaydı planı değiştirmez |
| 7 | İlk sürümde öğün yorumları, cevaplar ve bildirimler | İlişki ve paylaşım yetkileri bu işlemlerde de geçerlidir. Ayrı sohbet özelliği sonraki sürümdedir; bildirim kanalları ayrıca kararlaştırılır |
| 8 | Kategori bazlı paylaşım izinleri; tahliller için ayrıca açık onay | Aktif ilişki tek başına tüm verilere erişim sağlamaz. Sunucu ilgili kategori iznini ve tahliller için ayrı açık onayı denetler; geri çekilen izinle yeni erişim verilmez |

#### Beslenme, AI ve takip (9–17)

| No | Onaylı karar | Uygulama kuralı |
|---|---|---|
| 9 | Fotoğraf/galeri ile yemek tanıma; kullanıcı onaylı kalori ve makro tahmini | `FoodAnalysis` otomatik `MealLog` oluşturmaz. Kullanıcı besin ve miktarı kontrol edip düzeltir, tahmini onaylar; sürekli kamera analizi sonraki sürümdedir |
| 10 | Hibrit besin veritabanı, uygun hazır modeller/API'ler ve özel tarifler | Besin/model kaynakları, lisanslar ve sürümler izlenir. Belirli sağlayıcı veya özel model eğitimi zorunluluğu bu kararla seçilmiş değildir |
| 11 | Önce manuel tahlil girişi; ardından PDF/fotoğraf OCR | OCR çıktıları kullanıcı tarafından kontrol edilip onaylanmadan değerlendirmeye alınmaz. Tarih, ölçüm, birim ve laboratuvar referansı korunur |
| 12 | Referans aralığı değerlendirmesi; doğrulanabilir ML opsiyonel | Birim/aralık geçerliyse karşılaştırma yapılır; eksik veya uyumsuzsa `unknown`. ML ancak yeterli veri ve bilimsel doğrulamayla kullanılır; tanı, reçete veya tedavi önerilmez |
| 13 | Health Connect/HealthKit; adım, mesafe, egzersiz, süre, aktif kalori ve nabız | Desteklenen platform ve izinler kapsamında aktarım yapılır. Manuel giriş korunur; kaynak gösterilir, yeniden aktarım ve manuel/cihaz örtüşmeleri çift sayılmaz. Egzersiz verisi takiptir, antrenman programı değildir |
| 14 | Kişisel kalori/makro/su önerileri düzenlenebilir; diyetisyen hedefleri danışana salt okunur | Kişisel öneri ile diyetisyen hedefinin kaynağı ayırt edilir. Hesaplama yöntemi ayrıca doğrulanır; danışan kişisel düzenlemeyle diyetisyen hedefini değiştiremez |
| 15 | Kilo ve vücut ölçümleri; kaynak, geçmiş ve grafikler | Ölçümlerin kaynağı ve zamanı görünür olur; geçmiş ve gelişim grafikleri sunulur. İsteğe bağlı ölçümler gereksiz yere zorunlu tutulmaz |
| 16 | Diyetisyen görev atayabilir; son tarih, durum ve isteğe bağlı hatırlatmalar | Görevler yetkili danışana atanır; son tarih ve durum izlenir. Hatırlatma tercihi desteklenir; durum değerleri ve geçişleri sözleşmede ayrıca tanımlanır |
| 17 | Diyetisyen analizleri, grafikler, program uyumu ve PDF raporları | Analiz ve dışa aktarma yalnız yetkili kayıtları kapsar; kategori izinleri ve tahlil onayı geçerlidir. Uyum hesaplama yöntemi ayrıca belirlenir |

#### Yönetim ve mimari (18–22)

| No | Onaylı karar | Uygulama kuralı |
|---|---|---|
| 18 | Admin: doğrulama, kullanıcılar, şikâyetler, besin kataloğu, Audit Log ve sistem durumu | Özel sağlık verilerine varsayılan erişim yoktur. İstisnai erişim gerekçe, sınırlı yetki ve denetim izi gerektirir; mevcut `AuditEvent` kavramı korunur |
| 19 | E-posta/şifre, e-posta doğrulama, şifre sıfırlama ve güvenli oturum; Admin MFA zorunlu | Kimlik ve oturum kontrolleri sunucuda uygulanır. MFA yöntemi, token/cookie yaklaşımı ve süreler açık teknik kararlardır |
| 20 | Flutter/Dart, React/TypeScript, ASP.NET Core/C# ve PostgreSQL | AI ihtiyacı olduğunda Python/FastAPI kullanılır. Mobil/web aynı versiyonlu backend API'yi kullanır; iş kuralları ve yetkilendirme backend'dedir, istemciler DB'ye doğrudan bağlanmaz |
| 21 | Mert mobil ve ilgili API'ler; Uğur web, Auth ve ilgili API'ler; AI ortak | Yukarıdaki sahiplik sınırları geçerlidir. Feature branch + PR akışı kullanılır; ortak modülde tek PR lideri ve ortak sözleşmelerde iki tarafın onayı zorunludur |
| 22 | Premium UI/UX, ortak tasarım tokenları ve açık/koyu tema | Mobil ve webde iki tema desteklenir; görsel dil tutarlıdır. Flutter/React kodu paylaşılmaz; token karşılıkları eşdeğer tutulur. Renk, font ve kesin token değerleri henüz seçilmemiştir |

### Açık kararlar ve teknik ayrıntılar

Aşağıdaki konular **AÇIK**tır; onaylı kapsamı değiştirmeden ayrıca kararlaştırılmalıdır. Geçmiş verinin korunması, süresiz saklama kararı değildir; silme ve saklama kuralları yayın kapısının parçasıdır.

| Alan | Açık ayrıntı / sonraki işlem |
|---|---|
| Ortak sözleşmeler | `05`te kişisel program için `dietitianId` nullable, `06`da kişisel/atanmış yetkiler ve yeni kaynak yolları tanımlıdır. Tamamlanacaklar: alternatif/sürüm yapısı, tarif bileşenleri, hedefler, yorum/cevap, görev durumları, kategori/izin ve bildirim DTO'ları; mevcut metinlerdeki eski kontrol notlarının ortak onayla düzeltilmesi. Kritik bağımlılıklar aşağıdaki hazırlık tablosundadır |
| Rol ve uzman doğrulama | Kullanıcının birden çok rol/profil taşıyıp taşıyamayacağı; başvuru belgeleri, doğrulama ölçütleri, ret/yeniden başvuru ve doğrulama geri alma süreci. Doğrulayan tarafın Admin olması kesinleşmiştir |
| İlişki ve paylaşım | Davet kodu üretimi, ömrü ve kötüye kullanım kontrolleri; kategori listesi, varsayılan izinler, tahlil açık onayının kapsamı ve geri çekme akışı; geçmiş paylaşımın sınırları |
| Program ve hedefler | Kişisel programdan diyetisyen programına geçiş ve ilişkinin bitişindeki aktif program davranışı; sürüm saklama/gösterim yöntemi, öğün alternatiflerinin yapısı, tüketim eşleştirme ve uyum hesabı; güvenli kişisel öneri hesaplama yöntemi |
| Yorum, görev ve bildirim | Yorum/cevap düzenleme-silme ve moderasyon kuralları; görev türleri, durum değerleri, geçiş yetkileri ve saat dilimi; bildirim kanalları, teslim altyapısı ve hatırlatma tercihleri. İlk sürüm yorum/cevap/bildirim kapsamı onaylıdır |
| Besin ve AI kaynakları | Hibrit kataloğun kaynakları, birleştirme/öncelik kuralları ve lisansları; tarif hesaplama ve görünürlük; hazır model/API seçimi, veri seti ve değerlendirme ölçütleri. Fotoğraf saklama ve anonimleştirme ayrıca kararlaştırılır |
| Laboratuvar | Test kod standardı, birim dönüşümleri, referans doğrulama kuralları, OCR sağlayıcısı ve hata kontrolü; opsiyonel ML için izinli veri ve bilimsel validasyon. OCR'nin manuel girişten sonra gelmesi ve kullanıcı onayı zorunluluğu kesindir |
| Sağlık platformları | Android/iOS ilk önceliği, desteklenen OS/cihazlar, veri türlerinin platform karşılıkları, izin ve senkronizasyon ayrıntıları; adım/nabız gibi verilerin şeması ve kaynak bazlı tekilleştirme/örtüşme politikası. Tüm saatlerin doğrudan entegrasyonu garanti değildir |
| Auth ve ortam | JWT/token/cookie seçimi, mobil güvenli saklama, oturum süreleri/iptali, e-posta servisi ve Admin MFA yöntemi/kurtarma; paket ve çalışma zamanı sürümleri, dağıtım sağlayıcısı, altyapı ve maliyet |
| Tasarım ve kullanıcı kapsamı | Renk paleti, font, token değerleri, navigasyon ve 2–3 mobil ekran/web dashboard tasarım onayı; ülke/dil kapsamı, doğum tarihi zorunluluğu ve ücretli model. Açık/koyu tema desteği artık seçim beklemiyor |
| Veri koruma ve yayın | Sağlık verisi, fotoğraf/OCR dosyaları ve PDF raporları için saklama, silme ve yedek politikaları; üçüncü taraf/yurt dışı aktarım, audit kapsamı ve istisnai Admin erişimi. `11_SECURITY_AND_RELEASE.md` yayın kapısı korunur |
| Sprint ve modül liderliği | Ayrıntılı backend dosya/modül sınırları, ortak AI işlerinin tek PR lideri ve teslim sırası; ilk sürüm koşulları korunarak kapasite planı. Öğün kayıtlarının sürümleme ihtiyacı açıktır; program sürüm geçmişi ise onaylıdır |

## Geliştirmeye hazırlık ve sözleşme bulguları

**Durum: kısmen hazır.** Ürün, teknoloji, roller ve sahiplik sınırları belirli; bağımsız altyapı ve onaylı alanlara dayanan sentetik UI çalışmaları ayrı görevlerde başlayabilir. Ancak Auth, paylaşım ve program akışlarını kapsayan tam mobil–web–backend geliştirme/entegrasyonu henüz hazır değildir. Aşağıdaki açıklar ilgili özellikten önce iki geliştirici tarafından kapatılmalıdır; belgeyi güncellemek uygulama/test/yayın onayı değildir.

`04` adları, `05` alan/tip/ilişkileri, `06` method/route/payload ve hata kurallarını belirler. Geçerliliğini yitirmiş bir kontrol notu, güncel normatif alan tanımının yerine kullanılmaz; tereddütte yeni DTO/alias üretmek yerine çakışma kaydı ve ortak onay gerekir. Bu incelemede `04/05/06` değiştirilmemiştir.

| Alan | Bulgu / gerekli ortak karar | Geliştirmeye etkisi |
|---|---|---|
| Auth ve profil | `06`da register/me kök yanıtı, refresh/logout oturum gövdeleri, token/cookie ve MFA challenge/kurulum/kurtarma açıktır; `05` güvenlik kayıtlarını kesinleştirmemiştir | Gerçek giriş, güvenli oturum ve Admin paneli entegrasyonundan önce kapanmalı; farklı istemci oturum DTO'ları uydurulamaz |
| Paylaşım ve tahlil onayı | Kategori listesi, endpoint–kategori eşlemesi, rıza tür/kapsam/politika kanıtı açık; pending/ended ilişkide izin düzenleme ayrıntıları belirsiz | Diyetisyene sağlık verisi açmadan önce kapanmalı; kategori eksikliği varsayılan tüm erişimle giderilemez |
| Erişim ifadesinin kapsamı | `06` izin paragrafındaki “sağlık verisi erişimi her durumda active ilişkiye bağlıdır” genellemesi, aynı belgedeki danışanın ilişkisiz kendi veri erişimiyle çelişebilir | Active ilişki şartının diyetisyenin danışan verisine erişimi için olduğu ortak onayla açık yazılmalı; danışanın kendi verisi ilişki yok diye kapatılamaz |
| Program sürümü ve geçiş | Öğelerin sürüm/alternatif bağları, miktar/gün biçimi, tam items DTO'su, arşivleme/değiştirme request'i açıktır; `06` ikinci aktif programa `409` döndürür | Sürüm geçmişi ve program değiştirme özelliği uygulanmadan önce kapanmalı; eski sahiplik silinerek veya iki aktif programla aşılmaz |
| Tarif, görev ve yorum | Tarif bileşen/porsiyon/görünürlük, görev durum/geçiş/son tarih/hatırlatma, yorum kanonik adı/moderasyonu ve bildirim DTO/kanalları açık | Metadata/yol taslakları tam feature sözleşmesi sayılmaz. İlk sürüm yorum/cevap/bildirim şartı nedeniyle bunların onayı ilk sürüm planında önceliklidir |
| OCR, lab ve cihaz | OCR taslak/onay kanıtı ve sync gövdeleri, adım/nabız/aktif enerji modelleri, kaynak örtüşmesi; LabInsight method/limitations ve değişen tahlil geçmişi açık | Manuel girişi engellemez; bu entegrasyonlara başlanmadan ilgili veri/HTTP parçası kapatılmalı. Yeni genel job/ölçüm modeli uydurulmaz |
| Eski sözleşme kontrol notları | `04`, `05`teki tek aktif kuralları/nullable dietitianId ve yeni kaynakları hâlâ eksik sayıyor, ConsentRecord endpoint kararı yok diyor; `05`, güncel `06`daki kişisel program, kaynak yolları, PATCH ve makro alanlarını eski halleriyle anlatıyor | `04/05/06` için ayrı, iki tarafça onaylı düzeltme gerekir. Bu inceleme bu üç dosyada değişiklik yapma onayı değildir |
| Sürüm kapsamı ifadesi | `06`nın sonundaki ilk sürüm bildirimleri ve PDF raporlarını aynı cümlede anması takvimi belirsizleştiriyor | Karar 2/7 ilk sürüm web paneli ve yorum/cevap/bildirim şartıdır; karar 17 PDF kapsamını onaylar, yayın tarihini sabitlemez. `01`deki aşama ayrımı esas alınır; `06` ifadesi ortak onayla netleştirilmeli |
| Tasarım, kaynak ve yayın | Renk/font/token değerleri, katalog lisans/sağlayıcısı, model verisi/validasyon, hassasiyet/saat dilimi, saklama/silme/dağıtım açık | Tasarımın nihai onayı ilgili ekran kodundan; sağlayıcı/veri kararı ilgili entegrasyondan önce alınır. Gerçek veri/yayın için `11` kapısı ayrıca tamamlanır |

Her kapatılan karar için iki tarafın onayı, etkilenen belgeler/istemciler ve doğrulama sonucu kaydedilir. **Sonraki tek adım:** Auth/profil ve paylaşım sözleşmelerinin ortak onayını tamamlayıp ilk uçtan uca akışın kapsamını sabitlemek; ardından ilgili açık program/yorum şemasını aynı hazırlık ölçütüyle kapatmak.

## İlk Codex görevi (kod yazdırmadan — başlangıç incelemesi)

> `AGENTS.md`, `README.md` ve `docs/` altındaki 12 dosyayı oku. `04_NAMING_CONVENTIONS.md`, `05_DATA_DICTIONARY.md`, `06_API_CONTRACT.md` arasındaki isim/alan/rota uyuşmazlıklarını ve `12_TEAM_PLAN_AND_DECISIONS.md` içindeki açık kararları raporla. Kod yazma, dosya oluşturma veya değiştirme. Sadece kısa, somut rapor ver.

## Definition of Done — her feature için

- İş akışı ve istek kapsamı karşılandı; alakasız dosya değişmedi.
- Kanonik adlar ve API sözleşmesiyle uyumlu; contract etkisi açık raporlandı.
- İlgili lint/build/test çalıştırıldı; başarısızlık gizlenmedi.
- Yetki, veri sahipliği, tıbbi belirsizlik ve kişisel veri kuralları kontrol edildi.
- Mobil/web karşılıklı etkilendiğinde diğer geliştiriciye entegrasyon notu verildi.
