import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { AuthLayout } from './AuthLayout'
import { adminLogin, WebSessionError } from './webSessionApi'

export function AdminLoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [mfaCode, setMfaCode] = useState('')
  const [message, setMessage] = useState('')
  const [pending, setPending] = useState(false)
  const operation = useRef<AbortController | null>(null)
  const navigate = useNavigate()
  useEffect(() => () => operation.current?.abort(), [])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (operation.current) return
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) || !password || !mfaCode.trim()) {
      setMessage('E-posta, şifre ve doğrulama kodunu doldurun.'); return
    }
    const controller = new AbortController(); operation.current = controller
    const body = { email: email.trim(), password, mfaCode: mfaCode.trim() }
    setPassword(''); setMfaCode(''); setMessage(''); setPending(true)
    try {
      await adminLogin(body, controller.signal)
      if (!controller.signal.aborted) navigate('/yonetim/uzmanlar', { replace: true })
    } catch (error) {
      if (!controller.signal.aborted) setMessage(error instanceof WebSessionError ? error.message : 'Yönetici girişi tamamlanamadı.')
    } finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }

  return <AuthLayout title="Yönetici girişi" badge="Güvenli yönetim" description="Şifreniz ve kimlik doğrulayıcınızdaki kodla giriş yapın. Gerektiğinde tek kullanımlık kurtarma kodunuzu kullanabilirsiniz.">
    <form noValidate aria-label="Yönetici giriş formu" aria-busy={pending} onSubmit={event => { void submit(event) }}>
      <div className="form-field"><label htmlFor="admin-email">E-posta adresi</label><input id="admin-email" name="email" type="email" autoComplete="username" value={email} disabled={pending} required onChange={event => setEmail(event.target.value)} /></div>
      <div className="form-field"><label htmlFor="admin-password">Şifre</label><input id="admin-password" name="password" type="password" autoComplete="current-password" value={password} disabled={pending} required onChange={event => setPassword(event.target.value)} /></div>
      <div className="form-field"><label htmlFor="admin-mfa">Doğrulama veya kurtarma kodu</label><input id="admin-mfa" name="mfaCode" type="password" autoComplete="one-time-code" value={mfaCode} disabled={pending} required onChange={event => setMfaCode(event.target.value)} /></div>
      {message && <p className="form-message error-message" role="alert">{message}</p>}
      <button className="button button-primary form-submit" disabled={pending} type="submit">{pending ? 'Giriş doğrulanıyor…' : 'Güvenli giriş yap'}</button>
    </form>
  </AuthLayout>
}
