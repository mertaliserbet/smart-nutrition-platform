import { WebSessionError } from '../auth/webSessionApi'
import { isUuid } from '../relationships/relationshipApi'
import type { PagedResponse } from '../relationships/relationshipApi'
import type { MealLog, MealLogItem } from './clientTracking.types'

const invalid = () => new WebSessionError(500, 'Öğün yanıtı doğrulanamadı. Yeniden deneyin.')
function object(value: unknown, keys: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Object.keys(value).sort().join(',') !== keys) throw invalid()
  return value as Record<string, unknown>
}
const instant = (value: unknown) => typeof value === 'string' && Number.isFinite(Date.parse(value)) && /(?:Z|[+-]\d\d:\d\d)$/.test(value)
const nullableId = (value: unknown) => value === null || isUuid(value)
const quantity = (value: unknown) => value === null || (typeof value === 'number' && Number.isFinite(value) && value >= 0)

function meal(value: unknown, clientId: string): MealLog {
  const row = object(value, 'clientId,consumedAt,createdAt,foodAnalysisId,id,items,mealType,note,source')
  if (!isUuid(row.id) || row.clientId !== clientId || !instant(row.consumedAt) || !instant(row.createdAt) ||
    !['breakfast', 'lunch', 'dinner', 'snack', 'other'].includes(row.mealType as string) ||
    !['manual', 'wearable', 'ai_assisted'].includes(row.source as string) || !nullableId(row.foodAnalysisId) ||
    !(row.note === null || typeof row.note === 'string') || !Array.isArray(row.items) || row.items.length < 1 || row.items.length > 100) throw invalid()
  const items = row.items.map(value => {
    const item = object(value, 'caloriesKcal,carbsGrams,displayName,fatGrams,foodItemId,id,isEstimated,mealLogId,proteinGrams,quantityGrams,recipeId')
    if (!isUuid(item.id) || item.mealLogId !== row.id || !nullableId(item.foodItemId) || !nullableId(item.recipeId) ||
      typeof item.displayName !== 'string' || !item.displayName.trim() || typeof item.isEstimated !== 'boolean' ||
      ![item.quantityGrams, item.caloriesKcal, item.proteinGrams, item.carbsGrams, item.fatGrams].every(quantity)) throw invalid()
    return item as MealLogItem
  })
  if (new Set(items.map(item => item.id)).size !== items.length) throw invalid()
  return { ...row, items } as MealLog
}

export async function getMealLogs(clientId: string, page: number, range: { from?: string; to?: string }, signal: AbortSignal): Promise<PagedResponse<MealLog>> {
  if (!isUuid(clientId)) throw new WebSessionError(404, 'Danışan bulunamadı.')
  const params = new URLSearchParams({ page: String(page), pageSize: '10' })
  if (range.from) params.set('from', range.from)
  if (range.to) params.set('to', range.to)
  let response: Response
  try {
    response = await fetch(`/api/v1/dietitian/clients/${clientId}/meal-logs?${params}`, {
      method: 'GET', signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error', headers: { 'X-Profile-Context': 'dietitian' },
    })
  } catch { throw new WebSessionError(0, 'Öğünler için sunucuya ulaşılamadı. Bağlantınızı kontrol edip yeniden deneyin.') }
  if (response.status !== 200) {
    const message = response.status === 403 ? 'Öğün paylaşımı kapalı veya bu kayıtlara erişim yetkiniz bulunmuyor.'
      : response.status === 404 ? 'Danışan bulunamadı veya aktif bağlantınız sona erdi.'
      : response.status === 401 ? 'Oturumunuz sona ermiş olabilir. Yeniden giriş yapın.'
      : 'Öğünler okunamadı. Yeniden deneyin.'
    throw new WebSessionError(response.status, message)
  }
  let value: unknown
  try { value = await response.json() } catch { throw invalid() }
  const body = object(value, 'items,totalCount')
  if (!Array.isArray(body.items) || body.items.length > 10 || !Number.isSafeInteger(body.totalCount) ||
    (body.totalCount as number) < 0 || (body.items.length > 0 && (body.totalCount as number) < (page - 1) * 10 + body.items.length)) throw invalid()
  const items = body.items.map(value => meal(value, clientId))
  if (new Set(items.map(row => row.id)).size !== items.length) throw invalid()
  return { items, totalCount: body.totalCount as number }
}
