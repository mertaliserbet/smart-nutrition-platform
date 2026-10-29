import { useCallback, useEffect, useRef, useState } from 'react'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceSession, useWorkspaceRead } from '../workspace/workspaceSession'
import { changeRelationship, createInvitation, getRelationships } from './relationshipApi'
import type { InvitationCodeResponse, RelationshipStatus } from './relationshipApi'

const labels: Record<RelationshipStatus, string> = { pending: 'Bekleyen', active: 'Aktif', rejected: 'Reddedilen', ended: 'Sonlanan' }
export function ConnectionsPage() {
  const session = useWorkspaceSession()
  const [status, setStatus] = useState<RelationshipStatus>('pending'); const [page, setPage] = useState(1)
  const [invitation, setInvitation] = useState<InvitationCodeResponse>(); const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState(''); const [notice, setNotice] = useState('')
  const operation = useRef<AbortController | null>(null)
  const load = useCallback((signal: AbortSignal) => getRelationships(status, page, session.dietitianId, signal), [status, page, session.dietitianId])
  const state = useWorkspaceRead(load)
  useEffect(() => () => operation.current?.abort(), [])

  async function mutate(action: 'invite' | 'accept' | 'reject' | 'end', id?: string) {
    if (operation.current || state.pending) return
    const controller = new AbortController(); operation.current = controller; setBusy(true); setMessage(''); setNotice('')
    if (action === 'invite') setInvitation(undefined)
    try {
      if (action === 'invite') {
        const result = await createInvitation(session.token, controller.signal)
        if (!controller.signal.aborted) setInvitation(result)
      } else {
        await changeRelationship(id!, action, session.dietitianId, session.token, controller.signal)
        if (!controller.signal.aborted) { setNotice(action === 'accept' ? 'Bağlantı kabul edildi.' : action === 'reject' ? 'Talep reddedildi.' : 'Bağlantı sonlandırıldı.'); state.refresh() }
      }
    } catch (error) {
      if (!controller.signal.aborted && !session.onFailure(error)) setMessage(error instanceof WebSessionError ? error.message : 'İşlem doğrulanamadı.')
    } finally { if (!controller.signal.aborted) { operation.current = null; setBusy(false) } }
  }
  return <><div className="page-heading"><h1 tabIndex={-1}>Bağlantılar ve davet</h1><p>Danışan taleplerini karşılıklı onayla yönetin.</p></div>
    <section className="card"><h2>Davet kodu</h2><p>Kod, danışanın bağlantı talebi başlatmasını sağlar. Veri paylaşımı ayrıca danışanın kontrolündedir.</p>
      <button className="button button-secondary" disabled={busy || state.pending} onClick={() => { void mutate('invite') }}>{invitation ? 'Yeni kod oluştur' : 'Davet kodu oluştur'}</button>
      {invitation && <div className="form-message" role="status"><p>Davet kodunuz: <output>{invitation.invitationCode}</output></p><p>Son geçerlilik: <time dateTime={invitation.expiresAt}>{new Date(invitation.expiresAt).toLocaleString('tr-TR')}</time>. Bir kez kullanılabilir. Yeni kod eskisini geçersiz kılar.</p></div>}
    </section>
    {message && <p role="alert">{message}</p>}{notice && <p role="status">{notice}</p>}{busy && <p role="status">İşlem sürüyor…</p>}
    <section className="card"><header className="card-header"><h2>Danışan bağlantıları</h2><label>Durum<select disabled={busy || state.pending} value={status} onChange={event => { setStatus(event.target.value as RelationshipStatus); setPage(1); setNotice('') }}>{Object.entries(labels).map(([value, text]) => <option key={value} value={value}>{text}</option>)}</select></label></header>
      {state.pending && <p role="status">Bağlantılar okunuyor…</p>}{state.message && <p role="alert">{state.message}</p>}
      {state.data && <><p>{state.data.totalCount} bağlantı</p>{state.data.totalCount === 0 && <p>Bu durumda bağlantı bulunmuyor.</p>}
        <ul className="expert-review-list" aria-label="Danışan bağlantıları">{state.data.items.map(row => <li key={row.id}><h3>{labels[row.status]} bağlantı</h3><p>Danışan kimliği: {row.clientId}</p><p>Talep: <time dateTime={row.requestedAt}>{new Date(row.requestedAt).toLocaleString('tr-TR')}</time></p>
          {row.status === 'pending' && <div className="expert-pagination"><button className="button button-primary" disabled={busy || state.pending} onClick={() => { void mutate('accept', row.id) }}>Kabul et</button><button className="button button-secondary" disabled={busy || state.pending} onClick={() => { void mutate('reject', row.id) }}>Reddet</button></div>}
          {row.status === 'active' && <button className="button button-secondary" disabled={busy || state.pending} onClick={() => { void mutate('end', row.id) }}>Bağlantıyı sonlandır</button>}
        </li>)}</ul>
        <div className="expert-pagination"><button className="button button-secondary" disabled={busy || page <= 1} onClick={() => setPage(value => value - 1)}>Önceki sayfa</button><span>Sayfa {page}</span><button className="button button-secondary" disabled={busy || page * 10 >= state.data.totalCount} onClick={() => setPage(value => value + 1)}>Sonraki sayfa</button></div>
      </>}
      <button className="button button-secondary" disabled={busy || state.pending} onClick={state.refresh}>Bağlantıları yenile</button>
    </section>
  </>
}
