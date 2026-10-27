// These anonymous operations use the approved 06 contract and create no session.
export type VerifyEmailRequest = { token: string }
export type ResendVerificationRequest = { email: string }

export class EmailVerificationError extends Error {}

async function post(action: 'verify-email' | 'resend-verification', body: VerifyEmailRequest | ResendVerificationRequest, signal: AbortSignal) {
  let response: Response
  try {
    response = await fetch(`/api/v1/auth/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      credentials: 'omit',
      cache: 'no-store',
      redirect: 'error',
      signal,
    })
  } catch {
    // Never surface a request body, server echo or transport exception to the UI.
    throw new EmailVerificationError('Sunucuya ulaşılamadı. Bağlantınızı kontrol edip tekrar deneyin.')
  }
  const expectedStatus = action === 'verify-email' ? 204 : 202
  if (response.status === expectedStatus) return
  if (action === 'verify-email' && response.status === 422)
    throw new EmailVerificationError('Kod geçersiz veya süresi dolmuş. En son e-postadaki kodu kullanın ya da yeni kod isteyin.')
  if (response.status === 429)
    throw new EmailVerificationError('Çok fazla istek yapıldı. Bir süre bekleyip tekrar deneyin.')
  if (response.status === 400)
    throw new EmailVerificationError('Bilgileri kontrol edip tekrar deneyin.')
  throw new EmailVerificationError('İşlem tamamlanamadı. Lütfen daha sonra tekrar deneyin.')
}

export function verifyEmail(request: VerifyEmailRequest, signal: AbortSignal) {
  return post('verify-email', request, signal)
}

export function resendVerification(request: ResendVerificationRequest, signal: AbortSignal) {
  return post('resend-verification', request, signal)
}
