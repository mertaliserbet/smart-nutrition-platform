# 06 — HTTP API ortak sözleşmesi

> **İki Codex için ortak kaynak.** URL, request/response anahtarları, rol ve anlamlar burada değiştirilmeden kullanılacak. Bu bir **taslak V1 sözleşmesidir**; backend implementasyonundan önce teknoloji, auth ve MVP kapsamı onaylanır.

## Temel prensipler
- Base path: `/api/v1`. JSON `camelCase`; enum değerleri `04_NAMING_CONVENTIONS.md` içindeki lowercase değerler.
- `id` UUID string; zaman UTC ISO 8601 ör. `2026-10-15T12:30:00Z`, tarihler `YYYY-MM-DD`.
- Auth önerisi: kısa ömürlü access + yenilenebilir refresh token; secure storage/cookie ayrımı istemciye göre onaylanacak.
- Auth olmayan istek `401`, rol/ilişki yetkisiz `403`, bulunamayan `404`, doğrulama `400/422`, çakışma `409`, tekrar isteği `429`, iç hata `500`. Başka danışanın kaydına dair varlık bilgisi sızmaması için uygun yerde `404` tercih edilebilir.
- Liste: `page`, `pageSize` (sunucu limiti), `items`, `totalCount` sözlüğü; tarih aralığı gerektiğinde `from` ve `to`.
- Hata yanıtı: `error: { code: string, message: string, details?: object }, requestId: string`.
- API dokümanı ile uygulamanın OpenAPI çıktısı eşleştirilir; karşılıklı uyumsuzluk testte hata sayılır.

## Endpoint kataloğu (taslak)
| Alan | Method + route | Rol / anlam |
|---|---|---|
| Kimlik | `POST /api/v1/auth/register` | Kayıt (rol doğrulama politikası ayrı) |
| Kimlik | `POST /api/v1/auth/login` | Oturum |
| Kimlik | `POST /api/v1/auth/refresh` | Token yenileme |
| Kimlik | `POST /api/v1/auth/logout` | Oturum kapatma/refresh iptali |
| Profil | `GET /api/v1/me` | Giriş yapan kullanıcının profili |
| Profil | `PATCH /api/v1/me` | Kendi profilini güncelle |
| Diyetisyen | `GET /api/v1/dietitians` | Uygun uzman arama/görüntüleme (doğrulama şartı) |
| İlişki | `POST /api/v1/dietitian-relationships` | Danışanın ilişki talebi |
| İlişki | `GET /api/v1/dietitian-relationships` | Tarafa göre kendi bağlantıları |
| İlişki | `POST /api/v1/dietitian-relationships/{relationshipId}/accept` | Diyetisyen kabul |
| İlişki | `POST /api/v1/dietitian-relationships/{relationshipId}/reject` | Diyetisyen red |
| İlişki | `POST /api/v1/dietitian-relationships/{relationshipId}/end` | Yetkili taraf bitirir |
| Öğün | `GET /api/v1/meal-logs` | Danışanın kendi kayıtları, tarih filtresi |
| Öğün | `POST /api/v1/meal-logs` | Onaylı öğün kaydı |
| Öğün | `GET /api/v1/meal-logs/{mealLogId}` | Kendi detay |
| Öğün | `PATCH /api/v1/meal-logs/{mealLogId}` | Güncelle |
| Öğün | `DELETE /api/v1/meal-logs/{mealLogId}` | Sil / politikaya uygun işlem |
| Besin | `GET /api/v1/food-items` | Katalog araması (`query`) |
| AI yemek | `POST /api/v1/food-analyses` | Görsel gönder, tahmin işi başlat |
| AI yemek | `GET /api/v1/food-analyses/{analysisId}` | İş durum/sonuç |
| Su | `GET /api/v1/water-logs` | Kendi su kayıtları |
| Su | `POST /api/v1/water-logs` | Su ekle |
| Su | `DELETE /api/v1/water-logs/{waterLogId}` | Kendi kaydını sil |
| Ölçüm | `GET /api/v1/body-measurements` | Kendi geçmiş |
| Ölçüm | `POST /api/v1/body-measurements` | Ölçüm ekle |
| Aktivite | `GET /api/v1/activity-logs` | Kendi aktiviteleri |
| Aktivite | `POST /api/v1/activity-logs` | Aktivite ekle |
| Cihaz | `GET /api/v1/wearable-connections` | İzinli bağlantılar |
| Cihaz | `POST /api/v1/wearable-connections/sync` | İzinli/uyumlu senkronizasyon (sonraki aşama) |
| Laboratuvar | `GET /api/v1/lab-reports` | Kendi raporları |
| Laboratuvar | `POST /api/v1/lab-reports` | Ölçüm + değerler ekle |
| Laboratuvar | `GET /api/v1/lab-reports/{labReportId}` | Rapor detay |
| Laboratuvar | `POST /api/v1/lab-reports/{labReportId}/insights` | Yetkili kullanıcı için açıklayıcı analiz |
| Diyetisyen | `GET /api/v1/dietitian/clients` | Aktif/uygun danışan listesi |
| Diyetisyen | `GET /api/v1/dietitian/clients/{clientId}/dashboard` | İzinli danışan özetleri |
| Diyetisyen | `GET /api/v1/dietitian/clients/{clientId}/meal-logs` | İzinli öğün kayıtları |
| Diyetisyen | `GET /api/v1/dietitian/clients/{clientId}/lab-reports` | İzinli tahlil özet/sonuçları |
| Plan | `POST /api/v1/nutrition-plans` | Diyetisyen taslak oluşturur |
| Plan | `PATCH /api/v1/nutrition-plans/{nutritionPlanId}` | Yetkili diyetisyen düzenler |
| Plan | `POST /api/v1/nutrition-plans/{nutritionPlanId}/activate` | Atama/aktif etme |
| Plan | `GET /api/v1/nutrition-plans/active` | Danışan kendisine atanmış aktif planı görür |

**Not:** Admin, consent, bildirim, dışa aktarma vb. endpointler gereksinim netleşince eklenir; Codex bunları tahmin edip açmaz.

## Örnek 1 — manuel öğün oluşturma
```http
POST /api/v1/meal-logs
Authorization: Bearer <access-token>
Content-Type: application/json
```
```json
{
  "mealType": "lunch",
  "consumedAt": "2026-10-15T12:30:00Z",
  "note": "Öğle öğünü",
  "source": "manual",
  "items": [
    {
      "foodItemId": null,
      "displayName": "Mercimek çorbası",
      "quantityGrams": 250,
      "caloriesKcal": 180,
      "proteinGrams": 9,
      "carbsGrams": 25,
      "fatGrams": 5,
      "isEstimated": true
    }
  ]
}
```
Başarılı yanıt `201 Created`: `{ "id": "<uuid>", "clientId": "<uuid>", "mealType": "lunch", "consumedAt": "2026-10-15T12:30:00Z", "source": "manual", "items": [ ... ] }` (dönüş detayları kodlama öncesi genişletilecek). `clientId` auth öznesinden türetilir, istemciden gelen başka kullanıcı ID'sine güvenilmez.

## Örnek 2 — su ekleme
```json
{ "amountMl": 250, "consumedAt": "2026-10-15T15:00:00Z", "source": "manual" }
```
`POST /api/v1/water-logs`; negatif/sıfır miktar reddedilir. Dönen yanıt `id`, `clientId`, `amountMl`, `consumedAt`, `source` içerir.

## Örnek 3 — görsel analiz / ayrık onay
- `POST /api/v1/food-analyses`: `multipart/form-data` içindeki **`image`** dosyası; `202 Accepted` → `{ "id": "<uuid>", "status": "pending" }`.
- `GET /api/v1/food-analyses/{analysisId}` → `{ "id": "<uuid>", "status": "completed", "modelVersion": "...", "suggestions": [ { "displayName": "...", "quantityGrams": null, "caloriesKcal": null, "confidence": 0.72 } ], "limitations": ["Porsiyon doğrulanmadı"] }`.
- Tahminler kaloriye dair kesinlik iddia etmez; kullanıcı düzeltip ayrı `POST /api/v1/meal-logs` gönderir (`source: "ai_assisted"`, opsiyonel `foodAnalysisId`).

## Örnek 4 — laboratuvar verisi
```json
{
  "collectedAt": "2026-10-15T08:00:00Z",
  "labName": "Örnek laboratuvar",
  "results": [
    { "testName": "Örnek analit", "testCode": null, "value": 12.3, "unit": "unit", "referenceLow": null, "referenceHigh": null }
  ]
}
```
Sunucu `flag` hesaplar; referanslar yoksa `unknown`. Birimler normalizasyonu **kontrol edilmeden** karşılaştırma yapılmaz. `LabInsight` tıbbi tanı içeremez.

## Eşzamanlı çalışma güvenlik listesi
- Başka geliştirici API'yi uygulamadan istemci kendi endpointini üretmez; `API_CONTRACT`'a uyar ve mock'ları aynı şemayla hazırlar.
- Endpoint/alan değişikliği → 04 + 05 + 06 + OpenAPI/istemci tipleri için onaylı tek değişiklik.
- API `contract test`, rol/ilişki yetki testi ve karşılıklı parse testleri yapılmadan entegrasyon tamamlandı sayılmaz.
