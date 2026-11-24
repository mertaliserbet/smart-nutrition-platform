import { useCallback, useState } from 'react'
import { Link } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import { EmptyState } from '../../core/components/EmptyState'
import { MealLogPanel } from '../clients/MealLogPanel'
import { ReportsOverview } from './ReportsOverview'
import { NutritionPlanPanel } from '../nutritionPlans/NutritionPlanPanel'
import { PlanConfirmation } from '../nutritionPlans/PlanConfirmation'
import { getClients } from '../relationships/relationshipApi'
import { useWorkspaceRead } from './workspaceSession'

const content = {
  meals: { title: 'Öğün incelemeleri', description: 'Besinleri ve porsiyonları inceleyerek danışanınıza geri bildirim verin.', section: 'ogunler' },
  plans: { title: 'Programlar', description: 'Beslenme programlarını hazırlayın, danışanınıza uyarlayarak atayın.', section: 'program' },
  reports: { title: 'Raporlar', description: 'Danışanların paylaştığı ölçümleri ve su kayıtlarını dönemlere göre inceleyin.', section: 'olcum-su' },
} as const

export function ClientFeaturePage({ feature }: { feature: keyof typeof content }) {
  const [page, setPage] = useState(1)
  const [input, setInput] = useState('')
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState('')
  const [dirty, setDirty] = useState(false)
  const [busy, setBusy] = useState(false)
  const [transition, setTransition] = useState<{ run: () => void }>()
  function changeClient(run: () => void) {
    if (busy) return
    if (dirty) setTransition({ run })
    else run()
  }
  const load = useCallback((signal: AbortSignal) => getClients(page, query, 'asc', signal), [page, query])
  const state = useWorkspaceRead(load)
  const client = state.data?.items.find(item => item.id === selected) ?? state.data?.items[0]
  const copy = content[feature]
  return <div className={`reference-feature reference-${feature}`}>
    <div className="dashboard-heading"><div className="page-heading"><h1 tabIndex={-1}>{copy.title}</h1><p>{copy.description}</p></div>
      {feature === 'meals' && <Link className="button button-primary" to="/calisma-alani/baglantilar"><Icon name="plus" />Danışan ekle</Link>}</div>
    {feature === 'meals' && <div className="meal-review-status"><span>Tüm öğünler</span><span>Yorumlarla geri bildirim</span></div>}
    <div className="feature-client-toolbar">
      <details className="feature-search-disclosure"><summary aria-label="Danışan arama seçenekleri"><Icon name="search" /></summary><form onSubmit={event => { event.preventDefault(); changeClient(() => { setPage(1); setQuery(input.trim()); setSelected('') }) }} aria-label="Bölümde danışan ara">
        <label className="search-field"><Icon name="search" /><span className="sr-only">Danışan ara</span><input type="search" value={input} placeholder="Danışan adıyla ara" onChange={event => setInput(event.target.value)} /></label>
        <button className="button button-secondary" disabled={state.pending || busy}>Ara</button>
      </form></details>
      {state.data && state.data.items.length > 0 && <label className="feature-client-select"><Icon name="users" /><span className="sr-only">Danışan seç</span><select value={client?.id ?? ''} disabled={busy} onChange={event => { const id = event.target.value; changeClient(() => setSelected(id)) }}>{state.data.items.map(item => <option key={item.id} value={item.id}>{item.displayName}</option>)}</select></label>}
      {client && <Link className="text-link" to={`/calisma-alani/danisanlar/${client.id}?bolum=${copy.section}`}>Danışan profilini aç<Icon name="arrow" /></Link>}
    </div>
    {state.pending && <p className="form-message" role="status">Danışanlar okunuyor…</p>}
    {state.message && <div className="form-message error-message" role="alert"><p>{state.message}</p><button className="button button-secondary" onClick={state.refresh}>Yeniden dene</button></div>}
    {state.data && state.data.totalCount === 0 && <section className="card"><EmptyState icon="users" title={query ? 'Aramanıza uygun danışan bulunamadı' : 'Henüz aktif danışanınız yok'}>{query ? 'Başka bir adla arayın veya aramayı temizleyin.' : 'Bağlantılar bölümünden davet kodu oluşturabilir ve gelen talepleri yanıtlayabilirsiniz.'}</EmptyState>{query && <button className="button button-secondary" onClick={() => { setInput(''); setQuery(''); setPage(1) }}>Aramayı temizle</button>}</section>}
    {state.data && state.data.totalCount > 10 && <nav className="feature-client-pages" aria-label="Danışan seçim sayfaları"><button className="button button-secondary" disabled={page === 1 || busy} onClick={() => changeClient(() => setPage(value => value - 1))}>Önceki danışanlar</button><span>Sayfa {page}</span><button className="button button-secondary" disabled={page * 10 >= state.data.totalCount || busy} onClick={() => changeClient(() => setPage(value => value + 1))}>Sonraki danışanlar</button></nav>}
    {client && <div key={`${feature}:${client.id}`} className="feature-client-content"><div className="feature-client-caption"><span className="client-avatar" aria-hidden="true">{client.displayName.trim().slice(0, 1)}</span><strong>{client.displayName}</strong><span className="access-badge"><Icon name="check" />Aktif bağlantı</span></div>
      {feature === 'meals' && <MealLogPanel compact clientId={client.id} clientName={client.displayName} />}
      {feature === 'plans' && <NutritionPlanPanel compact clientId={client.id} clientName={client.displayName} onDirtyChange={setDirty} onBusyChange={setBusy} />}
      {feature === 'reports' && <ReportsOverview clientId={client.id} clientName={client.displayName} totalClients={state.data!.totalCount} />}
    </div>}
    {transition && <PlanConfirmation title="Danışanı değiştir" confirmLabel="Değişiklikleri sil ve devam et" onCancel={() => setTransition(undefined)} onConfirm={() => { const run = transition.run; setTransition(undefined); setDirty(false); run() }}><p>Kaydedilmemiş program değişiklikleri var. Danışanı veya listeyi değiştirdiğinizde bu taslak silinecek.</p></PlanConfirmation>}
  </div>
}
