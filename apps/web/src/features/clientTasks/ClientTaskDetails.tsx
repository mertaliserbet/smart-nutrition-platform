import type { PagedResponse } from '../relationships/relationshipApi'
import type { ClientTaskResponse, ClientTaskVersionResponse } from './clientTaskApi'
import { isOpenTask, taskStatusLabels } from './clientTaskApi'

export function TaskTime({ value }: { value: string | null }) {
  return value ? <time dateTime={value}>{new Date(value).toLocaleString('tr-TR', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit', timeZoneName: 'short' })}</time> : <>Belirtilmedi</>
}
export function ClientTaskDetails({ task, versions, page, disabled, editing, confirmation, onPage, onEdit, onCancel, onConfirmCancel, onDismissCancel }: {
  task: ClientTaskResponse; versions: PagedResponse<ClientTaskVersionResponse>; page: number; disabled: boolean; editing: boolean; confirmation: boolean
  onPage: (page: number) => void; onEdit: () => void; onCancel: () => void; onConfirmCancel: () => void; onDismissCancel: () => void
}) {
  return <section className="task-detail" aria-label="Görev detayı">
    <header className="card-header"><h3>Görev detayı</h3><span className={`task-status task-${task.status}`}>{taskStatusLabels[task.status]}</span></header>
    <p className="task-description">{task.description}</p>
    <dl className="task-metadata"><dt>Son tarih</dt><dd><TaskTime value={task.dueAt} /></dd>
      <dt>Atanma zamanı</dt><dd><TaskTime value={task.createdAt} /></dd>
      <dt>Son değişiklik</dt><dd><TaskTime value={task.updatedAt} /></dd>
      {task.status === 'completed' && <><dt>Danışanın tamamlama zamanı</dt><dd><TaskTime value={task.updatedAt} /></dd></>}
      <dt>Hatırlatma tercihi</dt><dd>{task.isReminderEnabled ? 'Danışan tarafından açıldı' : 'Kapalı'}</dd>
    </dl>
    <p className="task-help">Hatırlatma tercihini danışan yönetir. Bildirim teslimi henüz desteklenmiyor.</p>
    {isOpenTask(task) ? <div className="task-actions"><button className="button button-secondary" disabled={disabled || editing} onClick={onEdit}>Görevi düzenle</button><button className="button button-secondary" disabled={disabled || editing} onClick={onCancel}>Görevi iptal et</button></div>
      : <p className="task-help">{task.status === 'completed' ? 'Danışan görevi tamamladı.' : 'Görev iptal edildi.'} Kapanmış görevler yeniden düzenlenemez.</p>}
    {confirmation && <div role="group" aria-label="Görev iptali onayı" className="task-confirm"><p>Bu görev iptal edilsin mi?</p><div className="task-actions"><button className="button button-primary" disabled={disabled} onClick={onConfirmCancel}>İptali onayla</button><button className="button button-secondary" disabled={disabled} onClick={onDismissCancel}>Vazgeç</button></div></div>}
    <section className="task-history" aria-label="Görev değişiklik geçmişi"><h4>Değişiklik geçmişi</h4>
      <ol>{versions.items.map(row => <li key={row.id}><header><strong>Sürüm {row.versionNumber} · {taskStatusLabels[row.snapshot.status]}</strong><TaskTime value={row.createdAt} /></header>
        <p className="task-description">{row.snapshot.description}</p><p>Son tarih: <TaskTime value={row.snapshot.dueAt} /></p><p>Hatırlatma tercihi: {row.snapshot.isReminderEnabled ? 'Açık' : 'Kapalı'}</p>
      </li>)}</ol>
      {versions.items.length === 0 && <p>Bu geçmiş sayfasında kayıt yok.</p>}
      <div className="task-actions task-pagination"><button className="button button-secondary" disabled={disabled || page <= 1} onClick={() => onPage(page - 1)}>Önceki görev sürümleri</button><span>{versions.totalCount} değişiklik · Sayfa {page}</span><button className="button button-secondary" disabled={disabled || page * 10 >= versions.totalCount} onClick={() => onPage(page + 1)}>Sonraki görev sürümleri</button></div>
    </section>
  </section>
}
