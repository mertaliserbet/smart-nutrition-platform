# 16 — 29 Ekim beslenme programı oluşturma ve atama dilimi

**Tarih:** 29.10.2026 · **Durum: N1–N3 ORTAK ONAYLI.** Kullanıcı
“N1–N3 için ortak onay var; uygula.” yanıtıyla Uğur–Mert onayını teyit etti.
Lider Uğur; backend ve web. Flutter kaynakları değişmez. Güncel normatif
kaynak `04/05/06`dır; bu karar diğer açık sağlık/yayın paketlerine yayılmaz.

## N1 — program öğeleri ve istek/yanıt

- Mevcut `NutritionPlan` ve `NutritionPlanItem` adları/yolları korunur.
  POST title/startDate/items zorunlu; endDate, dailyCaloriesTargetKcal,
  dailyWaterTargetMl nullable. Diyetisyen clientId gönderir; kendi
  dietitianId'si sunucudan. Danışan clientId/dietitianId göndermez; kendi
  kişisel programı dietitianId=null olarak oluşturulur. Başlangıç draft.
- title kırpılmış 1–120 karakter; her description kırpılmış 1–2000 Unicode
  kod noktası. Tarihler date, endDate >= startDate. Hedefler bilinmiyorsa
  null; biliniyorsa pozitif decimal, kcal/mL. Yuvarlama/otomatik hesap yoktur;
  kalori/makro önerisi veya klinik hesap bu dilimde üretilmez.
- items 1–100 kalem. Her kalemde mealType mevcut enum, description ve
  sortOrder >=0 zorunlu; sortOrder aynı sürümde tektir. dayOfWeek nullable,
  ISO 1=Pazartesi..7=Pazar; null her gün. recommendedQuantity nullable
  serbest öneri metni, kırpılmış 1–200 karakter; boş metin null'a dönüşür.
- recipeId bu ilk dilimde yalnız null/atlanmış olabilir; dolu değer 422.
  Tarif şeması onaylanmadan tarif modeli/bağlantısı taklit edilmez.
- Yeni nullable item alanı alternativeGroupId: uuid. Aynı gün/mealType
  bağlamında en az iki alternatif bir yerel grup UUID'siyle gruplanabilir;
  farklı gün/mealType'lar aynı grupta olamaz. Grup kimliği yalnız ilgili
  program sürümünde anlamlıdır; başka program kalemine FK değildir.
- Item id/nutritionPlanId yanıt alanlarıdır, sunucu üretir; POST/PATCH kalem
  girdisinde kabul edilmez. Alternatif seçimi programı değiştirmez ve öğün
  kaydı oluşturmaz. Öğün gerçek tüketimi bu modülün dışındadır.
- Yanıt mevcut `05/06` NutritionPlan alanlarını ve items'ı eksiksiz taşır;
  iki yeni sunucu alanı versionId: uuid ve versionNumber: integer eklenir.
  İlk sürüm 1'dir; bilinmeyen nullable anahtarlar yanıtta null kalır.
- PATCH yalnız title/startDate/endDate/iki hedef/items; gönderilmeyen korunur,
  nullable alan açık null ile temizlenir. title/startDate/items null olamaz;
  items gönderilirse tüm koleksiyon değiştirilir. Boş PATCH/ek alan/kimlik
  veya status değiştirme girdisi 400; alan değer sınırları 422.
- POST/PATCH JSON gövdesi 128 KiB; şekil/tip/ek alan 400, değer 422,
  gövde aşımı 413, yanlış medya 415. Cookie yazmasında W2 CSRF/Origin gerekir.

## N2 — sürüm geçmişi ve tek aktif bütünlüğü

- Yeni kanonik sunucu modeli `NutritionPlanVersion`: id, nutritionPlanId,
  versionNumber, recordedByUserId, createdAt ve snapshot. snapshot o andaki
  title/tarihler/hedefler/items'ı koruyan JSONB'dir. Kalemlerin geçmiş ID ve
  grup bilgileri eski snapshot'ta değişmez. Snapshot sonradan güncellenmez.
- NutritionPlan güncel alanları/items JSONB'sini ve versionNumber'ı tutar;
  sürüm tablosunda (nutritionPlanId,versionNumber) unique ve User/Plan FK
  bulunur. Geçmiş sürümler bağımsız aktif program sayılmaz.
- Her geçerli PATCH yeni sürüm oluşturur; önceki sürümü yeniden yazmaz.
  Gövde birebir tekrar gönderilirse de yeni kaydetme/sürüm sayılır;
  istemci yazmayı otomatik tekrarlamaz. Güncel kalemler yeniden sunucu ID'si
  alır; eski sürüm kalemleri korunur. Yeni sürüm ve güncel program tek
  transaction'da, ClientProfile ve program satır kilitleriyle kaydedilir.
- Yeni `GET /nutrition-plans/{nutritionPlanId}/versions`: page/pageSize
  zorunlu; `{ items, totalCount }`, item id/nutritionPlanId/versionNumber/
  createdAt. Yeni `GET /nutrition-plans/{nutritionPlanId}/versions/{versionId}`:
  aynı metadata + snapshot. recordedByUserId yalnız sunucuda tutulur.
- Mevcut activate gövdesizdir; düzenleme yetkisiyle draft/archived programı
  active yapar. Zaten aynı tek aktif program 200; başka aktif program
  `409 active_nutrition_plan_conflict`. Aktiflik tarih aralığından bağımsız
  tek durumdur; ikinci active DB kısmi unique indeksle de engellenir.
- Yeni `POST /nutrition-plans/{nutritionPlanId}/archive`, gövdesiz,
  aynı düzenleme yetkisi; 200 archived, tekrarda değişmeyen 200. Bu işlem
  programı durdurur; başka programı etkinleştirmez. İçerik sürümü status
  değişiminde artmaz; geçmiş içerik ve sahiplik korunur.
- Otomatik veya çapraz sahiplikli program değiştirme yolu bu dilimde
  eklenmez. Başka aktif program sessizce arşivlenmez. Kişisel aktif program
  sahibi tarafından açıkça durdurulmadan diyetisyen ikinci programı
  etkinleştiremez; 409 gösterilir. Genel replace/geçiş isteği sonraki dilimdir.

## N3 — erişim, ilişki bitişi ve web akışı

- Danışan kendi kişisel/atanmış tüm programlarını ve sürümlerini okuyabilir;
  diyetisyen ilişkisi gerekmez. Yalnız kişisel programını yazar/etkinleştirir/
  arşivler. Atanmış program/hedefler danışana salt okunurdur.
- Doğrulanmış diyetisyen, aktif ilişki + R2 nutrition_plans izni ile
  danışanın kişisel/atanmış programlarını okur. Yalnız dietitianId'si
  kendisi olan programı yazar/etkinleştirir/arşivler. İzin yoksa 403;
  ilişkisiz veya başka danışana ait kaynakta varlık açıklamayan 404.
- GET liste diyetisyende clientId + page/pageSize ister; danışan kendi
  kapsamı için yalnız page/pageSize gönderir. Sıra createdAt azalan/id.
  GET active yalnız danışanın kendi tek aktif programını döndürür; yoksa 404.
  Literal active yolu program UUID'si olarak yorumlanmaz. Admin erişmez.
- Program yazmaları, iznin geri çekilmesi ve ilişki sonlandırmasıyla aynı
  ClientProfile kilidini kullanır; stale izinle yeni yazma commit edilmez.
- **R1'de açık bırakılan bitiş kararı:** aktif ilişki sona erdiğinde o
  diyetisyenin bu danışana ait active atanmış programı aynı transaction'da
  archived olur. dietitianId/içerik/sürüm geçmişi değişmez; danışan arşivi
  okumayı sürdürür, eski diyetisyenin yeni erişimi kesilir. Kişisel program
  otomatik durdurulmaz. Böylece eski ilişkinin aktif programı yeni ilişkiyi
  ikinci aktif programla kilitlemez. Bu sistem geçişi doğrudan danışan
  program düzenleme yetkisi oluşturmaz.
- Webde gerçek danışan detayına program listesi, taslak oluşturma, kendi
  atadığı programı düzenleme, açık etkinleştirme/arşivleme ve geçmiş
  sürüm görüntüleme eklenir. Danışanın kişisel/başkasının atadığı programı
  salt okunur gösterir. İlk form miktar metni/gün/öğün ve kalem içeriklerini
  kullanır; varsayılan klinik hedef doldurmaz. Alternatif grup alanları
  API'de doğrulanır; UI'de grup oluşturma isteğe bağlıdır.
- Program kategorisi kapalıysa program bölümü veriyi kaldırır ve erişim
  durumunu gösterir; temel danışan kimlik görünümüne sahte sağlık özeti
  eklenmez. 401/CSRF bağlam hatasında hassas UI temizlenir. Başarısız veya
  409 aktivasyonda atanmış/aktif başarı mesajı gösterilmez; taslak korunur.
- Mobil entegrasyon Mert'in alanıdır. Yeni DTO ve sürüm alanları belgelenir;
  Flutter kodu yazılmaz. Program önerileri tıbbi tanı veya otomatik diyet değildir.

## Kabul ve onay

Testler: kişisel/atanmış sahipliği, kategori/ilişki geri çekme, başka danışan
ve alt kayıt kimliği, tek aktif program yarışı/DB indeksi, atomik sürüm ve
rollback, eski snapshot değişmezliği, ilişki bitişinde atanmışın arşivlenmesi,
literal active rotası, CSRF, gerçek web istek/hata/iptal/409 ve salt okunurluk.

**Ortak onay kaydı:** Kullanıcının açık teyidi: “N1–N3 için ortak onay var; uygula.”

**Uygulama ve doğrulama:** Backend/web birlikte uygulandı; Flutter kaynakları
değişmedi. Geçici PostgreSQL + Mailpit üzerinde 250 backend testi (0 atlama),
128 web testi, typecheck/lint ve production build geçti. Migration
`AddNutritionPlansAndVersions` mevcut şemaya program/sürüm tablolarını ekler.
Kabul senaryoları gerçek HTTP/DB testleri ve web bileşen/istek testleriyle
doğrulandı; tam canlı tarayıcı/mobil sunum provası henüz yapılmadı.

## Sentetik sunum sırası

1. Webde uzman başvurusu, e-posta doğrulaması ve ayrı MFA Admin onayı.
2. Doğrulanmış uzman girişi; çalışma alanında davet kodu üretimi.
3. Danışan API/mobil tarafında pending talep; uzman webde kabul eder.
   Danışan nutrition_plans iznini ayrıca açar. Kabul tek başına izin vermez.
4. Webde gerçek danışanı aç; boş hedeflerle taslak oluştur, gün/miktar ve
   istenirse aynı öğünde iki alternatif göster. Kaydetme sonrası açıkça
   etkinleştir; danışan GET active üzerinden atanmış programı salt okunur okur.
5. İçeriği değiştirip yeni sürüm kaydet; eski sürümü geçmişten aç. Başka aktif
   program varsa 409'u göster; otomatik program değiştirme yapılmaz.
6. İlişkiyi sonlandır; atanmış active programın archived olduğunu ve danışanın
   geçmişi okuyabildiğini doğrula. Eski uzmanın yeni erişimi reddedilir.

Bu sıra yalnız sentetik hesap/veriyle kullanılır. Yerel Admin, HTTPS ve DB
kurulumu backend/web README'lerindedir; gerçek sağlık verisi/yayın kapısı `11`dir.
