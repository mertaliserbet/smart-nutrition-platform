# 10 — Yapay zekâ / görüntü işleme / laboratuvar değerlendirmesi

> Bu belge araştırma ve geliştirme hedeflerini tanımlar. **Model eğitildi, kalori kesin hesaplanır veya hastalık saptanır** gibi doğrulanmamış iddialar yasaktır.

`12` karar 9–12 ve 20 uyarınca fotoğraf/galeri tahmini, hibrit besin kaynağı/özel tarifler, manuel tahlilden sonra kullanıcı onaylı OCR onaylı kapsamdır; lab ML opsiyoneldir. Uygun hazır model/API kullanılabilir; gerektiğinde Python/FastAPI çalışır, özel eğitim veya ayrı AI servisi zorunlu değildir. Sağlayıcı, veri/lisans, model ve performans eşiği henüz seçilmemiştir; ilgili entegrasyon öncesi ortak onay gerekir.

## A. Fotoğrafla yemek analizi
**Girdi:** Mobil kamera ile çekilen veya galeriden seçilen yemek fotoğrafı. Canlı kamera önizlemesinden fotoğraf yakalama MVP için yeterlidir; gerçek zamanlı sürekli video analizi daha sonraki araştırma aşamasıdır.

**Önerilen işlem hattı:**
1. Kullanıcının onayı ve kontrollü görüntü yüklemesi.
2. Görüntü ön işleme; uygun besin sınıfı/nesne tahmini ve belirsizlik.
3. Gıda veri kataloğundaki karşılıkların eşleştirilmesi; kaynakları kontrol.
4. Porsiyon miktarı kullanıcıdan doğrulanır (tek fotoğraf 3D hacmi güvenilir biçimde vermez).
5. Yaklaşık enerji/makro hesaplanır; **kesin olmadığını belirterek** kullanıcı kontrolüne sunulur, gerektiğinde düzeltilir. Doğru önerinin zorla değiştirilmesi gerekmez.
6. Kullanıcı onay verirse `MealLog` kaydı oluşur. `FoodAnalysis` tek başına öğün değildir.

**İlgili kavramlar:** `FoodAnalysis`, `FoodItem`, `Recipe`, `MealLog`, `MealLogItem`. Hibrit katalog/tarif bağlantısı besin temeli ve belirsizliği korur; tarif bileşen/porsiyon ve görünürlük şeması açıktır. **Endpoint:** `POST /api/v1/food-analyses`, `GET /api/v1/food-analyses/{analysisId}`; onaylı kayıt `POST /api/v1/meal-logs`.

**Mevcut HTTP çıktı yerleşimi (`06`):** `suggestions[]` öğeleri `displayName`, `confidence` (0..1), nullable `quantityGrams`, `caloriesKcal`, `proteinGrams`, `carbsGrams`, `fatGrams` içerir. Porsiyon/makro gram, enerji kcal; bilinmeyen değer null'dır. `limitations` **analiz kökünde** metin listesidir; öneri öğesinin içine taşınmaz. FoodAnalysis durumları mevcut pending/processing/completed/failed değerleridir. Model/besin kaynağı sürümleri izlenir; limitations'ın dahili saklama/üretim ayrımı `05`te açıktır, yeni persist alanı varsayılmaz.

**Değerlendirme:** veri seti lisansı/temsil yeterliliği; besin sınıflandırma precision/recall/F1; test ayrımı; Türk yemeklerine ait yeterlilik; porsiyon/kalori için hata dağılımı ve kullanıcı düzeltme sıklığı. Veri bulunmadan performans sözü verilmez.

## B. Kan tahlili / vitamin-mineral değerleri
**Girdi:** `LabReport` + `LabResult`: test adı, ölçüm, birim, tarih ve mümkünse raporda yazılı laboratuvar referans aralığı.

**MVP güvenilir temel:**
1. Giriş doğrula: sayısal değer, birim, test türü ve referans aralığı eşleşiyor mu?
2. Aralık geçerliyse yalnız `low/normal/high` karşılaştırması yap. Birim/aralık uyuşmuyorsa `unknown`.
3. Kullanıcıya ölçüm, birim, aralık, tarih, durumun kapsamı ve sınırları göster.
4. Diyetisyen kendi klinik değerlendirmesini yapar. Uygulama **tanı, reçete veya tedavi önerisi** vermez.
5. Geçmiş raporlar aynı analit/kod ve **aynı veya doğrulanmış dönüştürülmüş birim** temelinde karşılaştırılır.

**ML ancak bilimsel doğrulamayla:** Etiketli/izinli veri, ayrık eğitim-test, leakage kontrolleri, sınıf dengesizliği, açıklanabilirlik, veri temsili ve klinik uzman değerlendirmesi gerekir. Veri ve validasyon yoksa kural tabanlı referans yorumundan öte iddiada bulunma. Modelin tahmini ayrıca etiketlenir; gerçek ölçüm gibi gösterilmez.

**OCR:** Manuel girişin ardından PDF/fotoğraftan kullanıcı onaylı sonuç çıkarma **onaylı sonraki geliştirme aşamasıdır**; yayın takvimi açıktır. OCR taslağı **kullanıcı tarafından kontrol edilip onaylanmadan** kalıcı LabResult/değerlendirmeye dönüşmez; diyetisyen incelemesi kullanıcının onayının yerine geçmez. Rapordaki tarih, birim ve referans korunur. `06`daki `/lab-reports/ocr` önerisinin senkron/asenkron yanıtı, taslak/iş kimliği ve onay kanıtı açıktır; FoodAnalysis enumu veya yeni job/isConfirmed alanları buraya kendiliğinden uygulanmaz.

**İlgili entity:** `LabReport`, `LabResult`, `LabInsight`. **Endpoint:** `POST /api/v1/lab-reports`, `POST /api/v1/lab-reports/{labReportId}/insights`.

## C. AI servis sınırları
- Backend kullanıcı/rol/ilişki yetkisini denetler; model buna karar vermez.
- Diyetisyenin tahlil açıklamasında doğrulanmış uzman + aktif ilişki + ilgili kategori izni + geri çekilmemiş tahlil açık onayı gerekir. AI aktarım izni ve diyetisyene paylaşım izni farklı amaçlardır; biri diğerini kendiliğinden sağlamaz. Analiz/rapor okurken de güncel erişim korunur.
- AI servisinde mümkünse kimliği açığa çıkaran alanları gönderme; saklama/retention politikasına uy.
- Model sürüm, deneme tarihi, temel değerlendirme sonuçları, bilinen hatalar ve veri lisansı belgelenir.
- Timeout/hata halinde manuel kayıt ve rapor gösterimi çalışmaya devam eder.
- Üretilen metin açıklama içindir; tıbbi açıdan riskli/yanıltıcı çıktı filtreleme ve kullanıcı uyarısı gerekir.
- Geçersiz referans `unknown` olarak açıklanır; normal laboratuvar bayrağı genel sağlık hükmü değildir. Rapor değerleri değişince eski LabInsight güncel değerlendirme diye sunulmaz; geçmiş/yeniden analiz ve method/limitations biçimi ortak sözleşmede açıktır.

## D. Ortak geliştirme / görev paylaşımı
Fotoğraf analizi ve lab AI/ML **iki geliştiricinin ortak sorumluluğudur**. Model eğitimi, servis kontratı ve entegrasyon değişiklikleri için görev bazlı lider atanır; iki Codex aynı şema/endpointi paralel düzenlemez. `12_TEAM_PLAN_AND_DECISIONS.md`.

Değerlendirme planı, manuel fallback, kullanıcı düzeltme/onay ve izin geri çekme senaryoları ilgili feature'da doğrulanır. Belgede değerlendirme ölçütü bulunması eğitilmiş/başarılı model veya test sonucu değildir. Açık şema ve sağlayıcı kararları için `12` hazırlık tablosu kullanılır.
