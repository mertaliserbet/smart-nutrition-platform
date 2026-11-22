# 10 — AI, besin kataloğu ve laboratuvar/OCR gereksinimleri

**Durum: onaylı ürün kapsamı, henüz uygulama yok.** Kaynakta FoodAnalysis/FoodItem/Recipe/LabReport/LabResult/LabInsight için EF, controller veya çalışan model servisi bulunmuyor. React'teki sentetik tahlil/aktivite önizlemeleri ve mobil “Tahlil ekle” önizlemesi bu kapsamın teslimi değildir.

İsimler [04](04_NAMING_CONVENTIONS.md), korunmuş alan adayları [05](05_DATA_DICTIONARY.md), mevcut olmayan taslak HTTP yolları [06](06_API_CONTRACT.md)'dadır. Bu belge yeni DTO/endpoint veya sağlayıcı kararı vermez.

## Fotoğraftan yemek analizi

Onaylı girdi kamera ile çekilen veya galeriden seçilen tek yemek fotoğrafıdır. Canlı önizlemeden fotoğraf yakalamak yeterlidir; sürekli video analizi sonraki sürüm/araştırmadır.

Akış: kontrollü yükleme → modelden besin sınıfı ve belirsizlik → lisanslı katalog eşlemesi → porsiyon/gramın kullanıcıca doğrulanması → tahmini enerji/makro → kontrol, gerekirse düzeltme ve açık onay → ayrı MealLog kaydı.

Tek fotoğraftan güvenilir 3D hacim veya kesin kalori sözü verilmez. Doğru öneriyi değiştirmek zorunlu değildir. Analiz başlatmak/okumak veya completed durumu onay değildir; otomatik öğün oluşturulmaz. Model başarısız/yavaşsa manuel kayıt devam etmelidir.

Korunan taslakta suggestions öğeleri displayName, confidence ve nullable miktar/enerji/makrolar taşır; limitations analiz kökündedir. Alanlar öneri altına sessizce taşınmaz. Dahili saklama/onay kanıtı ve dosya limitleri kesinleşmeden kalıcı şema üretilmez.

## Hibrit besin kaynağı ve tarif

FoodItem değerleri tek servingBasisGrams temeline dayanır; enerji kcal, makrolar gramdır. Veri kaynağı, kaynak/lisans, sürüm ve belirsizlik izlenir. Birden çok sağlayıcıda eşleştirme/öncelik/birleştirme kuralları ayrıca belirlenir.

Recipe kullanıcının özel tarifidir; bileşen, miktar, porsiyon, toplam/besin hesabı, görünürlük ve geçmiş düzeni açık kararlardır. Katalog/tarif değişikliği eski MealLogItem veya program snapshot'ını yeniden hesaplayıp değiştirmemelidir. Mevcut manuel API'nin dolu katalog/tarif/analiz UUID'lerini reddetmesi, gelecekteki kapsamın kaldırılması değildir.

## Manuel laboratuvar ve açıklama

Önce manuel rapor girişi uygulanır: test adı/kodu, gerçek değer, birim, tarih ve laboratuvar referans aralığı. Geçerli analit/birim/aralık eşleşmesinde yalnız low/normal/high karşılaştırılır; eksik/uyumsuzsa unknown olur. Genel pozitif değer kuralı veya otomatik klinik eşik uydurulmaz.

Ölçüm, birim, referans, tarih ve açıklamanın sınırı birlikte görünmelidir. Geçmiş karşılaştırma aynı analit ve aynı/doğrulanmış dönüştürülmüş birimde yapılır. Rapor değeri değişince eski LabInsight güncel sonuç gibi sunulmaz; sürüm/yeniden analiz davranışı ayrıca kararlaştırılır.

LabInsight tanı, reçete, tedavi veya hastalık saptama iddiası taşımaz. Diyetisyen klinik kararı kendisi verir; “normal” bayrağı genel sağlıklı hükmü değildir. method/limitations biçimi ve model kaynakları açık karardır.

## OCR

Manuel temel sonrasında PDF/fotoğraftan OCR onaylı geliştirme aşamasıdır. OCR yalnız taslak üretir. Kullanıcı test/değer/birim/tarih/referansı kontrol edip gerekirse düzelterek açıkça onaylamadan kalıcı LabResult veya değerlendirme oluşmaz. Diyetisyenin yardımcı incelemesi bu onayın yerine geçmez.

Dosya MIME/içerik/limit/tarama, private storage, OCR sağlayıcısı, taslak/iş kimliği, senkron/asenkron yanıt ve sunucuda onay kanıtı açık kararlardır. FoodAnalysisStatus OCR'ye otomatik uygulanmaz; job/isConfirmed gibi yeni alanlar varsayılmaz. Laboratuvar belgesi ile dışa aktarılan diyetisyen PDF raporu farklı kavramdır.

## Model ve değerlendirme

Uygun hazır model/API kullanılabilir; özel eğitim, ayrı servis veya belirli sağlayıcı zorunlu değildir. Gerektiğinde Python/FastAPI onaylıdır. Model sürümü, değerlendirme tarihi, veri kaynağı/lisansı, sınırlılıklar ve bilinen hata örnekleri izlenmelidir.

Fotoğraf için ayrık test verisi, Türk yemeklerinin temsili, sınıflandırma precision/recall/F1, porsiyon/kalori hata dağılımı ve kullanıcı düzeltme sıklığı değerlendirilir. Veri ve ölçüm olmadan doğruluk oranı taahhüt edilmez.

Laboratuvar ML'i opsiyoneldir: etiketli/izinli veri, leakage kontrolü, bağımsız eğitim/test, sınıf dengesi, açıklanabilirlik ve klinik uzman doğrulaması gerekir. Bu kapılar yoksa referans karşılaştırmasının ötesinde iddia üretilmez.

## Mimari ve güvenlik sınırı

Kaynak/rol/ilişki/izin kararını backend verir, model vermez. AI aktarım amacı ile diyetisyene paylaşım amacı ayrı değerlendirilir. En az veri, kimlik ayıklama, sağlayıcı/yer/retention ve hukuki dayanak [11](11_SECURITY_AND_RELEASE.md)'deki yayın kapısına tabidir.

Uygulama öncesi manuel fallback, timeout, izin geri çekme, dosya sahipliği, kullanıcı kontrol/onayı ve yanıltıcı/riskli metin kontrolleri test edilmelidir. Bunlar kabul gereksinimleridir; eğitilmiş model, bilimsel başarı veya gerçekleştirilmiş test sonucu değildir. Açık kararların ana kaynağı [12](12_TEAM_PLAN_AND_DECISIONS.md)'dir.
