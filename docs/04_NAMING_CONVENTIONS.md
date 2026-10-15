# 04 — KANONİK İSİMLENDİRME SÖZLEŞMESİ

> **TEK KAYNAK (source of truth):** İki Codex'in aynı alanı farklı adlandırmasını engelleyen ortak kurallar. `05_DATA_DICTIONARY.md` alan tiplerini; `06_API_CONTRACT.md` URL ve payloadları belirler. Değişiklik süreci için `AGENTS.md` ve `12_TEAM_PLAN_AND_DECISIONS.md`.

## Kanonik terimler (kesin geçerli çalışma sözlüğü)
| Türkçe kavram | Backend/domain (PascalCase) | JSON/TS/Dart adı | API kaynağı |
|---|---|---|---|
| Kullanıcı hesabı | `User` | `user` | `/users` (admin ihtiyacı halinde) |
| Danışan profili | `ClientProfile` | `clientProfile` | `/dietitian/clients` (diyetisyen görünümü) |
| Diyetisyen profili | `DietitianProfile` | `dietitianProfile` | `/dietitians` |
| Diyetisyen–danışan ilişkisi | `DietitianClientRelationship` | `dietitianClientRelationship` | `/dietitian-relationships` |
| Öğün kaydı | `MealLog` | `mealLog` | `/meal-logs` |
| Öğün besin kalemi | `MealLogItem` | `mealLogItem` | `MealLog.items` altında |
| Besin katalog girdisi | `FoodItem` | `foodItem` | `/food-items` |
| Görsel besin analizi | `FoodAnalysis` | `foodAnalysis` | `/food-analyses` |
| Su kaydı | `WaterLog` | `waterLog` | `/water-logs` |
| Beslenme planı | `NutritionPlan` | `nutritionPlan` | `/nutrition-plans` |
| Plan öğesi | `NutritionPlanItem` | `nutritionPlanItem` | `NutritionPlan.items` altında |
| Vücut ölçümü | `BodyMeasurement` | `bodyMeasurement` | `/body-measurements` |
| Aktivite kaydı | `ActivityLog` | `activityLog` | `/activity-logs` |
| Tahlil raporu | `LabReport` | `labReport` | `/lab-reports` |
| Tahlil değeri | `LabResult` | `labResult` | `LabReport.results` altında |
| Tahlil açıklayıcı analizi | `LabInsight` | `labInsight` | `/lab-reports/{labReportId}/insights` |
| Cihaz bağlantısı | `WearableConnection` | `wearableConnection` | `/wearable-connections` |
| İzin/rıza kaydı | `ConsentRecord` | `consentRecord` | henüz endpoint kararı yok |
| Denetim olayı | `AuditEvent` | `auditEvent` | yalnız backend/admin; endpoint kararı yok |

**Yasak eşanlamlı entity örnekleri:** `FoodRecord`/`MealEntry`/`Meal` yerine `MealLog`; `DietPlan`/`MealPlan` yerine `NutritionPlan`; `BloodTest`/`MedicalReport` yerine `LabReport`; `Coach`/`Trainer` yerine `Dietitian`. `FoodAnalysis` ile `MealLog` farklı kavramlardır.

## Dil ve dosya kuralları
| Konum | Kural | Örnek |
|---|---|---|
| C# class/entity/DTO | `PascalCase` | `MealLog`, `CreateMealLogRequest` |
| C# property | `PascalCase` | `ConsumedAt`, `ClientId` |
| C# local/param | `camelCase` | `mealLogId` |
| TypeScript type/component | `PascalCase` | `MealLog`, `MealLogCard` |
| TS/Dart variable/field | `camelCase` | `caloriesKcal`, `consumedAt` |
| Flutter file | `snake_case.dart` | `meal_log_page.dart` |
| Web TSX file | isim tutarlı; component `PascalCase.tsx`, helper `camelCase.ts` | `MealLogCard.tsx` |
| Backend dosya | C# type ile `PascalCase.cs` | `MealLogService.cs` |
| DB table/column | `snake_case` çoğul tablolar | `meal_logs`, `consumed_at` |
| REST endpoint | `/api/v1/` + çoğul `kebab-case` kaynak | `/api/v1/meal-logs` |
| JSON fields | **her yerde `camelCase`** | `clientId`, `caloriesKcal` |
| Git branch | `feature/`, `fix/`, `docs/` + kebab-case | `feature/client-meal-logs` |

## Alan ve birim isimleri
- Kimlik: `id`; ilişki alanları `clientId`, `dietitianId`, `mealLogId` gibi `...Id`. Önerilen ID: UUID string.
- Zaman: olay zamanı `...At` (UTC ISO 8601), takvim günü `...Date` (`YYYY-MM-DD`), tüm saatler net ofset ile.
- Enerji: `caloriesKcal` (kcal); besin makroları `proteinGrams`, `carbsGrams`, `fatGrams` (gram); su `amountMl` (mL); vücut ağırlığı `weightKg`, boy `heightCm`; porsiyon `quantityGrams` (gram).
- Değer+birim ayrılmaz: laboratuvar `value`, `unit`, `referenceLow`, `referenceHigh`; rapordaki laboratuvar aralığı saklanır.
- Boolean `is...`/`has...`, ör. `isVerified`, `isEstimated`.
- İşleme durumu `status`; sabit string enumlar **lowercase** ve gerektiğinde `snake_case`.

## Başlangıç enum sözlüğü
| Enum | JSON değerleri |
|---|---|
| `UserRole` | `client`, `dietitian`, `admin` |
| `MealType` | `breakfast`, `lunch`, `dinner`, `snack`, `other` |
| `RelationshipStatus` | `pending`, `active`, `rejected`, `ended` |
| `NutritionPlanStatus` | `draft`, `active`, `archived` |
| `FoodAnalysisStatus` | `pending`, `processing`, `completed`, `failed` |
| `LabFlag` | `low`, `normal`, `high`, `unknown` |
| `RecordSource` | `manual`, `wearable`, `ai_assisted` |

## Değişiklik yönetimi — kritik
1. Yeni kavram gerekiyorsa mevcut terimin karşılığı mı, gerçek yeni domain kavramı mı kontrol et.
2. Aynı kavramsa **mevcut adı yeniden kullan**. Yeni gerekliyse ad önerisini ekip onayına sun.
3. Onay sonrası **önce bu sözlüğü**, sonra `05`, `06`, etkilenen UI/AI belgelerini **aynı PR/commit** içinde güncelle.
4. API breaking change ise sürüm/taşıma/istemci etkisini yaz ve iki geliştiriciden onay al.
5. İki geliştirici de aynı commit'i çektikten sonra ilgili kod değişikliğine başlasın; diğer Codex'e çelişkili isim üretme görevi verme.

**Karar boşlukları:** ilişkide birden fazla aktif diyetisyen, laboratuvar test kod standardı ve besin veri kaynağı henüz onaylanmadı; uydurma değerler ekleme.
