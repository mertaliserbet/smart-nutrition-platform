import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { NutritionPlanPanel } from '../nutritionPlans/NutritionPlanPanel'
import { ClientTaskPanel } from '../clientTasks/ClientTaskPanel'
import { MealLogPanel } from '../clients/MealLogPanel'
import { BodyMeasurementPanel } from '../clients/BodyMeasurementPanel'
import { WaterLogPanel } from '../clients/WaterLogPanel'
import { getClientDashboard } from './relationshipApi'
import type { ClientDashboardResponse } from './relationshipApi'

const sections = { ozet: 'Özet', program: 'Program', ogunler: 'Öğünler', gorevler: 'Görevler', 'olcum-su': 'Ölçüm ve Su' } as const
type Section = keyof typeof sections

export function LiveClientDetailsPage() {
  const { clientId = '' } = useParams()
  const { dietitianId, token } = useWorkspaceSession()
  return <ClientDetails key={`${dietitianId}:${token}:${clientId}`} clientId={clientId} />
}

function ClientDetails({ clientId }: { clientId: string }) {
  const load = useCallback((signal: AbortSignal) => document.visibilityState === 'visible'
    ? getClientDashboard(clientId, signal) : Promise.resolve(undefined), [clientId])
  const state = useWorkspaceRead<ClientDashboardResponse | undefined>(load)
  const { refresh, revalidate } = state
  useEffect(() => {
    const visible = () => { if (document.visibilityState === 'visible') revalidate() }
    const visibility = () => { if (document.visibilityState === 'visible') revalidate(); else refresh() }
    const timer = window.setInterval(visible, 30_000)
    window.addEventListener('focus', visible); document.addEventListener('visibilitychange', visibility)
    return () => { window.clearInterval(timer); window.removeEventListener('focus', visible); document.removeEventListener('visibilitychange', visibility) }
  }, [refresh, revalidate])
  return <>
    <Link className="text-link back-link" to="/calisma-alani/danisanlar"><Icon name="back" />Danışan listesine dön</Link>
    <div className="client-detail-banner"><span className="client-avatar large-avatar" aria-hidden="true">{state.data?.displayName.trim().split(/\s+/).slice(0, 2).map(part => Array.from(part)[0]).join('').toLocaleUpperCase('tr-TR') || <Icon name="users" />}</span><div className="page-heading"><p className="eyebrow">DANIŞAN TAKİBİ</p><h1 tabIndex={-1}>{state.data?.displayName ?? 'Danışan detayı'}</h1><p>Beslenme programları, görevler ve paylaşılan günlük kayıtlar.</p></div>{state.data && <span className="access-badge"><Icon name="check" />Aktif bağlantı</span>}</div>
    {state.pending && <p role="status">Danışan bağlantısı kontrol ediliyor…</p>}
    {state.message && <p role="alert">{state.message}</p>}
    {state.data && <ClientSections client={state.data} />}
    {!state.data && !state.pending && <button className="button button-secondary" onClick={refresh}>Danışanı yeniden kontrol et</button>}
  </>
}

function ClientSections({ client }: { client: ClientDashboardResponse }) {
  const [params] = useSearchParams()
  const navigate = useNavigate()
  const requested = params.get('bolum') ?? 'ozet'
  const section: Section = Object.hasOwn(sections, requested) ? requested as Section : 'ozet'
  // Editors are loaded on first visit and remain mounted within this client only.
  // Native history navigation therefore preserves drafts without storing health data.
  const [opened, setOpened] = useState({ program: section === 'program', gorevler: section === 'gorevler' })
  if ((section === 'program' || section === 'gorevler') && !opened[section]) setOpened({ ...opened, [section]: true })
  const heading = useRef<HTMLHeadingElement>(null)
  useEffect(() => {
    heading.current?.focus({ preventScroll: true })
  }, [section])
  function target(value: Section) {
    const next = new URLSearchParams(params)
    next.set('bolum', value)
    return `?${next}`
  }
  return <>
    <nav className="client-section-navigation" aria-label="Danışan bölümleri">
      {Object.entries(sections).map(([value, label]) => <Link key={value} to={target(value as Section)} aria-current={section === value ? 'page' : undefined}>{label}</Link>)}
    </nav>
    <h2 ref={heading} tabIndex={-1} className="client-section-heading">{sections[section]}</h2>
    {section === 'ozet' && <section className="card client-profile-card" aria-label="Danışan özeti">
      <span className="client-avatar large-avatar" aria-hidden="true">{client.displayName.slice(0, 1).toLocaleUpperCase('tr-TR')}</span>
      <div><h3>Aktif danışan bağlantısı</h3><p>Her kayıt türü danışanın bağımsız paylaşım izniyle açılır.</p><p>Program ve görev taslaklarınız bu danışanın bölümleri arasında geçiş yaparken korunur.</p></div>
      <span className="access-badge">Aktif bağlantı</span>
    </section>}
    {section === 'ozet' && <div className="client-overview-grid">{([
      ['program', 'plan', 'Beslenme programı', 'Program hazırlayın, düzenleyin ve sürüm geçmişini inceleyin.'],
      ['ogunler', 'meal', 'Öğün incelemeleri', 'Paylaşılan tüketim kayıtlarını açın ve geri bildirim bırakın.'],
      ['gorevler', 'check', 'Danışan görevleri', 'Görev atayın, son tarihleri ve tamamlanma durumunu takip edin.'],
      ['olcum-su', 'chart', 'Ölçüm ve su', 'İzinli ölçümleri, grafikleri ve su kayıtlarını inceleyin.'],
    ] as const).map(([value, icon, title, description]) => <Link className="card client-overview-link" key={value} to={target(value)}><span className="strip-icon"><Icon name={icon} /></span><h3>{title}</h3><p>{description}</p><span className="text-link">Bölümü aç<Icon name="arrow" /></span></Link>)}</div>}
    {(opened.program || section === 'program') && <div hidden={section !== 'program'} inert={section !== 'program'}><NutritionPlanPanel clientId={client.clientId} clientName={client.displayName} active={section === 'program'} onReturnToEditor={() => { if (section !== 'program') navigate(target('program')) }} /></div>}
    {(opened.gorevler || section === 'gorevler') && <div hidden={section !== 'gorevler'} inert={section !== 'gorevler'}><ClientTaskPanel clientId={client.clientId} /></div>}
    {section === 'ogunler' && <MealLogPanel clientId={client.clientId} />}
    {section === 'olcum-su' && <><BodyMeasurementPanel clientId={client.clientId} /><WaterLogPanel clientId={client.clientId} /></>}
  </>
}
