# Codex ortak çalışma talimatları — Smart Nutrition Platform

> Baseline: `DOCS-V1` · 15.10.2026 · durum: **taslak / ekip onayı bekliyor**. Bu repo eski fitness uygulamasının devamı değildir. **Sıfırdan** geliştirilecek diyetisyen odaklı üründür.

## 1. Her görevden önce oku
1. Bu `AGENTS.md`.
2. `docs/01_PROJECT_SCOPE.md` ve `docs/12_TEAM_PLAN_AND_DECISIONS.md`.
3. Değiştireceğin alana göre ilgili ekran/AI/mimari dokümanı.
4. **Her zaman** `docs/04_NAMING_CONVENTIONS.md`, `docs/05_DATA_DICTIONARY.md`, `docs/06_API_CONTRACT.md` dosyalarını kontrol et; alan veya endpoint ekleniyorsa sözleşmeyle uyumluluğunu doğrula.
5. Repo içindeki mevcut kod varsa önce ona bak; kullanılmayan veya uydurulmuş alternatifleri oluşturma.

## 2. İki Codex, tek sözleşme
- **Tek kanonik terimler**: `docs/04_NAMING_CONVENTIONS.md`. Yeni ad uydurma, eşanlamlı entity oluşturma (ör. `MealLog` yerine `FoodRecord`).
- **Alanlar/ilişkiler/değer tipleri**: `docs/05_DATA_DICTIONARY.md`.
- **HTTP rotaları, JSON anahtarları, hata formatı**: `docs/06_API_CONTRACT.md`.
- Backend C# entity adı, Flutter model adı ve web TypeScript tipi aynı kavramı anlatmalı; platformun dil kurallarına göre küçük sözdizimi farkları olabilir. JSON anahtarları `camelCase` olarak ortak kalır.
- Bunlar **ortak ekip sözleşmeleri**dir. Üzerlerinde değişiklik gerektiren görevde önce çakışmayı raporla ve değişiklik önerisini sun. **Açık ekip onayı olmadan mevcut kanonik adları, endpointleri veya zorunlu alanları değiştirme.** Onaylı değişiklik tek PR/commit içinde doküman, backend, mobil ve web etkileriyle birlikte ele alınır.
- Her iki Codex, `main` üzerinden aynı onaylı dokümantasyon sürümünü çekmeli. Ayrı branchlerde farklı sözleşme üretmeyin. Sözleşme değişince her iki geliştirici `git pull` ile eşitlenmeden entegrasyon yapılmasın.

## 3. Görev kapsamı
- Sadece istenen işi yap. İlgisiz ekran, teknoloji, paket, endpoint veya veri modeli ekleme.
- Belirsiz veya ürün/sağlık açısından önemli kararları **kendiliğinden kesinleştirme**; raporla, çözüm öner.
- Taslak teknoloji kararları için uygulama iskeleti üretmeden önce `docs/12_TEAM_PLAN_AND_DECISIONS.md` durumunu kontrol et.
- **Eski fitness repo/doküman/kodlarını kopyalama, taşıma veya referans alma.** Trainer, workout planı, gym ekipmanı vb. özellikler yoktur. Yalnız beslenmeye destek olan günlük fiziksel aktivite kaydı var.

## 4. Dengeli modülerlik / refactor
- Tüm kodu tek dosyaya toplama. Tek sorumluluk ilkesi ve **feature-based** yapı kullan.
- Her küçük metot/widget için ayrı dosya açma; önemsiz soyutlama, gereksiz katman ve derin klasörler üretme.
- Bir dosyada birbirinden bağımsız birden fazla büyük sorumluluk belirdiğinde, ortak kullanım veya test ihtiyacı doğduğunda uygun biçimde ayır.
- Refactor yalnızca ihtiyaç oldukça ve davranışı koruyarak yap; başka geliştiricinin alanında geniş çaplı taşıma/yeniden adlandırma yapma.
- Bir kodu tek yerde tut; tekrar kullanılıyorsa gerçekten ortak bileşen/service çıkar. Mimari uğruna mimari kurma.
- Yapılan refactor sonrası ilgili derleme, statik analiz ve testleri çalıştır.

## 5. Mimari ve güvenlik
- Ayrı istemciler (mobil/web) aynı versiyonlu backend API'yi kullanır; iş kuralları sunucudadır.
- Yetki kontrolü yalnızca istemcide değil **sunucuda her işlemde** yapılır; diyetisyen sadece aktif ilişkili ve erişimine izin verilmiş danışanı görür.
- Sahte sağlık iddiası oluşturma. Gıda fotoğrafı kalori ve porsiyonu **tahmindir**; kullanıcı düzeltir ve onaylar. Kan tahlili çıktısı **tıbbi tanı/tedavi değildir**; birim ve laboratuvar referans aralığı bilinmiyorsa kesin yorum verme.
- Gerçek sağlık verisini seed/test/log içine koyma; sırları commit etme; sahte sentetik veri kullan.
- Sağlık verisi / KVKK / açık rıza / silme / audit / mağaza yayını için `docs/11_SECURITY_AND_RELEASE.md` geçerlidir.

## 6. Çalışma ve rapor formatı
Her Codex görevi sonunda **kısa ve somut** rapor ver:
1. Ne yaptın?
2. Hangi dosyaları değiştirdin?
3. Hangi test/build/lint komutlarını çalıştırdın ve sonuçları?
4. Sözleşme (`04/05/06`) değişti mi, diğer geliştiriciyi etkiliyor mu?
5. Eksikler / bilinen hatalar / sonraki önerilen tek adım?

İstenen dışındaki değişiklikleri yapma. Kullanıcıya doğrulanmamış test sonucu bildirme. Kod değişikliği istenmemişse **hiçbir dosyayı değiştirme**.
