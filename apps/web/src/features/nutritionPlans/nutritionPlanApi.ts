import { WebSessionError } from '../auth/webSessionApi'
import { isUuid } from '../relationships/relationshipApi'
import type { PagedResponse } from '../relationships/relationshipApi'

export type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snack' | 'other'
export type NutritionPlanStatus = 'draft' | 'active' | 'archived'
export type NutritionPlanItemRequest = { dayOfWeek: number | null; mealType: MealType; description: string; recommendedQuantity: string | null; sortOrder: number; recipeId: null; alternativeGroupId: string | null }
export type NutritionPlanItem = NutritionPlanItemRequest & { id: string; nutritionPlanId: string }
export type NutritionPlanSnapshot = { title: string; startDate: string; endDate: string | null; dailyCaloriesTargetKcal: number | null; dailyWaterTargetMl: number | null; items: NutritionPlanItem[] }
export type NutritionPlanResponse = NutritionPlanSnapshot & { id: string; clientId: string; dietitianId: string | null; status: NutritionPlanStatus; createdAt: string; versionId: string; versionNumber: number }
export type NutritionPlanVersionInfo = { id: string; nutritionPlanId: string; versionNumber: number; createdAt: string }
export type NutritionPlanVersionResponse = NutritionPlanVersionInfo & { snapshot: NutritionPlanSnapshot }
export type PlanContentRequest = Omit<NutritionPlanSnapshot, 'items'> & { items: NutritionPlanItemRequest[] }
export type CreateNutritionPlanRequest = PlanContentRequest & { clientId: string }
export type PatchNutritionPlanRequest = Partial<PlanContentRequest>
export const mealLabels: Record<MealType, string> = { breakfast: 'Kahvaltı', lunch: 'Öğle', dinner: 'Akşam', snack: 'Ara öğün', other: 'Diğer' }

const invalid = () => new WebSessionError(500, 'Program yanıtı doğrulanamadı. Yeniden kontrol edin.')
function object(value: unknown, keys: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Object.keys(value).sort().join(',') !== keys) throw invalid()
  return value as Record<string, unknown>
}
const date = (value: unknown): value is string => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value
const instant = (value: unknown) => typeof value === 'string' && Number.isFinite(Date.parse(value)) && /(?:Z|[+-]\d\d:\d\d)$/.test(value)
const target = (value: unknown) => value === null || (typeof value === 'number' && Number.isFinite(value) && value > 0)

function snapshot(data: Record<string, unknown>, planId: string): NutritionPlanSnapshot {
  if (typeof data.title !== 'string' || !data.title.trim() || !date(data.startDate) || !(data.endDate === null || date(data.endDate)) ||
    (typeof data.endDate === 'string' && data.endDate < data.startDate) || !target(data.dailyCaloriesTargetKcal) || !target(data.dailyWaterTargetMl) ||
    !Array.isArray(data.items) || data.items.length < 1 || data.items.length > 100) throw invalid()
  const items = data.items.map(value => {
    const row = object(value, 'alternativeGroupId,dayOfWeek,description,id,mealType,nutritionPlanId,recipeId,recommendedQuantity,sortOrder')
    if (!isUuid(row.id) || row.nutritionPlanId !== planId || !(row.dayOfWeek === null || (Number.isInteger(row.dayOfWeek) && (row.dayOfWeek as number) >= 1 && (row.dayOfWeek as number) <= 7)) ||
      typeof row.mealType !== 'string' || !Object.hasOwn(mealLabels, row.mealType) || typeof row.description !== 'string' || !row.description.trim() ||
      !(row.recommendedQuantity === null || typeof row.recommendedQuantity === 'string') || !Number.isSafeInteger(row.sortOrder) || (row.sortOrder as number) < 0 ||
      row.recipeId !== null || !(row.alternativeGroupId === null || isUuid(row.alternativeGroupId))) throw invalid()
    return row as NutritionPlanItem
  })
  if (new Set(items.map(row => row.id)).size !== items.length || new Set(items.map(row => row.sortOrder)).size !== items.length) throw invalid()
  const groups = new Map<string, NutritionPlanItem[]>()
  for (const row of items) if (row.alternativeGroupId) groups.set(row.alternativeGroupId, [...(groups.get(row.alternativeGroupId) ?? []), row])
  if ([...groups.values()].some(rows => rows.length < 2 || rows.some(row => row.dayOfWeek !== rows[0]?.dayOfWeek || row.mealType !== rows[0]?.mealType))) throw invalid()
  return { title: data.title, startDate: data.startDate, endDate: data.endDate as string | null, dailyCaloriesTargetKcal: data.dailyCaloriesTargetKcal as number | null,
    dailyWaterTargetMl: data.dailyWaterTargetMl as number | null, items: items.sort((a, b) => a.sortOrder - b.sortOrder) }
}
function plan(value: unknown, clientId: string): NutritionPlanResponse {
  const row = object(value, 'clientId,createdAt,dailyCaloriesTargetKcal,dailyWaterTargetMl,dietitianId,endDate,id,items,startDate,status,title,versionId,versionNumber')
  if (!isUuid(row.id) || row.clientId !== clientId || !(row.dietitianId === null || isUuid(row.dietitianId)) ||
    !['draft', 'active', 'archived'].includes(row.status as string) || !instant(row.createdAt) || !isUuid(row.versionId) || !Number.isSafeInteger(row.versionNumber) || (row.versionNumber as number) < 1) throw invalid()
  return { ...(row as NutritionPlanResponse), ...snapshot(row, row.id) }
}
function page<T>(value: unknown, parse: (row: unknown) => T): PagedResponse<T> {
  const row = object(value, 'items,totalCount')
  if (!Array.isArray(row.items) || row.items.length > 10 || !Number.isSafeInteger(row.totalCount) || (row.totalCount as number) < row.items.length) throw invalid()
  return { items: row.items.map(parse), totalCount: row.totalCount as number }
}
async function request(path: string, signal: AbortSignal, method = 'GET', token?: string, body?: CreateNutritionPlanRequest | PatchNutritionPlanRequest): Promise<unknown> {
  let response: Response
  try {
    response = await fetch(`/api/v1/nutrition-plans${path}`, { method, signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      headers: { ...(token ? { 'X-CSRF-TOKEN': token } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) })
  } catch { throw new WebSessionError(0, 'İşlem sonucu doğrulanamadı. Tekrar göndermeden programları yeniden kontrol edin.') }
  if (response.status !== (method === 'POST' && path === '' ? 201 : 200)) {
    const message = response.status === 401 ? 'Oturumunuz doğrulanamadı. Yeniden giriş yapın.'
      : response.status === 403 ? 'Programlara erişim veya düzenleme izniniz bulunmuyor.'
      : response.status === 404 ? 'Program bulunamadı veya danışan bağlantısı sona erdi.'
      : response.status === 409 ? 'Başka bir aktif program var. Mevcut programın sahibi önce onu durdurmalı; taslak korunuyor.'
      : response.status === 400 ? 'İstek veya oturum bağlamı doğrulanamadı. Yeniden kontrol edin.'
      : response.status === 422 ? 'Program alanlarını ve alternatif gruplarını kontrol edin.'
      : 'İşlem sonucu doğrulanamadı. Programları yeniden kontrol edin.'
    throw new WebSessionError(response.status, message)
  }
  try { return await response.json() } catch { throw invalid() }
}
export async function getNutritionPlans(clientId: string, number: number, signal: AbortSignal) {
  const result = page(await request(`?clientId=${clientId}&page=${number}&pageSize=10`, signal), row => plan(row, clientId))
  if (new Set(result.items.map(row => row.id)).size !== result.items.length) throw invalid()
  return result
}
export async function saveNutritionPlan(clientId: string, content: PlanContentRequest, token: string, signal: AbortSignal, existing?: NutritionPlanResponse) {
  const result = plan(await request(existing ? `/${existing.id}` : '', signal, existing ? 'PATCH' : 'POST', token, existing ? content : { ...content, clientId }), clientId)
  if ((existing && (result.id !== existing.id || result.versionNumber <= existing.versionNumber)) || (!existing && (result.status !== 'draft' || result.versionNumber !== 1))) throw invalid()
  return result
}
export async function changeNutritionPlan(clientId: string, id: string, action: 'activate' | 'archive', token: string, signal: AbortSignal) {
  const result = plan(await request(`/${id}/${action}`, signal, 'POST', token), clientId)
  if (result.id !== id || result.status !== (action === 'activate' ? 'active' : 'archived')) throw invalid()
  return result
}
function versionInfo(value: unknown, planId: string): NutritionPlanVersionInfo {
  const row = object(value, 'createdAt,id,nutritionPlanId,versionNumber')
  if (!isUuid(row.id) || row.nutritionPlanId !== planId || !instant(row.createdAt) || !Number.isSafeInteger(row.versionNumber) || (row.versionNumber as number) < 1) throw invalid()
  return row as NutritionPlanVersionInfo
}
export async function getNutritionPlanVersions(planId: string, number: number, signal: AbortSignal) {
  const result = page(await request(`/${planId}/versions?page=${number}&pageSize=10`, signal), row => versionInfo(row, planId))
  if (new Set(result.items.map(row => row.id)).size !== result.items.length || new Set(result.items.map(row => row.versionNumber)).size !== result.items.length) throw invalid()
  return result
}
export async function getNutritionPlanVersion(planId: string, versionId: string, signal: AbortSignal): Promise<NutritionPlanVersionResponse> {
  const row = object(await request(`/${planId}/versions/${versionId}`, signal), 'createdAt,id,nutritionPlanId,snapshot,versionNumber')
  const { snapshot: content, ...metadata } = row
  const info = versionInfo(metadata, planId)
  if (info.id !== versionId) throw invalid()
  return { ...info, snapshot: snapshot(object(content, 'dailyCaloriesTargetKcal,dailyWaterTargetMl,endDate,items,startDate,title'), planId) }
}
