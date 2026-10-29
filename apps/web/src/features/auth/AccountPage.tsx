import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { AuthLayout } from './AuthLayout'
import { getAccount, getCsrf, logout, WebSessionError } from './webSessionApi'
import type { CurrentUserResponse } from './webSessionApi'

export function AccountPage() {
  const [account, setAccount] = useState<CurrentUserResponse>()
  const [pending, setPending] = useState(false)
  const [message, setMessage] = useState('')
  const [logoutFailed, setLogoutFailed] = useState(false)
  const context = useRef<{ token: string; userId: string } | null>(null)
  const operation = useRef<AbortController | null>(null)
  const navigate = useNavigate()

  async function load() {
    if (operation.current) return
    const controller = new AbortController()
    operation.current = controller
    context.current = null
    setAccount(undefined)
    setMessage('')
    setLogoutFailed(false)
    setPending(true)
    try {
      // Capture CSRF BEFORE reading the account: a later cookie change cannot authorize an old tab's write.
      const token = await getCsrf(controller.signal)
      const user = await getAccount(controller.signal)
      if (!controller.signal.aborted) { context.current = { token, userId: user.id }; setAccount(user) }
    } catch (error) {
      if (!controller.signal.aborted) {
        if (error instanceof WebSessionError && error.status === 401) navigate('/giris', { replace: true })
        else setMessage(error instanceof WebSessionError ? error.message : 'Hesap okunamadı. Lütfen tekrar deneyin.')
      }
    } finally {
      if (!controller.signal.aborted) { operation.current = null; setPending(false) }
    }
  }

  useEffect(() => {
    void load()
    return () => { operation.current?.abort(); operation.current = null; context.current = null }
    // The account is restored on mount, never by background keepalive polling.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function signOut() {
    if (operation.current || !context.current) return
    const captured = context.current
    const retry = logoutFailed
    const controller = new AbortController()
    operation.current = controller
    setAccount(undefined)
    setMessage('')
    setPending(true)
    try {
      let token = captured.token
      if (retry) {
        token = await getCsrf(controller.signal)
        try {
          const current = await getAccount(controller.signal)
          if (current.id !== captured.userId) throw new WebSessionError(400, 'Hesap değişti. Hesabı yeniden kontrol edin.')
        } catch (error) { if (!(error instanceof WebSessionError && error.status === 401)) throw error }
      }
      await logout(token, controller.signal)
      if (!controller.signal.aborted) { context.current = null; navigate('/giris', { replace: true }) }
    } catch (error) {
      if (!controller.signal.aborted) {
        if (error instanceof WebSessionError && [400, 401, 403].includes(error.status)) {
          context.current = null
          setLogoutFailed(false)
          setMessage('Oturum bağlamı değişti. Hesabı yeniden kontrol edin.')
        } else {
          setLogoutFailed(true)
          setMessage('Çıkış sunucuda doğrulanamadı; tekrar deneyin.')
        }
      }
    } finally {
      if (!controller.signal.aborted) { operation.current = null; setPending(false) }
    }
  }

  return <AuthLayout title="Hesabım" badge="Hesap" description="Hesap bilgilerinizi görüntüleyebilir ve oturumunuzu kapatabilirsiniz.">
    {pending && <p role="status">İşlem sürüyor…</p>}
    {message && <p className="form-message error-message" role="alert">{message}</p>}
    {account && <section aria-label="Hesap bilgileri">
      <dl className="account-details">
        <dt>Ad</dt><dd>{account.displayName ?? 'Belirtilmemiş'}</dd>
        <dt>E-posta</dt><dd>{account.email}</dd>
        <dt>Hesap türü</dt><dd>{account.role === 'client' ? 'Danışan' : account.role === 'admin' ? 'Yönetici' : 'Diyetisyen'}</dd>
        <dt>E-posta doğrulaması</dt><dd>Doğrulandı</dd>
      </dl>
      {account.role === 'admin' && <Link className="preview-link" to="/yonetim/uzmanlar">Uzman başvurularını incele</Link>}
      {account.role === 'dietitian' && <Link className="preview-link" to="/uzman/basvuru-durumu">Başvuru durumum</Link>}
      <button className="button button-primary form-submit" onClick={() => { void signOut() }} disabled={pending}>Çıkış yap</button>
    </section>}
    {logoutFailed && <button className="button button-primary form-submit" disabled={pending} onClick={() => { void signOut() }}>Çıkışı tekrar dene</button>}
    {!account && !pending && <button className="button button-secondary form-submit" onClick={() => { void load() }}>Hesabı yeniden kontrol et</button>}
    <Link className="preview-link" to="/giris">Giriş ekranına git</Link>
  </AuthLayout>
}
