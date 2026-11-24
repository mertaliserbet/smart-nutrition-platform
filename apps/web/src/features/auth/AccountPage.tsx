import { useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { WorkspaceLayout } from '../workspace/WorkspaceLayout'
import { Icon } from '../../core/components/Icon'
import { getAccount, getCsrf, logout, WebSessionError } from './webSessionApi'
import type { CurrentUserResponse } from './webSessionApi'

export function AccountPage() {
  const [account, setAccount] = useState<CurrentUserResponse>()
  const [pending, setPending] = useState(false)
  const [message, setMessage] = useState('')
  const [logoutFailed, setLogoutFailed] = useState(false)
  const [accountReturn, setAccountReturn] = useState('/giris')
  const context = useRef<{ token: string; userId: string; returnTo: string } | null>(null)
  const operation = useRef<AbortController | null>(null)
  const navigate = useNavigate()
  const location = useLocation()
  const [recovering, setRecovering] = useState(location.state?.logoutRecovery === true)
  const requestedReturn = location.state?.returnTo === '/yonetici-giris' || location.state?.returnTo === '/giris'
    ? location.state.returnTo as '/yonetici-giris' | '/giris' : undefined
  const returnTo = requestedReturn ?? accountReturn

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
      if (!controller.signal.aborted) {
        const destination = user.role === 'admin' ? '/yonetici-giris' : '/giris'
        context.current = { token, userId: user.id, returnTo: requestedReturn ?? destination }
        setAccountReturn(destination)
        setAccount(user)
      }
    } catch (error) {
      if (!controller.signal.aborted) {
        if (error instanceof WebSessionError && error.status === 401) navigate(returnTo, { replace: true })
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
    setRecovering(false)
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
      if (!controller.signal.aborted) { context.current = null; navigate(captured.returnTo, { replace: true }) }
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

  return <WorkspaceLayout audience={account?.role === 'admin' ? 'admin' : 'dietitian'} profile={account && context.current ? { displayName: account.displayName ?? 'Hesabım', email: account.email, token: context.current.token } : undefined}>
    <div className="page-heading"><h1 tabIndex={-1}>Ayarlar</h1><p>Profilini, çalışma düzenini ve hesap tercihlerini yönet.</p></div>
    <div className="settings-layout"><nav className="card settings-navigation" aria-label="Hesap bölümleri"><a href="#account-profile"><Icon name="users" />Profil ve kurum</a><a href="#account-hours"><Icon name="calendar" />Çalışma saatleri</a><a href="#account-notifications"><Icon name="bell" />Bildirimler</a><a href="#account-security"><Icon name="shield" />Hesap ve güvenlik</a><a href="#account-privacy"><Icon name="database" />Gizlilik ve veriler</a></nav><div className="card settings-profile" id="account-profile"><h2>Profil ve kurum bilgileri</h2>
    {pending && <p role="status">İşlem sürüyor…</p>}
    {message && <p className="form-message error-message" role="alert">{message}</p>}
    {account && recovering && <p className="form-message error-message" role="alert">Çıkış doğrulanamadı. Devam etmeden önce açık hesabı kontrol edin.</p>}
    {account && typeof location.state?.accessNotice === 'string' && <p className="form-message" role="status">{location.state.accessNotice}</p>}
    {account && <section aria-label="Hesap bilgileri">
      <div className="settings-identity"><span className="client-avatar large-avatar" aria-hidden="true">{account.displayName?.trim().split(/\s+/).slice(0, 2).map(part => Array.from(part)[0]).join('') || <Icon name="users" />}</span><div><button className="button button-secondary" disabled aria-describedby="profile-unavailable"><Icon name="camera" />Fotoğraf değiştir</button></div></div>
      <dl className="account-details">
        <div><dt>Ad soyad</dt><dd>{account.displayName ?? 'Belirtilmemiş'}</dd></div>
        <div><dt>E-posta</dt><dd>{account.email}</dd></div>
        <div><dt>Web profili</dt><dd>{account.role === 'admin' ? 'Yönetici' : 'Diyetisyen'}</dd></div>
        <div><dt>E-posta doğrulaması</dt><dd>{account.isEmailVerified ? 'Doğrulandı' : 'Doğrulanmadı'}</dd></div>
        {['Telefon', 'Kurum adı', 'Şehir', 'Zaman dilimi'].map(label => <div key={label}><dt>{label}</dt><dd aria-label={`${label} sunulmuyor`}>—</dd></div>)}
      </dl><label className="settings-biography">Kısa biyografi<textarea disabled placeholder="Bu sürümde sunulmuyor" rows={3} /></label><div className="settings-visibility" id="account-privacy"><h3>Profil görünürlüğü</h3><div className="settings-visibility-row" title="Bu tercih bilgisi sunulmuyor">Adımı ve unvanımı danışanlara göster</div><div className="settings-visibility-row" title="Bu tercih bilgisi sunulmuyor">Kurum bilgilerimi randevu sayfasında göster</div><button className="button button-primary" disabled>Değişiklikleri kaydet</button></div>
    </section>}
    {logoutFailed && <button className="button button-primary form-submit" disabled={pending} onClick={() => { void signOut() }}>Çıkışı tekrar dene</button>}
    {!account && !pending && <button className="button button-secondary form-submit" onClick={() => { void load() }}>Hesabı yeniden kontrol et</button>}
    </div><aside className="settings-aside"><section className="card" id="account-hours"><div className="settings-card-heading"><span className="marketing-icon"><Icon name="calendar" /></span><h2>Çalışma düzeni</h2></div><div className="settings-placeholder-row"><span>Hafta içi</span><strong>—</strong></div><div className="settings-placeholder-row"><span>Hafta sonu</span><strong>—</strong></div><button className="button button-secondary" disabled>Çalışma düzeni sunulmuyor</button></section><section className="card" id="account-notifications"><div className="settings-card-heading"><span className="marketing-icon"><Icon name="bell" /></span><h2>Bildirim tercihleri</h2></div><div className="settings-placeholder-row"><span>Yeni randevu talebi</span><span>—</span></div><div className="settings-placeholder-row"><span>Yeni mesaj</span><span>—</span></div><p>Bildirim tercihleri bu sürümde sunulmuyor.</p></section><section className="card settings-security" id="account-security"><div className="settings-card-heading"><span className="marketing-icon"><Icon name="shield" /></span><h2>Hesap güvenliği</h2></div><p>Bu tarayıcıdaki oturumunuzu güvenli biçimde kapatabilirsiniz.</p>{account && <button className="button button-secondary" onClick={() => { void signOut() }} disabled={pending}>Çıkış yap</button>}<div className="settings-account-links">{account?.role === 'admin' ? <Link to="/yonetim/uzmanlar">Uzman başvurularını incele</Link> : <><Link to="/uzman/basvuru-durumu">Başvuru durumum</Link><Link to="/calisma-alani">Çalışma alanımı aç</Link></>}<Link to={returnTo}>Giriş ekranına git</Link></div></section></aside></div>
    <div className="inline-note" id="profile-unavailable"><Icon name="info" /><p>Profil bilgileri salt okunur. Fotoğraf, kurum ve profil düzenleme bu sürümde sunulmuyor.</p></div>
  </WorkspaceLayout>
}
