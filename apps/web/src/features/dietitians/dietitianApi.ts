import { WebSessionError } from '../auth/webSessionApi'

export type DietitianStatusResponse = { id: string; displayName: string; isVerified: boolean }
export type DietitianReviewItem = DietitianStatusResponse & { licenseInfo: string }
export type DietitianApplicationRequest = { email: string; password: string; displayName: string; licenseInfo: string }
const uuid = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i

async function send(path: string, signal: AbortSignal, method = 'GET', token?: string, body?: DietitianApplicationRequest): Promise<unknown> {
  let response: Response
  try {
    response = await fetch(`/api/v1/${path}`, {
      method, signal, credentials: body ? 'omit' : 'same-origin', cache: 'no-store', redirect: 'error',
      headers: { ...(token ? { 'X-CSRF-TOKEN': token } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    })
  } catch { throw new WebSessionError(0, 'İşlem sonucu doğrulanamadı. Bağlantınızı kontrol edip tekrar deneyin.') }
  if (response.status !== (body ? 201 : 200)) {
    const message = response.status === 401 ? 'Oturumunuz doğrulanamadı. Yeniden giriş yapın.'
      : response.status === 403 ? 'Bu işlem için yetkiniz bulunmuyor.'
      : response.status === 409 ? (body ? 'Bu e-posta adresiyle başvuru tamamlanamadı.' : 'Uzmanın e-posta doğrulaması tamamlanmadan onay verilemez.')
      : response.status === 429 ? 'Çok fazla istek yapıldı. Bir süre bekleyip tekrar deneyin.'
      : response.status === 400 || response.status === 422 ? 'Bilgiler veya oturum bağlamı doğrulanamadı. Kontrol edip tekrar deneyin.'
      : 'İşlem tamamlanamadı. Lütfen daha sonra tekrar deneyin.'
    throw new WebSessionError(response.status, message)
  }
  try { return await response.json() }
  catch { throw new WebSessionError(500, 'Sunucu yanıtı doğrulanamadı.') }
}

function status(value: unknown, review = false): DietitianStatusResponse | DietitianReviewItem {
  if (typeof value !== 'object' || value === null) throw new WebSessionError(500, 'Uzman bilgileri doğrulanamadı.')
  const row = value as Record<string, unknown>
  if (Object.keys(row).sort().join(',') !== (review ? 'displayName,id,isVerified,licenseInfo' : 'displayName,id,isVerified') ||
    typeof row.id !== 'string' || !uuid.test(row.id) || /^0{8}-0{4}-0{4}-0{4}-0{12}$/.test(row.id) ||
    typeof row.displayName !== 'string' || !row.displayName.trim() || typeof row.isVerified !== 'boolean' ||
    (review && (typeof row.licenseInfo !== 'string' || !row.licenseInfo.trim())))
    throw new WebSessionError(500, 'Uzman bilgileri doğrulanamadı.')
  return row as DietitianStatusResponse | DietitianReviewItem
}

export async function applyDietitian(body: DietitianApplicationRequest, signal: AbortSignal) {
  const value = await send('dietitians/apply', signal, 'POST', undefined, body)
  if (typeof value !== 'object' || value === null || Object.keys(value).join(',') !== 'id' ||
    !('id' in value) || typeof value.id !== 'string' || !uuid.test(value.id) || /^0{8}-0{4}-0{4}-0{4}-0{12}$/.test(value.id))
    throw new WebSessionError(500, 'Başvuru sonucu doğrulanamadı. Giriş veya e-posta doğrulama ekranından kontrol edebilirsiniz.')
}

export async function getDietitianStatus(signal: AbortSignal) {
  return status(await send('dietitians/me', signal)) as DietitianStatusResponse
}

export async function listApplications(page: number, signal: AbortSignal) {
  const value = await send(`admin/dietitians?isVerified=false&page=${page}&pageSize=10`, signal)
  if (typeof value !== 'object' || value === null) throw new WebSessionError(500, 'Başvurular doğrulanamadı.')
  const data = value as Record<string, unknown>
  if (Object.keys(data).sort().join(',') !== 'items,totalCount' || !Array.isArray(data.items) ||
    !Number.isSafeInteger(data.totalCount) || (data.totalCount as number) < 0 || data.items.length > 10 ||
    (data.totalCount as number) < data.items.length) throw new WebSessionError(500, 'Başvurular doğrulanamadı.')
  const items = data.items.map(row => status(row, true) as DietitianReviewItem)
  if (items.some(row => row.isVerified) || new Set(items.map(row => row.id)).size !== items.length)
    throw new WebSessionError(500, 'Başvurular doğrulanamadı.')
  return { items, totalCount: data.totalCount as number }
}

export async function verifyDietitian(id: string, token: string, signal: AbortSignal) {
  if (!uuid.test(id)) throw new WebSessionError(400, 'Başvuru doğrulanamadı.')
  const value = status(await send(`admin/dietitians/${id}/verify`, signal, 'POST', token))
  if (value.id !== id || !value.isVerified) throw new WebSessionError(500, 'Onay sonucu doğrulanamadı.')
  return value
}
