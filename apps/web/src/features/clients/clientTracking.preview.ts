import type { BodyMeasurement, ClientProfileListItem, MealLog, WaterLog } from './clientTracking.types'

// Fictional, development-only presentation fixtures. No dashboard, permission,
// category, Auth or open-schema API response is defined here.
export const previewClients: ClientProfileListItem[] = [
  { id: '10000000-0000-4000-8000-000000000001', displayName: 'Örnek Deniz' },
  { id: '10000000-0000-4000-8000-000000000002', displayName: 'Örnek İpek' },
  { id: '10000000-0000-4000-8000-000000000003', displayName: 'Örnek Işık' },
  { id: '10000000-0000-4000-8000-000000000004', displayName: 'Örnek Çağla' },
  { id: '10000000-0000-4000-8000-000000000005', displayName: 'Örnek Öykü' },
  { id: '10000000-0000-4000-8000-000000000006', displayName: 'Örnek Şule' },
]

export function getPreviewRecords(clientId: string) {
  const clientIndex = previewClients.findIndex((client) => client.id === clientId)
  if (clientIndex === -1) return undefined
  const id = (sequence: number) => `20000000-0000-4000-8000-${String(clientIndex + 1).padStart(8, '0')}${String(sequence).padStart(4, '0')}`
  const mealLogs: MealLog[] = [
    {
      id: id(1), clientId, mealType: 'lunch', consumedAt: '2026-10-25T09:00:00Z',
      source: 'manual', foodAnalysisId: null, createdAt: '2026-10-25T09:05:00Z',
      note: 'Bu öğün yalnızca ekranı incelemek için hazırlanmış sentetik bir örnektir.',
      items: [
        { id: id(2), mealLogId: id(1), foodItemId: null, recipeId: null,
          displayName: 'Mercimek çorbası (örnek)', quantityGrams: 250, caloriesKcal: 180,
          proteinGrams: 9, carbsGrams: 25, fatGrams: 5, isEstimated: true },
        { id: id(3), mealLogId: id(1), foodItemId: null, recipeId: null,
          displayName: 'Salata (örnek)', quantityGrams: null, caloriesKcal: null,
          proteinGrams: null, carbsGrams: null, fatGrams: null, isEstimated: true },
      ],
    },
    {
      id: id(4), clientId, mealType: 'snack', consumedAt: '2026-10-25T12:00:00Z',
      source: 'manual', foodAnalysisId: null, createdAt: '2026-10-25T12:01:00Z', note: null,
      items: [{ id: id(5), mealLogId: id(4), foodItemId: null, recipeId: null,
        displayName: 'Şekersiz çay (örnek)', quantityGrams: 200, caloriesKcal: 0,
        proteinGrams: 0, carbsGrams: 0, fatGrams: 0, isEstimated: false }],
    },
  ]
  const waterLogs: WaterLog[] = [
    { id: id(6), clientId, amountMl: 250, consumedAt: '2026-10-25T07:30:00Z', source: 'manual' },
    { id: id(7), clientId, amountMl: 400, consumedAt: '2026-10-25T10:00:00Z', source: 'manual' },
  ]
  const bodyMeasurements: BodyMeasurement[] = [
    { id: id(8), clientId, measuredAt: '2026-10-18T06:00:00Z', weightKg: 72.4,
      waistCm: 83.1, bodyFatPercent: null, source: 'manual' },
    { id: id(9), clientId, measuredAt: '2026-10-25T06:00:00Z', weightKg: 72.1,
      waistCm: null, bodyFatPercent: null, source: 'manual' },
  ]
  return { mealLogs, waterLogs, bodyMeasurements }
}
