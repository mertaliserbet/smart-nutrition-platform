import { DateField } from '../../core/components/DateField'
import { useId, useState } from 'react'
import type { FormEvent } from 'react'
import { isDirtyDraft, taskContent } from './clientTaskForm'
import type { TaskDraft } from './clientTaskForm'
export function ClientTaskEditor({ draft, disabled, checking, conflicted, onChange, onClose, onSave, onRestart }: {
  draft: TaskDraft; disabled: boolean; checking: boolean; conflicted: boolean; onChange: (draft: TaskDraft) => void; onClose: () => void
  onSave: (content: { description: string; dueAt: string | null }) => void; onRestart: () => void
}) {
  const id = useId(); const [error, setError] = useState(''); const [discard, setDiscard] = useState(false)
  function submit(event: FormEvent) { event.preventDefault(); if (disabled || checking || conflicted) return; try { const content = taskContent(draft); setError(''); onSave(content) } catch (error) { setError((error as Error).message) } }
  return <form className="task-editor" onSubmit={submit} aria-label={draft.original ? 'Görevi düzenle' : 'Yeni görev atama'}>
    <h3>{draft.original ? 'Görevi düzenle' : 'Yeni görev ata'}</h3>
    <fieldset disabled={disabled}>
      <label htmlFor={`${id}-description`}>Görev açıklaması</label>
      <textarea id={`${id}-description`} rows={4} value={draft.description} onChange={event => { onChange({ ...draft, description: event.target.value }); setDiscard(false) }} required aria-describedby={`${id}-length`} />
      <p id={`${id}-length`} className="task-help">{[...draft.description].length} / 2000 karakter</p>
      <label htmlFor={`${id}-due`}>Son tarih ve saat (isteğe bağlı)</label>
      <DateField id={`${id}-due`} type="datetime-local" step="1" value={draft.dueInput} onChange={event => { onChange({ ...draft, dueInput: event.target.value }); setDiscard(false) }} aria-describedby={`${id}-zone`} />
      <p id={`${id}-zone`} className="task-help">Saat dilimi: {Intl.DateTimeFormat().resolvedOptions().timeZone}. Seçtiğiniz yerel saat kaydedilir. Son tarih olmadan da görev atayabilirsiniz.</p>
      {error && <p role="alert" className="error-message">{error}</p>}
      {conflicted && <p role="alert">Görevin güncel durumu değişti. Yazdıklarınız kaydedilmedi; güncel görevi inceleyin.</p>}
      <div className="task-actions"><button className="button button-primary" type="submit" disabled={conflicted || checking}>{draft.original ? 'Değişiklikleri kaydet' : 'Görevi oluştur ve ata'}</button>
        <button className="button button-secondary" type="button" onClick={() => isDirtyDraft(draft) ? setDiscard(true) : onClose()}>Düzenlemeyi kapat</button>
        {conflicted && <button className="button button-secondary" type="button" onClick={onRestart}>Taslağı silip güncel sürüme dön</button>}
      </div>
      {discard && <div className="task-confirm" role="group" aria-label="Kaydedilmemiş değişiklikler"><p>Kaydedilmemiş değişiklikler silinsin mi?</p>
        <button className="button button-secondary" type="button" onClick={onClose}>Değişiklikleri sil</button><button className="button button-secondary" type="button" onClick={() => setDiscard(false)}>Düzenlemeye dön</button></div>}
    </fieldset>
  </form>
}
