import { WebSessionError } from '../auth/webSessionApi'
import { localDayRange } from '../nutritionPlans/mealComparisonApi'
import { isUuid } from '../relationships/relationshipApi'
import type { PagedResponse } from '../relationships/relationshipApi'
import type { WaterLog } from './clientTracking.types'

export type WaterLogDailyTotal = { from: string; to: string; totalAmountMl: number }
export type WaterRange = { from: string; to: string }
export { localDayRange }
const invalid = () => new WebSessionError(500, 'Su takibi yanıtı doğrulanamadı. Yeniden deneyin.')
const instant = (value: unknown): value is string => typeof value === 'string' &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value))
const amount = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value) && value >= 0
function object(value: unknown, keys: string) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).sort().join(',') !== keys) throw invalid()
  return value as Record<string, unknown>
}
function daily(value: unknown): WaterLogDailyTotal {
  const row = object(value, 'from,to,totalAmountMl')
  if (!instant(row.from) || !instant(row.to) || Date.parse(row.from) >= Date.parse(row.to) || !amount(row.totalAmountMl)) throw invalid()
  return row as WaterLogDailyTotal
}
async function read(clientId: string, path: string, params: URLSearchParams, signal: AbortSignal): Promise<unknown> {
  if (!isUuid(clientId)) throw new WebSessionError(404, 'Danışan bulunamadı veya aktif bağlantınız sona erdi.')
  signal.throwIfAborted()
  let response: Response
  try {
    response = await fetch(`/api/v1/dietitian/clients/${clientId}/water-logs${path}?${params}`, {
      method: 'GET', signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error', headers: { 'X-Profile-Context': 'dietitian' },
    })
  } catch (error) {
    signal.throwIfAborted()
    if (error instanceof WebSessionError) throw error
    throw new WebSessionError(0, 'Su takibi için sunucuya ulaşılamadı. Bağlantınızı kontrol edip yeniden deneyin.')
  }
  if (response.status !== 200) throw new WebSessionError(response.status,
    response.status === 403 ? 'Su paylaşımı kapalı veya bu kayıtlara erişiminiz yok. Danışan paylaşımı mobil uygulamadaki bağlantı izinlerinden yönetmelidir.'
      : response.status === 404 ? 'Danışan bulunamadı veya aktif bağlantınız sona erdi.'
      : response.status === 401 ? 'Oturumunuz sona ermiş olabilir. Yeniden giriş yapın.'
      : response.status === 400 ? 'Su takibi tarih aralığı veya saat dilimi geçersiz. Seçiminizi kontrol edin.'
      : response.status === 422 ? 'Su toplamı hesaplanamadı. Sayısal değerler desteklenen sınırı aşmış olabilir.'
      : 'Su takibi okunamadı. Yeniden deneyin.')
  try { return await response.json() } catch { throw invalid() }
}
export async function getWaterLogs(clientId: string, page: number, range: WaterRange, signal: AbortSignal): Promise<PagedResponse<WaterLog>> {
  const value = object(await read(clientId, '', new URLSearchParams({ page: String(page), pageSize: '10', ...range }), signal), 'items,totalCount')
  if (!Array.isArray(value.items) || value.items.length > 10 || !Number.isSafeInteger(value.totalCount) || (value.totalCount as number) < 0 ||
      value.items.length > 0 && (value.totalCount as number) < (page - 1) * 10 + value.items.length) throw invalid()
  const items = value.items.map(value => {
    const row = object(value, 'amountMl,clientId,consumedAt,id,source')
    if (!isUuid(row.id) || row.clientId !== clientId || !instant(row.consumedAt) ||
        Date.parse(row.consumedAt) < Date.parse(range.from) || Date.parse(row.consumedAt) >= Date.parse(range.to) ||
        !amount(row.amountMl) || row.amountMl === 0 || !['manual', 'wearable', 'ai_assisted'].includes(row.source as string)) throw invalid()
    return row as WaterLog
  })
  if (new Set(items.map(x => x.id)).size !== items.length) throw invalid()
  return { items, totalCount: value.totalCount as number }
}
export async function getWaterDailyTotal(clientId: string, range: WaterRange, signal: AbortSignal): Promise<WaterLogDailyTotal> {
  const row = daily(await read(clientId, '/daily-total', new URLSearchParams(range), signal))
  if (Date.parse(row.from) !== Date.parse(range.from) || Date.parse(row.to) !== Date.parse(range.to)) throw invalid()
  return row
}
export function localDateInput(date: Date) {
  return `${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}
export function waterHistoryRange(first: string, last: string) {
  const start = localDayRange(first), end = localDayRange(last)
  const days = (Date.parse(`${last}T00:00:00Z`) - Date.parse(`${first}T00:00:00Z`)) / 86400000 + 1
  if (!Number.isInteger(days) || days < 1 || days > 31) throw new WebSessionError(400, 'Su geçmişi için başlangıç ve bitiş dahil en fazla 31 gün seçin.')
  return { from: start.from, to: end.to, timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone, days }
}
export async function getWaterHistory(clientId: string, range: ReturnType<typeof waterHistoryRange>, signal: AbortSignal): Promise<WaterLogDailyTotal[]> {
  const { from, to, timeZone, days } = range
  const value = object(await read(clientId, '/daily-history', new URLSearchParams({ from, to, timeZone, page: '1', pageSize: '31' }), signal), 'items,totalCount')
  if (!Array.isArray(value.items) || value.totalCount !== days || value.items.length !== days) throw invalid()
  const items = value.items.map(daily)
  for (let i = 0; i < items.length; i++) {
    const row = items[i]!, previousEnd = i === 0 ? from : items[i - 1]!.to
    const hours = (Date.parse(row.to) - Date.parse(row.from)) / 3600000
    if (Date.parse(row.from) !== Date.parse(previousEnd) || hours < 22 || hours > 26) throw invalid()
  }
  if (Date.parse(items[items.length - 1]!.to) !== Date.parse(to)) throw invalid()
  return items
}
