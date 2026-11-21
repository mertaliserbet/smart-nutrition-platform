import type { MealType, NutritionPlanResponse, PlanContentRequest } from './nutritionPlanApi'

export const planDays = ['Her gün', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar']
export type ItemForm = { key: string; day: string; meal: MealType; description: string; quantity: string; group: string }
export type PlanDraft = { title: string; start: string; end: string; calories: string; water: string; items: ItemForm[] }
export const blankItem = (day = ''): ItemForm => ({ key: crypto.randomUUID(), day, meal: 'breakfast', description: '', quantity: '', group: '' })
export function planDraft(initial?: NutritionPlanResponse): PlanDraft {
  return { title: initial?.title ?? '', start: initial?.startDate ?? '', end: initial?.endDate ?? '',
    calories: initial?.dailyCaloriesTargetKcal?.toString() ?? '', water: initial?.dailyWaterTargetMl?.toString() ?? '',
    items: initial?.items.map(item => ({ key: item.id, day: item.dayOfWeek?.toString() ?? '', meal: item.mealType,
      description: item.description, quantity: item.recommendedQuantity ?? '', group: item.alternativeGroupId ?? '' })) ?? [blankItem()] }
}
export function copyItems(items: ItemForm[], day?: string): ItemForm[] {
  const groups = new Map<string, string>()
  return items.map(item => {
    if (item.group && !groups.has(item.group)) groups.set(item.group, crypto.randomUUID())
    return { ...item, key: crypto.randomUUID(), day: day ?? item.day, group: item.group ? groups.get(item.group)! : '' }
  })
}
export function reusablePlanDraft(source: NutritionPlanResponse): PlanDraft {
  return { ...planDraft(), items: copyItems(planDraft(source).items) }
}
export function draftSignature(draft: PlanDraft) {
  return JSON.stringify({ ...draft, items: draft.items.map(({ key: _key, ...item }) => item) })
}
const validDate = (input: string) => /^\d{4}-\d{2}-\d{2}$/.test(input) && input.slice(0, 4) !== '0000' &&
  Number.isFinite(Date.parse(`${input}T00:00:00Z`)) && new Date(`${input}T00:00:00Z`).toISOString().slice(0, 10) === input
const target = (input: string) => input.trim() === '' ? null : /^\d+(?:[.,]\d+)?$/.test(input.trim()) ? Number(input.trim().replace(',', '.')) : NaN
export function validateDraft(draft: PlanDraft): Record<string, string> {
  const errors: Record<string, string> = {}
  if (!draft.title.trim() || Array.from(draft.title.trim()).length > 120) errors['plan-title'] = 'Başlık 1–120 karakter olmalı.'
  if (!validDate(draft.start)) errors['plan-start'] = 'Geçerli bir başlangıç tarihi seçin.'
  if (draft.end && (!validDate(draft.end) || draft.end < draft.start)) errors['plan-end'] = 'Bitiş tarihi başlangıçtan önce olamaz.'
  for (const [id, value] of [['plan-kcal', target(draft.calories)], ['plan-water', target(draft.water)]] as const)
    if (value !== null && (!Number.isFinite(value) || value <= 0)) errors[id] = 'Hedef boş veya pozitif bir sayı olmalı.'
  if (draft.items.length < 1 || draft.items.length > 100) errors['plan-add-item'] = 'Program 1–100 öğün önerisi içermeli.'
  for (const item of draft.items) {
    if (!item.description.trim() || Array.from(item.description.trim()).length > 2000) errors[`description-${item.key}`] = 'Açıklama 1–2000 karakter olmalı.'
    if (Array.from(item.quantity.trim()).length > 200) errors[`quantity-${item.key}`] = 'Miktar en fazla 200 karakter olmalı.'
    if (item.group) {
      const members = draft.items.filter(row => row.group === item.group)
      if (members.length < 2 || members.some(row => row.day !== item.day || row.meal !== item.meal))
        errors[`group-${item.key}`] = 'Alternatif grubunda aynı gün ve öğün türüne ait en az iki öneri bulunmalı.'
    }
  }
  return errors
}
export function draftContent(draft: PlanDraft): PlanContentRequest {
  return { title: draft.title.trim(), startDate: draft.start, endDate: draft.end || null,
    dailyCaloriesTargetKcal: target(draft.calories), dailyWaterTargetMl: target(draft.water),
    items: draft.items.map((item, index) => ({ dayOfWeek: item.day ? Number(item.day) : null, mealType: item.meal,
      description: item.description.trim(), recommendedQuantity: item.quantity.trim() || null, sortOrder: index, recipeId: null, alternativeGroupId: item.group || null })) }
}
