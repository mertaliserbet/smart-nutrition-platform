import { WebSessionError } from '../auth/webSessionApi'

export type RelationshipStatus = 'pending' | 'active' | 'rejected' | 'ended'
export type RelationshipResponse = { id: string; clientId: string; dietitianId: string; status: RelationshipStatus; requestedAt: string; respondedAt: string | null; endedAt: string | null }
export type InvitationCodeResponse = { invitationCode: string; expiresAt: string }
export type ClientListItem = { id: string; displayName: string }
export type ClientDashboardResponse = { clientId: string; displayName: string }
export type PagedResponse<T> = { items: T[]; totalCount: number }
export const isUuid = (value: unknown): value is string => typeof value === 'string' && /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(value) && !/^0{8}-0{4}-0{4}-0{4}-0{12}$/.test(value)
const timestamp = (value: unknown): value is string => typeof value === 'string' && Number.isFinite(Date.parse(value)) && /(?:Z|[+-]\d\d:\d\d)$/.test(value)
const invalid = () => new WebSessionError(500, 'Sunucu yanıtı doğrulanamadı. Yeniden kontrol edin.')

async function send(path: string, signal: AbortSignal, token?: string): Promise<unknown> {
  let response: Response
  try {
    response = await fetch(`/api/v1/${path}`, { method: token ? 'POST' : 'GET', signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      ...(token ? { headers: { 'X-CSRF-TOKEN': token } } : {}) })
  } catch { throw new WebSessionError(0, 'Sunucuya ulaşılamadı. Bağlantınızı kontrol edip tekrar deneyin.') }
  if (response.status !== 200) {
    const message = response.status === 401 ? 'Oturumunuz sona ermiş olabilir. Yeniden giriş yapın.'
      : response.status === 403 ? 'Bu işlem için güncel erişim yetkiniz bulunmuyor.'
      : response.status === 404 ? 'Kayıt bulunamadı veya erişiminiz sona erdi.'
      : response.status === 409 ? 'Bağlantının durumu değişmiş veya başka aktif bağlantı bulunuyor. Yeniden kontrol edin.'
      : response.status === 429 ? 'Çok fazla istek yapıldı. Bir süre bekleyip tekrar deneyin.'
      : response.status === 400 ? 'Oturum bağlamı değişmiş veya istek doğrulanamamış olabilir. Yeniden kontrol edin.'
      : 'İşlem tamamlanamadı. Yeniden kontrol edin.'
    throw new WebSessionError(response.status, message)
  }
  try { return await response.json() } catch { throw invalid() }
}
function object(value: unknown, keys: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Object.keys(value).sort().join(',') !== keys) throw invalid()
  return value as Record<string, unknown>
}
function paged<T>(value: unknown, read: (row: unknown) => T): PagedResponse<T> {
  const data = object(value, 'items,totalCount')
  if (!Array.isArray(data.items) || data.items.length > 10 || !Number.isSafeInteger(data.totalCount) || (data.totalCount as number) < data.items.length) throw invalid()
  const items = data.items.map(read)
  return { items, totalCount: data.totalCount as number }
}
function relationship(value: unknown, dietitianId: string): RelationshipResponse {
  const row = object(value, 'clientId,dietitianId,endedAt,id,requestedAt,respondedAt,status')
  if (!isUuid(row.id) || !isUuid(row.clientId) || row.dietitianId !== dietitianId ||
    !['pending', 'active', 'rejected', 'ended'].includes(row.status as string) || !timestamp(row.requestedAt) ||
    !(row.respondedAt === null || timestamp(row.respondedAt)) || !(row.endedAt === null || timestamp(row.endedAt))) throw invalid()
  return row as RelationshipResponse
}
export async function getRelationships(status: RelationshipStatus, page: number, dietitianId: string, signal: AbortSignal) {
  const result = paged(await send(`dietitian-relationships?status=${status}&page=${page}&pageSize=10`, signal), row => relationship(row, dietitianId))
  if (result.items.some(row => row.status !== status) || new Set(result.items.map(row => row.id)).size !== result.items.length) throw invalid()
  return result
}
export async function changeRelationship(id: string, action: 'accept' | 'reject' | 'end', dietitianId: string, token: string, signal: AbortSignal) {
  if (!isUuid(id)) throw invalid()
  const row = relationship(await send(`dietitian-relationships/${id}/${action}`, signal, token), dietitianId)
  if (row.id !== id || row.status !== ({ accept: 'active', reject: 'rejected', end: 'ended' } as const)[action]) throw invalid()
  return row
}
export async function createInvitation(token: string, signal: AbortSignal): Promise<InvitationCodeResponse> {
  const row = object(await send('dietitians/me/invitation-code', signal, token), 'expiresAt,invitationCode')
  if (typeof row.invitationCode !== 'string' || !/^[A-Z2-7]{16}$/.test(row.invitationCode) || !timestamp(row.expiresAt)) throw invalid()
  return row as InvitationCodeResponse
}
export async function getClients(page: number, query: string, sort: string, signal: AbortSignal) {
  const params = new URLSearchParams({ page: String(page), pageSize: '10', query, sortOrder: sort })
  const result = paged(await send(`dietitian/clients?${params}`, signal), value => {
    const row = object(value, 'displayName,id')
    if (!isUuid(row.id) || typeof row.displayName !== 'string' || !row.displayName.trim()) throw invalid()
    return row as ClientListItem
  })
  if (new Set(result.items.map(row => row.id)).size !== result.items.length) throw invalid()
  return result
}
export async function getClientDashboard(clientId: string, signal: AbortSignal) {
  if (!isUuid(clientId)) throw new WebSessionError(404, 'Danışan bulunamadı.')
  const row = object(await send(`dietitian/clients/${clientId}/dashboard`, signal), 'clientId,displayName')
  if (row.clientId !== clientId || typeof row.displayName !== 'string' || !row.displayName.trim()) throw invalid()
  return row as ClientDashboardResponse
}
