# 10 — Yapay zekâ / görüntü işleme / laboratuvar değerlendirmesi

> Bu belge araştırma ve geliştirme hedeflerini tanımlar. **Model eğitildi, kalori kesin hesaplanır veya hastalık saptanır** gibi doğrulanmamış iddialar yasaktır.

## A. Fotoğrafla yemek analizi
**Girdi:** Mobil kamera ile çekilen veya galeriden seçilen yemek fotoğrafı. Canlı kamera önizlemesinden fotoğraf yakalama MVP için yeterlidir; gerçek zamanlı sürekli video analizi daha sonraki araştırma aşamasıdır.

**Önerilen işlem hattı:**
1. Kullanıcının onayı ve kontrollü görüntü yüklemesi.
2. Görüntü ön işleme; uygun besin sınıfı/nesne tahmini ve belirsizlik.
3. Gıda veri kataloğundaki karşılıkların eşleştirilmesi; kaynakları kontrol.
4. Porsiyon miktarı kullanıcıdan doğrulanır (tek fotoğraf 3D hacmi güvenilir biçimde vermez).
5. Yaklaşık enerji/makro hesaplanır; **kesin olmadığını belirterek** kullanıcıya düzenletilir.
6. Kullanıcı onay verirse `MealLog` kaydı oluşur. `FoodAnalysis` tek başına öğün değildir.

**İlgili entity:** `FoodAnalysis`, `FoodItem`, `MealLog`, `MealLogItem`. **Endpoint:** `POST /api/v1/food-analyses`, `GET /api/v1/food-analyses/{analysisId}`; onaylı kayıt `POST /api/v1/meal-logs`.

**Önerilen çıktı:** `suggestions[]` öğeleri için `displayName`, `confidence` (0..1), `quantityGrams?`, `caloriesKcal?`, `limitations[]` (isteğe bağlı). İlgili model ve besin veri kaynağı versiyonlanır.

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

**OCR:** Tahlil görseli/PDF'sinden sonuç çıkarma ileri faz olabilir. OCR değerleri **her zaman kullanıcı/diyetisyen tarafından doğrulanmadan klinik yorumlamaya alınmaz**; rapordaki tarih, birim ve referans korunur.

**İlgili entity:** `LabReport`, `LabResult`, `LabInsight`. **Endpoint:** `POST /api/v1/lab-reports`, `POST /api/v1/lab-reports/{labReportId}/insights`.

## C. AI servis sınırları
- Backend kullanıcı/rol/ilişki yetkisini denetler; model buna karar vermez.
- AI servisinde mümkünse kimliği açığa çıkaran alanları gönderme; saklama/retention politikasına uy.
- Model sürüm, deneme tarihi, temel değerlendirme sonuçları, bilinen hatalar ve veri lisansı belgelenir.
- Timeout/hata halinde manuel kayıt ve rapor gösterimi çalışmaya devam eder.
- Üretilen metin açıklama içindir; tıbbi açıdan riskli/yanıltıcı çıktı filtreleme ve kullanıcı uyarısı gerekir.

## D. Ortak geliştirme / görev paylaşımı
Fotoğraf analizi ve lab AI/ML **iki geliştiricinin ortak sorumluluğudur**. Model eğitimi, servis kontratı ve entegrasyon değişiklikleri için görev bazlı lider atanır; iki Codex aynı şema/endpointi paralel düzenlemez. `12_TEAM_PLAN_AND_DECISIONS.md`.
