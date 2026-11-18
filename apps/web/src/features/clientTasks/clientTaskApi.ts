import { WebSessionError } from '../auth/webSessionApi'
import { isUuid } from '../relationships/relationshipApi'
import type { PagedResponse } from '../relationships/relationshipApi'

export type ClientTaskStatus = 'pending' | 'in_progress' | 'completed' | 'cancelled'
export type ClientTaskResponse = {
  id: string; clientId: string; dietitianId: string; relationshipId: string; description: string
  status: ClientTaskStatus; dueAt: string | null; isReminderEnabled: boolean
  createdAt: string; updatedAt: string; versionNumber: number
}
export type ClientTaskVersionResponse = { id: string; clientTaskId: string; versionNumber: number; createdAt: string; snapshot: ClientTaskResponse }
export type CreateClientTaskRequest = { clientId: string; description: string; dueAt?: string | null }
export type PatchClientTaskRequest = { expectedVersionNumber: number; description?: string; dueAt?: string | null; status?: ClientTaskStatus; isReminderEnabled?: boolean }
export const taskStatusLabels: Record<ClientTaskStatus, string> = { pending: 'Bekliyor', in_progress: 'Devam ediyor', completed: 'Tamamlandı', cancelled: 'İptal edildi' }
export const isOpenTask = (task: ClientTaskResponse) => task.status === 'pending' || task.status === 'in_progress'
const invalid = () => new WebSessionError(500, 'Görev yanıtı doğrulanamadı. Görevleri yeniden kontrol edin.')
const instant = (value: unknown): value is string => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value))
function object(value: unknown, keys: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value) || Object.keys(value).sort().join(',') !== keys) throw invalid()
  return value as Record<string, unknown>
}
function task(value: unknown, clientId: string, dietitianId: string, id?: string): ClientTaskResponse {
  const row = object(value, 'clientId,createdAt,description,dietitianId,dueAt,id,isReminderEnabled,relationshipId,status,updatedAt,versionNumber')
  if (!isUuid(row.id) || id !== undefined && row.id !== id || row.clientId !== clientId || row.dietitianId !== dietitianId || !isUuid(row.relationshipId) ||
    typeof row.description !== 'string' || !row.description.trim() || row.description.includes('\0') || [...row.description].length > 2000 ||
    !Object.hasOwn(taskStatusLabels, row.status as string) || typeof row.isReminderEnabled !== 'boolean' ||
    !instant(row.createdAt) || !instant(row.updatedAt) || Date.parse(row.updatedAt) < Date.parse(row.createdAt) ||
    !(row.dueAt === null || instant(row.dueAt) && Date.parse(row.dueAt) >= Date.parse(row.createdAt)) ||
    row.isReminderEnabled && row.dueAt === null || !Number.isSafeInteger(row.versionNumber) || (row.versionNumber as number) < 1) throw invalid()
  return row as ClientTaskResponse
}
function page<T>(value: unknown, number: number, read: (value: unknown) => T & { id: string }): PagedResponse<T> {
  const row = object(value, 'items,totalCount')
  if (!Array.isArray(row.items) || row.items.length > 10 || !Number.isSafeInteger(row.totalCount) || (row.totalCount as number) < 0 ||
    row.items.length > 0 && (row.totalCount as number) < (number - 1) * 10 + row.items.length) throw invalid()
  const items = row.items.map(read)
  if (new Set(items.map(row => row.id)).size !== items.length) throw invalid()
  return { items, totalCount: row.totalCount as number }
}
async function send(path: string, signal: AbortSignal, method = 'GET', token?: string, body?: object): Promise<unknown> {
  let response: Response
  try {
    response = await fetch(`/api/v1/client-tasks${path}`, { method, signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      headers: { 'X-Profile-Context': 'dietitian', ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { 'X-CSRF-TOKEN': token } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}) })
  } catch { throw new WebSessionError(0, method === 'GET' ? 'Görev sunucusuna ulaşılamadı. Bağlantınızı kontrol edip yeniden deneyin.' : 'Görev işleminin sonucu doğrulanamadı. Yeniden göndermeden önce görevleri kontrol edin.') }
  if (response.status !== (method === 'POST' ? 201 : 200)) {
    const message = response.status === 403 ? 'Görev paylaşımı kapalı veya bu görevlere erişim yetkiniz bulunmuyor.'
      : response.status === 404 ? 'Görev bulunamadı veya aktif danışan bağlantınız sona erdi.'
      : response.status === 401 ? 'Oturumunuz sona ermiş olabilir. Yeniden giriş yapın.'
      : response.status === 400 ? 'İstek veya oturum doğrulanamadı. Çalışma alanını yeniden kontrol edin.'
      : response.status === 409 ? 'Görev başka bir oturumda değişmiş veya kapanmış. Güncel sürümü inceleyip düzenlemeyi yeniden başlatın.'
      : response.status === 422 ? 'Açıklamayı ve son tarihi kontrol edin. Değiştirilen son tarih gelecekte olmalı.'
      : response.status === 429 ? 'Çok fazla istek yapıldı. Biraz bekleyip görevleri yenileyin.'
      : 'Görev işlemi tamamlanamadı. Yeniden göndermeden önce görevleri kontrol edin.'
    throw new WebSessionError(response.status, message)
  }
  try { return await response.json() } catch { throw invalid() }
}
export async function getClientTasks(clientId: string, dietitianId: string, number: number, signal: AbortSignal) {
  if (!isUuid(clientId) || !isUuid(dietitianId)) throw invalid()
  return page(await send(`?${new URLSearchParams({ clientId, page: String(number), pageSize: '10' })}`, signal), number, value => task(value, clientId, dietitianId))
}
export async function getClientTask(clientId: string, dietitianId: string, id: string, signal: AbortSignal) {
  if (!isUuid(id)) throw invalid()
  return task(await send(`/${id}`, signal), clientId, dietitianId, id)
}
export async function getClientTaskVersions(current: ClientTaskResponse, number: number, signal: AbortSignal) {
  const result = page<ClientTaskVersionResponse>(await send(`/${current.id}/versions?page=${number}&pageSize=10`, signal), number, value => {
    const row = object(value, 'clientTaskId,createdAt,id,snapshot,versionNumber')
    if (!isUuid(row.id) || row.clientTaskId !== current.id || !Number.isSafeInteger(row.versionNumber) || (row.versionNumber as number) < 1 || !instant(row.createdAt)) throw invalid()
    const snapshot = task(row.snapshot, current.clientId, current.dietitianId, current.id)
    if (snapshot.relationshipId !== current.relationshipId || snapshot.versionNumber !== row.versionNumber || Date.parse(snapshot.updatedAt) !== Date.parse(row.createdAt)) throw invalid()
    return { ...row, snapshot } as ClientTaskVersionResponse
  })
  if (new Set(result.items.map(row => row.versionNumber)).size !== result.items.length || result.items.some((row, index) => index > 0 && result.items[index - 1]!.versionNumber <= row.versionNumber)) throw invalid()
  return result
}
export async function saveClientTask(clientId: string, dietitianId: string, content: { description: string; dueAt: string | null }, token: string, signal: AbortSignal, current?: ClientTaskResponse) {
  const body: CreateClientTaskRequest | PatchClientTaskRequest = current
    ? { expectedVersionNumber: current.versionNumber, description: content.description, ...(content.dueAt === current.dueAt ? {} : { dueAt: content.dueAt }) }
    : { clientId, ...content }
  return task(await send(current ? `/${current.id}` : '', signal, current ? 'PATCH' : 'POST', token, body), clientId, dietitianId, current?.id)
}
export async function cancelClientTask(current: ClientTaskResponse, token: string, signal: AbortSignal) {
  const result = task(await send(`/${current.id}`, signal, 'PATCH', token, { expectedVersionNumber: current.versionNumber, status: 'cancelled' } satisfies PatchClientTaskRequest), current.clientId, current.dietitianId, current.id)
  if (result.status !== 'cancelled') throw invalid()
  return result
}
