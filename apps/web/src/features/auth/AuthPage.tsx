import { useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import { AuthLayout } from './AuthLayout'

type AuthMode = 'login' | 'reset'

// Login/reset remain presentation-only until the client session contract is approved.
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
  const emailInput = useRef<HTMLInputElement>(null)
  const passwordInput = useRef<HTMLInputElement>(null)
  const isLogin = mode === 'login'

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (isLoading) return
    const nextErrors = { email: emailError(email), password: isLogin && password.length === 0 ? 'Şifrenizi girin.' : undefined }
    setErrors(nextErrors)
    setNotice('')
    if (nextErrors.email) { emailInput.current?.focus(); return }
    if (nextErrors.password) { passwordInput.current?.focus(); return }
    // No request, storage, account lookup, success state or session simulation.
    setPassword('')
    setShowPassword(false)
    setNotice(isLogin
      ? 'Giriş şu anda kullanılamıyor. Arayüz önizlemesindesiniz; oturum açılmadı.'
      : 'Şifre sıfırlama şu anda kullanılamıyor. Herhangi bir e-posta gönderilmedi.')
  }

  return (
    <form noValidate onSubmit={submit} aria-label={isLogin ? 'Giriş formu' : 'Şifre sıfırlama formu'} aria-busy={isLoading}>
      <div className="form-field">
        <label htmlFor="email">E-posta adresi</label>
        <input id="email" name="email" type="email" autoComplete="email" ref={emailInput}
          placeholder="eposta@ornek.com" value={email} disabled={isLoading} required
          aria-invalid={Boolean(errors.email)} aria-describedby={errors.email ? 'email-error' : undefined}
          onChange={(event) => { setEmail(event.target.value); setErrors((current) => ({ ...current, email: undefined })); setNotice('') }} />
        {errors.email && <p className="field-error" id="email-error" role="alert">{errors.email}</p>}
      </div>
      {isLogin && <div className="form-field">
        <div className="field-label"><label htmlFor="password">Şifre</label><Link to="/sifremi-unuttum">Şifremi unuttum</Link></div>
        <div className="password-field">
          <input id="password" name="password" type={showPassword ? 'text' : 'password'} autoComplete="current-password"
            ref={passwordInput} placeholder="Şifrenizi girin" value={password} disabled={isLoading} required
            aria-invalid={Boolean(errors.password)} aria-describedby={errors.password ? 'password-error' : undefined}
            onChange={(event) => { setPassword(event.target.value); setErrors((current) => ({ ...current, password: undefined })); setNotice('') }} />
          <button type="button" className="password-toggle" onClick={() => setShowPassword(!showPassword)}
            disabled={isLoading} aria-label={showPassword ? 'Şifreyi gizle' : 'Şifreyi göster'} aria-pressed={showPassword}>
            <Icon name={showPassword ? 'eyeOff' : 'eye'} />
          </button>
        </div>
        {errors.password && <p className="field-error" id="password-error" role="alert">{errors.password}</p>}
      </div>}
      {errorMessage && <p className="form-message error-message" role="alert">{errorMessage}</p>}
      {notice && <p className="form-message" role="status">{notice}</p>}
      <button className="button button-primary form-submit" type="submit" disabled={isLoading}>
        {isLoading ? 'İşlem sürüyor…' : isLogin ? 'Giriş yap' : 'Sıfırlama bağlantısı iste'}{!isLoading && <Icon name="arrow" />}
      </button>
    </form>
  )
}

export function AuthPage({ mode }: { mode: AuthMode }) {
  const isLogin = mode === 'login'
  return (
    <AuthLayout isLogin={isLogin}
      title={isLogin ? 'Tekrar hoş geldiniz.' : 'Şifrenizi mi unuttunuz?'}
      description={isLogin ? 'Çalışma alanınıza giriş yaparak takibe kaldığınız yerden devam edin.' : 'Hesabınızın e-posta adresiyle şifre sıfırlama bağlantısı isteyebilirsiniz.'}>
      <div className="preview-note"><Icon name="info" /><p>Bu ekran bir arayüz önizlemesidir. {isLogin ? 'Hesap girişi henüz kullanılamıyor.' : 'Bu aşamada sıfırlama e-postası gönderilmez.'}</p></div>
      <AuthForm key={mode} mode={mode} />
      {isLogin && <Link to="/eposta-dogrulama" className="preview-link">E-postamı doğrula<Icon name="arrow" /></Link>}
      {isLogin && import.meta.env.DEV && <Link to="/onizleme" className="preview-link">Panel tasarımını incele<Icon name="arrow" /></Link>}
    </AuthLayout>
  )
}
