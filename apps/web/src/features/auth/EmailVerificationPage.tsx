import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { AuthLayout } from './AuthLayout'
import { EmailVerificationError, resendVerification, verifyEmail } from './emailVerificationApi'

export function EmailVerificationPage() {
  const [token, setToken] = useState('')
  const [email, setEmail] = useState('')
  const [tokenError, setTokenError] = useState('')
  const [emailError, setEmailError] = useState('')
  const [feedback, setFeedback] = useState<{ action: 'verify' | 'resend'; message: string; isError: boolean }>()
  const [pending, setPending] = useState<'verify' | 'resend'>()
  const [isVerified, setIsVerified] = useState(false)
  const tokenInput = useRef<HTMLInputElement>(null)
  const emailInput = useRef<HTMLInputElement>(null)
  const operation = useRef<AbortController | null>(null)

  useEffect(() => () => operation.current?.abort(), [])

  async function submit(event: FormEvent<HTMLFormElement>, action: 'verify' | 'resend') {
    event.preventDefault()
    if (operation.current || isVerified) return
    setFeedback(undefined)
    if (action === 'verify' && !/^[A-Za-z0-9_-]{43}$/.test(token.trim())) {
      setTokenError('E-postadaki 43 karakterlik doğrulama kodunu eksiksiz girin.')
      tokenInput.current?.focus()
      return
    }
    if (action === 'resend' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      setEmailError('Geçerli bir e-posta adresi girin.')
      emailInput.current?.focus()
      return
    }
    const controller = new AbortController()
    operation.current = controller
    setPending(action)
    const submittedToken = token.trim()
    setToken('')
    setTokenError('')
    setEmailError('')
    try {
      if (action === 'verify') {
        await verifyEmail({ token: submittedToken }, controller.signal)
        if (!controller.signal.aborted) setIsVerified(true)
      } else {
        await resendVerification({ email: email.trim() }, controller.signal)
        if (!controller.signal.aborted) setFeedback({ action, isError: false,
          message: 'Hesap doğrulama için uygunsa kod gönderimi işleme alınır. Gelen kutunuzu ve spam klasörünü kontrol edin. Yeni kod gelirse en son e-postadaki kodu kullanın.' })
      }
    } catch (error) {
      if (!controller.signal.aborted) setFeedback({ action, isError: true,
        message: error instanceof EmailVerificationError ? error.message : 'İşlem tamamlanamadı. Lütfen tekrar deneyin.' })
    } finally {
      if (!controller.signal.aborted) {
        operation.current = null
        setPending(undefined)
      }
    }
  }

  function message(action: 'verify' | 'resend') {
    return feedback?.action === action && <p className={`form-message${feedback.isError ? ' error-message' : ''}`}
      role={feedback.isError ? 'alert' : 'status'}>{feedback.message}</p>
  }

  return (
    <AuthLayout title="E-postanızı doğrulayın." badge="E-posta doğrulama"
      description="Size gönderilen e-postadaki tek kullanımlık kodu girin. Kod 30 dakika geçerlidir.">
      {isVerified ? <p className="form-message" role="status">E-posta adresiniz doğrulandı. Oturum açılmadı. Giriş ekranına dönebilirsiniz.</p> : <>
        <form noValidate aria-label="E-posta doğrulama formu" aria-busy={pending === 'verify'} onSubmit={(event) => { void submit(event, 'verify') }}>
          <div className="form-field">
            <label htmlFor="verification-token">Doğrulama kodu</label>
            <input id="verification-token" name="token" type="password" autoComplete="off" spellCheck={false}
              autoCapitalize="none" value={token} ref={tokenInput} disabled={Boolean(pending)} required
              aria-invalid={Boolean(tokenError)} aria-describedby={tokenError ? 'verification-token-error' : undefined}
              onChange={(event) => { setToken(event.target.value); setTokenError(''); setFeedback(undefined) }} />
            {tokenError && <p id="verification-token-error" className="field-error" role="alert">{tokenError}</p>}
          </div>
          {message('verify')}
          <button type="submit" className="button button-primary form-submit" disabled={Boolean(pending)}>
            {pending === 'verify' ? 'Doğrulanıyor…' : 'E-postamı doğrula'}
          </button>
        </form>
        <section className="verification-resend" aria-labelledby="resend-title">
          <h2 id="resend-title">Kod ulaşmadı mı?</h2>
          <p className="auth-description">Hesabınızın e-posta adresiyle yeni kod isteyebilirsiniz.</p>
          <form noValidate aria-label="Doğrulama kodunu yeniden isteme formu" aria-busy={pending === 'resend'} onSubmit={(event) => { void submit(event, 'resend') }}>
            <div className="form-field">
              <label htmlFor="verification-email">E-posta adresi</label>
              <input id="verification-email" name="email" type="email" autoComplete="email" value={email}
                ref={emailInput} disabled={Boolean(pending)} required aria-invalid={Boolean(emailError)}
                aria-describedby={emailError ? 'verification-email-error' : undefined}
                onChange={(event) => { setEmail(event.target.value); setEmailError(''); setFeedback(undefined) }} />
              {emailError && <p id="verification-email-error" className="field-error" role="alert">{emailError}</p>}
            </div>
            {message('resend')}
            <button type="submit" className="button button-secondary form-submit" disabled={Boolean(pending)}>
              {pending === 'resend' ? 'İstek gönderiliyor…' : 'Yeni kod iste'}
            </button>
          </form>
        </section>
      </>}
    </AuthLayout>
  )
}
