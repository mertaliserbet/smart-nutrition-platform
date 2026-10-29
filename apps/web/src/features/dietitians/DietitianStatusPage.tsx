import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { AuthLayout } from '../auth/AuthLayout'
import { getAccount, WebSessionError } from '../auth/webSessionApi'
import { getDietitianStatus } from './dietitianApi'
import type { DietitianStatusResponse } from './dietitianApi'

export function DietitianStatusPage() {
  const [profile, setProfile] = useState<DietitianStatusResponse>()
  const [message, setMessage] = useState('')
  const [pending, setPending] = useState(false)
  const operation = useRef<AbortController | null>(null)
  const navigate = useNavigate()
  async function load() {
    if (operation.current) return
    const controller = new AbortController(); operation.current = controller
    setProfile(undefined); setMessage(''); setPending(true)
    try {
      const account = await getAccount(controller.signal)
      if (account.role !== 'dietitian') throw new WebSessionError(403, 'Bu alan diyetisyen başvuruları içindir.')
      const result = await getDietitianStatus(controller.signal)
      if (!controller.signal.aborted) setProfile(result)
    } catch (error) {
      if (!controller.signal.aborted) {
        if (error instanceof WebSessionError && error.status === 401) navigate('/giris', { replace: true })
        else setMessage(error instanceof WebSessionError ? error.message : 'Başvuru durumu okunamadı.')
      }
    } finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }
  useEffect(() => {
    void load()
    return () => { operation.current?.abort(); operation.current = null }
    // Reads only on entry or explicit refresh, without background session keepalive.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  return <AuthLayout title="Başvuru durumum" badge="Uzman hesabı" description="Mesleki başvurunuzun güncel Admin onayını takip edin.">
    {pending && <p role="status">Başvuru durumu okunuyor…</p>}
    {message && <p className="form-message error-message" role="alert">{message}</p>}
    {profile && <section aria-label="Başvuru durumu"><h2>{profile.displayName}</h2>
      <p className="form-message">{profile.isVerified ? 'Uzman doğrulamanız tamamlandı.' : 'Başvurunuz Admin incelemesini bekliyor.'}</p>
      <p>Danışanlara erişim için aktif bağlantı ve danışanın ilgili paylaşım izni gerekir.</p>
    </section>}
    <button className="button button-secondary form-submit" disabled={pending} onClick={() => { void load() }}>Durumu yenile</button>
    <Link className="preview-link" to="/hesabim">Hesabım ve çıkış</Link>
  </AuthLayout>
}
