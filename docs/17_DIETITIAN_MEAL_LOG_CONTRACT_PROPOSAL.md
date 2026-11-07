# 17 — İlk Uğur adımı: diyetisyenin salt okunur öğün günlüğü

**Tarih:** 07.11.2026 · **Durum: G1 ORTAK ONAYLI; UYGULAMA YALNIZ G1.**

Kullanıcı, ön raporun ikinci sayfasındaki “Beslenme, Ölçüm ve Aktivite
Modülleri (12.11.2026)” aşamasına Uğur'un görevleriyle, tek tek başlanmasını
istedi. Kullanıcı “Ortak onay var; yalnız G1’i uygula” yanıtıyla ortak onayı
teyit etti. Bu teslim G1'dir; G2–G3 sonraki ayrı adımlar olarak kalır.
G1 normatif kaydı `04/05/06/11/12`ye işlenir.
Rapordaki tarih planlama başlığıdır; uygulamanın tamamlandığı anlamına gelmez.
Kanonik kaynaklar `04/05/06`, sahiplik ve hazırlık kaynağı `12` olarak kalır.

## İlk özelliğin sonucu ve sınırı

Diyetisyen, aktif ilişkili ve öğün paylaşım izni veren danışanının öğünlerini
webde kaynak, zaman, miktar, enerji ve makro alanlarıyla salt okunur izler.
Bu ilk özellik sonraki yorum/cevap işinin de veri ve yetki temelidir.

Su, ölçüm/grafik, aktivite, kişisel hedef, program–tüketim karşılaştırması,
yorum/cevap/bildirim, görev ve Health Connect/HealthKit ayrı adımlardır.
Burada bunların kategorileri, DTO'ları veya hesaplama kuralları belirlenmez.

## İnceleme bulguları

İnceleme tabanı ortak `main`: `93b7106`. Önceki web paneli PR #7 açıktır;
bu belge o PR'ı değiştirmez veya birleştirmez. Web uygulama adımında panelin
ortak main'deki güncel hali kullanılmalı; ikinci bir panel oluşturulmamalıdır.

| Bulgu | Mevcut kaynak | Etki |
|---|---|---|
| `MealLog`, `MealLogItem`, `MealType` C# modelleri var; EF'e kayıtlı değiller, öğün API'si/migration'ı yok | `backend/src/SmartNutrition.Api/Features/MealLogs/`, `Data/AppDbContext.cs`, `backend/README.md` | Gerçek okuma, Mert'in öğün saklama/yazma dilimine bağımlı |
| Webde öğün tipleri ve `MealLogList` var; yalnız sentetik önizlemede kullanılıyor | `apps/web/src/features/clients/clientTracking.types.ts`, `ClientRecordViews.tsx`, `ClientDetailsPage.tsx` | Mevcut sunum yeniden kullanılabilir; önizleme verisi gerçek panele taşınmaz |
| Diyetisyen öğün liste yolu ve öğün yanıt alanları belgeli; kategori eşlemesi açık | `06`, günlük kayıtlar ve kaynak/kategori erişimi; `12`, hazırlık tablosu | Rota varlığı gerçek yetkilendirme/uygulama onayı değildir |
| İzin API'si/modeli/DB kısıtı yalnız `nutrition_plans` kabul ediyor | `Features/Relationships/DataSharingPermissionsController.cs`, `RelationshipModels.cs` | Öğün erişimi mevcut program izninden türetilemez |
| Mobil izin ayrıştırıcısı yalnız `nutrition_plans` ve ilişki başına en fazla bir izin bekliyor | `mobile/lib/features/dietitians/dietitian_api.dart`, `permission()` ve `_permission()` | İkinci kategori eski mobil bağlantı ekranını bozabilir; geçiş eşgüdüm gerektirir |

## G1 — Ortak onaylı ek öğün paylaşım izni

- Mevcut `DataSharingPermission` ve `DietitianClientRelationship` korunur.
  Yeni entity/rol veya genel `all` izni eklenmez. **Önerilen ek kategori kodu
  `meal_logs`**, yalnız aşağıdaki G2 öğün okumasına karşılık gelir.
- `nutrition_plans` program yetkisini sürdürür; iki kategori bağımsızdır.
  Eski program izni öğünleri açmaz. Öğün izni başka sağlık kategorisini açmaz.
- Mevcut POST/PATCH/GET izin yolları ve JSON alanları korunur. İzin oluşturma
  yalnız `nutrition_plans` veya `meal_logs` kabul edecek şekilde genişletilir;
  diğer kodlar bu dilimde `422` kalır. `consentRecordId` bu iki kategoride
  yalnız null/atlanmış olabilir. Tahlil açık onayı ayrı kalır.
- Yalnız aktif ilişkinin danışanı kendi iznini açar/geri çeker. Diyetisyen
  ve Admin danışan adına izin veremez. Pending/ended yazmaları mevcut `409`
  davranışını korur. Her ilişki/kategori için tek güncel izin vardır.
- İzin kaydı yoksa veya `isGranted=false` ise erişim kapalıdır. Yeni kategori
  için otomatik izin satırı, varsayılan true, geçmiş izinlerden kopyalama veya
  backfill yapılmaz. İlişki biterse kayıt geçmişi yeni erişim sağlamaz.
- Önerilen DB değişikliği yalnız mevcut kategori check kısıtını iki değere
  genişletir; ilişki/kategori unique indeksi ve eski izinler korunur. Bu
  öğün tablolarının migration'ı değildir. Geri alma yeni kategori satırlarını
  sessizce silerek yapılamaz; veri koruyan geri alma ayrıca kontrol edilir.

**Mobil geçiş koşulu:** İzin listesinin `{ items, totalCount }` anlamı
değiştirilmez; istemciyi tahmin ederek farklı liste döndürülmez. Mert,
ayrıştırıcı/modeli kategori taşıyacak ve birden çok kategori satırını
sayfalayarak okuyup doğru kategoriyle eşleştirecek şekilde uyarlamalıdır.
`nutrition_plans` anahtarı mevcut işlevini korur; danışan öğün paylaşımını
ayrı ve açık bir işlemle seçer. Bu uyarlama ve regresyon doğrulanmadan aynı
ortamda `meal_logs` yazması etkinleştirilmez. Bu görev Flutter'a yazmaz.

G1 uygulamasında dahili `Relationships:Sharing:MealLogsEnabled` ayarı
varsayılan false'tur. Kapalıyken meal_logs POST (true/false) ve mevcut
satıra PATCH true `422`; mevcut satırı geri çeken PATCH false aynı yetkiyle
`200` olur. Ayar satırları gizlemez/silmez ve danışan izni vermez. Eski
mobil sürüme dönüş yalnız flag kapatılarak güvenli sayılmaz.

## G2 — Mevcut diyetisyen öğün okuma yolunun kesinleştirilmesi önerisi

Yeni rota veya alias önerilmez:
`GET /api/v1/dietitian/clients/{clientId}/meal-logs`.

| Parça | Önerilen davranış |
|---|---|
| İstek | Gövdesiz; zorunlu `page` ve `pageSize`, isteğe bağlı `from`/`to`; başka query yok |
| Sayfalama | `page >= 1`; yalnız bu uç için `1 <= pageSize <= 100`; varsayılan yok. Web açıkça 10 gönderir. Int32 offset taşması dahil geçersiz biçim/değer `400` |
| Zaman | Mevcut `consumedAt` filtresi; `from` dahil, `to` hariç. Verilen an açık UTC/ofset içermeli, UTC'ye normalize edilmeli; ikisi varsa `from < to`. Eksik ofset/geçersiz aralık `400` |
| Sıra | `consumedAt` azalan, eşitlikte `id` artan; filtre ve sıra sayfalama öncesinde uygulanır |
| Başarı | `200`, mevcut `{ items, totalCount }`; sayı yalnız yetkili ve filtrelenmiş öğünleri kapsar. Yetkili boş küme `items=[]`, `totalCount=0` |
| Öğün | `05/06`daki alanlar aynen: `id`, `clientId`, `mealType`, `consumedAt`, `note`, `source`, `foodAnalysisId`, `createdAt`, `items` |
| Kalem | `id`, `mealLogId`, `foodItemId`, `recipeId`, `displayName`, `quantityGrams`, `caloriesKcal`, `proteinGrams`, `carbsGrams`, `fatGrams`, `isEstimated` |

Nullable anahtarlar açık null kalır; yeni alan veya bağımsız özet DTO'su
eklenmez. Decimal değerler JSON number, zamanlar UTC ISO 8601, enum değerleri
`04`teki mevcut değerlerdir. Dönen her öğün istenen danışana, her kalem kendi
öğününe ait olmalıdır. Referans kimlikleri katalog/tarif/AI verisine ayrıca
erişim hakkı vermez; bu yol ilişkili kaynakları genişletmez veya hesaplamaz.

Her okumada sunucuda güncel e-posta/hesap, onaylı DietitianProfile, danışanla
aktif ilişki ve aynı ilişkide açık `meal_logs` izni kontrol edilir. Temel rolü
client kalan onaylı çift profilli hesap aynı uzman denetimiyle kabul edilir.
Danışanın kendi `/meal-logs` erişimi ilişki şartına bağlanmaz; o yolun
yazma/saklama uygulaması Mert'in dilimidir. Admin sağlık yetkisi kazanmaz.

- Eksik/geçersiz oturum `401`; uygun olmayan/onaysız uzman veya Admin `403`.
- Olmayan danışan, başka uzmanın danışanı veya artık aktif olmayan ilişki
  `404`; varlık bilgisi/sağlık kaydı sayısı açıklanmaz.
- Kendi aktif danışanında öğün izni yok/kapalı ise `403`; kayıtlı öğün olup
  olmadığı açıklanmaz. Bu durum sahte boş listeye dönüştürülmez.
- Hatalar mevcut ortak `error`/`requestId` zarfını kullanır. DB hatası `500`
  ve kapalı erişimdir; kayıt notları/değerleri loga veya hata gövdesine çıkmaz.
- W2 HTTPS cookie ve mevcut istemciler için JWT kabulü, aynı kaynak/kimlik
  kurallarını uygular. Web aynı origin cookie kullanır; kalıcı JS tokenı yoktur.
  Yanıtlar `no-store` olur. İzin/ilişki kontrolü, sayım ve satır okuması
  tutarlı yapılır; geri çekme sonrasında başlayan okuma veriyi açamaz.

## G3 — İlk web görünümü ve kabul önerisi

Mevcut gerçek danışan detayında “Öğün günlüğü” bölümü ve mevcut `MealLogList`
sunumu kullanılır. Program yönetimi kendi izniyle çalışmaya devam eder;
öğün izninin kapalı olması program iznini kapatmaz veya tersini sağlamaz.

- Sayfalama ve açık yenileme bulunur. Tarih-saat filtresinde seçilen ofset
  kullanıcıya gösterilir; API'ye UTC an gönderilir. “Bugün”, günlük toplam
  veya hedef uyumu için henüz kararlaştırılmamış gün/saat dilimi seçilmez.
- Miktar/besin değeri null ise “Bilinmiyor”, gerçek sıfır birimiyle sıfır,
  `isEstimated=true` ise “Tahmini” gösterilir. Günlük makro/kalori toplamı
  veya klinik değerlendirme bu adımda üretilmez.
- Yükleniyor, yetkili boş liste, paylaşım kapalı, bulunamadı ve ağ/sunucu
  hatası ayrı görünür. Danışan/filtre/sayfa değişince eski içerik ve sayılar
  hemen gizlenir; önceki istek iptal edilir, geç yanıt yok sayılır.
- İzin geri çekilince sonraki okumada öğünler/sayılar kaldırılır. Polling
  veya anlık bildirim vaadi yoktur. Önbellekteki/sentetik veriye dönüş yoktur.
- Web tüketim kaydını düzenlemez/silmez; yorum/cevap alanı bu ilk adıma eklenmez.

## Sahiplik ve uygulama sırası

1. **Onay kaydı:** Öneri önce koddan ayrı hazırlandı. Kullanıcı
   “Ortak onay var; yalnız G1’i uygula” yanıtını verdi.
2. **Bu görevdeki Uğur kod adımı:** G1 paylaşım izin altyapısı ve
   mevcut program izinlerini koruyan testler. Onaylı `04/05/06` değişikliği,
   backend etkisi ve mobil geçiş notu birlikte ele alınır. Kategori kullanımı
   mobil uyumluluk koşulunu bekler; Flutter değişikliğini Mert yapar.
3. **Mert bağımlılığı:** mevcut MealLog/MealLogItem saklama, danışanın öğün
   kayıt/yazma API'si, ilgili migration ve mobil paylaşım uyarlaması ortak
   main'e entegre edilir. Ayrıntılı yazma/AI/tarif kararları bu okuma
   önerisinden onaylanmış sayılmaz; bu dosyaların liderliği devralınmaz.
4. **Sonraki Uğur adımı:** G2 salt okunur API ve G3 web entegrasyonu;
   gerçek veri kaynağı olmadan endpoint veya kesin API mock'u üretilmez.

Her adım ayrı tamamlanıp raporlanır; bu onay diğer 12 Kasım modüllerini
aynı görevde uygulama talimatı değildir. Ortak sözleşme değişikliği sonrası
iki geliştirici aynı main sürümüne eşitlenerek entegrasyon yapar.

## Uygulamada doğrulanacak kabul kontrolleri

- Mevcut `nutrition_plans` izni öğün açmaz; `meal_logs` izni program açmaz.
  Eksik izin, aktif olmayan/yabancı ilişki, onaysız uzman ve Admin erişemez.
- Mobilde aynı ilişkiye ait iki kategori kaydı, sayfalama ve kategoriye göre
  açma/geri çekme mevcut program paylaşımını bozmaz. İzinler otomatik açılmaz.
- Yetki kaybından sonraki okuma ve DB hatası kayıt/sayı sızdırmaz; çift profil
  doğru uzman bağlamında çalışır. Yanlış danışan/kalem sahipliği gösterilmez.
- Sayfalama/zaman sınırları, stabil sıra, null–sıfır ayrımı ve tahmin etiketleri
  doğrulanır; filtre/rota değişimi veya geç yanıt eski veriyi geri getirmez.
- Backend entegrasyonları sentetik PostgreSQL verisiyle; web testleri,
  typecheck/lint/build ve iki temada responsive kontrol ilgili uygulama
  adımında çalıştırılır. Bu belge bunların geçtiğini iddia etmez.

**Kapsam teyidi:** Kullanıcının ortak onay yanıtı kaydedildi. Bu kod görevi
yalnız G1'dir; G2–G3 bağımlılıklarıyla sırada kalır. Kontrollerin gerçekleşen
sonuçları görev raporunda belirtilir; yukarıdaki kabul listesi test sonucu değildir.
