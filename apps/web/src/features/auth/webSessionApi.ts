export type LoginUserRequest = { email: string; password: string }
export type CurrentUserResponse = {
  id: string; displayName: string | null; email: string; role: 'client' | 'dietitian'; isEmailVerified: boolean
}
export type CsrfTokenResponse = { requestToken: string }

export class WebSessionError extends Error {
  readonly status: number
  constructor(status: number, message: string) { super(message); this.status = status }
}

async function request(path: string, expected: number, signal: AbortSignal, method = 'GET', token?: string, body?: LoginUserRequest) {
  let response: Response
  try {
    response = await fetch(`/api/v1/auth/${path}`, {
      method, signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      headers: { ...(token ? { 'X-CSRF-TOKEN': token } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    })
  } catch { throw new WebSessionError(0, 'Sunucuya ulaşılamadı. Bağlantınızı kontrol edip tekrar deneyin.') }
  if (response.status !== expected) {
    const message = response.status === 401 ? 'Giriş bilgileri doğrulanamadı. Bilgilerinizi ve e-posta doğrulamanızı kontrol edin.'
      : response.status === 409 ? 'Bu tarayıcıda açık bir oturum var. Hesabınızı açıp önce çıkış yapın.'
      : response.status === 400 || response.status === 403 ? 'Oturum bağlamı değişmiş veya istek doğrulanamamış olabilir. Hesabı yeniden kontrol edip tekrar deneyin.'
      : response.status === 429 ? 'Çok fazla istek yapıldı. Bir süre bekleyip tekrar deneyin.'
      : 'İşlem tamamlanamadı. Lütfen daha sonra tekrar deneyin.'
    throw new WebSessionError(response.status, message)
  }
  return response
}

async function readJson(response: Response): Promise<unknown> {
  try { return await response.json() }
  catch { throw new WebSessionError(500, 'Sunucu yanıtı doğrulanamadı. Lütfen tekrar deneyin.') }
}

function account(value: unknown): CurrentUserResponse {
  if (typeof value !== 'object' || value === null) throw new WebSessionError(500, 'Hesap bilgileri doğrulanamadı.')
  const data = value as Record<string, unknown>
  if (Object.keys(data).sort().join(',') !== 'displayName,email,id,isEmailVerified,role' ||
    typeof data.id !== 'string' || !/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(data.id) ||
    /^0{8}-0{4}-0{4}-0{4}-0{12}$/.test(data.id) || typeof data.email !== 'string' || !data.email ||
    (data.displayName !== null && typeof data.displayName !== 'string') ||
    (data.role !== 'client' && data.role !== 'dietitian') || data.isEmailVerified !== true)
    throw new WebSessionError(500, 'Hesap bilgileri doğrulanamadı.')
  return data as CurrentUserResponse
}

export async function getCsrf(signal: AbortSignal): Promise<string> {
  const data = await readJson(await request('csrf', 200, signal))
  if (typeof data !== 'object' || data === null || Object.keys(data).join(',') !== 'requestToken' ||
    typeof (data as CsrfTokenResponse).requestToken !== 'string' || !(data as CsrfTokenResponse).requestToken)
    throw new WebSessionError(500, 'İstek doğrulanamadı. Lütfen tekrar deneyin.')
  return (data as CsrfTokenResponse).requestToken
}

export async function login(requestBody: LoginUserRequest, signal: AbortSignal) {
  const token = await getCsrf(signal)
  return account(await readJson(await request('web-session', 200, signal, 'POST', token, requestBody)))
}

export async function getAccount(signal: AbortSignal) {
  return account(await readJson(await request('me', 200, signal)))
}

export async function logout(token: string, signal: AbortSignal) {
  await request('web-session', 204, signal, 'DELETE', token)
}
