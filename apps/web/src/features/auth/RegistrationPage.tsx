import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import { AuthLayout } from './AuthLayout'
import { RegistrationError, registerUser } from './registrationApi'

export function RegistrationPage() {
  const [displayName, setDisplayName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [errors, setErrors] = useState<{ displayName?: string; email?: string; password?: string }>({})
  const [notice, setNotice] = useState('')
  const [pending, setPending] = useState(false)
  const [registered, setRegistered] = useState(false)
  const displayNameInput = useRef<HTMLInputElement>(null)
  const emailInput = useRef<HTMLInputElement>(null)
  const passwordInput = useRef<HTMLInputElement>(null)
  const operation = useRef<AbortController | null>(null)
  useEffect(() => () => operation.current?.abort(), [])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (operation.current || registered) return
    const passwordLength = Array.from(password).length
    const nextErrors = {
      displayName: displayName.trim() ? undefined : 'Adınızı ve soyadınızı girin.',
      email: /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) ? undefined : 'Geçerli bir e-posta adresi girin.',
      password: passwordLength >= 8 && passwordLength <= 128 ? undefined : 'Şifreniz 8–128 karakter olmalı.',
    }
    setErrors(nextErrors)
    setNotice('')
    if (nextErrors.displayName) { displayNameInput.current?.focus(); return }
    if (nextErrors.email) { emailInput.current?.focus(); return }
    if (nextErrors.password) { passwordInput.current?.focus(); return }
    const controller = new AbortController()
    operation.current = controller
    const request = { displayName: displayName.trim(), email: email.trim(), password }
    setPassword('')
    setShowPassword(false)
    setPending(true)
    try {
      await registerUser(request, controller.signal)
      if (!controller.signal.aborted) {
        setDisplayName('')
        setEmail('')
        setRegistered(true)
      }
    } catch (error) {
      if (!controller.signal.aborted) setNotice(error instanceof RegistrationError ? error.message : 'Kayıt tamamlanamadı. Lütfen tekrar deneyin.')
    } finally {
      if (!controller.signal.aborted) { operation.current = null; setPending(false) }
    }
  }

  return (
    <AuthLayout title="Danışan hesabı oluşturun." badge="Danışan kaydı"
      description="Beslenme takibinize başlamak için hesabınızı oluşturun. Bu form danışan kaydı içindir.">
      {registered ? <p className="form-message" role="status">Hesabınız oluşturuldu. Giriş yapmadan önce e-postanızı doğrulayın. Kod ulaşmazsa doğrulama ekranından yeni kod isteyebilirsiniz.</p> :
        <form noValidate aria-label="Danışan kayıt formu" aria-busy={pending} onSubmit={(event) => { void submit(event) }}>
          <div className="form-field">
            <label htmlFor="registration-name">Ad ve soyad</label>
            <input id="registration-name" name="displayName" autoComplete="name" ref={displayNameInput}
              value={displayName} disabled={pending} required aria-invalid={Boolean(errors.displayName)}
              aria-describedby={errors.displayName ? 'registration-name-error' : undefined}
              onChange={(event) => { setDisplayName(event.target.value); setErrors((current) => ({ ...current, displayName: undefined })); setNotice('') }} />
            {errors.displayName && <p className="field-error" id="registration-name-error" role="alert">{errors.displayName}</p>}
          </div>
          <div className="form-field">
            <label htmlFor="registration-email">E-posta adresi</label>
            <input id="registration-email" name="email" type="email" autoComplete="email" ref={emailInput}
              value={email} disabled={pending} required aria-invalid={Boolean(errors.email)}
              aria-describedby={errors.email ? 'registration-email-error' : undefined}
              onChange={(event) => { setEmail(event.target.value); setErrors((current) => ({ ...current, email: undefined })); setNotice('') }} />
            {errors.email && <p className="field-error" id="registration-email-error" role="alert">{errors.email}</p>}
          </div>
          <div className="form-field">
            <label htmlFor="registration-password">Şifre</label>
            <div className="password-field">
              <input id="registration-password" name="password" type={showPassword ? 'text' : 'password'} autoComplete="new-password"
                ref={passwordInput} value={password} disabled={pending} required aria-invalid={Boolean(errors.password)}
                aria-describedby={`registration-password-help${errors.password ? ' registration-password-error' : ''}`}
                onChange={(event) => { setPassword(event.target.value); setErrors((current) => ({ ...current, password: undefined })); setNotice('') }} />
              <button type="button" className="password-toggle" disabled={pending} onClick={() => setShowPassword(!showPassword)}
                aria-label={showPassword ? 'Şifreyi gizle' : 'Şifreyi göster'} aria-pressed={showPassword}>
                <Icon name={showPassword ? 'eyeOff' : 'eye'} />
              </button>
            </div>
            <p className="auth-description" id="registration-password-help">8–128 karakter. Boşluk kullanabilirsiniz.</p>
            {errors.password && <p className="field-error" id="registration-password-error" role="alert">{errors.password}</p>}
          </div>
          {notice && <p className="form-message error-message" role="alert">{notice}</p>}
          <button type="submit" className="button button-primary form-submit" disabled={pending}>
            {pending ? 'Hesap oluşturuluyor…' : 'Hesap oluştur'}
          </button>
        </form>}
      <Link to="/eposta-dogrulama" className="preview-link">E-postamı doğrula<Icon name="arrow" /></Link>
    </AuthLayout>
  )
}
