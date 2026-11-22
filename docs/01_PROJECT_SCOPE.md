# 01 — Ürün kapsamı, roller ve kullanıcı akışları

Bu repo eski fitness uygulamasından bağımsız, sıfırdan geliştirilen Smart Nutrition Platform'dur. Amaç diyetisyen–danışan takibi, bağımsız kişisel beslenme kaydı ve sınırları açık AI desteğidir. Üniversite bitirme projesi olarak başlayan ürünün gerçek kullanıcıya açılması [yayın gereksinimlerine](11_SECURITY_AND_RELEASE.md) bağlıdır.

Bu belge ürün kapsamını tanımlar. Kaynakta bulunan özelliklerin güncel durumu ve doğrulama sınırları [12](12_TEAM_PLAN_AND_DECISIONS.md), HTTP davranışı [06](06_API_CONTRACT.md) içindedir. Onaylı kapsam, uygulanmış özellik veya yayın taahhüdü anlamına gelmez.

## Roller ve ürün sınırları

| Rol | Temel deneyim |
|---|---|
| Danışan (Client) | Flutter üzerinden kendi öğün, su, ölçüm, aktivite ve ilerlemesini takip eder; hedef/program oluşturabilir, atanmış programını okur, paylaşımını yönetir |
| Diyetisyen (Dietitian) | Admin onayıyla React panelinden aktif danışanlarını izin verilen kategorilerde izler, kendi atadığı program ve görevleri yönetir, öğünlere yorum bırakır |
| Yönetici (Admin) | MFA ile ayrı web alanına girer; uzman doğrulama ve onaylı operasyon kapsamını yürütür; sağlık verisine varsayılan erişimi yoktur |

Bir kullanıcı aynı hesapla hem danışan hem diyetisyen olabilir; aynı User altında ClientProfile ve DietitianProfile bulunur, ikinci kullanıcı hesabı oluşturulmaz. Mevcut backend başvuruda onaysız DietitianProfile oluşturur; Admin onayı uzman yetkisini açar. Başvuru ve onay, danışan profilini, öğünleri, ölçümleri, diğer kişisel kayıtları veya temel hesap rolünü değiştirmez. Başvuru veya istemcide profil seçimi uzman onayı değildir; başvuru ve yetkilendirme kuralları [05](05_DATA_DICTIONARY.md)/[06](06_API_CONTRACT.md)'daki haliyle korunur.

**Flutter V1 yalnız danışan kullanımına yöneliktir.** Onaylı diyetisyen mobilde kendi danışan özelliklerini kullanmaya devam eder; mobil diyetisyen yönetim paneli geliştirilmez. Diyetisyen/Admin yönetimi webdedir. Aşağıdaki Profil başvuru/durum ve web paneline geçiş akışı kesinleşmiş gereksinimdir; mevcut mobil navigasyonda eksiktir ve geliştirme/uygulama doğrulaması tamamlanmış sayılmaz ([07](07_MOBILE_SPEC.md), [12](12_TEAM_PLAN_AND_DECISIONS.md)).

Danışanın en fazla bir aktif diyetisyeni, kişisel/atanmış programların toplamında en fazla bir aktif beslenme programı olur. İlişki ve program geçmişi korunur. Kişisel kullanım diyetisyen ilişkisine bağlı değildir. Program tavsiyesi NutritionPlan, gerçek tüketim MealLog'dur; biri diğerini otomatik değiştirmez.

## Onaylı özellikler ve aşamalar

| Özellik | Korunan kapsam | Aşama |
|---|---|---|
| Hesap ve oturum | E-posta/şifre, doğrulama, sıfırlama, güvenli mobil/web oturumu; Admin MFA | Temel ürün döngüsü |
| Uzman ve bağlantı | Mobil/web başvuru, Admin doğrulama, uzman arama veya davet kodu, karşılıklı onay, ilişki geçmişi | Temel ürün döngüsü |
| Program | Kişisel veya atanmış program, gün/miktar/alternatifler, değişmeyen sürümler, tek aktif program | Temel ürün döngüsü |
| Manuel beslenme ve su | Öğün/besin/miktar, nullable enerji/makrolar, düzeltme/silme, su kayıt ve toplamları | Temel ürün döngüsü |
| Kişisel hedefler | Düzenlenebilir kalori/makro/su hedefleri; atanmış program hedefleri danışana salt okunur | Temel ürün döngüsü; otomatik öneri hesabı ayrıca kararlaştırılır |
| Ölçüm ve gelişim | Kilo, bel/kalça/göğüs ve vücut yağ oranı, tarih/kaynak, geçmiş ve grafik | Temel ürün döngüsü; cihaz kompozisyon entegrasyonu ayrıca değerlendirilir |
| Aktivite ve sağlık platformları | Manuel aktivite; izinli Health Connect/HealthKit adım, mesafe, egzersiz/süre, aktif enerji ve nabız | Onaylı; desteklenen cihaz/OS ve yayın kapsamı doğrulanmalıdır |
| Yorum ve bildirim | Öğün yorumu/cevabı, bunların ve kritik sistem olaylarının bildirimleri | İlk sürüm koşulu; teslim kanalları ayrıca seçilir |
| Görevler | Diyetisyen ataması, son tarih, durum/geçmiş ve danışana ait isteğe bağlı hatırlatma tercihi | Onaylı; hatırlatma teslimi ayrıca geliştirilir |
| Paylaşım | Bağımsız kategori izinleri, tahliller için ayrıca açık onay ve geri çekme | Her ilgili işlemin temel yetki koşulu |
| Besin ve tarif | Hibrit besin kataloğu, kaynak/lisans izlenebilirliği ve özel tarifler | Onaylı, uygulama takvimi açık |
| Fotoğraftan beslenme analizi | Kamera/galeri, tahmini porsiyon/enerji/makro, kullanıcı kontrolü/düzeltme/onayı ve manuel devam | Onaylı geliştirme kapsamı; doğruluk garantisi yok |
| Laboratuvar | Önce manuel değer/birim/tarih/referans, açıklayıcı değerlendirme; sonra kullanıcı onaylı PDF/fotoğraf OCR | Manuel temel öncelikli; OCR onaylı sonraki aşama |
| Analiz ve PDF raporları | İzinli trend/grafik, program karşılaştırması ve ileride tanımlanacak uyum hesabı, yetkili PDF dışa aktarma | Onaylı; PDF yayın tarihi ve tam uyum yöntemi açık |
| Admin operasyonları | Uzman doğrulama, kullanıcılar, şikâyetler, katalog, Audit Log ve sistem durumu | Onaylı; tamamı uygulanmış sayılmaz |
| Tasarım | Ortak görsel dil, premium deneyim, erişilebilirlik, açık/koyu tema | Onaylı; uygulanan değerler [09](09_DESIGN_SYSTEM.md) içinde |

Ayrı sohbet ve sürekli kamera/video analizi sonraki sürüm/araştırmadır. Bilimsel doğrulanabilir laboratuvar ML'i opsiyonel araştırmadır. Barkod ve kişiselleştirilmiş su hatırlatmaları önceki önerilerdir; onaylı teslim kapsamı sayılmaz. Trainer, antrenman programı, gym ekipmanı ve eski fitness kodu kapsam dışıdır.

## Kullanıcı akışları

1. **İlk kullanım ve uzman başvurusu:** kullanıcı mobilde danışan olarak kayıt olur, e-postasını doğrular ve giriş yapar. İsteğe bağlı hedef/ölçüm girebilir; diyetisyen bağlamadan günlük takip yapar. Daha sonra mobil **Profil** ekranından mevcut hesabıyla diyetisyen başvurusu yapar ve güncel başvuru/onay durumunu görür. Admin onayından sonra **“Diyetisyen Paneline Git”** güvenilir HTTPS web adresindeki çalışma alanını harici tarayıcıda açar. Web oturumu yoksa aynı e-posta/şifreyle ayrıca giriş yapılır; mobil JWT/refresh token web adresine, URL'ye veya tarayıcıya aktarılmaz. Bekleyen/onaysız kullanıcı çalışma alanına erişemez. Doğrulanmış e-posta ve Admin onayı ayrı koşullardır; mevcut web başvuru yolu da korunur.
2. **Bağlantı ve paylaşım:** danışan uzman araması veya davet koduyla istek gönderir; uzman kabul/red verir. Kabul ilişkiyi kurar, sağlık kategorilerini açmaz. Danışan kategorileri ayrı açıp geri çekebilir; ilişki sonlandırılabilir.
3. **Gerçek tüketim:** manuel öğün ve su kaydedilir. Gelecekte fotoğraf analizi kullanıldığında kullanıcı öneriyi kontrol edip gerekirse düzeltir; doğru öneriyi değiştirmeye zorlanmaz. Ayrı onaylı MealLog kaydı oluşur; AI başarısızsa manuel akış sürer.
4. **Program:** danışan kişisel programını, uzman yalnız kendi atadığı programı düzenler. Etkinleştirme ve arşivleme açıktır; başka aktif program sessizce değiştirilmez. Atanmış hedefler danışana salt okunurdur. İlişki bittiğinde o uzmanın aktif atanmış programı arşivlenir, kişisel program ve geçmiş korunur.
5. **Takip ve iletişim:** uzman izinli kayıtları görür, öğüne yorum bırakır; danışan kendi öğününde yorum/cevap verebilir. Uzman görev atar, danışan izinli durumunu/hatırlatma tercihini değiştirir. Bildirim teslimi ayrı geliştirmedir; sohbet veya anlık WebSocket varsayılmaz.
6. **İlerleme:** kendi ölçümleri ve kayıtları grafiklerle izlenir. Seçilen içerik sürümüyle günlük tüketim karşılaştırması, o gün gerçekten aktif sürümün kanıtı veya genel uyum yüzdesi değildir. Kayıt yokluğu “yemedi” anlamına gelmez.
7. **Aktivite:** danışan manuel kayıt veya açık OS izniyle platform okuması yapar; uygulamaya aktarımı ayrıca yönetir. Kaynak ve tekilleştirme kuralları [20](20_HEALTH_DATA_SYNC_CONTRACT.md) içindedir. Bütün saatlerin doğrudan desteği taahhüt edilmez.
8. **Planlanan laboratuvar:** danışan rapor değerini, birimini ve laboratuvar referansını girer; sonra OCR taslağını kontrol/onaylayabilir. Uygun birim/aralık yoksa kesin karşılaştırma yapılmaz. Diyetisyen incelemesi kullanıcı onayının yerine geçmez.
9. **Planlanan rapor ve veri hakları:** PDF ve veri indirme/silme yalnız tanımlanacak yetki ve saklama politikasına göre uygulanır. Geçmişi korumak süresiz saklama kararı değildir.

Fotoğraf kalorisi/porsiyonu tahmindir. Laboratuvar çıktısı tanı, reçete veya tedavi değildir. Ayrıntılı AI sınırları [10](10_AI_SPEC.md), izin ve mahremiyet kuralları [11](11_SECURITY_AND_RELEASE.md) içindedir.
