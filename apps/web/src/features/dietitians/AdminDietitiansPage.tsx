import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { AuthLayout } from '../auth/AuthLayout'
import { getAccount, getCsrf, WebSessionError } from '../auth/webSessionApi'
import { listApplications, verifyDietitian } from './dietitianApi'
import type { DietitianReviewItem } from './dietitianApi'
import './dietitians.css'

export function AdminDietitiansPage() {
  const [items, setItems] = useState<DietitianReviewItem[]>([])
  const [total, setTotal] = useState<number>()
  const [page, setPage] = useState(1)
  const [pending, setPending] = useState(false)
  const [message, setMessage] = useState('')
  const [notice, setNotice] = useState('')
  const operation = useRef<AbortController | null>(null)
  const csrf = useRef<string | null>(null)
  const navigate = useNavigate()

  function failed(error: unknown) {
    if (error instanceof WebSessionError && [400, 401, 403].includes(error.status)) {
      csrf.current = null; setItems([]); setTotal(undefined)
    }
    if (error instanceof WebSessionError && error.status === 401) navigate('/yonetici-giris', { replace: true })
    else setMessage(error instanceof WebSessionError ? error.message : 'İşlem doğrulanamadı. Yeniden kontrol edin.')
  }

  async function load(targetPage = page) {
    if (operation.current) return
    const controller = new AbortController(); operation.current = controller
    setItems([]); setTotal(undefined); csrf.current = null; setMessage(''); setNotice(''); setPending(true)
    try {
      const token = await getCsrf(controller.signal)
      const account = await getAccount(controller.signal)
      if (account.role !== 'admin') throw new WebSessionError(403, 'Bu alan yalnız MFA ile giriş yapan yöneticiler içindir.')
      const result = await listApplications(targetPage, controller.signal)
      if (!controller.signal.aborted) { csrf.current = token; setItems(result.items); setTotal(result.totalCount); setPage(targetPage) }
    } catch (error) { if (!controller.signal.aborted) failed(error) }
    finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }

  useEffect(() => {
    void load(1)
    return () => { operation.current?.abort(); operation.current = null; csrf.current = null }
    // No automatic polling or mutation retry across account/session changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function approve(id: string) {
    if (operation.current || !csrf.current) return
    const controller = new AbortController(); operation.current = controller
    setMessage(''); setNotice(''); setPending(true)
    try {
      const result = await verifyDietitian(id, csrf.current, controller.signal)
      if (!controller.signal.aborted) {
        setItems(current => current.filter(row => row.id !== result.id)); setTotal(current => current === undefined ? undefined : Math.max(0, current - 1))
        setNotice(`${result.displayName} için uzman onayı kaydedildi.`)
      }
    } catch (error) { if (!controller.signal.aborted) failed(error) }
    finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }

  return <AuthLayout title="Uzman başvuruları" badge="Yönetim" description="Mesleki kayıt açıklamasını inceleyerek uzmanı doğrulayın. Bu alan danışan sağlık verisi içermez.">
    {pending && <p role="status">İşlem sürüyor…</p>}
    {message && <p className="form-message error-message" role="alert">{message}</p>}
    {notice && <p className="form-message" role="status">{notice}</p>}
    {total !== undefined && <p>İnceleme bekleyen başvuru: {total}</p>}
    {!pending && total === 0 && <p>İnceleme bekleyen başvuru bulunmuyor.</p>}
    <ul className="expert-review-list" aria-label="Bekleyen uzman başvuruları">
      {items.map(row => <li key={row.id}><h2>{row.displayName}</h2><p className="expert-license">{row.licenseInfo}</p>
        <button className="button button-primary" disabled={pending || !csrf.current} onClick={() => { void approve(row.id) }} aria-label={`${row.displayName} için uzman onayı ver`}>Uzmanı onayla</button>
      </li>)}
    </ul>
    <p className="auth-description">Onay öncesinde uzmanın e-posta doğrulamasını tamamlaması gerekir.</p>
    <div className="expert-pagination">
      <button className="button button-secondary" disabled={pending || page <= 1} onClick={() => { void load(page - 1) }}>Önceki sayfa</button>
      <span>Sayfa {page}</span>
      <button className="button button-secondary" disabled={pending || total === undefined || page * 10 >= total} onClick={() => { void load(page + 1) }}>Sonraki sayfa</button>
    </div>
    <button className="button button-secondary form-submit" disabled={pending} onClick={() => { void load() }}>Başvuruları yeniden kontrol et</button>
    <Link className="preview-link" to="/hesabim">Hesabım ve çıkış</Link>
  </AuthLayout>
}
