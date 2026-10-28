export type RegisterUserRequest = { email: string; password: string; displayName: string }
export type RegisterUserResponse = { id: string }

export class RegistrationError extends Error {}

export async function registerUser(request: RegisterUserRequest, signal: AbortSignal): Promise<void> {
  let response: Response
  try {
    response = await fetch('/api/v1/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request),
      credentials: 'omit',
      cache: 'no-store',
      redirect: 'error',
      signal,
    })
  } catch {
    throw new RegistrationError('Kayıt sonucu doğrulanamadı. Giriş veya e-posta doğrulama ekranından kontrol edebilirsiniz.')
  }
  if (response.status === 201) {
    try {
      const body: unknown = await response.json()
      if (typeof body === 'object' && body !== null && Object.keys(body).length === 1 &&
        'id' in body && typeof body.id === 'string' &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.id)) return
    } catch { /* A malformed response must not be presented as a confirmed registration. */ }
    throw new RegistrationError('Kayıt sonucu doğrulanamadı. Giriş veya e-posta doğrulama ekranından kontrol edebilirsiniz.')
  }
  if (response.status === 409)
    throw new RegistrationError('Bu e-posta adresiyle kayıt tamamlanamadı. Giriş yapabilir veya e-postanızı doğrulayabilirsiniz.')
  if (response.status === 422)
    throw new RegistrationError('Şifre kayıt kurallarını karşılamıyor. Şifrenizi kontrol edip tekrar deneyin.')
  if (response.status === 400)
    throw new RegistrationError('Kayıt bilgilerini kontrol edip tekrar deneyin.')
  if (response.status === 429)
    throw new RegistrationError('Çok fazla istek yapıldı. Bir süre bekleyip tekrar deneyin.')
  throw new RegistrationError('Kayıt tamamlanamadı. Lütfen daha sonra tekrar deneyin.')
}
