import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import { getDietitianStatus } from '../dietitians/dietitianApi'
import { AuthLayout } from './AuthLayout'
import { login, WebSessionError } from './webSessionApi'
import './login.css'

type AuthMode = 'login' | 'reset'

// Password reset remains presentation-only until its separate contract is approved.
function emailError(value: string) {
  if (!value.trim()) return 'E-posta adresinizi girin.'
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()) ? undefined : 'Geçerli bir e-posta adresi girin.'
}

export function AuthForm({ mode, isLoading = false, errorMessage }: {
  mode: AuthMode; isLoading?: boolean; errorMessage?: string
}) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [errors, setErrors] = useState<{ email?: string; password?: string }>({})
  const [notice, setNotice] = useState('')
  const [pending, setPending] = useState(false)
  const [sessionConflict, setSessionConflict] = useState(false)
  const operation = useRef<AbortController | null>(null)
  const navigate = useNavigate()
  const emailInput = useRef<HTMLInputElement>(null)
  const passwordInput = useRef<HTMLInputElement>(null)
  const isLogin = mode === 'login'
  const busy = isLoading || pending
  useEffect(() => () => operation.current?.abort(), [])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (busy || operation.current) return
    const nextErrors = { email: emailError(email), password: isLogin && password.length === 0 ? 'Şifrenizi girin.' : undefined }
    setErrors(nextErrors)
    setNotice('')
    if (nextErrors.email) { emailInput.current?.focus(); return }
    if (nextErrors.password) { passwordInput.current?.focus(); return }
    const submittedPassword = password
    setPassword('')
    setShowPassword(false)
    if (!isLogin) { setNotice('Şifre sıfırlama şu anda kullanılamıyor. Herhangi bir e-posta gönderilmedi.'); return }
    const controller = new AbortController()
    operation.current = controller
    setPending(true)
    try {
      const account = await login({ email: email.trim(), password: submittedPassword }, controller.signal)
      if (controller.signal.aborted) return
      let destination = '/hesabim'
      let accessNotice: string | undefined
      try {
        // A verified expert can still have role=client. The current profile decides the destination.
        const profile = await getDietitianStatus(controller.signal)
        destination = profile.isVerified ? '/calisma-alani' : '/uzman/basvuru-durumu'
      } catch (error) {
        if (error instanceof WebSessionError && error.status === 401) throw error
        if (!(error instanceof WebSessionError && error.status === 404 && account.role === 'client')) {
          accessNotice = 'Giriş yapıldı; diyetisyen erişimi şu anda doğrulanamadı. Çalışma alanınızı yeniden açarak kontrol edebilirsiniz.'
        }
      }
      if (!controller.signal.aborted) navigate(destination, { replace: true, state: { accessNotice } })
    } catch (error) {
      if (!controller.signal.aborted) {
        if (error instanceof WebSessionError && error.status === 409) setSessionConflict(true)
        setNotice(error instanceof WebSessionError ? error.message : 'Giriş tamamlanamadı. Lütfen tekrar deneyin.')
      }
    } finally {
      if (!controller.signal.aborted) { operation.current = null; setPending(false) }
    }
  }

  return (
    <form noValidate onSubmit={(event) => { void submit(event) }} aria-label={isLogin ? 'Giriş formu' : 'Şifre sıfırlama formu'} aria-busy={busy}>
      <div className="form-field">
        <label htmlFor="email">E-posta adresi</label>
        <input id="email" name="email" type="email" autoComplete="email" ref={emailInput}
          placeholder="eposta@ornek.com" value={email} disabled={busy} required
          aria-invalid={Boolean(errors.email)} aria-describedby={errors.email ? 'email-error' : undefined}
          onChange={(event) => { setEmail(event.target.value); setErrors((current) => ({ ...current, email: undefined })); setNotice('') }} />
        {errors.email && <p className="field-error" id="email-error" role="alert">{errors.email}</p>}
      </div>
      {isLogin && <div className="form-field">
        <div className="field-label"><label htmlFor="password">Şifre</label><Link to="/sifremi-unuttum">Şifremi unuttum</Link></div>
        <div className="password-field">
          <input id="password" name="password" type={showPassword ? 'text' : 'password'} autoComplete="current-password"
            ref={passwordInput} placeholder="Şifrenizi girin" value={password} disabled={busy} required
            aria-invalid={Boolean(errors.password)} aria-describedby={errors.password ? 'password-error' : undefined}
            onChange={(event) => { setPassword(event.target.value); setErrors((current) => ({ ...current, password: undefined })); setNotice('') }} />
          <button type="button" className="password-toggle" onClick={() => setShowPassword(!showPassword)}
            disabled={busy} aria-label={showPassword ? 'Şifreyi gizle' : 'Şifreyi göster'} aria-pressed={showPassword}>
            <Icon name={showPassword ? 'eyeOff' : 'eye'} />
          </button>
        </div>
        {errors.password && <p className="field-error" id="password-error" role="alert">{errors.password}</p>}
      </div>}
      {errorMessage && <p className="form-message error-message" role="alert">{errorMessage}</p>}
      {notice && <p className="form-message" role="status">{notice}</p>}
      {sessionConflict && <Link className="button button-secondary form-submit" to="/hesabim" state={{ returnTo: '/giris' }}>Açık hesabı görüntüle ve çıkış yap</Link>}
      <button className="button button-primary form-submit" type="submit" disabled={busy}>
        {busy ? 'İşlem sürüyor…' : isLogin ? 'Giriş yap' : 'Sıfırlama bağlantısı iste'}{!busy && <Icon name="arrow" />}
      </button>
    </form>
  )
}

const loginOptions = [
  { to: '/uzman-basvurusu', label: 'Diyetisyen başvurusu yap', icon: 'users' },
  { to: '/yonetici-giris', label: 'Yönetici girişi', icon: 'shield' },
] as const

function LoginOptions() {
  return (
    <nav className="login-options" aria-label="Başvuru ve yönetici girişi">
      {loginOptions.map(({ to, label, icon }) => (
        <Link className="login-option" key={to} to={to}>
          <span className="login-option-icon"><Icon name={icon} /></span>
          <span>{label}</span>
          <Icon name="arrow" />
        </Link>
      ))}
      {import.meta.env.DEV && (
        <Link className="text-link login-preview-link" to="/onizleme"><Icon name="grid" />Panel tasarımını incele</Link>
      )}
    </nav>
  )
}

export function AuthPage({ mode }: { mode: AuthMode }) {
  const isLogin = mode === 'login'
  return (
    <AuthLayout isLogin={isLogin}
      badge={isLogin ? 'Hesap girişi' : 'Arayüz önizlemesi'}
      title={isLogin ? 'Tekrar hoş geldiniz.' : 'Şifrenizi mi unuttunuz?'}
      description={isLogin ? 'Çalışma alanınıza giriş yaparak takibe kaldığınız yerden devam edin.' : 'Hesabınızın e-posta adresiyle şifre sıfırlama bağlantısı isteyebilirsiniz.'}>
      {!isLogin && <div className="preview-note"><Icon name="info" /><p>Bu ekran bir arayüz önizlemesidir. Bu aşamada sıfırlama e-postası gönderilmez.</p></div>}
      <AuthForm key={mode} mode={mode} />
      {isLogin && <p className="auth-description">Danışan kaydı ve danışan işlemleri mobil uygulamada yapılır.</p>}
      {isLogin && <LoginOptions />}
    </AuthLayout>
  )
}
