# 05 — Ortak veri sözlüğü (domain schema)

> Kanonik model adları: `04_NAMING_CONVENTIONS.md`. Bu belge tablo/alan/anlam otoritesidir. **Taslak sözleşme**; migration hazırlamadan önce ekip onayı al. Tüm `id`/`...Id` UUID; `createdAt`, `updatedAt` UTC instant. Saklanacak teknik alanlar aşağıdaki asgari alanlara eklenebilir ancak yeni domain alanları onay gerektirir.

## Genel kurallar
- Tüm ilişkili sağlık kayıtları `clientId` ile kendi verisine bağlanır.
- Silme ve veri saklama süresi KVKK tasarımına göre kararlaştırılır; sağlık verisi için varsayılan herkes görür yaklaşımı **yok**.
- Sayısal ölçümler `decimal` karşılığı hassas tip; kesin olmayan kalori ve makro alanları tahmin bayrağı/analiz kaynağıyla ilişkilidir.
- `null` bilinmiyor demektir; `0` ölçülmüş gerçek sıfırdır. Eksik laboratuvar aralığı için sıfır yazılmaz.
- Tablo adı `snake_case` çoğul: `meal_logs`, `lab_reports` vb.; backend property PascalCase; JSON camelCase.

## Kullanıcı ve ilişki
| Entity | Temel alanlar | Not / kısıt |
|---|---|---|
| `User` | `id`, `email`, `passwordHash`, `role`, `createdAt`, `updatedAt` | E-posta unique; hash/secret API yanıtına çıkmaz |
| `ClientProfile` | `id`, `userId`, `displayName`, `birthDate?`, `heightCm?` | `userId` unique; yaş/kişisel veri hassas ele alınır |
| `DietitianProfile` | `id`, `userId`, `displayName`, `licenseInfo?`, `isVerified` | Belgeli doğrulama süreç kararı bekliyor |
| `DietitianClientRelationship` | `id`, `clientId`, `dietitianId`, `status`, `requestedAt`, `respondedAt?`, `endedAt?` | `clientId` → ClientProfile, `dietitianId` → DietitianProfile; V1 tek aktif ilişkili kural öneri |

## Beslenme ve günlük takip
| Entity | Temel alanlar | Not / kısıt |
|---|---|---|
| `FoodItem` | `id`, `name`, `servingBasisGrams`, `caloriesKcal`, `proteinGrams`, `carbsGrams`, `fatGrams`, `dataSource` | Besin bileşimi kullanılan gram temeline bağlı; kaynak/kanıt saklanır |
| `MealLog` | `id`, `clientId`, `mealType`, `consumedAt`, `note?`, `source`, `foodAnalysisId?`, `createdAt` | Bir öğünün kalemleri `MealLogItem` |
| `MealLogItem` | `id`, `mealLogId`, `foodItemId?`, `displayName`, `quantityGrams?`, `caloriesKcal?`, `proteinGrams?`, `carbsGrams?`, `fatGrams?`, `isEstimated` | Katalog dışı kullanıcı girdisi mümkün; null porsiyon bilinmiyor |
| `FoodAnalysis` | `id`, `clientId`, `status`, `createdAt`, `completedAt?`, `modelVersion?`, `suggestions[]?`, `errorCode?` | Bir tahmin **otomatik kayıt değildir**. Özel medya saklama politikası gerekir |
| `WaterLog` | `id`, `clientId`, `amountMl`, `consumedAt`, `source` | Pozitif miktar; günlük toplam hesaplanır |
| `NutritionPlan` | `id`, `clientId`, `dietitianId`, `title`, `status`, `startDate`, `endDate?`, `dailyCaloriesTargetKcal?`, `dailyWaterTargetMl?`, `createdAt` | Plan diyetisyen sahipliğindedir; tek aktif plan kuralı karar bekliyor |
| `NutritionPlanItem` | `id`, `nutritionPlanId`, `dayOfWeek?`, `mealType`, `description`, `recommendedQuantity?`, `sortOrder` | Her satır plan tavsiyesidir; kullanıcı tüketim kaydı değildir |
| `BodyMeasurement` | `id`, `clientId`, `measuredAt`, `weightKg?`, `waistCm?`, `bodyFatPercent?`, `source` | İstenmeyen ölçümleri zorunlu yapma |
| `ActivityLog` | `id`, `clientId`, `activityType`, `startedAt`, `durationMinutes?`, `distanceKm?`, `caloriesKcal?`, `source`, `externalRecordId?` | Aktivite izleme, antrenman programı değil. Dış ID ile dedup |

## Laboratuvar ve cihaz
| Entity | Temel alanlar | Not / kısıt |
|---|---|---|
| `LabReport` | `id`, `clientId`, `collectedAt`, `labName?`, `note?`, `createdAt` | Kullanıcının tek analiz/rapor oturumu |
| `LabResult` | `id`, `labReportId`, `testCode?`, `testName`, `value`, `unit`, `referenceLow?`, `referenceHigh?`, `flag` | Rapordaki birim/aralık esastır; `flag=unknown` olabilir |
| `LabInsight` | `id`, `labReportId`, `createdAt`, `summary`, `method`, `modelVersion?`, `limitations` | Kaynak ve açıklanabilirlik; klinik tanı içermez |
| `WearableConnection` | `id`, `clientId`, `provider`, `status`, `lastSyncedAt?` | Token/secrets API yanıtına çıkmaz; ayrı izin |
| `ConsentRecord` | `id`, `userId`, `consentType`, `granted`, `policyVersion`, `recordedAt`, `withdrawnAt?` | İzin geçmişi ve geri çekilme |
| `AuditEvent` | `id`, `actorUserId`, `action`, `resourceType`, `resourceId`, `createdAt`, `metadata?` | Sağlık değeri/password loglanmaz; erişim/işlem izleri |

## İlişki ve bütünlük kuralları
- `User` 1:0..1 `ClientProfile` **veya** `DietitianProfile` (rol modeli netleştirilecek); `DietitianClientRelationship` üzerinde kullanıcı ID yerine profil ID kullanılır.
- `ClientProfile` 1:N `MealLog`, `WaterLog`, `LabReport`, `ActivityLog`, `BodyMeasurement`.
- `MealLog` 1:N `MealLogItem`; `LabReport` 1:N `LabResult`; `NutritionPlan` 1:N `NutritionPlanItem`.
- `FoodAnalysis` bağımsız rapordur; isteğe bağlı `MealLog.foodAnalysisId` ilişkisi vardır.
- `LabResult.flag` referans aralığına güvenilebiliyorsa hesaplanır; aralık yoksa/uyumsuzsa `unknown`.
- `ActivityLog.externalRecordId`/provider üzerinden kaynak özelinde tekrar içe alma engellenir.
- Planın diyetisyeni ile danışan arasında yetkili/aktif ilişki olmalı.

## Hesaplanan / saklanan alan ayrımı
Günlük kalori, makro ve su toplamları `MealLogItem`/`WaterLog` kayıtlarından hesaplanabilir. Agregasyon performans için tutulacaksa tutarlılık/yeniden hesaplama politikası gerekir. `FoodAnalysis.suggestions` öneri şeması `06_API_CONTRACT.md` altında belirlenir.

## Onay bekleyen şema kararları
Tek aktif diyetisyen/plan kısıtı; doğum tarihi zorunluluğu; besin veri sağlayıcısı; laboratuvar test kod standardı; gıda fotoğrafları saklama ve anonimleştirme; öğün/plan sürümleme.
