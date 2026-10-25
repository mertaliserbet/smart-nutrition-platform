// Only closed fields from docs/04, 05 and 06. This list item is the explicit
// id/displayName subset of ClientProfile, not a full profile/dashboard DTO.
export type ClientProfileListItem = { id: string; displayName: string }
export type RecordSource = 'manual' | 'wearable' | 'ai_assisted'
export type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snack' | 'other'

export type MealLogItem = {
  id: string
  mealLogId: string
  foodItemId: string | null
  recipeId: string | null
  displayName: string
  quantityGrams: number | null
  caloriesKcal: number | null
  proteinGrams: number | null
  carbsGrams: number | null
  fatGrams: number | null
  isEstimated: boolean
}

export type MealLog = {
  id: string
  clientId: string
  mealType: MealType
  consumedAt: string
  note: string | null
  source: RecordSource
  foodAnalysisId: string | null
  createdAt: string
  items: MealLogItem[]
}

export type WaterLog = {
  id: string
  clientId: string
  amountMl: number
  consumedAt: string
  source: RecordSource
}

export type BodyMeasurement = {
  id: string
  clientId: string
  measuredAt: string
  weightKg: number | null
  waistCm: number | null
  bodyFatPercent: number | null
  source: RecordSource
}
