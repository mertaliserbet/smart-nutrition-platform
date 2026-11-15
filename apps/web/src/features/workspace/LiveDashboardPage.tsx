import { useCallback } from 'react'
import { Link } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import { EmptyState } from '../../core/components/EmptyState'
import { getClients, getRelationships } from '../relationships/relationshipApi'
import { useWorkspaceRead, useWorkspaceSession } from './workspaceSession'

export function LiveDashboardPage() {
  const { dietitianId } = useWorkspaceSession()
  const load = useCallback(async (signal: AbortSignal) => {
    const [clients, requests] = await Promise.all([
      getClients(1, '', 'asc', signal), getRelationships('pending', 1, dietitianId, signal),
    ])
    return { clients, requests }
  }, [dietitianId])
  const state = useWorkspaceRead(load)
  return <>
    <div className="dashboard-heading"><div className="page-heading"><p className="eyebrow">ÇALIŞMA ALANINIZA HOŞ GELDİNİZ</p><h1 tabIndex={-1}>Genel bakış</h1><p>Danışanlarınız, bağlantılarınız ve bir sonraki adımınız.</p></div>
      <button className="button button-secondary" disabled={state.pending} onClick={state.refresh}><Icon name="clock" />Özeti yenile</button>
    </div>
    <section className="welcome-panel" aria-labelledby="live-welcome-title">
      <div><span className="welcome-kicker"><span />BİRLİKTE, ADIM ADIM</span><h2 id="live-welcome-title">İyi bir takip,<br />güçlü bir bağla başlar.</h2><p>Danışanlarınızın paylaştığı beslenme programlarını inceleyin ve birlikte planlayın.</p>
        <Link className="button button-welcome" to="/calisma-alani/danisanlar">Danışanlarımı görüntüle<Icon name="arrow" /></Link>
      </div>
      <div className="welcome-art" aria-hidden="true"><div className="welcome-ring ring-one" /><div className="welcome-ring ring-two" /><span className="welcome-leaf"><Icon name="leaf" /></span><span className="art-caption">her adımda, birlikte.</span></div>
    </section>
    {state.pending && <p className="panel-feedback" role="status">Çalışma alanı özeti okunuyor…</p>}
    {state.message && <p className="form-message error-message" role="alert">{state.message}</p>}
    <section className="metrics-grid live-metrics" aria-label="Çalışma alanı özeti">
      <article className="metric-card"><div className="metric-top"><h2>Aktif danışanlar</h2><span className="metric-icon green"><Icon name="users" /></span></div>
        <strong className="metric-value">{state.data?.clients.totalCount ?? '—'}</strong><p>Aktif bağlantı kurduğunuz danışanlar</p>
      </article>
      <article className="metric-card"><div className="metric-top"><h2>Bekleyen istekler</h2><span className="metric-icon amber"><Icon name="link" /></span></div>
        <strong className="metric-value">{state.data?.requests.totalCount ?? '—'}</strong><p>Yanıtınızı bekleyen bağlantı talepleri</p>
      </article>
    </section>
    <div className="dashboard-columns"><div className="dashboard-primary">
      <section className="card" aria-labelledby="live-clients-title"><header className="card-header"><div><h2 id="live-clients-title">Danışanlarım</h2><p>Ad sırasına göre ilk danışanlarınız.</p></div><Link className="text-link" to="/calisma-alani/danisanlar">Tümünü gör<Icon name="arrow" /></Link></header>
        {state.data && (state.data.clients.totalCount === 0
          ? <EmptyState icon="users" title="İlk danışanınızla bağlantı kurun">Bağlantılar bölümünden davet kodu oluşturabilir ve gelen talepleri yanıtlayabilirsiniz.</EmptyState>
          : <ul className="live-client-list">{state.data.clients.items.slice(0, 5).map(client => <li key={client.id}><Link className="live-client-row" to={`/calisma-alani/danisanlar/${client.id}`}>
            <span className="client-avatar" aria-hidden="true">{client.displayName.slice(0, 1).toLocaleUpperCase('tr-TR')}</span><span className="client-identity"><strong>{client.displayName}</strong><small>Beslenme programlarını incele</small></span><Icon name="arrow" />
          </Link></li>)}</ul>)}
      </section>
      <section className="request-strip"><span className="strip-icon"><Icon name="link" /></span><div><h2>Yeni bağlantılara yer açın</h2><p>Davet kodunuzu oluşturun, gelen talepleri yanıtlayın.</p></div><Link className="icon-button" to="/calisma-alani/baglantilar" aria-label="Bağlantıları ve daveti aç"><Icon name="arrow" /></Link></section>
    </div><aside className="dashboard-secondary" aria-label="Takip rehberi">
      <section className="card journey-card"><p className="eyebrow">BESLENME PROGRAMLARI</p><h2>Birlikte planlayın.</h2><p className="panel-description">Danışan detayından program oluşturabilir, kendi atadığınız programları düzenleyebilir ve sürüm geçmişini inceleyebilirsiniz.</p><Link className="text-link" to="/calisma-alani/danisanlar">Danışan seç<Icon name="arrow" /></Link></section>
      <section className="privacy-card"><Icon name="shield" /><h2>Paylaşım danışanın kontrolünde.</h2><p>Program erişimi için aktif bağlantı ve danışanın paylaşım izni gerekir.</p><span>İZNE DAYALI TAKİP</span></section>
    </aside></div>
  </>
}
