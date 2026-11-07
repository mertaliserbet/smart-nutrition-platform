import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { WorkspaceLayout } from '../workspace/WorkspaceLayout'
import { EmptyState } from '../../core/components/EmptyState'
import { Icon } from '../../core/components/Icon'
import { getAccount, getCsrf, WebSessionError } from '../auth/webSessionApi'
import { listApplications, verifyDietitian } from './dietitianApi'
import type { DietitianReviewItem } from './dietitianApi'
import './dietitians.css'

export function AdminDietitiansPage() {
  const [items, setItems] = useState<DietitianReviewItem[]>([])
  const [total, setTotal] = useState<number>()
  const [page, setPage] = useState(1)
  const [verified, setVerified] = useState(false)
  const [displayName, setDisplayName] = useState<string>()
  const [pending, setPending] = useState(false)
  const [message, setMessage] = useState('')
  const [notice, setNotice] = useState('')
  const operation = useRef<AbortController | null>(null)
  const csrf = useRef<string | null>(null)
  const navigate = useNavigate()

  function failed(error: unknown) {
    if (error instanceof WebSessionError && [400, 401, 403].includes(error.status)) {
      csrf.current = null; setItems([]); setTotal(undefined); setDisplayName(undefined)
    }
    if (error instanceof WebSessionError && error.status === 401) navigate('/yonetici-giris', { replace: true })
    else setMessage(error instanceof WebSessionError ? error.message : 'İşlem doğrulanamadı. Yeniden kontrol edin.')
  }

  async function load(targetPage = page, targetVerified = verified) {
    if (operation.current) return
    const controller = new AbortController(); operation.current = controller
    setItems([]); setTotal(undefined); setDisplayName(undefined); csrf.current = null; setMessage(''); setNotice(''); setPending(true)
    setVerified(targetVerified); setPage(targetPage)
    try {
      const token = await getCsrf(controller.signal)
      const account = await getAccount(controller.signal)
      if (account.role !== 'admin') throw new WebSessionError(403, 'Bu alan yalnız MFA ile giriş yapan yöneticiler içindir.')
      const result = await listApplications(targetPage, controller.signal, targetVerified)
      if (!controller.signal.aborted) { csrf.current = token; setItems(result.items); setTotal(result.totalCount); setDisplayName(account.displayName ?? 'Yönetici') }
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

  return <WorkspaceLayout audience="admin" displayName={displayName}>
    <div className="page-heading"><p className="eyebrow">YÖNETİM ÇALIŞMA ALANI</p><h1 tabIndex={-1}>Uzman başvuruları</h1><p>Mesleki kayıt açıklamalarını inceleyin ve diyetisyen doğrulamalarını yönetin.</p></div>
    <div className="inline-note"><Icon name="shield" /><p>Uzman onayı yalnız mesleki profili doğrular. Danışan sağlık verilerine erişim sağlamaz.</p></div>
    {pending && <p role="status">İşlem sürüyor…</p>}
    {message && <p className="form-message error-message" role="alert">{message}</p>}
    {notice && <p className="form-message" role="status">{notice}</p>}
    <section className="card"><header className="card-header"><div><h2>{verified ? 'Onaylı diyetisyenler' : 'İnceleme bekleyen başvurular'}</h2>
      <p>{total === undefined ? 'Başvurular kontrol ediliyor' : verified ? `Onaylı diyetisyen: ${total}` : `İnceleme bekleyen başvuru: ${total}`}</p></div>
      <label className="panel-filter">Başvuru durumu<select value={String(verified)} disabled={pending} onChange={event => { void load(1, event.target.value === 'true') }}><option value="false">Onay bekleyen</option><option value="true">Onaylı</option></select></label>
    </header>
    {!pending && total === 0 && <EmptyState icon="shield" title={verified ? 'Onaylı diyetisyen bulunmuyor.' : 'İnceleme bekleyen başvuru bulunmuyor.'}>Başvuruları yenileyerek güncel listeyi kontrol edebilirsiniz.</EmptyState>}
    <ul className="expert-review-list admin-review-list" aria-label={verified ? 'Onaylı diyetisyenler' : 'Bekleyen uzman başvuruları'}>
      {items.map(row => <li key={row.id}><div className="connection-heading"><h2>{row.displayName}</h2><span className={row.isVerified ? 'access-badge' : 'neutral-badge'}>{row.isVerified ? 'Onaylı' : 'Onay bekliyor'}</span></div><p className="eyebrow license-label">MESLEKİ KAYIT AÇIKLAMASI</p><p className="expert-license">{row.licenseInfo}</p>
        {!row.isVerified && <button className="button button-primary" disabled={pending || !csrf.current} onClick={() => { void approve(row.id) }} aria-label={`${row.displayName} için uzman onayı ver`}>Uzmanı onayla<Icon name="check" /></button>}
      </li>)}
    </ul>
    {!verified && <p className="panel-description panel-inset">Onay öncesinde uzmanın e-posta doğrulamasını tamamlaması gerekir.</p>}
    <div className="panel-pagination">
      <button className="button button-secondary" disabled={pending || page <= 1} onClick={() => { void load(page - 1) }}>Önceki sayfa</button>
      <span>Sayfa {page}</span>
      <button className="button button-secondary" disabled={pending || total === undefined || page * 10 >= total} onClick={() => { void load(page + 1) }}>Sonraki sayfa</button>
    </div>
    <div className="panel-actions"><button className="button button-secondary" disabled={pending} onClick={() => { void load() }}>Başvuruları yeniden kontrol et</button></div>
    </section>
    {message && !displayName && <Link className="text-link" to="/yonetici-giris">Yönetici girişine dön</Link>}
  </WorkspaceLayout>
}
