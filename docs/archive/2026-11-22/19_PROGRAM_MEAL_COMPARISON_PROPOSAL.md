> **TARİHSEL ARŞİV — 22.11.2026 öncesindeki metin korunmuştur.** Bu dosyadaki durumlar, test sayıları, teklifler, Git/sahiplik talimatları ve açık kararlar güncel teknik sözleşme değildir. Güncel kaynaklar [aktif belge dizininde](../../../README.md) ve [12](../../12_TEAM_PLAN_AND_DECISIONS.md) içindedir. Aşağıdaki gövde yalnız tarihsel kayıttır; yerel bağlantı yolları arşiv konumuna uyarlanmıştır.

# 19 — İkinci Uğur adımı: program–gerçekleşen öğün karşılaştırması

**Tarih:** 18.11.2026 · **İnceleme tabanı:** ortak `main`, `0678c3c`.
**Durum:** Kullanıcı 18.11.2026 tarihinde “K1–K4'ü onaylıyorum, backend ve webi
uygula” yanıtıyla bu dilimin ortak sözleşme kararını açıkça onayladı.
K1–K4 `04/05/06`ya işlendi; backend ve React uygulaması bu görev dalındadır.

Kapsam, son görev dağılımındaki ikinci Uğur işidir: karşılaştırmanın backend
hesabı ve diyetisyen web görünümü. Flutter görünümünün lideri Mert'tir.
İlk adımın ölçüm geliştirmesi ayrı #12 PR'dadır; bu dal onu birleştirmez.
Ölçüm önerisindeki M1–M4 onayından bağımsız yeni K1–K4 onayı alınmıştır.

## Mevcut koddan doğrulanan sınırlar

- `NutritionPlanItem` tavsiye metni ve serbest miktar içerir. Sayısal kalem
  hedefleri veya `MealLogItem`a doğrudan eşleştirme anahtarı yoktur.
- `NutritionPlanVersion` değişmeyen içerik snapshot'ıdır. Aktivasyon/arşivleme
  içerik sürümü oluşturmaz; geçmişte hangi sürümün hangi saatte aktif olduğunu
  kesin belirleyen aktivasyon geçmişi tutulmaz.
- `MealLog` zamanı açık offsetli instant'tır; silinmiş öğünler normal
  okumalardan çıkarılır. Kcal/makro değerleri nullable'dır.
- `nutrition_plans` ve `meal_logs` izinleri bağımsızdır. Birinden diğerine
  erişim çıkarılamaz. Kişisel hedef API'si yalnız danışanın kendisine açıktır.
- `05` hesaplanan alanlar, `06` temel zaman prensibi ve `12` hazırlık tablosu
  uyum formülü, gün/saat dilimi ve tarih–sürüm eşleştirmesini açık bırakır.

## K1 — Açık gün ve sürüm seçimi

İlk teslim **seçilen program sürümüyle bir günlük tüketimin karşılaştırması**
olur. Webde program ve sürüm açıkça seçilir; ilk seçim güncel sürümdür ve sürüm
numarası/kayıt zamanı gösterilir. Kullanıcı geçmiş sürümü ayrıca seçebilir.
Başlık ve açıklama bunun seçilen içerikle karşılaştırma olduğunu söyler;
geçmişte o gün gerçekten atanmış/aktif sürüm olduğu iddia edilmez.

İstek `from` ve `to` ile seçilen takvim gününün yerel gece yarısını ve ertesi
günün gece yarısını **ayrı açık UTC offsetleriyle** gönderir. Mevcut su günlük
toplamının sınır doğrulaması örnek alınır: iki yerel saat 00:00, takvim
tarihleri ardışık, instant olarak `from < to`. Yaz/kış saati nedeniyle offsetler
farklı olabilir. Aralık `[from,to)` olur. Takvim günü `from`un offsetli
tarihinden alınır; sunucunun yerel saati veya UTC tarihiyle değiştirilmez.

Web, kullanılan tarayıcı saat diliminin adını ve iki sınırın UTC offsetini
gösterir. Bu, danışanın kayıtlı saat dilimi veya tüm uygulamanın genel saat
dilimi kararı sayılmaz. Uzak bir danışanla farklı saat dilimindeki kullanımda
seçimin hangi güne ait olduğu görünür kalır. İlk teslimde ayrı saat dilimi
ayar sistemi eklenmez. Gün değişince sınırlar yeniden hesaplanır.

Seçilen gün snapshot'ın `startDate`–`endDate` (dahil; null bitiş sınırsız)
aralığında olmalıdır; dışında 422 döner. Draft/active/archived programların
seçilebilir sürümleri aynı okuma yetkisiyle karşılaştırılır. Bu işlem programı
etkinleştirmez ve tüketimi değiştirmez.

## K2 — Backend hesabı ve belirsizlik

Sunucu ISO haftanın gününü seçilen takvim tarihinden hesaplar. Snapshot'ta
`dayOfWeek == null` veya seçilen ISO gününe eşit öğeler kullanılır. Gruplar
mevcut beş `MealType` sırasındadır: breakfast, lunch, dinner, snack, other.
Her grupta plan öğeleri `sortOrder` artan sıralanır; alternatif grup üyeleri
birbirinin seçeneği olarak gösterilir, ayrı zorunlu öğün sayılmaz.

Gerçekleşen tarafta aynı danışanın aralıktaki silinmemiş **tüm** MealLogItem
kayıtları kendi MealLog'larının mealType'ına göre toplanır. Liste sayfalaması
toplamları etkilemez. Kayıt yokluğu yalnızca "Kayıt yok" anlamındadır; kişinin
o öğünü yemediği veya programa uymadığı sonucuna çevrilmez. Açıklama metni,
yemek adı veya gram miktarından otomatik plan–tüketim eşleştirmesi yapılmaz.

Her besin değeri için `{ knownTotal, missingItemCount }` döner:

- `knownTotal`: yalnız null olmayan değerlerin decimal toplamı; kcal veya g.
- `missingItemCount`: ilgili değeri null olan kalem sayısı.
- Gün ve her öğün için ayrıca mealLogCount, itemCount, estimatedItemCount.
- Hiç kalem yoksa bilinen toplam 0 ve eksik sayısı 0 olabilir; arayüz bunu
  günlük tam tüketim veya sıfır kalorili beslenme diye sunmaz.
- Eksik değer varsa bilinen kısım ve eksik kalem sayısı görünür; toplamın tam
  olmadığı belirtilir. Tahmini kalem sayısı ayrıca görünür.
- Günlük `caloriesDifferenceKcal`, yalnız en az bir kalem, tüm kaloriler
  biliniyor ve snapshot kalori hedefi doluysa `knownTotal - hedef` olur;
  diğer durumlarda açık null'dır. Bu, kaydedilen kcal farkıdır; sağlık veya
  uyum değerlendirmesi değildir. İstemci bu farkı yeniden hesaplamaz.

Uyum yüzdesi, "başarılı/başarısız", tamamlanan plan öğesi sayısı, otomatik
gıda eşleşmesi ve klinik eşik eklenmez. Günlük kalori hedefi yalnız seçilen
snapshot'tan alınır; kişisel hedef API'si ve su tüketimi bu hesaba katılmaz.
Makrolar gerçek kayıtlardan gösterilir; programda olmayan makro hedefleri
uydurulmaz. Sunucuda kalıcı toplam/önbellek veya yeni tablo gerekmez.
Decimal hesapta otomatik yuvarlama yapılmaz; ekran basamak sınırlaması yalnız
gösterimdir. Decimal toplamın temsil sınırını aşması kontrollü genel 422 olur;
taşmış, sonsuz veya sessizce kırpılmış sayısal yanıt dönmez.

## K3 — Onaylanan ortak HTTP/JSON sözleşmesi

Tek salt okunur yol:

`GET /api/v1/nutrition-plans/{nutritionPlanId}/versions/{versionId}/meal-comparison?from=...&to=...`

`from`/`to` zorunlu, tek değerli ve açık offsetli ISO 8601'dir; `+` URL'de
encode edilir. Başka query, gövde veya pagination kabul edilmez. Biçim/sınır
hatası 400; geçerli günün snapshot tarih aralığı dışında olması 422.
UUID'ler ve sürüm–program bağlantısı doğrulanır; yabancı/yok kaynak 404.

Onaylanan `NutritionPlanMealComparisonResponse` alanları:

| Alan | Tip / anlam |
|---|---|
| clientId | UUID; programın danışanı |
| nutritionPlanVersion | Mevcut NutritionPlanVersionResponse; id/nutritionPlanId/versionNumber/createdAt/snapshot aynı kalır |
| date | YYYY-MM-DD; seçilen offsetli başlangıcın takvim tarihi |
| from, to | UTC instant; kullanılan dahil/hariç sınırlar |
| actual | Aşağıdaki MealLogNutritionSummary; tüm gün |
| caloriesDifferenceKcal | Nullable decimal; K2'deki tam kalori şartıyla |
| meals | Aşağıdaki beş NutritionPlanMealComparison dizisi; boş gruplar da vardır |

`NutritionPlanMealComparison`: mealType (mevcut enum), plannedItems (mevcut
NutritionPlanItem dizisi; K2 gün filtresi), actual (MealLogNutritionSummary).
`MealLogNutritionSummary`: mealLogCount, itemCount, estimatedItemCount
(negatif olmayan integer); caloriesKcal, proteinGrams, carbsGrams, fatGrams
(her biri NutritionValueSummary).
`NutritionValueSummary`: knownTotal (negatif olmayan decimal),
missingItemCount (0..itemCount integer). Nullable alanlar atlanmaz.

Yanıt günlük bütün öğünlerin ham listesini içermez; mevcut izinli öğün
günlüğü ayrıntı görünümü korunur. Özet ve plan öğesi sayısı sınırlı olduğundan
gün içindeki kayıt sayısı yanıtı sınırsız büyütmez. Yeni endpoint mevcut liste
ve sürüm yollarının request/response sözleşmelerini değiştirmez.

## K4 — Yetki, web davranışı ve entegrasyon

- Bearer veya mevcut W2 web cookie; mevcut profil bağlamı kuralları geçerli.
  Danışan yalnız kendi program/tüketimini ilişkisiz de okuyabilir. Admin
  MFA ile bile bu yoldan sağlık verisi okuyamaz.
- Diyetisyen için güncel doğrulama + aktif ilişki ve **aynı ilişkinin hem
  nutrition_plans hem meal_logs açık izinleri** gerekir. İzin eksikliği 403;
  ilişkisiz/yabancı program/sürüm varlık açıklamayan 404 olur. Biri kapalıyken
  bu bileşen kısmi sonuç, hedef, sayım veya özet döndürmez; ayrı izinli program
  ve öğün bileşenleri kendi normal yetkileriyle çalışmayı sürdürür.
- Actor, ilişki, iki izin, program/snapshot ve tüketim agregasyonu aynı
  PostgreSQL repeatable-read transaction'ında okunur. Başlamış okuma kendi
  snapshot'ında tamamlanabilir; izin geri çekme commit'inden sonra başlayan
  yeni okuma reddedilir. no-store ve mevcut ortak hata/requestId biçimi.
- Web gerçek danışan detayındaki program kartında seçilen programa/sürüme
  bağlı karşılaştırmayı sunar; gün seçimi ve yenileme vardır. Program/sürüm,
  gün, danışan veya oturum değişince önceki sonuç kaldırılır; geç yanıtlar
  yok sayılır. Görünür sekmeye dönüşte/odakta ve manuel yenilemede yetki tekrar
  okunur. 403/404'te önceki hassas karşılaştırma kalmaz; 401 ortak oturumu
  sonlandırır. Hata halinde örnek/sentetik veriye düşülmez.
- Mert Flutter'da aynı yolu ve alanları kullanabilir. Bu çalışma Flutter
  dosyalarını değiştirmez; mobil ekran Mert'in işidir. Yeni alanlar ancak
  onay sonrası `04/05/06`, backend ve React'te birlikte uygulanır; ortak main
  güncellenmeden diğer checkout'ta entegrasyon tamamlandı sayılmaz.

## Uygulamadan önce kabul edilecek doğrulamalar

1. Gerçek HTTP ile kendi MealLog oluşturma → aynı gün/sürüm karşılaştırma;
   kcal/makro toplamları ve farkı, farklı öğün türleri, alternatifler/gün filtresi.
2. Null/0 değerler, tümü eksik besinler, tahmini kalemler, günün boş olması,
   silinmiş/başka danışan kayıtları, sayfa boyutunu aşan kayıtlar ve taşma.
3. Gece yarısı dahil/hariç, UTC tarihinden farklı yerel gün, 23/25 saatlik gün,
   tarih aralığı dışı seçim ve açık geçmiş sürüm; yeni revizyon eski sonucu değiştirmez.
4. İki izin ayrı ayrı kapalı/geri çekilmiş, ilişki bitmiş/pending/yabancı,
   doğrulama geri alınmış, cookie/bearer ve çift profilli hesap, Admin reddi.
5. React'te gerçek API şekli, gün/sürüm değişimi, sayısal belirsizlik,
   alternatiflerin sunumu, hata ve geç yanıtla eski veri sızmaması.
6. İlgili backend testleri/derlemesi, web test/build/lint ve sözleşme farkı
   kontrolü. Mobil–web ortak canlı prova ayrıca açıkça raporlanır.

**Onay kaydı:** K1–K4 kullanıcı tarafından açıkça onaylandı. Kanonik HTTP ve
alan tanımları `04/05/06`ya birlikte işlendi. Bu kayıt diğer açık özellikler
için toplu onay değildir. Kontrol sonuçları `12`de raporlanır.
