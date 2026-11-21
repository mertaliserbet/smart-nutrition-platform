import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { AuthLayout } from './AuthLayout'
import { AuthPage } from './AuthPage'
import { resetPassword, resetPasswordError, validResetToken } from './passwordResetApi'
import { WebSessionError } from './webSessionApi'

type Input = { kind: 'request'; token?: undefined } | { kind: 'invalid'; token?: undefined } | { kind: 'reset'; token: string }
function capture(hash: string, search: string): Input {
  if (!hash && !search) return { kind: 'request' }
  const fields = new URLSearchParams(hash.slice(1)), tokens = fields.getAll('token')
  return !search && [...fields].length === 1 && tokens.length === 1 && validResetToken(tokens[0]!)
    ? { kind: 'reset', token: tokens[0]! } : { kind: 'invalid' }
}
export function PasswordResetPage() {
  const location = useLocation(), navigate = useNavigate()
  const [source, setSource] = useState<Input & { revision: number }>(() => ({ ...capture(location.hash, location.search), revision: 0 }))
  useLayoutEffect(() => {
    if (!location.hash && !location.search) return
    const next = capture(location.hash, location.search)
    // The router URL is external state: capture a newly opened link before its secret is removed.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setSource(current => current.kind === next.kind && current.token === next.token ? current : { ...next, revision: current.revision + 1 })
  }, [location.hash, location.search])
  useEffect(() => {
    if (!location.hash && !location.search) return
    // Keep the secret only in this mounted page; never in router state or a clean URL.
    // Navigate after the parent router has subscribed to its history updates.
    navigate({ pathname: '/sifremi-unuttum', search: '', hash: '' }, { replace: true, state: null })
  }, [location.hash, location.search, navigate])
  function requestNew() { setSource(current => ({ kind: 'request', revision: current.revision + 1 })) }
  if (source.kind === 'request') return <AuthPage mode="reset" />
  return <AuthLayout badge="Şifre sıfırlama" title="Yeni şifrenizi belirleyin." description="Yeni şifrenizi iki alana aynı şekilde girin.">
    {source.kind === 'invalid' ? <>
      <p className="form-message error-message" role="alert">Sıfırlama bağlantısı eksik, geçersiz, süresi dolmuş veya kullanılmış olabilir; şifre de sunucu kurallarını karşılamamış olabilir. E-postadaki bağlantıyı yeniden açabilir veya yeni bağlantı isteyebilirsiniz.</p>
      <Link className="button button-primary form-submit" to="/sifremi-unuttum" onClick={requestNew}>Yeni sıfırlama bağlantısı iste</Link>
    </> : <ResetForm key={source.revision} token={source.token}
      onRejected={() => setSource(current => ({ kind: 'invalid', revision: current.revision + 1 }))}
      onSuccess={() => {
        requestNew()
        // Auth/account/workspace data is route-local; replacement unmounts it and
        // drops this token/password state. No persistent credential cache exists.
        navigate('/giris', { replace: true, state: { passwordResetComplete: true } })
      }} />}
  </AuthLayout>
}
function ResetForm({ token, onSuccess, onRejected }: { token: string; onSuccess: () => void; onRejected: () => void }) {
  const [password, setPassword] = useState(''), [repeat, setRepeat] = useState('')
  const [errors, setErrors] = useState<{ password?: string; repeat?: string }>({})
  const [message, setMessage] = useState(''), [pending, setPending] = useState(false)
  const passwordInput = useRef<HTMLInputElement>(null), repeatInput = useRef<HTMLInputElement>(null)
  const operation = useRef<AbortController | null>(null)
  useEffect(() => () => operation.current?.abort(), [])
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (operation.current) return
    const next = { password: resetPasswordError(password), repeat: password !== repeat ? 'Şifreler aynı olmalı.' : undefined }
    setErrors(next); setMessage('')
    if (next.password) { passwordInput.current?.focus(); return }
    if (next.repeat) { repeatInput.current?.focus(); return }
    const submitted = password, controller = new AbortController()
    operation.current = controller; setPending(true); setPassword(''); setRepeat('')
    try {
      await resetPassword({ token, password: submitted }, controller.signal)
      if (!controller.signal.aborted) onSuccess()
    } catch (error) {
      if (controller.signal.aborted) return
      if (error instanceof WebSessionError && error.status === 422) onRejected()
      else setMessage(error instanceof WebSessionError ? error.message : 'İşlem tamamlanamadı. Yeniden deneyin.')
    } finally {
      if (!controller.signal.aborted) { operation.current = null; setPending(false) }
    }
  }
  return <form noValidate aria-label="Yeni şifre formu" aria-busy={pending} onSubmit={event => { void submit(event) }}>
    <p id="reset-password-policy" className="auth-description">Şifre 8–128 Unicode karakter olmalı. Boşluklar aynen korunur; şifreniz kırpılmaz. Son kontrol sunucudadır.</p>
    <div className="form-field"><label htmlFor="reset-password">Yeni şifre</label>
      <input id="reset-password" name="password" type="password" autoComplete="new-password" value={password} ref={passwordInput} required disabled={pending}
        aria-invalid={Boolean(errors.password)} aria-describedby={`reset-password-policy${errors.password ? ' reset-password-error' : ''}`}
        onChange={e => { setPassword(e.target.value); setErrors(current => ({ ...current, password: undefined })); setMessage('') }} />
      {errors.password && <p id="reset-password-error" className="field-error" role="alert">{errors.password}</p>}
    </div>
    <div className="form-field"><label htmlFor="reset-repeat">Yeni şifre tekrarı</label>
      <input id="reset-repeat" name="passwordRepeat" type="password" autoComplete="new-password" value={repeat} ref={repeatInput} required disabled={pending}
        aria-invalid={Boolean(errors.repeat)} aria-describedby={errors.repeat ? 'reset-repeat-error' : undefined}
        onChange={e => { setRepeat(e.target.value); setErrors(current => ({ ...current, repeat: undefined })); setMessage('') }} />
      {errors.repeat && <p id="reset-repeat-error" className="field-error" role="alert">{errors.repeat}</p>}
    </div>
    {message && <p className="form-message error-message" role="alert">{message}</p>}
    <button className="button button-primary form-submit" disabled={pending}>{pending ? 'Şifre yenileniyor…' : 'Şifreyi yenile'}</button>
    <Link className="text-link" to="/giris">Giriş ekranına dön</Link>
  </form>
}
