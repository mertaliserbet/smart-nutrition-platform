import { useCallback, useEffect, useRef, useState } from 'react'
import { EmptyState } from '../../core/components/EmptyState'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { cancelClientTask, getClientTask, getClientTasks, getClientTaskVersions, isOpenTask, saveClientTask, taskStatusLabels } from './clientTaskApi'
import type { ClientTaskResponse } from './clientTaskApi'
import { ClientTaskEditor } from './ClientTaskEditor'
import { taskDraft } from './clientTaskForm'
import type { TaskDraft } from './clientTaskForm'
import { ClientTaskDetails, TaskTime } from './ClientTaskDetails'
import './clientTasks.css'

export function ClientTaskPanel({ clientId }: { clientId: string }) {
  const session = useWorkspaceSession()
  return <ClientTaskContent key={`${session.dietitianId}:${session.token}:${clientId}`} clientId={clientId} />
}
function ClientTaskContent({ clientId }: { clientId: string }) {
  const session = useWorkspaceSession()
  const [page, setPage] = useState(1); const [selected, setSelected] = useState<string>(); const [historyPage, setHistoryPage] = useState(1)
  const [draft, setDraft] = useState<TaskDraft>(); const [cancelVersion, setCancelVersion] = useState<number>()
  const [busy, setBusy] = useState(false); const [message, setMessage] = useState(''); const [notice, setNotice] = useState(''); const [denied, setDenied] = useState('')
  const [conflict, setConflict] = useState(false); const [uncertain, setUncertain] = useState(false)
  const operation = useRef<AbortController | null>(null)
  const handleDenied = useCallback((error: unknown) => {
    if (error instanceof WebSessionError && [403, 404].includes(error.status)) {
      operation.current?.abort(); operation.current = null
      setBusy(false); setDenied(error.message); setDraft(undefined); setSelected(undefined); setCancelVersion(undefined); setMessage(''); setNotice(''); return true
    }
    return false
  }, [])
  const load = useCallback(async (signal: AbortSignal) => {
    if (document.visibilityState !== 'visible') return { kind: 'hidden' as const }
    const list = await getClientTasks(clientId, session.dietitianId, page, signal)
    const detail = selected ? await getClientTask(clientId, session.dietitianId, selected, signal) : undefined
    const versions = detail ? await getClientTaskVersions(detail, historyPage, signal) : undefined
    return { kind: 'ready' as const, list, detail, versions }
  }, [clientId, session.dietitianId, page, selected, historyPage])
  const state = useWorkspaceRead(load, handleDenied)
  const recheck = useRef({ refresh: state.refresh, revalidate: state.revalidate, denied })
  useEffect(() => { recheck.current = { refresh: state.refresh, revalidate: state.revalidate, denied } }, [state.refresh, state.revalidate, denied])
  useEffect(() => {
    const refreshVisible = () => { if (document.visibilityState === 'visible' && !operation.current && !recheck.current.denied) recheck.current.revalidate() }
    const visibility = () => {
      if (document.visibilityState !== 'visible') {
        setDraft(undefined); setSelected(undefined); setCancelVersion(undefined); setNotice('')
        if (operation.current) {
          operation.current.abort(); operation.current = null; setBusy(false); setUncertain(true)
          setMessage('Görev işleminin sonucu doğrulanamadı. Yeniden göndermeden önce görevleri kontrol edin.')
        }
        recheck.current.refresh()
      } else refreshVisible()
    }
    const timer = window.setInterval(refreshVisible, 30_000)
    window.addEventListener('focus', refreshVisible); document.addEventListener('visibilitychange', visibility)
    return () => { window.clearInterval(timer); window.removeEventListener('focus', refreshVisible); document.removeEventListener('visibilitychange', visibility); operation.current?.abort(); operation.current = null }
  }, [])
  const data = !denied && state.data?.kind === 'ready' ? state.data : undefined
  const current = data?.detail
  const conflicted = conflict || !!draft?.original && !!current && draft.original.versionNumber !== current.versionNumber
  const disabled = busy || state.pending || uncertain
  function refresh() { if (operation.current) return; setDenied(''); setMessage(''); setNotice(''); setUncertain(false); setCancelVersion(undefined); state.refresh() }
  async function mutate(content?: { description: string; dueAt: string | null }, cancel?: ClientTaskResponse) {
    if (operation.current || !data || state.pending || denied || uncertain || !cancel && conflicted) return
    const controller = new AbortController(); operation.current = controller; setBusy(true); setMessage(''); setNotice('')
    try {
      const result = cancel ? await cancelClientTask(cancel, session.token, controller.signal)
        : await saveClientTask(clientId, session.dietitianId, content!, session.token, controller.signal, draft?.original)
      if (!controller.signal.aborted) {
        setNotice(cancel ? 'Görev iptal edildi.' : draft?.original ? 'Görev değişiklikleri kaydedildi.' : 'Görev oluşturuldu ve danışana atandı.')
        setDraft(undefined); setSelected(result.id); setHistoryPage(1); setPage(1); setCancelVersion(undefined); setConflict(false); state.refresh()
      }
    } catch (error) {
      if (!controller.signal.aborted && !handleDenied(error) && !session.onFailure(error)) {
        setMessage(error instanceof WebSessionError ? error.message : 'Görev işlemi doğrulanamadı.')
        if (error instanceof WebSessionError && error.status === 409) { setConflict(true); setCancelVersion(undefined); state.refresh() }
        else if (!(error instanceof WebSessionError) || error.status === 0 || error.status >= 500) setUncertain(true)
      }
    } finally { if (!controller.signal.aborted) { operation.current = null; setBusy(false) } }
  }
  return <section className="card client-task-panel" aria-label="Danışan görevleri">
    <header className="card-header"><div><p className="eyebrow">GÖREV ATAMA VE TAKİP</p><h2>Danışan görevleri</h2><p>Açık görevleri yönetin, danışanın ilerlemesini takip edin.</p></div><span className="neutral-badge">{data ? `${data.list.totalCount} görev` : 'Görev paylaşımı'}</span></header>
    <div className="task-actions task-toolbar"><button className="button button-secondary" disabled={busy || state.pending} onClick={refresh}>Görevleri yenile</button>
      {data && <button className="button button-primary" disabled={disabled || !!draft} onClick={() => { setDraft(taskDraft()); setCancelVersion(undefined); setConflict(false); setMessage(''); setNotice('') }}>Yeni görev ata</button>}
    </div>
    {state.pending && <p role="status" className="panel-feedback">Görevler kontrol ediliyor…</p>}
    {denied && <p role="alert" className="panel-feedback">{denied} Danışanın bağımsız görev paylaşım izni gerekir.</p>}
    {state.message && <p role="alert" className="panel-feedback error-message">{state.message}</p>}
    {data && <>
      {message && <p role="alert" className="panel-feedback error-message">{message}</p>}{notice && <p role="status" className="panel-feedback">{notice}</p>}
      {draft && <ClientTaskEditor draft={draft} disabled={busy || uncertain} checking={state.pending} conflicted={conflicted} onChange={setDraft} onClose={() => { setDraft(undefined); setConflict(false); setMessage('') }}
        onSave={content => { void mutate(content) }} onRestart={() => { setDraft(current && isOpenTask(current) ? taskDraft(current) : undefined); setConflict(false); setMessage('') }} />}
      <div className={`task-layout${current ? ' task-with-detail' : ''}`}><div>
        {data.list.items.length === 0 ? <EmptyState icon="check" title={data.list.totalCount ? 'Bu sayfada görev yok' : 'Henüz atanmış görev yok'}>Yeni bir görev atayabilir veya görev listesini yenileyebilirsiniz.</EmptyState>
          : <ul className="task-list" aria-label="Atanan görevler">{data.list.items.map(task => <li key={task.id} className={task.id === selected ? 'task-selected' : ''}>
            <span className={`task-status task-${task.status}`}>{taskStatusLabels[task.status]}</span><p className="task-description">{task.description}</p>
            <p className="task-help">Son tarih: <TaskTime value={task.dueAt} /></p>
            {task.status === 'completed' && <p className="task-help">Danışan tamamladı · <TaskTime value={task.updatedAt} /></p>}
            <button className="text-link" disabled={disabled || !!draft} onClick={() => { setSelected(task.id); setHistoryPage(1); setCancelVersion(undefined); setConflict(false); setMessage(''); setNotice('') }}>Görev detayını aç<span className="sr-only">: {task.description}</span></button>
          </li>)}</ul>}
        <div className="task-actions task-pagination"><button className="button button-secondary" disabled={disabled || !!draft || page <= 1} onClick={() => { setPage(value => value - 1); setSelected(undefined) }}>Önceki görev sayfası</button>
          <span>{data.list.totalCount} görev · Sayfa {page}</span><button className="button button-secondary" disabled={disabled || !!draft || page * 10 >= data.list.totalCount} onClick={() => { setPage(value => value + 1); setSelected(undefined) }}>Sonraki görev sayfası</button></div>
      </div>
        {current && data.versions && <ClientTaskDetails task={current} versions={data.versions} page={historyPage} disabled={disabled} editing={!!draft}
          confirmation={cancelVersion === current.versionNumber} onPage={setHistoryPage}
          onEdit={() => { setDraft(taskDraft(current)); setCancelVersion(undefined); setConflict(false); setMessage(''); setNotice('') }}
          onCancel={() => setCancelVersion(current.versionNumber)} onDismissCancel={() => setCancelVersion(undefined)} onConfirmCancel={() => { void mutate(undefined, current) }} />}
      </div>
    </>}
  </section>
}
