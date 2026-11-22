import { useCallback, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import { EmptyState } from '../../core/components/EmptyState'
import { getClients, getRelationships } from '../relationships/relationshipApi'
import { useWorkspaceRead, useWorkspaceSession } from './workspaceSession'

import { defaultClientList, useClientListState } from '../relationships/clientListState'

export function LiveDashboardPage() {
  const [, setList] = useClientListState()
  useEffect(() => { setList(defaultClientList()) }, [setList])
  const { dietitianId } = useWorkspaceSession()
  const loadClients = useCallback((signal: AbortSignal) => getClients(1, '', 'asc', signal), [])
  const loadRequests = useCallback((signal: AbortSignal) => getRelationships('pending', 1, dietitianId, signal), [dietitianId])
  const clients = useWorkspaceRead(loadClients)
  const requests = useWorkspaceRead(loadRequests)
  return <>
    <div className="dashboard-heading"><div className="page-heading"><p className="eyebrow">GÜNLÜK ÇALIŞMA ALANI</p><h1 tabIndex={-1}>Genel bakış</h1><p>Danışanlarınız, bağlantılarınız ve bir sonraki adımınız.</p></div>
      <button className="button button-secondary" disabled={clients.pending || requests.pending} onClick={() => { clients.refresh(); requests.refresh() }}><Icon name="clock" />Özeti yenile</button>
    </div>
    <section className="card dashboard-quick-actions" aria-label="Günlük işlemler"><h2>Danışanlarla çalışmaya başlayın</h2><div className="expert-pagination">
      <Link className="button button-primary" to="/calisma-alani/danisanlar"><Icon name="search" />Danışan ara ve görüntüle</Link>
      <Link className="button button-secondary" to="/calisma-alani/baglantilar">Bekleyen isteklere git</Link>
    </div></section>
    <section className="metrics-grid live-metrics" aria-label="Çalışma alanı özeti">
      <article className="metric-card"><div className="metric-top"><h2>Aktif danışanlar</h2><span className="metric-icon green"><Icon name="users" /></span></div>
        <strong className="metric-value">{clients.data?.totalCount ?? '—'}</strong><p>Aktif bağlantı kurduğunuz danışanlar</p>
      </article>
      <article className="metric-card" aria-labelledby="live-requests-title"><div className="metric-top"><h2 id="live-requests-title">Bekleyen istekler</h2><span className="metric-icon amber"><Icon name="link" /></span></div>
        <strong className="metric-value">{requests.data?.totalCount ?? '—'}</strong><p>Yanıtınızı bekleyen bağlantı talepleri</p>
        {requests.pending && <p role="status">Bekleyen istekler okunuyor…</p>}
        {requests.message && <><p role="alert" className="error-message">{requests.message}</p><button className="button button-secondary" onClick={requests.refresh}>İstekleri yeniden dene</button></>}
        {requests.data && <p>{requests.data.totalCount === 0 ? 'Bekleyen bağlantı talebi bulunmuyor.' : 'Talepleri Bağlantılar bölümünden yanıtlayabilirsiniz.'}</p>}
      </article>
    </section>
    <div className="dashboard-primary">
      <section className="card" aria-labelledby="live-clients-title"><header className="card-header"><div><h2 id="live-clients-title">Danışanlarım</h2><p>Ad sırasına göre ilk danışanlarınız.</p></div><Link className="text-link" to="/calisma-alani/danisanlar">Tümünü gör<Icon name="arrow" /></Link></header>
        {clients.pending && <p role="status">Aktif danışanlar okunuyor…</p>}
        {clients.message && <><p role="alert" className="error-message">{clients.message}</p><button className="button button-secondary" onClick={clients.refresh}>Danışanları yeniden dene</button></>}
        {clients.data && (clients.data.totalCount === 0
          ? <EmptyState icon="users" title="İlk danışanınızla bağlantı kurun">Bağlantılar bölümünden davet kodu oluşturabilir ve gelen talepleri yanıtlayabilirsiniz.</EmptyState>
          : <ul className="live-client-list">{clients.data.items.slice(0, 5).map(client => <li key={client.id}><Link className="live-client-row" to={`/calisma-alani/danisanlar/${client.id}`}>
            <span className="client-avatar" aria-hidden="true">{client.displayName.slice(0, 1).toLocaleUpperCase('tr-TR')}</span><span className="client-identity"><strong>{client.displayName}</strong><small>Beslenme programlarını incele</small></span><Icon name="arrow" />
          </Link></li>)}</ul>)}
      </section>
      <section className="request-strip"><span className="strip-icon"><Icon name="link" /></span><div><h2>Yeni bağlantılara yer açın</h2><p>Davet kodunuzu oluşturun, gelen talepleri yanıtlayın.</p></div><Link className="icon-button" to="/calisma-alani/baglantilar" aria-label="Bağlantıları ve daveti aç"><Icon name="arrow" /></Link></section>
    </div>
  </>
}
