import { WebSessionError } from '../auth/webSessionApi'
import { isUuid } from '../relationships/relationshipApi'
import type { PagedResponse } from '../relationships/relationshipApi'
import type { BodyMeasurement } from './clientTracking.types'

const invalid = () => new WebSessionError(500, 'Ölçüm yanıtı doğrulanamadı. Yeniden kontrol edin.')
const positive = (value: unknown) => value === null || (typeof value === 'number' && Number.isFinite(value) && value > 0)
const instant = (value: unknown) => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value))
function object(value: unknown, keys: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value) || Object.keys(value).sort().join(',') !== keys) throw invalid()
  return value as Record<string, unknown>
}
function measurement(value: unknown, clientId: string): BodyMeasurement {
  const row = object(value, 'bodyFatPercent,chestCm,clientId,hipCm,id,measuredAt,note,source,waistCm,weightKg')
  if (!isUuid(row.id) || row.clientId !== clientId || !instant(row.measuredAt) ||
    !['manual', 'wearable', 'ai_assisted'].includes(row.source as string) ||
    ![row.weightKg, row.waistCm, row.hipCm, row.chestCm].every(positive) ||
    !(row.bodyFatPercent === null || (typeof row.bodyFatPercent === 'number' && Number.isFinite(row.bodyFatPercent) && row.bodyFatPercent >= 0 && row.bodyFatPercent <= 100)) ||
    !(row.note === null || typeof row.note === 'string') ||
    [row.weightKg, row.waistCm, row.hipCm, row.chestCm, row.bodyFatPercent].every(value => value === null)) throw invalid()
  return row as BodyMeasurement
}

export async function getBodyMeasurements(clientId: string, page: number, range: { from?: string; to?: string }, signal: AbortSignal, sortOrder?: 'asc'): Promise<PagedResponse<BodyMeasurement>> {
  if (!isUuid(clientId)) throw new WebSessionError(404, 'Danışan bulunamadı.')
  const params = new URLSearchParams({ page: String(page), pageSize: '10' })
  if (sortOrder) params.set('sortOrder', sortOrder)
  if (range.from) params.set('from', range.from)
  if (range.to) params.set('to', range.to)
  let response: Response
  try {
    response = await fetch(`/api/v1/dietitian/clients/${clientId}/body-measurements?${params}`, {
      method: 'GET', signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error', headers: { 'X-Profile-Context': 'dietitian' },
    })
  } catch { throw new WebSessionError(0, 'Ölçümler için sunucuya ulaşılamadı. Bağlantınızı kontrol edip yeniden deneyin.') }
  if (response.status !== 200) {
    const message = response.status === 403 ? 'Ölçüm paylaşımı kapalı veya bu kayıtlara erişim yetkiniz bulunmuyor.'
      : response.status === 404 ? 'Danışan bulunamadı veya aktif bağlantınız sona erdi.'
      : response.status === 401 ? 'Oturumunuz sona ermiş olabilir. Yeniden giriş yapın.'
      : 'Ölçümler okunamadı. Yeniden kontrol edin.'
    throw new WebSessionError(response.status, message)
  }
  let value: unknown
  try { value = await response.json() } catch { throw invalid() }
  const result = object(value, 'items,totalCount')
  if (!Array.isArray(result.items) || result.items.length > 10 || !Number.isSafeInteger(result.totalCount) || (result.totalCount as number) < 0 ||
    (result.items.length > 0 && (result.totalCount as number) < (page - 1) * 10 + result.items.length)) throw invalid()
  const items = result.items.map(value => measurement(value, clientId))
  if (new Set(items.map(item => item.id)).size !== items.length) throw invalid()
  return { items, totalCount: result.totalCount as number }
}

// Charts cover the complete filtered history, independently of the visible diary page.
export async function getBodyMeasurementHistory(clientId: string, range: { from?: string; to?: string }, signal: AbortSignal, expectedTotal: number): Promise<BodyMeasurement[]> {
  const records: BodyMeasurement[] = []
  const ids = new Set<string>()
  for (let page = 1; records.length < expectedTotal; page++) {
    signal.throwIfAborted()
    const result = await getBodyMeasurements(clientId, page, range, signal, 'asc')
    if (result.totalCount !== expectedTotal || result.items.length === 0) throw invalid()
    for (const row of result.items) {
      if (ids.has(row.id)) throw invalid()
      ids.add(row.id)
      records.push(row)
    }
    if (records.length > expectedTotal) throw invalid()
  }
  return records
}
