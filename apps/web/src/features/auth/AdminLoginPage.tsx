import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { AuthLayout } from './AuthLayout'
import { adminLogin, requestAdminEmailCode, WebSessionError } from './webSessionApi'

export function AdminLoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [mfaCode, setMfaCode] = useState('')
  const [message, setMessage] = useState('')
  const [pending, setPending] = useState(false)
  const [sessionConflict, setSessionConflict] = useState(false)
  const [emailMethod, setEmailMethod] = useState(import.meta.env.DEV)
  const [notice, setNotice] = useState('')
  const [retryAt, setRetryAt] = useState(0)
  const [secondsLeft, setSecondsLeft] = useState(0)
  const operation = useRef<AbortController | null>(null)
  const navigate = useNavigate()
  useEffect(() => () => operation.current?.abort(), [])
  useEffect(() => {
    if (!retryAt) return
    const update = () => setSecondsLeft(Math.max(0, Math.ceil((retryAt - Date.now()) / 1000)))
    update()
    const timer = window.setInterval(update, 1000)
    return () => window.clearInterval(timer)
  }, [retryAt])

  async function sendCode() {
    if (operation.current || Date.now() < retryAt) return
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) || !password) {
      setMessage('Kod istemek için e-posta adresinizi ve şifrenizi girin.'); return
    }
    const controller = new AbortController(); operation.current = controller
    setPending(true); setMessage(''); setNotice(''); setMfaCode('')
    try {
      await requestAdminEmailCode({ email: email.trim(), password }, controller.signal)
      if (!controller.signal.aborted) {
        setNotice('Bilgileriniz uygunsa giriş kodu e-postanıza gönderildi. Mailpit’teki 6 haneli kodu girin; kod 5 dakika geçerlidir.')
        setSecondsLeft(60); setRetryAt(Date.now() + 60_000)
      }
    } catch (error) {
      if (!controller.signal.aborted) {
        if (error instanceof WebSessionError && error.status === 409) setSessionConflict(true)
        setMessage(error instanceof WebSessionError && error.status === 404
          ? 'Bu ortamda e-posta kodu kullanılamıyor. Kimlik doğrulayıcı veya kurtarma koduyla giriş yapın.'
          : error instanceof WebSessionError ? error.message : 'Kod isteği tamamlanamadı.')
      }
    } finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (operation.current) return
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) || !password || !mfaCode.trim()) {
      setMessage('E-posta, şifre ve doğrulama kodunu doldurun.'); return
    }
    const controller = new AbortController(); operation.current = controller
    const body = { email: email.trim(), password, mfaCode: mfaCode.trim() }
    setPassword(''); setMfaCode(''); setMessage(''); setNotice(''); setPending(true)
    try {
      await adminLogin(body, controller.signal)
      if (!controller.signal.aborted) navigate('/yonetim/uzmanlar', { replace: true })
    } catch (error) {
      if (!controller.signal.aborted) {
        if (error instanceof WebSessionError && error.status === 409) setSessionConflict(true)
        setMessage(error instanceof WebSessionError ? error.message : 'Yönetici girişi tamamlanamadı.')
      }
    } finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }

  return <AuthLayout title="Yönetici girişi" badge="Güvenli yönetim" description={emailMethod
    ? 'Yerel geliştirme ortamında giriş kodunu e-postanıza gönderip Mailpit üzerinden görüntüleyebilirsiniz.'
    : 'Şifreniz ve kimlik doğrulayıcınızdaki kodla giriş yapın. Gerektiğinde tek kullanımlık kurtarma kodunuzu kullanabilirsiniz.'}>
    <form noValidate aria-label="Yönetici giriş formu" aria-busy={pending} onSubmit={event => { void submit(event) }}>
      <div className="form-field"><label htmlFor="admin-email">E-posta adresi</label><input id="admin-email" name="email" type="email" autoComplete="username" value={email} disabled={pending} required onChange={event => setEmail(event.target.value)} /></div>
      <div className="form-field"><label htmlFor="admin-password">Şifre</label><input id="admin-password" name="password" type="password" autoComplete="current-password" value={password} disabled={pending} required onChange={event => setPassword(event.target.value)} /></div>
      {import.meta.env.DEV && <>
        <button className="button button-secondary form-submit" disabled={pending} type="button" onClick={() => { setEmailMethod(!emailMethod); setMfaCode(''); setMessage(''); setNotice('') }}>
          {emailMethod ? 'Kimlik doğrulayıcı / kurtarma kodu kullan' : 'E-posta ile kod kullan'}
        </button>
        {emailMethod && <button className="button button-secondary form-submit" disabled={pending || secondsLeft > 0} type="button" onClick={() => { void sendCode() }}>
          {secondsLeft > 0 ? `Tekrar kod gönder (${secondsLeft} sn)` : 'E-posta ile kod gönder'}
        </button>}
      </>}
      <div className="form-field"><label htmlFor="admin-mfa">Doğrulama veya kurtarma kodu</label><input id="admin-mfa" name="mfaCode" type="password" autoComplete="one-time-code" value={mfaCode} disabled={pending} required onChange={event => setMfaCode(event.target.value)} /></div>
      {notice && <p className="form-message" role="status">{notice}</p>}
      {message && <p className="form-message error-message" role="alert">{message}</p>}
      {sessionConflict && <Link className="button button-secondary form-submit" to="/hesabim" state={{ returnTo: '/yonetici-giris' }}>Açık hesabı görüntüle ve çıkış yap</Link>}
      <button className="button button-primary form-submit" disabled={pending} type="submit">{pending ? 'Giriş doğrulanıyor…' : 'Güvenli giriş yap'}</button>
    </form>
    <Link className="preview-link" to="/hesabim" state={{ returnTo: '/yonetici-giris' }}>Açık yönetici hesabımı kontrol et</Link>
    <Link className="preview-link" to="/giris">Diyetisyen / danışan girişine dön</Link>
  </AuthLayout>
}
