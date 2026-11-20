import { WebSessionError } from './webSessionApi'

export type PasswordResetRequest = { email: string }
export type ResetPasswordRequest = { token: string; password: string }
export const passwordResetNotice = 'Uygun bir hesap varsa sıfırlama talebi işleme alınır. Gelen kutunuzu kontrol edin.'
export const validResetToken = (value: string) => /^[A-Za-z0-9_-]{43}$/.test(value)
export function resetPasswordError(password: string): string | undefined {
  const characters = Array.from(password)
  if (characters.some(c => c.length === 1 && c.charCodeAt(0) >= 0xd800 && c.charCodeAt(0) <= 0xdfff)) return 'Şifre geçerli Unicode karakterlerinden oluşmalı.'
  if (characters.length < 8 || characters.length > 128) return 'Şifre 8–128 karakter olmalı. Boşluklar aynen korunur.'
}
async function send(path: string, body: PasswordResetRequest | ResetPasswordRequest, expected: number, signal: AbortSignal) {
  signal.throwIfAborted()
  let response: Response
  try {
    response = await fetch(`/api/v1/auth/${path}`, { method: 'POST', signal, credentials: 'omit', cache: 'no-store',
      redirect: 'error', referrerPolicy: 'no-referrer', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
  } catch {
    signal.throwIfAborted()
    throw new WebSessionError(0, 'İşlem sonucu doğrulanamadı. Bağlantınızı kontrol edin; sıfırlama gönderdiyseniz giriş yapmayı deneyebilir veya yeni bağlantı isteyebilirsiniz.')
  }
  if (response.status !== expected) throw new WebSessionError(response.status,
    response.status === 429 ? 'Çok fazla istek yapıldı. Bir süre bekleyip tekrar deneyin.'
      : response.status === 422 ? 'Bağlantı veya şifre doğrulanamadı. Bağlantı geçersiz, süresi dolmuş veya kullanılmış olabilir. Şifre kurallarını kontrol edip yeni bağlantı isteyin.'
      : response.status === 400 ? 'Bilgiler doğrulanamadı. Formu ve sıfırlama bağlantısını kontrol edin.'
      : 'İşlem sunucuda tamamlanamadı. Daha sonra tekrar deneyin.')
  // Both canonical endpoints return an empty body. Never echo server text or credentials.
}
export function requestPasswordReset(body: PasswordResetRequest, signal: AbortSignal) {
  return send('password-reset-requests', body, 202, signal)
}
export function resetPassword(body: ResetPasswordRequest, signal: AbortSignal) {
  return send('reset-password', body, 204, signal)
}
