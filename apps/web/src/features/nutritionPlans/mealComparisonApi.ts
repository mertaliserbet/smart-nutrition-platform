import { WebSessionError } from '../auth/webSessionApi'
import { mealLabels, parseNutritionPlanVersion } from './nutritionPlanApi'
import type { MealType, NutritionPlanItem, NutritionPlanVersionResponse } from './nutritionPlanApi'

export type NutritionValueSummary = { knownTotal: number; missingItemCount: number }
export type MealLogNutritionSummary = { mealLogCount: number; itemCount: number; estimatedItemCount: number;
  caloriesKcal: NutritionValueSummary; proteinGrams: NutritionValueSummary; carbsGrams: NutritionValueSummary; fatGrams: NutritionValueSummary }
export type NutritionPlanMealComparison = { mealType: MealType; plannedItems: NutritionPlanItem[]; actual: MealLogNutritionSummary }
export type NutritionPlanMealComparisonResponse = { clientId: string; nutritionPlanVersion: NutritionPlanVersionResponse;
  date: string; from: string; to: string; actual: MealLogNutritionSummary; caloriesDifferenceKcal: number | null; meals: NutritionPlanMealComparison[] }

const invalid = () => new WebSessionError(500, 'Karşılaştırma yanıtı doğrulanamadı. Yeniden kontrol edin.')
function object(value: unknown, keys: string) {
  if (!value || typeof value !== 'object' || Object.keys(value).sort().join(',') !== keys) throw invalid()
  return value as Record<string, unknown>
}
const count = (value: unknown): value is number => typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
function summary(value: unknown): MealLogNutritionSummary {
  const row = object(value, 'caloriesKcal,carbsGrams,estimatedItemCount,fatGrams,itemCount,mealLogCount,proteinGrams')
  if (!count(row.mealLogCount) || !count(row.itemCount) || !count(row.estimatedItemCount) || row.mealLogCount > row.itemCount ||
      row.estimatedItemCount > row.itemCount || (row.mealLogCount === 0 && row.itemCount !== 0)) throw invalid()
  for (const key of ['caloriesKcal', 'proteinGrams', 'carbsGrams', 'fatGrams']) {
    const nutrient = object(row[key], 'knownTotal,missingItemCount')
    if (typeof nutrient.knownTotal !== 'number' || !Number.isFinite(nutrient.knownTotal) || nutrient.knownTotal < 0 ||
        !count(nutrient.missingItemCount) || nutrient.missingItemCount > row.itemCount ||
        (nutrient.missingItemCount === row.itemCount && nutrient.knownTotal !== 0)) throw invalid()
  }
  return row as MealLogNutritionSummary
}

function offsetInstant(date: Date) {
  const offset = -date.getTimezoneOffset()
  const part = (n: number) => String(n).padStart(2, '0')
  return `${String(date.getFullYear()).padStart(4, '0')}-${part(date.getMonth() + 1)}-${part(date.getDate())}T00:00:00${offset >= 0 ? '+' : '-'}${part(Math.floor(Math.abs(offset) / 60))}:${part(Math.abs(offset) % 60)}`
}
export function localDayRange(date: string) {
  const start = new Date(`${date}T00:00:00`)
  const end = new Date(start); end.setDate(end.getDate() + 1)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) ||
      start.getFullYear() < 1 || end.getFullYear() > 9999 || offsetInstant(start).slice(0, 10) !== date || start.getHours() !== 0 || end.getHours() !== 0)
    throw new WebSessionError(400, 'Seçilen gün için gece yarısı sınırları oluşturulamadı. Tarihi kontrol edin.')
  return { from: offsetInstant(start), to: offsetInstant(end) }
}
export async function getMealComparison(clientId: string, planId: string, versionId: string, date: string, signal: AbortSignal): Promise<NutritionPlanMealComparisonResponse> {
  const range = localDayRange(date)
  let response: Response
  try {
    response = await fetch(`/api/v1/nutrition-plans/${planId}/versions/${versionId}/meal-comparison?${new URLSearchParams(range)}`,
      { signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error', headers: { 'X-Profile-Context': 'dietitian' } })
  } catch { throw new WebSessionError(0, 'Karşılaştırma okunamadı. Bağlantınızı kontrol edip yenileyin.') }
  if (response.status !== 200) throw new WebSessionError(response.status,
    response.status === 401 ? 'Oturumunuz doğrulanamadı. Yeniden giriş yapın.'
      : response.status === 403 ? 'Karşılaştırma için program ve öğün paylaşım izinlerinin ikisi de gerekli.'
      : response.status === 404 ? 'Program sürümü bulunamadı veya danışan bağlantısı sona erdi.'
      : response.status === 422 ? 'Günü seçilen program sürümünün tarih aralığında seçin. Sayısal toplam da desteklenen sınırları aşmış olabilir.'
      : 'Karşılaştırma okunamadı. Seçiminizi kontrol edip yenileyin.')
  let value: unknown
  try { value = await response.json() } catch { throw invalid() }
  const row = object(value, 'actual,caloriesDifferenceKcal,clientId,date,from,meals,nutritionPlanVersion,to')
  if (row.clientId !== clientId || row.date !== date || typeof row.from !== 'string' || typeof row.to !== 'string' ||
      !/(Z|[+-]\d\d:\d\d)$/.test(row.from) || !/(Z|[+-]\d\d:\d\d)$/.test(row.to) ||
      Date.parse(row.from) !== Date.parse(range.from) || Date.parse(row.to) !== Date.parse(range.to)) throw invalid()
  const version = parseNutritionPlanVersion(row.nutritionPlanVersion, planId, versionId)
  if (date < version.snapshot.startDate || (version.snapshot.endDate && date > version.snapshot.endDate)) throw invalid()
  const actual = summary(row.actual)
  if (!(row.caloriesDifferenceKcal === null || (typeof row.caloriesDifferenceKcal === 'number' && Number.isFinite(row.caloriesDifferenceKcal))) ||
      ((actual.itemCount === 0 || actual.caloriesKcal.missingItemCount > 0 || version.snapshot.dailyCaloriesTargetKcal === null) && row.caloriesDifferenceKcal !== null)) throw invalid()
  const types = Object.keys(mealLabels)
  if (!Array.isArray(row.meals) || row.meals.length !== types.length) throw invalid()
  const day = (new Date(`${date}T00:00:00Z`).getUTCDay() + 6) % 7 + 1
  const meals = row.meals.map((value, index) => {
    const meal = object(value, 'actual,mealType,plannedItems')
    if (meal.mealType !== types[index] || !Array.isArray(meal.plannedItems)) throw invalid()
    const expected = version.snapshot.items.filter(item => item.mealType === meal.mealType && (item.dayOfWeek === null || item.dayOfWeek === day)).sort((a, b) => a.sortOrder - b.sortOrder)
    if (meal.plannedItems.length !== expected.length || meal.plannedItems.some((value, i) => {
      const item = object(value, 'alternativeGroupId,dayOfWeek,description,id,mealType,nutritionPlanId,recipeId,recommendedQuantity,sortOrder')
      const target = expected[i]
      return !target || Object.keys(item).some(key => item[key] !== target[key as keyof NutritionPlanItem])
    })) throw invalid()
    return { mealType: meal.mealType as MealType, plannedItems: expected, actual: summary(meal.actual) }
  })
  if (meals.reduce((sum, meal) => sum + meal.actual.mealLogCount, 0) !== actual.mealLogCount ||
      meals.reduce((sum, meal) => sum + meal.actual.itemCount, 0) !== actual.itemCount ||
      meals.reduce((sum, meal) => sum + meal.actual.estimatedItemCount, 0) !== actual.estimatedItemCount) throw invalid()
  for (const key of ['caloriesKcal', 'proteinGrams', 'carbsGrams', 'fatGrams'] as const) {
    if (meals.reduce((sum, meal) => sum + meal.actual[key].missingItemCount, 0) !== actual[key].missingItemCount) throw invalid()
  }
  return { clientId, nutritionPlanVersion: version, date, from: row.from, to: row.to, actual, caloriesDifferenceKcal: row.caloriesDifferenceKcal as number | null, meals }
}
