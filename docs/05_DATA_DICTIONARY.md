# 05 — Ortak veri sözlüğü (domain schema)

> Kanonik model adları: `04_NAMING_CONVENTIONS.md`. Bu belge alan/tip/ilişki otoritesidir. **Taslak sözleşme**; migration hazırlamadan önce ekip onayı al. Karar temeli: `12_TEAM_PLAN_AND_DECISIONS.md` içindeki 22 onaylı karar. Bu güncelleme yalnız veri sözlüğünü değiştirir; HTTP sözleşmesi `06_API_CONTRACT.md` ayrıca uyarlanmalıdır.

Mevcut geçerli alanlar korunur; kişisel program için `NutritionPlan.dietitianId` nullable yapılır. Yeni asgari alanlar aşağıda tanımlanır. Henüz kesinleşmemiş alt kayıt adları, enum değerleri ve saklama tercihleri **AÇIK** veya **ÖNERİ** olarak ayrılır; bunlar uygulama için onaylanmış kabul edilmez. Bir domain ilişkisi tanımlanması her ilişki için ayrı tablo/model oluşturulmasını gerektirmez.

## Genel kurallar

- Tüm ilişkili sağlık kayıtları `clientId` ile kendi verisine bağlanır.
- Silme ve veri saklama süresi KVKK tasarımına göre kararlaştırılır; sağlık verisi için varsayılan herkes görür yaklaşımı **yok**.
- Sayısal ölçümler `decimal` karşılığı hassas tip; kesin olmayan kalori ve makro alanları tahmin bayrağı/analiz kaynağıyla ilişkilidir.
- Ölçümlerde `null` bilinmiyor demektir; `0` ölçülmüş gerçek sıfırdır. Eksik laboratuvar aralığı için sıfır yazılmaz. Opsiyonel ilişkilerde null, bağlantının bulunmadığını ifade edebilir; kişisel programın boş `dietitianId`si gibi istisnaların anlamı ilgili modelde belirtilir.
- Tablo adı `snake_case` çoğul: `meal_logs`, `lab_reports` vb.; backend property PascalCase; JSON camelCase.

### Tip, nullability ve birim gösterimi

Tablolarda `alan: tip?` nullable, `alan: tip` zorunludur. `?` JSON anahtarının parçası değildir. Bir alanın domain'de zorunlu olması istemcinin onu göndermesini gerektirmez: kimlik, sahiplik, hesaplanan bayrak ve audit alanları sunucu tarafından atanabilir. PATCH'te alanın gönderilmemesi ile açıkça `null` gönderilmesinin farkı `06`da tanımlanmalıdır.

| Tip | Anlam / eşleme |
|---|---|
| `uuid` | İç kayıt/FK kimliği; PostgreSQL `uuid`, JSON UUID string. `externalRecordId` dış sistemin string kimliğidir; UUID olması beklenmez |
| `instant` | UTC an; PostgreSQL `timestamptz`, JSON ofseti açık ISO 8601. `createdAt`, `updatedAt` dahil tüm `...At` alanları bu tiptedir |
| `date` | Saat dilimsiz takvim günü; PostgreSQL `date`, JSON `YYYY-MM-DD` |
| `decimal` | Kesin ondalık ölçüm; PostgreSQL `numeric`, JSON number. Hassasiyet, ölçek ve yuvarlama henüz seçilmemiştir; bilinmeyen değer sıfıra çevrilmez |
| `integer` | Tam sayı; sıralama/adet gibi anlamlar için. `dayOfWeek` gün numaralama standardı **AÇIK**tır |
| `string`, `boolean` | Metin ve true/false. Zorunlu ad/açıklama alanları boş veya yalnız boşluk olamaz; uzunluk sınırları ayrıca onaylanır |
| `object`, `list<T>` | Mantıksal nesne/koleksiyon; fiziksel tablo veya JSON/JSONB saklama seçimi değildir |
| `UserRole`, `MealType`, `RelationshipStatus`, `NutritionPlanStatus`, `FoodAnalysisStatus`, `LabFlag`, `RecordSource` | `04`teki mevcut string enumlar ve değerleri aynen korunur; yeni enum değeri eklenmez |
| `AÇIK` | Alanın adı korunur, tipi veya biçimi henüz kesinleşmemiştir; kod/DTO/migration için varsayılan tip seçilmez |

`heightCm`, `weightKg`, `waistCm` ve bilinen porsiyon/servis gramı pozitiftir; enerji, makro, mesafe ve süre negatif olamaz. `amountMl` pozitiftir; `bodyFatPercent` biliniyorsa 0–100 aralığındadır. Laboratuvar değerlerine genel bir pozitiflik kuralı uygulanmaz; analit/birim kuralları ayrıca doğrulanır. Sayılar sonlu olmalıdır; keyfî klinik alt/üst sınır uydurulmaz.

## Kullanıcı ve ilişki

| Entity | Temel alanlar | Not / kısıt |
|---|---|---|
| `User` | `id: uuid`, `email: string`, `passwordHash: string`, `role: UserRole`, `createdAt: instant`, `updatedAt: instant` | E-posta unique; hash/secret API yanıtına çıkmaz. E-posta doğrulama, şifre sıfırlama, güvenli oturum ve zorunlu Admin MFA için güvenlik kayıtlarının ayrıntıları **AÇIK**tır |
| `ClientProfile` | `id: uuid`, `userId: uuid`, `displayName: string`, `birthDate: date?`, `heightCm: decimal?` | `userId` → User ve unique; boy cm. Yaş/kişisel veri hassas ele alınır; doğum tarihi şimdilik isteğe bağlıdır |
| `DietitianProfile` | `id: uuid`, `userId: uuid`, `displayName: string`, `licenseInfo: AÇIK?`, `isVerified: boolean` | `userId` → User ve unique; uzmanı Admin doğrular. Mobil/web başvuru, belge biçimi ve doğrulama geçmişinin yapısı **AÇIK**tır; `isVerified` istemcinin kendi değiştireceği bir alan değildir |
| `DietitianClientRelationship` | `id: uuid`, `clientId: uuid`, `dietitianId: uuid`, `status: RelationshipStatus`, `requestedAt: instant`, `respondedAt: instant?`, `endedAt: instant?` | `clientId` → ClientProfile, `dietitianId` → DietitianProfile; danışan başına en fazla bir aktif ilişki. Karşılıklı onay gerekir; arama/davet kodu onayın yerine geçmez |

## Beslenme ve günlük takip

| Entity | Temel alanlar | Not / kısıt |
|---|---|---|
| `FoodItem` | `id: uuid`, `name: string`, `servingBasisGrams: decimal`, `caloriesKcal: decimal`, `proteinGrams: decimal`, `carbsGrams: decimal`, `fatGrams: decimal`, `dataSource: string` | Enerji kcal, makrolar gram; hepsi aynı `servingBasisGrams` temeline aittir. Hibrit katalog kaynağı/kanıtı korunur; sağlayıcı ve lisans seçimi **AÇIK**tır |
| `MealLog` | `id: uuid`, `clientId: uuid`, `mealType: MealType`, `consumedAt: instant`, `note: string?`, `source: RecordSource`, `foodAnalysisId: uuid?`, `createdAt: instant` | Bir öğünün kalemleri `MealLogItem`; plan dışı gerçek tüketim de kaydedilebilir |
| `MealLogItem` | `id: uuid`, `mealLogId: uuid`, `foodItemId: uuid?`, `recipeId: uuid?`, `displayName: string`, `quantityGrams: decimal?`, `caloriesKcal: decimal?`, `proteinGrams: decimal?`, `carbsGrams: decimal?`, `fatGrams: decimal?`, `isEstimated: boolean` | `recipeId` → Recipe yeni opsiyonel bağlantıdır. Değerler tüketilen kalemin toplamıdır; katalogdaki gram temeliyle karıştırılmaz. Katalog dışı giriş mümkündür; null porsiyon/besin değeri bilinmiyor demektir |
| `FoodAnalysis` | `id: uuid`, `clientId: uuid`, `status: FoodAnalysisStatus`, `createdAt: instant`, `completedAt: instant?`, `modelVersion: string?`, `suggestions: list<object>?`, `errorCode: string?` | Bir tahmin **otomatik kayıt değildir**. Öneri tipi aşağıda açıklanır; özel medya saklama politikası gerekir |
| `WaterLog` | `id: uuid`, `clientId: uuid`, `amountMl: decimal`, `consumedAt: instant`, `source: RecordSource` | Miktar mL; günlük toplam hesaplanır |
| `NutritionPlan` | `id: uuid`, `clientId: uuid`, `dietitianId: uuid?`, `title: string`, `status: NutritionPlanStatus`, `startDate: date`, `endDate: date?`, `dailyCaloriesTargetKcal: decimal?`, `dailyWaterTargetMl: decimal?`, `createdAt: instant` | **Değişiklik:** `dietitianId` nullable; null ise kişisel program, dolu ise diyetisyen programı. İkisi birlikte danışan başına en fazla bir aktif program sınırına tabidir |
| `NutritionPlanItem` | `id: uuid`, `nutritionPlanId: uuid`, `dayOfWeek: integer?`, `mealType: MealType`, `description: string`, `recommendedQuantity: AÇIK?`, `sortOrder: integer`, `recipeId: uuid?` | Her satır tavsiyedir; tüketim kaydı değildir. `recipeId` → Recipe opsiyonel bağlantıdır; sıralama negatife düşmez. Miktarın metin mi değer/birim mi olacağı, gün numaraları ve boş günün anlamı **AÇIK**tır |
| `BodyMeasurement` | `id: uuid`, `clientId: uuid`, `measuredAt: instant`, `weightKg: decimal?`, `waistCm: decimal?`, `bodyFatPercent: decimal?`, `source: RecordSource` | Kilo kg, bel cm, yağ oranı yüzde. En az bir ölçüm bulunur; istenmeyen ölçüm zorunlu yapılmaz; kaynak ve geçmiş korunur |
| `ActivityLog` | `id: uuid`, `clientId: uuid`, `activityType: string`, `startedAt: instant`, `durationMinutes: decimal?`, `distanceKm: decimal?`, `caloriesKcal: decimal?`, `source: RecordSource`, `externalRecordId: string?`, `wearableConnectionId: uuid?` | Süre dakika, mesafe km, enerji kcal. `wearableConnectionId` → WearableConnection yeni opsiyonel kaynak bağlantısıdır. Aktivite izleme, antrenman programı değildir |

### Kişisel program, hedefler ve sürüm ilişkileri

- `NutritionPlan.clientId` her iki program türünde de zorunludur ve programın danışanını belirler. Kişisel programda `dietitianId = null` olur; sahte diyetisyen kaydı/UUID'si oluşturulmaz. Kullanıcının diyetisyen ilişkisi bulunmaması program oluşturmayı engellemez.
- Diyetisyen programını yalnız yetkili diyetisyen düzenler; kişisel programı kendi danışanı düzenler. Diyetisyen programı oluşturma, atama ve düzenlemede aynı danışanla aktif ilişki gerekir. Eski programdaki diyetisyen referansı ilişki bitince null yapılarak sahiplik değiştirilmez; geçmiş erişim izni sağlamaz. İlişki bitince programın otomatik arşivlenmesi/devam etmesi ve kişisel programla geçişi **AÇIK**tır.
- `endDate` varsa `startDate`ten önce olamaz. Aktiflik `status = active` ile belirlenir; tarih aralığı tek aktif sınırını delmek için kullanılmaz. Aynı danışanın kişisel ve diyetisyen programları aynı anda aktif olamaz.
- Program hedefi ile gerçekleşen `MealLogItem`/`WaterLog` toplamları ayrı tutulur. Danışan gerçek tüketimini kaydederek programı veya diyetisyen hedefini değiştirmez. Kişisel kalori/makro/su önerileri düzenlenebilir; öneri hesaplama yöntemi ve programsız hedeflerin saklanacağı yer **AÇIK**tır. Kişisel program hedefleri mevcut nullable hedef alanlarını kullanabilir; makro hedeflerinin alan adları henüz kesinleşmemiştir.
- **Sürüm ilişkisi:** Bir `NutritionPlan`ın 1:N geçmiş sürümü bulunur; her sürüm o andaki başlık, tarih, hedef ve `NutritionPlanItem` içerik/alternatiflerini geri getirilebilir biçimde korur. Revizyon geçmiş sürümü değiştirmez. Her sürümün program bağlantısı, kararlı ayıracı, kaydeden `User` bağlantısı ve kayıt zamanı gerekir. Geçmiş sürümler ayrı aktif program sayılmaz; tüketim karşılaştırması doğru tarih/sürüme dayanmalıdır.
- **Öğün alternatifi ilişkisi:** Aynı programın aynı sürümü ve gün/öğün bağlamındaki `NutritionPlanItem` önerileri alternatif olabilir. Alternatifler birlikte zorunlu tüketim veya toplanacak ayrı öğünler gibi değerlendirilmez; başka danışanın/programın öğesi aynı gruba bağlanamaz. Kullanıcının bir alternatifi seçmesi programı düzenlemesi anlamına gelmez.
- Sürümün ayrı tablo mu snapshot mı olacağı, sürüm kimliğinin alan adı/tipi, öğelerin sürüme bağlanacağı alan ve alternatif grubunun gösterimi **AÇIK**tır. `04`te adı bulunmayan yeni sürüm/alternatif entity'si kesinleştirilmez; mevcut `nutritionPlanId` korunur. Bu teknik ayrıntılar onaylanmadan yalnız güncel öğeleri yerinde değiştirip sürüm geçmişi tamamlandı denemez.

### Tarif, görev ve yorum ilişkileri

`04`te karşılığı bulunan üç yeni kavram için asgari alanlar aşağıdadır. Bunlar yeni endpoint veya enum listesi tanımlamaz.

| Kavram | Asgari alanlar | İlişki / bütünlük |
|---|---|---|
| `Recipe` | `id: uuid`, `userId: uuid`, `name: string`, `createdAt: instant` | `userId` → tarifi oluşturan User; bir kullanıcının N tarifi olabilir. Recipe 1:N bileşenden oluşur; FoodItem ile eşleşen bileşen ilgili besine bağlanır. Bileşen modeli/yapısı ve tarif görünürlüğü **AÇIK**tır |
| `ClientTask` | `id: uuid`, `clientId: uuid`, `dietitianId: uuid`, `description: string`, `status: string`, `createdAt: instant` | Görev bir danışana ve atayan diyetisyene bağlıdır; atama için aktif/yetkili ilişki gerekir. Durum değerleri ve kimin hangi geçişi yapacağı **AÇIK**tır; serbest rastgele durum değerleri kabul edilmez |
| `DataSharingPermission` | `id: uuid`, `relationshipId: uuid`, `category: string`, `isGranted: boolean`, `consentRecordId: uuid?`, `createdAt: instant`, `updatedAt: instant` | `relationshipId` → DietitianClientRelationship; danışan/diyetisyen bu ilişkiden türetilir, tekrar saklanmaz. Kategori listesi **AÇIK**tır. Aynı ilişki/kategori için tek güncel izin bulunur; değişiklikler audit/rıza geçmişini silmez |

- Tarif bileşenlerinin miktar/birim bilgisi ve pişmiş toplam/porsiyon temeli korunmadan hesaplanmış enerji/makro gösterilmez; kaynak ve belirsizlik görünür tutulur. Bilinen gram miktarı `decimal` ve pozitiftir; bilinmeyen miktar sıfır sayılmaz. Bileşenlerin gram/adet dönüşümü, katalog dışı bileşen yapısı ve tarifin daha sonra değişmesindeki sürümleme yöntemi **AÇIK**tır.
- `MealLogItem.recipeId` veya `NutritionPlanItem.recipeId` doluysa tarif mevcut ve ilgili kullanıcıya erişilebilir olmalıdır. Tarif/katalog değişikliği önceki tüketim değerlerini veya program geçmişini yeniden yazamaz; kayıttaki değerler tüketim anındaki veriyi korur. `foodItemId` ile `recipeId`nin birlikte kullanım kuralı **AÇIK**tır; aynı kalem iki kez hesaba katılmaz.
- Görevin son tarihi ve isteğe bağlı hatırlatma tercihi tutulmalıdır. **Alan önerileri:** `dueAt: instant?` ve `isReminderEnabled: boolean`; son tarihin yalnız gün mü kesin saat mi olduğu, zorunluluğu, varsayılan tercih ve hatırlatma zamanlaması **AÇIK**tır. Bunlar onaylanmadan son tarih için keyfî alan/tip veya görev enumu eklenmez. Görev geçmişi ilişki sona erince eski diyetisyene yeni erişim sağlamaz.
- **Yorum ilişkisi:** `MealLog` 1:N yorum, `User` 1:N yazdığı yorum; cevap aynı öğünün bir yorumuna bağlıdır. Yazar danışanın kendisi veya o öğüne erişmeye yetkili diyetisyen olmalıdır. Başka öğüne/başka danışana cevap bağlantısı ve döngü kurulamaz. Diyetisyenin yorum yetkisi güncel ilişki/paylaşım kontrollerinden bağımsız değildir; bu yapı sohbet özelliği değildir.
- **Yorum için asgari alan önerisi:** `id: uuid`, `mealLogId: uuid`, `authorUserId: uuid`, `text: string`, `createdAt: instant`, `parentCommentId: uuid?` (null ise kök yorum). Kanonik yorum model adı `04`te yoktur; ayrı yorum/cevap modelleri, cevap derinliği, düzenleme/silme ve moderasyon kuralları **AÇIK**tır. Bu öneri henüz onaylı payload değildir.
- İlk sürüm yorum/cevap bildirimleri ile görev hatırlatmaları ilgili kayıt ve alıcıyla ilişkilendirilmelidir; bildirimde sağlık içeriği gösterimi paylaşım iznini aşamaz. Bildirim modeli, saklama ve teslim kanalı açık olduğundan yeni notification entity'si tanımlanmaz.

## Laboratuvar ve cihaz

| Entity | Temel alanlar | Not / kısıt |
|---|---|---|
| `LabReport` | `id: uuid`, `clientId: uuid`, `collectedAt: instant`, `labName: string?`, `note: string?`, `createdAt: instant` | Kullanıcının tek analiz/rapor oturumu; manuel/OCR giriş aynı kavramı kullanır |
| `LabResult` | `id: uuid`, `labReportId: uuid`, `testCode: string?`, `testName: string`, `value: decimal`, `unit: string`, `referenceLow: decimal?`, `referenceHigh: decimal?`, `flag: LabFlag` | Rapordaki birim/aralık esastır; sunucu hesaplar, `unknown` olabilir |
| `LabInsight` | `id: uuid`, `labReportId: uuid`, `createdAt: instant`, `summary: string`, `method: string`, `modelVersion: string?`, `limitations: AÇIK` | Sınırlılık açıklaması zorunludur; metin/liste biçimi ve method değerleri **AÇIK**tır. Kaynak/açıklanabilirlik korunur; klinik tanı içermez |
| `WearableConnection` | `id: uuid`, `clientId: uuid`, `provider: string`, `status: string`, `lastSyncedAt: instant?` | Provider/durum değerleri **AÇIK**tır; token/secrets API yanıtına çıkmaz, ayrı platform izni gerekir |
| `ConsentRecord` | `id: uuid`, `userId: uuid`, `consentType: string`, `granted: boolean`, `policyVersion: string`, `recordedAt: instant`, `withdrawnAt: instant?` | `userId` → User; izin/rıza geçmişi ve geri çekilme. Mevcut `granted` adı korunur; onay türü kodları henüz belirlenmemiştir |
| `AuditEvent` | `id: uuid`, `actorUserId: uuid`, `action: string`, `resourceType: string`, `resourceId: uuid`, `createdAt: instant`, `metadata: object?` | `actorUserId` → User; sağlık değeri/password/token loglanmaz. Kaynak türü/id çifti ilgili kaydı işaret eder; metadata ayrıntıları **AÇIK**tır |

### Paylaşım ve tahlil bütünlüğü

- `ClientProfile` → User üzerinden rıza sahibi belirlenir. `DataSharingPermission` erişim kapsamını, `ConsentRecord` rıza/izin geçmişini temsil eder; aynı kayıt veya birbirinin yerine kullanılan boolean değildir.
- Bir kategorinin diyetisyene açılması için ilgili ilişki `active`, güncel kategori izni `isGranted = true` olmalıdır. İzin kaydı yoksa diyetisyene erişim yoktur. İlişki bitince veya izin geri çekilince mevcut kayıtlar/PDF raporları dahil diyetisyenin yeni erişimi kesilir; geçmiş kayıt saklamak erişim hakkı vermez. Danışanın kendi verisine erişimi diyetisyen ilişkisine bağlı değildir.
- Tahlil kategorisi izni veriliyorsa ayrıca `consentRecordId` dolu ve ilgili danışanın User kaydına ait olmalıdır; açık onayın türü/kapsamı tahlil paylaşımıyla eşleşmeli, `granted = true`, `withdrawnAt = null` olmalıdır. Yalnız genel gizlilik kabulü veya cihaz izni yeterli değildir. Kapsam/kategori kodları onaylanmadan uydurulmaz.
- `ConsentRecord.withdrawnAt` varsa `recordedAt`ten önce olamaz; geri çekilmiş rıza yeni erişimde kullanılamaz. Rıza değişiminde geçmiş kabulün politika sürümü ve zamanı korunur. `DataSharingPermission` veya rızanın eski halinin cache'te kalması erişimi sürdürmez.
- `LabReport` en az bir `LabResult` içerir. Referans sınırları biliniyorsa aynı analit/birim için anlamlı olmalı; ikisi de varsa `referenceLow <= referenceHigh` sağlanmalıdır. Eksik/uyumsuz birim/aralıkta `flag = unknown`; sıfır referans uydurulmaz. Tek taraflı aralıkların güvenli değerlendirme kuralı **AÇIK**tır.
- OCR, kullanıcı doğrulamasından önce değerlendirmeye alınan kesin `LabResult` üretmez. Taslak OCR değeri, orijinal birim/referans/tarih ve kullanıcı onayının nasıl saklanacağı **AÇIK**tır; doğrulanmış veriyle karıştırılamaz. Trendler yalnız aynı analit ve aynı/doğrulanmış dönüştürülmüş birimle karşılaştırılır. `LabInsight` tanı/tedavi değildir; ML kullanımı opsiyonel ve validasyona bağlıdır.

### Aktivite, platform kaynağı ve tekilleştirme

- `ActivityLog.wearableConnectionId` doluysa bağlantının `clientId`si aktivite sahibine eşit olmalıdır. `source = wearable` olan içe aktarımda bu bağlantı zorunludur; sağlayıcı buradan belirlenir. Manuel girişte platform bağlantısı ve dış kimlik zorunlu değildir; `source` gerçeği yansıtır.
- İçe aktarılan kaydın kararlı dış kimliği varsa `externalRecordId` korunur; aynı danışan + sağlayıcı + dış aktivite kimliği tekrar aktarımda ikinci kayıt oluşturmaz. Bağlantının yeniden kurulması bu kuralı bozmaz. Sağlayıcı kararlı kimlik vermiyorsa kaynak anahtarı üretme politikası **AÇIK**tır; sahte UUID ile tekilleştirme tamamlandı sayılmaz.
- Manuel/cihaz örtüşmesini belirleme yöntemi **AÇIK**tır; yalnız dış ID kontrolü manuel kaydın aynı aktivite olduğunu kanıtlamaz. Örtüşen veriler günlük toplamlarda çift sayılmaz; otomatik birleştirme/silme eşiği uydurulmaz. İzin geri alındığında yeni senkronizasyon durur; silme/saklama ayrı politikadır.
- Health Connect/HealthKit kapsamındaki mesafe km, süre dakika, enerji kcal olarak açık birimle normalleştirilir; orijinal kaynak korunur. `ActivityLog.caloriesKcal` alanının aktif/toplam enerji anlamı mevcut sözleşmede kesinleşmemiştir; aktif kaloriyle sessizce eşitlenmez.

| Ek sağlık verisi | Gerekli mantıksal ilişki / tip | Açık ayrıntı |
|---|---|---|
| Adım sayısı | ClientProfile'a ait 1:N kaynak kayıt; `integer`, birim adım; kayıt zaman/aralığı ve varsa WearableConnection bağlantısı | Kanonik model/alan adı, zaman aralığı ve gün bazlı agregasyon |
| Nabız | ClientProfile'a ait 1:N kaynak ölçüm; `decimal`, birim atım/dakika; ölçüm zamanı ve varsa WearableConnection bağlantısı | Kanonik model/alan adı; tek ölçüm/seri ve aktiviteyle opsiyonel eşleme |
| Aktif kalori | ClientProfile'a ait kaynak kayıt; `decimal`, birim kcal; aktivite veya zaman aralığı bağlamı | Alan/model adı; aktivite kaydı ile günlük toplamın ayrımı |

Bu verilerin tamamı zorla `ActivityLog` veya `BodyMeasurement` içine yerleştirilmez. Manuel giriş imkânı korunur; eksik ölçüm sıfır olmaz. Bağımsız kayıt mı mevcut modele bağlantı mı gerekeceği onaylanmadan genel amaçlı karmaşık bir ölçüm tablosu tasarlanmaz.

## İlişki ve bütünlük kuralları

- `User` 1:0..1 `ClientProfile` **veya** `DietitianProfile` (rol modeli netleştirilecek); `DietitianClientRelationship` üzerinde kullanıcı ID yerine profil ID kullanılır.
- `ClientProfile` 1:N `MealLog`, `WaterLog`, `LabReport`, `ActivityLog`, `BodyMeasurement`.
- `ClientProfile` 1:N `NutritionPlan`, `ClientTask`, `DietitianClientRelationship`, `WearableConnection`; `DietitianProfile` 1:N atadığı ClientTask ve diyetisyen programı. Kişisel programın DietitianProfile bağlantısı yoktur.
- `MealLog` 1:N `MealLogItem`; `LabReport` 1:N `LabResult`; `NutritionPlan` 1:N `NutritionPlanItem`.
- `FoodAnalysis` bağımsız rapordur; isteğe bağlı `MealLog.foodAnalysisId` ilişkisi vardır. İki kaydın danışanı aynı olmalıdır; analiz başka danışanın öğününe bağlanamaz. Katalog/tarif referansı olmayan manuel `MealLogItem` geçerlidir.
- `LabResult.flag` referans aralığına güvenilebiliyorsa hesaplanır; aralık yoksa/uyumsuzsa `unknown`.
- `ActivityLog.externalRecordId` ve bağlantının provider'ı üzerinden kaynak özelinde tekrar içe alma engellenir; kaynak bağlantısı aynı danışana ait olmalıdır.
- Diyetisyen programı ve görev atamasında ilgili diyetisyenle danışan arasında yetkili/aktif ilişki olmalı; bu şart kişisel program oluşturmak için aranmaz. Diyetisyenin görev/yorum/rapor erişimlerinde de güncel ilişki ve kategori izinleri kontrol edilir.
- **Tek aktif diyetisyen:** Her `clientId` için `status = active` olan ilişki sayısı en fazla 1'dir. Kabul işlemi diğer aktif ilişkiyle yarıştığında da kural korunur. `active` ilişki karşılıklı onaylanmış olmalı (`respondedAt` dolu, `endedAt` boş); `ended` için `endedAt` doludur. Olay sırası `requestedAt <= respondedAt <= endedAt` olacak şekilde mevcut zamanlara uygulanır; diğer durum geçiş ayrıntıları **AÇIK**tır. Geçmiş ilişki silinerek veya profil kimliği değiştirilerek sınır aşılmaz.
- **Tek aktif program:** Her `clientId` için `status = active` olan NutritionPlan sayısı en fazla 1'dir; `dietitianId`ye göre ayrı ayrı sayılmaz. Program değiştirmede eski aktif kaydın durum değişimi ve yeni kaydın aktifleşmesi tutarlı/atomik olmalıdır. Aynı anda iki aktivasyon sınırı aşamaz; tarihleri farklı iki `active` kayıt da kabul edilmez.
- Bu iki tekillik yalnız UI kontrolüyle sağlanmaz; backend ve PostgreSQL tarafında eşzamanlı işlemlerde de korunur. Kısmi unique indeks/transaction gibi mekanizmanın ayrıntısı uygulama kararıdır; burada migration/SQL üretilmez.
- FK bağlantılarında danışanın özel alt kayıt/program/analizleri başka danışanın özel kayıtlarına bağlanamaz. Ortak katalog/tarif bağlantısı için ilgili kaynağa erişim yetkisi ayrıca kontrol edilir; bunların görünürlüğü özel sağlık kaydı sahipliğiyle karıştırılmaz. Tarihçe koruma kararı otomatik cascade silme veya süresiz saklama anlamına gelmez; silme/anonymizasyon/FK davranışı veri koruma tasarımında netleşir.

## Hesaplanan / saklanan alan ayrımı

Günlük kalori, makro ve su toplamları `MealLogItem`/`WaterLog` kayıtlarından hesaplanabilir. Agregasyon performans için tutulacaksa tutarlılık/yeniden hesaplama politikası gerekir. Bilinmeyen besin değerleri tam toplam varmış gibi sıfır sayılmaz; eksiklik görünür olmalıdır. Grafikler ve PDF raporları aynı yetkili kaynak verilerden üretilir; bunlar için otomatik yeni entity veya sağlık verisi kopyası gerekmez. Program uyum hesabı, tarih/sürüm eşleştirmesi ve günlük saat dilimi politikası **AÇIK**tır.

`FoodAnalysis.suggestions` için `06`daki mevcut örnek; `displayName: string`, `quantityGrams: decimal?`, `caloriesKcal: decimal?`, `confidence: decimal` (0–1) içerir. Kalori/porsiyon belirsizliği korunur. Onaylı makro tahmini için aynı `proteinGrams`/`carbsGrams`/`fatGrams` adları nullable decimal/gram olarak kullanılmalıdır; `06`daki öneri şeması bunları henüz içermemektedir. Analiz düzeyindeki `limitations` dönüşü `06`da vardır; saklanacak mı üretilecek mi olduğu ve `10` ile iç içelik uyumu **AÇIK**tır. Kullanıcı düzeltip ayrıca onaylamadan MealLog oluşturulmaz.

## `06_API_CONTRACT.md` ile uyumsuzluklar (bu görevde değiştirilmedi)

- Plan oluşturma/düzenleme/aktif etme işlemleri yalnız diyetisyen için anlatılır; kişisel NutritionPlan sahipliği, nullable `dietitianId` ve danışanın kendi programını düzenlemesi API'ye yansıtılmalıdır. Mevcut endpointler bu dosyada değiştirilmez veya yeni alternatif rota üretilmez.
- `Recipe`, `ClientTask`, `DataSharingPermission` ve yeni `recipeId`/`wearableConnectionId` bağlantılarının request/response karşılıkları yoktur. Sürüm/alternatif, yorum/cevap, son tarih/hatırlatma ve tahlil açık onayı için de payload/yetki kuralları tamamlanmalıdır.
- Mevcut enum değerleri korunmuştur; görev durumları, paylaşım kategorileri ve provider değerleri henüz belirlenmemiştir. Bunlar serbest string olarak istemcilerde ayrı ayrı uydurulamaz. API null/eksik alan ve PATCH davranışı netleştirilmelidir.
- Aktivite sağlayıcı kimliği, tekilleştirme, adım/nabız ve aktif enerji ayrımı mevcut API örneklerinde tanımlı değildir. Lab OCR taslağı/kullanıcı onayı, güvenli birim dönüşümü ve LabInsight yanıt ayrıntıları da eksiktir.
- Fotoğraf analizi önerilerinde makrolar eksiktir; `limitations` biçim/konumu belgeler arasında netleştirilmelidir. E-posta doğrulama, şifre sıfırlama ve Admin MFA'nın HTTP ayrıntıları bu veri sözlüğüyle belirlenmez.

## Onay bekleyen şema kararları

Tek aktif diyetisyen/program, kişisel program, program sürüm geçmişi ve öğün alternatifleri **onaylı gereksinimlerdir**; yeniden açık ürün kararı sayılmaz. Açık kalanlar:

- Sürüm/alternatif/yorum alt kayıtlarının kanonik adları, alanları ve saklama biçimi; tüketim–program sürümü eşleştirmesi. Öğün kayıtlarının kendi sürümleme ihtiyacı ayrıca açıktır.
- Tarif bileşenleri, toplam/porsiyon temeli, görünürlük ve değişiklik geçmişi; kişisel makro hedef alanları, programsız hedeflerin yeri ve öneri hesaplama yöntemi.
- Görev son tarihinin gün/saat anlamı ve nullability'si, durum geçişleri, hatırlatma tercihleri; yorum/cevap moderasyonu ve bildirim teslim modeli.
- Paylaşım kategorileri, rıza tür/kapsam kodları, davet/başvuru doğrulama kayıtları, çoklu rol/profil ve doğum tarihi zorunluluğu.
- Nabız/adım/aktif enerji veri yapıları, platform/cihaz desteği ve manuel/cihaz örtüşme politikası; günlük zaman dilimi ve yeniden senkronizasyon anahtarları.
- Besin sağlayıcısı/lisans, test kod standardı, birim dönüşümleri, OCR onay kaydı, AI modeli/veri validasyonu; `licenseInfo`, `recommendedQuantity` ve `LabInsight.limitations` biçimleri.
- Auth/MFA güvenlik kayıtları, sayısal hassasiyet/yuvarlama, metin sınırları, veri/fotoğraf/PDF saklama-silme ve anonimleştirme; geçmişi koruyan FK davranışları. Gerçek yayın için `11_SECURITY_AND_RELEASE.md` kapısı geçerlidir.

Sonraki ortak sözleşme adımı; açık alt kayıt adlarını `04`te, şema ayrıntılarını burada ve HTTP karşılıklarını `06`da iki geliştiricinin onayıyla eşgüdümlü tamamlamaktır. Bu görev yalnız `05`i günceller; diğer belgelerdeki eski açık karar/alan açıklamaları yerinde kalmıştır.
