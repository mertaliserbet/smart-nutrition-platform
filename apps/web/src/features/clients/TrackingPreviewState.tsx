import type { ReactNode } from 'react'
import { EmptyState } from '../../core/components/EmptyState'
import { Icon } from '../../core/components/Icon'

// UI scenarios only, not server status values or sharing category codes.
const scenarios = {
  sample: 'Örnek kayıtlar',
  disconnected: 'Veri bağlı değil',
  empty: 'Boş liste',
  restricted: 'Paylaşım kapalı',
  loading: 'Yükleniyor',
  error: 'Bağlantı hatası',
} as const
export type TrackingPreviewScenario = keyof typeof scenarios

export function TrackingPreviewControl({ scenario, onChange }: {
  scenario: TrackingPreviewScenario; onChange: (scenario: TrackingPreviewScenario) => void
}) {
  return (
    <div className="tracking-preview-control">
      <div><span className="preview-badge">Sentetik önizleme</span><p>Bu alandaki kişiler ve kayıtlar örnektir. İşlem veya gerçek veri erişimi yapılmaz.</p></div>
      <label>Önizleme senaryosu<select value={scenario} onChange={(event) => onChange(event.target.value as TrackingPreviewScenario)}>
        {Object.entries(scenarios).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
      </select></label>
    </div>
  )
}

export function TrackingPreviewState({ scenario, scope, onShowSample, children }: {
  scenario: TrackingPreviewScenario; scope: 'list' | 'records'; onShowSample: () => void; children: ReactNode
}) {
  if (scenario === 'sample') return children
  if (scenario === 'loading') return <div className="tracking-loading" role="status"><p>Kayıtlar yükleniyor… <span>Önizleme senaryosu</span></p><div aria-hidden="true" className="tracking-skeleton"><span /><span /><span /></div></div>
  if (scenario === 'error') return <div role="alert"><EmptyState icon="info" title="Kayıtlar görüntülenemedi" action={<button className="button button-secondary" onClick={onShowSample}>Örnek görünümüne dön<Icon name="arrow" /></button>}>Bağlantı hatası görünümünü inceliyorsunuz. Bu önizlemede ağ isteği yapılmaz.</EmptyState></div>
  if (scenario === 'restricted') return <EmptyState icon="shield" title={scope === 'list' ? 'Danışan listesine erişilemiyor' : 'Bu kayıtlar paylaşılmıyor'}>Bu görünümde erişim kapalıdır. Kayıt değerleri, sayıları ve özetleri gösterilmez. Gerçek erişim her işlemde sunucuda kontrol edilmelidir.</EmptyState>
  if (scenario === 'disconnected') return <EmptyState icon="link" title="Veri bağlantısı bekleniyor">Hesap ve kayıtlar bağlı değil. Veri alınmadan listenin boş olduğu veya değerlerin sıfır olduğu varsayılmaz.</EmptyState>
  return <EmptyState icon={scope === 'list' ? 'users' : 'plan'} title={scope === 'list' ? 'Henüz danışan bulunmuyor' : 'Henüz kayıt bulunmuyor'}>Boş liste senaryosunu inceliyorsunuz. Bu durum, erişimin kapalı olmasından veya verinin henüz alınmamasından farklıdır.</EmptyState>
}
