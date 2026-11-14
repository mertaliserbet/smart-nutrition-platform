import { useState } from 'react'
import type { FormEvent } from 'react'
import { EmptyState } from '../../core/components/EmptyState'
import { MealLogList } from './ClientRecordViews'
import type { MealLog } from './clientTracking.types'

const pageSize = 2
const unfiltered = { from: Number.NEGATIVE_INFINITY, to: Number.POSITIVE_INFINITY }

export function MealLogPreview({ clientId, records }: { clientId: string; records: MealLog[] }) {
  const [range, setRange] = useState(unfiltered)
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const clientRecords = records.filter(record => record.clientId === clientId)
  const filteredRecords = clientRecords.filter(record => {
    const consumedAt = Date.parse(record.consumedAt)
    return consumedAt >= range.from && consumedAt < range.to
  })
  const pageCount = Math.ceil(filteredRecords.length / pageSize)

  function applyFilter(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    const fromInput = form.get('from')
    const toInput = form.get('to')
    const from = fromInput ? Date.parse(`${fromInput}Z`) : unfiltered.from
    const to = toInput ? Date.parse(`${toInput}Z`) : unfiltered.to

    if (!(from < to)) {
      setError('Bitiş tarihi ve saati başlangıçtan sonra olmalı.')
      return
    }
    setError('')
    setRange({ from, to })
    setPage(1)
  }

  function clearFilter() {
    setError('')
    setRange(unfiltered)
    setPage(1)
  }

  return (
    <>
      <form className="meal-preview-filters" onSubmit={applyFilter} onReset={clearFilter} aria-label="Öğün tarihi filtresi">
        <p id="meal-preview-time-zone">Filtre saatleri UTC (UTC+00:00). Kayıt saatleri cihazın saat diliminde gösterilir.</p>
        <label>Başlangıç<input name="from" type="datetime-local" aria-describedby="meal-preview-time-zone" /></label>
        <label>Bitiş<input name="to" type="datetime-local" aria-describedby="meal-preview-time-zone" /></label>
        <div className="meal-preview-actions">
          <button className="button button-primary" type="submit">Filtrele</button>
          <button className="button button-secondary" type="reset">Filtreyi temizle</button>
        </div>
        {error && <p role="alert">{error}</p>}
      </form>
      {filteredRecords.length === 0 && clientRecords.length > 0 ? (
        <EmptyState icon="leaf" title="Bu aralıkta öğün kaydı yok">Başka bir tarih aralığı seçin veya filtreyi temizleyin.</EmptyState>
      ) : (
        <MealLogList clientId={clientId} records={filteredRecords} page={{ number: page, size: pageSize }} />
      )}
      {filteredRecords.length > 0 && (
        <div className="meal-preview-pagination">
          {pageCount > 1 && <button className="button button-secondary" type="button" disabled={page <= 1} onClick={() => setPage(current => current - 1)}>Önceki sayfa</button>}
          <p role="status">{filteredRecords.length} öğün{pageCount > 1 && ` · Sayfa ${page} / ${pageCount}`}</p>
          {pageCount > 1 && <button className="button button-secondary" type="button" disabled={page >= pageCount} onClick={() => setPage(current => current + 1)}>Sonraki sayfa</button>}
        </div>
      )}
    </>
  )
}
