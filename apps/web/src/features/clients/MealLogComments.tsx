import { useCallback, useEffect, useId, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { createMealLogComment, getMealLogComments, validCommentText } from './mealLogCommentApi'

export function MealLogComments({ mealLogId, onAccessDenied }: { mealLogId: string; onAccessDenied: (error: WebSessionError) => void }) {
  const session = useWorkspaceSession()
  return <CommentSection key={`${session.dietitianId}:${session.token}:${mealLogId}`} mealLogId={mealLogId} onAccessDenied={onAccessDenied} />
}
function CommentSection({ mealLogId, onAccessDenied }: { mealLogId: string; onAccessDenied: (error: WebSessionError) => void }) {
  const [open, setOpen] = useState(false)
  const id = useId()
  return <div className="meal-comments">
    <button className="button button-secondary" aria-expanded={open} aria-controls={id} onClick={() => setOpen(value => !value)}>Yorumlar ve yanıtlar</button>
    {open && <div id={id}><CommentContent mealLogId={mealLogId} onAccessDenied={onAccessDenied} /></div>}
  </div>
}
function CommentContent({ mealLogId, onAccessDenied }: { mealLogId: string; onAccessDenied: (error: WebSessionError) => void }) {
  const session = useWorkspaceSession()
  const [page, setPage] = useState(1)
  const [text, setText] = useState('')
  const [writing, setWriting] = useState(false)
  const [locked, setLocked] = useState(false)
  const [writeError, setWriteError] = useState('')
  const [notice, setNotice] = useState('')
  const writeController = useRef<AbortController | null>(null)
  const load = useCallback(async (signal: AbortSignal) => {
    if (document.visibilityState !== 'visible') return undefined
    try { return await getMealLogComments(mealLogId, page, signal) }
    catch (error) { if (error instanceof WebSessionError && [403, 404].includes(error.status)) onAccessDenied(error); throw error }
  }, [mealLogId, page, onAccessDenied])
  const state = useWorkspaceRead(load)
  const latest = useRef({ refresh: state.refresh, writing })
  useEffect(() => { latest.current = { refresh: state.refresh, writing } }, [state.refresh, writing])
  useEffect(() => {
    const recheck = () => { if (document.visibilityState === 'visible' && !latest.current.writing) latest.current.refresh() }
    const visibility = () => {
      if (document.visibilityState !== 'visible') { setText(''); setNotice(''); latest.current.refresh() }
      else recheck()
    }
    const timer = window.setInterval(recheck, 30_000)
    window.addEventListener('focus', recheck); document.addEventListener('visibilitychange', visibility)
    return () => { window.clearInterval(timer); window.removeEventListener('focus', recheck); document.removeEventListener('visibilitychange', visibility); writeController.current?.abort() }
  }, [])
  function refresh() {
    if (locked) { setText(''); setLocked(false); setWriteError('') }
    state.refresh()
  }
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (writing || locked || state.pending || !state.data) return
    if (!validCommentText(text)) { setWriteError('Yorum boş olamaz ve en fazla 2000 karakter içerebilir.'); return }
    const controller = new AbortController(); writeController.current = controller
    setWriting(true); setWriteError(''); setNotice('')
    try {
      await createMealLogComment(mealLogId, text, session.token, controller.signal)
      if (controller.signal.aborted) return
      setText(''); setNotice('Yorum kaydedildi.')
      setPage(Math.max(1, Math.ceil((state.data.totalCount + 1) / 10)))
      state.refresh()
    } catch (error) {
      if (controller.signal.aborted) return
      const failure = error instanceof WebSessionError ? error : new WebSessionError(0, 'Gönderim sonucu doğrulanamadı. Yorumları yenileyip kontrol edin.')
      setWriteError(failure.message)
      if ([403, 404].includes(failure.status)) onAccessDenied(failure)
      else if (failure.status === 401) { session.onFailure(failure); setLocked(true); state.refresh() }
      else if (![400, 422].includes(failure.status)) { setLocked(true); state.refresh() }
    } finally { if (!controller.signal.aborted) setWriting(false) }
  }
  const ready = state.data && !state.pending && !writing
  const fieldId = useId()
  return <section aria-label="Öğün yorumları">
    <h4>Yorumlar ve danışan yanıtları</h4>
    {(state.pending || writing) && <p role="status">{writing ? 'Yorum gönderiliyor…' : 'Yorumlar okunuyor…'}</p>}
    {state.message && <p role="alert">{state.message}</p>}
    {writeError && <p role="alert">{writeError}</p>}
    {notice && <p role="status">{notice}</p>}
    {ready && <>
      {state.data!.items.length === 0 && <p>{state.data!.totalCount > 0 ? 'Bu sayfada yorum kalmadı. Önceki sayfaya dönebilirsiniz.' : 'Henüz yorum veya yanıt yok.'}</p>}
      <ol className="meal-comment-list" aria-label="Yorum geçmişi">{state.data!.items.map(item => {
        const parent = state.data!.items.find(row => row.id === item.parentCommentId)
        return <li key={item.id} className={item.parentCommentId ? 'meal-comment-reply' : ''}>
          <strong>{item.parentCommentId ? 'Danışan yanıtı' : 'Diyetisyen yorumu'}</strong>
          <time dateTime={item.createdAt}>{new Date(item.createdAt).toLocaleString('tr-TR')}</time>
          {item.parentCommentId && (parent ? <blockquote>{parent.text}</blockquote> : <p className="meal-comment-context">İlgili yorum başka bir sayfada.</p>)}
          <p className="meal-comment-text">{item.text}</p>
        </li>
      })}</ol>
      <div className="meal-comment-pagination">
        <button className="button button-secondary" disabled={page <= 1} onClick={() => setPage(value => value - 1)}>Önceki yorum sayfası</button>
        <span>{state.data!.totalCount} yorum/yanıt · Sayfa {page}</span>
        <button className="button button-secondary" disabled={page * 10 >= state.data!.totalCount} onClick={() => setPage(value => value + 1)}>Sonraki yorum sayfası</button>
      </div>
    </>}
    <form onSubmit={submit} aria-label="Diyetisyen yorumu yaz">
      <label htmlFor={fieldId}>Öğüne yorumunuz</label>
      <textarea id={fieldId} rows={3} value={text} disabled={!ready || locked} onChange={event => { setText(event.target.value); setWriteError(''); setNotice('') }} aria-describedby={`${fieldId}-count`} />
      <p id={`${fieldId}-count`}>{[...text.trim()].length}/2000 karakter</p>
      <button className="button button-primary" disabled={!ready || locked} type="submit">Yorum gönder</button>
    </form>
    <button className="button button-secondary" disabled={writing || state.pending} onClick={refresh}>Yorumları yenile</button>
  </section>
}
