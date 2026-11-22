# Ortak çalışma talimatları — Smart Nutrition Platform

Sıfırdan geliştirilen diyetisyen odaklı mobil + web + API ürünüdür. Çalışma usulünde güncel kullanıcı talimatı ve bu dosya, README ve planlardaki eski Git, sahiplik ve hazırlık ifadelerinin önündedir.

## 1. Görev ve yazma sınırları

- Yalnız istenen işi ve görevin izin verdiği dosyaları değiştir. İlgisiz ekran, teknoloji, paket, endpoint veya veri modeli ekleme. Yalnız inceleme/rapor istenmişse hiçbir dosyayı değiştirme.
- **`AGENTS.md`, bütün `README.md` dosyaları ve `docs/**` varsayılan olarak salt okunurdur.** Yalnız kullanıcı açıkça ilgili belgeyi düzenleme görevi verirse o belge değiştirilebilir. Kod geliştirme, sözleşme onayı veya belgede hata bulmak otomatik belge güncelleme izni vermez; eksik ve çelişkileri sonuç raporunda belirt.
- Belge düzenleme görevi kod, uygulama iskeleti veya yeni belge oluşturma izni değildir. Korunan dosyaları biçimlendirme ya da araç çıktısı yoluyla da değiştirme.
- Ürün veya sağlık açısından önemli belirsiz kararları kendiliğinden kesinleştirme. Kapsam dışı değişiklik gerekiyorsa nedenini ve öneriyi raporla; bağımsız, izinli işleri sürdür.

## 2. Görev öncesi inceleme

- Bu dosyayı, kök `README.md`, `docs/01_PROJECT_SCOPE.md`, `docs/12_TEAM_PLAN_AND_DECISIONS.md` ve ilgili ekran/AI/mimari belgesini oku. Her zaman `docs/04_NAMING_CONVENTIONS.md`, `docs/05_DATA_DICTIONARY.md`, `docs/06_API_CONTRACT.md` dosyalarının ilgili tanımlarını kontrol et.
- Gerçek repository yapısını, mevcut kodu ve ilgili testleri önce incele; kullanılmayan alternatifler veya tamamlanmış işlerin kopyalarını oluşturma.
- `git status`, `git branch --show-current`, `git remote -v`, yakın commitler ve ilgili dosyaların diff'leriyle checkout'u ve bekleyen değişiklikleri kontrol et. Uzak depo adını varsayma; URL ile doğrula. Yerel Git bilgisi uzak deponun güncelliğini kanıtlamaz.
- Eski hazırlık tabloları, teslim notları ve görev kimlikleri yeni görevin zorunlu başlangıç koşulu değildir. İlgili gerçek açık kararları güncel uygulama ve kesinleşmiş sözleşmeyle değerlendir.
- **`docs/archive/**` tarihsel başvuru kaynağıdır; güncel teknik sözleşme veya uygulama yetkisi sayılmaz.**

## 3. Görev bazlı sorumluluk ve koordinasyon

- Mert ağırlıklı olarak Flutter/mobil, Uğur ağırlıklı olarak React/web geliştirir. **Backend, API, veritabanı, migration, test ve entegrasyonu her ikisi de üstlenebilir; backend tek kişiye ait değildir.** Her iki geliştirici diğerinin daha önce geliştirdiği backend modüllerinde çalışabilir. Yazma sorumluluğunu kişinin adı değil, güncel görevin kapsamı belirler.
- Backend veya ortak modülde değişiklikten önce mevcut kodu, son değişiklikleri ve diğer geliştiricinin devam eden işlerini kontrol et. Diğer checkout/oturumun durumunu doğrulayamıyorsan bunu belirt; çakışma ihtimali olan kısmı sorumluluk netleşmeden değiştirme.
- Aynı fiziksel checkout'a iki oturum eşzamanlı yazmaz. Ayrı checkout'larda da aynı dosya veya özellik üzerinde koordinasyonsuz paralel değişiklik yapılmaz; çakışan iş için görev bazında tek değişiklik sorumlusu belirlenir. Bu, kalıcı kişi sahipliği değildir.
- Özellikle EF Core migration, `AppDbContext`, model snapshot ve ortak API sözleşmesinde tek görev sorumlusu bulunur; aynı anda iki migration üretilmez. Farklı zamanlarda her iki geliştirici de bu dosyalarda çalışabilir. Migration sırasını ve uygulanmış DB sürümünü kontrol et; paylaşılmış/uygulanmış migration geçmişini silme veya yeniden adlandırma.
- Uygulama veritabanına migration uygulamak ayrıca açık görev kapsamı ve doğrulanabilir yedek gerektirir; mevcut kayıtları koru.

## 4. Git çalışma modeli ve işlem yetkisi

- Ortak depo `https://github.com/mertaliserbet/smart-nutrition-platform.git`, entegrasyon dalı `main`dir.
- Mevcut model korunur: **Mert bu checkout'ta yerel `main` üzerinde çalışır**; ortak uzak depo `origin`dir. **Uğur kendi checkout'unda ortak `main` tabanlı görev/feature branch'i kullanır**, kendi fork'una gönderir ve ortak deponun `main` dalına PR açar; ortak `main`e doğrudan push yapmaz. Uğur'un belgelenmiş uzak adları ortak depo için `upstream`, fork için `origin`dir; her checkout'ta URL'leri ayrıca doğrula.
- Bu model işlem izni değildir. **Açık kullanıcı talimatı olmadan Git senkronizasyonu (`fetch`/`pull`), commit, push, merge, rebase, reset, stash veya force işlemi yapma; dal oluşturma/değiştirme/silme ya da PR açma/birleştirme/kapatma.** Temiz çalışma ağacı otomatik pull gerekçesi değildir. Commit mesajı istemek commit/push izni vermez.
- Geliştiriciyi ve checkout'u doğrulamadan bu akışları birbirine uygulama. Kullanıcı istemedikçe Mert'e feature branch/PR zorunluluğu getirme. Dal stratejisi belirsiz veya yeni talimatla çelişkiliyse kararı raporla; kendiliğinden dal değiştirme.
- Kullanıcı değişikliklerini ezme veya otomatik stash/reset ile kaldırma. Force push yapma, başkasının commitini silme, paylaşılmış/uzak geçmişi yeniden yazma. İzinli Git işleminde de iki tarafın işini koru; güvenli ilerlenemiyorsa çakışmayı raporla.
- Dal, commit/PR başlığı, dosya, klasör ve modül adlarında geliştirme aracının adını kullanma; değişikliğin amacını anlatan proje terimleri kullan.

## 5. Ortak teknik sözleşme

- Kanonik adlar `docs/04_NAMING_CONVENTIONS.md`, alan/tip/ilişkiler `docs/05_DATA_DICTIONARY.md`, HTTP rotaları/DTO/JSON/hatalar `docs/06_API_CONTRACT.md` ile belirlenir. API, DTO veya veritabanı yapısını varsayarak oluşturma; ilgili kesinleşmiş tanımı ve mevcut uygulamayı birlikte kontrol et. Taslak veya açık şemadan kesin kod/mock üretme.
- Aynı kavramı C#, Dart ve TypeScript'te koru; dilin sözdizimi farklı olabilir, JSON anahtarları `camelCase` ve sözleşmedeki enum değerleri ortak kalır. Eşanlamlı entity, alternatif endpoint veya kopya model oluşturma; örneğin `MealLog` yerine `FoodRecord` türetme.
- Mevcut kanonik ad, endpoint, zorunlu alan veya ortak şema değişikliği için önce çakışmayı, öneriyi ve backend/mobil/web etkilerini raporla; iki geliştiricinin açık ortak onayı olmadan değiştirme. Kullanıcı bu onayı mevcut görevde teyit etmişse yeniden isteme. Belge yazma ve Git işlemi izinleri ayrıca kendi kurallarına tabidir.
- Güncel kod ile belge veya belgeler kendi aralarında çelişirse kendi kararınla sözleşmeyi değiştirme. İlgili dosyaları ve somut farkı raporla; çelişkili bölüm için yeni kod/DTO üretme, bağımsız izinli işe devam et. Korunan belgeler değişmeden kalır.
- Ortak entegrasyondan önce iki checkout'un kullandığı onaylı sözleşme ve API sürümlerinin uyumunu doğrula; bu gereklilik otomatik Git işlemi yetkisi vermez.

## 6. Mimari, modülerlik ve güvenlik

- Onaylı teknolojiler Flutter/Dart, React/TypeScript, ASP.NET Core/C# ve PostgreSQL'dir; AI gerektiğinde Python/FastAPI kullanılır. Yeniden teknoloji seçme. Mobil/web aynı versiyonlu backend API'yi kullanır; iş kuralları sunucudadır, istemciler DB'ye doğrudan bağlanmaz.
- Tek sorumluluk ve feature-based yapı kullan. Bağımsız büyük sorumluluklar, gerçek ortak kullanım veya test ihtiyacı doğduğunda ayır; her küçük metot/widget için dosya, gereksiz katman veya derin klasör üretme. Tekrarlanan kodu gerçekten ortak bileşen/service olarak tut.
- Refactor yalnız görev gerektiriyorsa ve davranışı koruyarak yapılır; kapsam dışı geniş taşıma/yeniden adlandırma yapma. Sonrasında ilgili derleme, statik analiz ve testleri çalıştır.
- Eski fitness repo/doküman/kodlarını kopyalama, taşıma veya referans alma. Trainer, workout planı, gym ekipmanı kapsamda yoktur; yalnız beslenmeye destek günlük fiziksel aktivite kaydı vardır.
- Yetkiyi **sunucuda her işlemde** kontrol et. Doğrulanmış diyetisyen yalnız aktif ilişkili ve kategori izni verilmiş danışan verisini görür; tahliller ayrıca geri çekilmemiş açık onay gerektirir. Admin sağlık verisini varsayılan göremez. Danışanın kendi verisine erişimi diyetisyen ilişkisine bağlı değildir.
- En fazla bir aktif diyetisyen ve kişisel/atanmış toplamında bir aktif beslenme programı kuralını, geçmişi ve veri sahipliğini koru. Danışan atanmış programı/hedefleri değiştiremez; gerçek tüketimini serbestçe kaydeder.
- Gıda fotoğrafından kalori/porsiyon tahmindir; kullanıcı düzeltip onaylamadan sağlık kaydı oluşmaz. Tahlil/OCR çıktısı kullanıcı onayı gerektirir, tanı/tedavi değildir; geçerli birim ve laboratuvar referansı yoksa kesin yorum verme.
- Gerçek sağlık verisini seed/test/log içine koyma; sentetik veri kullan, sırları commit etme. Sağlık verisi, KVKK, açık rıza, silme, audit ve mağaza yayını için `docs/11_SECURITY_AND_RELEASE.md` kurallarını koru.

## 7. Doğrulama ve sonuç raporu

- Uygulanmış/tamamlanmış işleri, testle doğrulanan davranışları ve planlanan özellikleri ayrı değerlendir. Geçmiş test raporu güncel çalıştırma sonucu değildir; atlanan, başarısız veya ortam nedeniyle çalıştırılamayan kontrolleri açıkça belirt. Belge onayı uygulama, test veya yayın tamamlanması sayılmaz.
- Görevle ilgili build/lint/testleri ve dosya değiştiyse `git diff --check` çalıştır. Belge düzenlemesinde gereksiz uygulama testleri çalıştırma; yalnız izinli dosyaların değiştiğini son diff ile doğrula.
- Her görev sonunda kısa Türkçe rapor ver:
  1. Ne yapıldı ve hangi dosyalar değişti?
  2. Hangi doğrulama komutları çalıştı, sonuçları ve çalıştırılamayanlar neler?
  3. Sözleşme (`04/05/06`) değişti mi; diğer geliştiriciye etkisi nedir?
  4. Belge/kod çelişkileri, belirsizlikler, bilinen eksikler ve sonraki önerilen tek adım nedir?
  5. İstenmişse Türkçe Conventional Commit mesajı öner.
