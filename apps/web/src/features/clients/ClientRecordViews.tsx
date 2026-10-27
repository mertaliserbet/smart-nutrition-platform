import { Icon } from '../../core/components/Icon'
import { EmptyState } from '../../core/components/EmptyState'
import type { ActivityLog, BodyMeasurement, LabFlag, LabReport, LabResult, MealLog, MealType, RecordSource, WaterLog } from './clientTracking.types'

const sourceLabels: Record<RecordSource, string> = {
  manual: 'Manuel kayıt', wearable: 'Cihaz aktarımı', ai_assisted: 'AI destekli kayıt',
}
const mealLabels: Record<MealType, string> = {
  breakfast: 'Kahvaltı', lunch: 'Öğle öğünü', dinner: 'Akşam öğünü', snack: 'Ara öğün', other: 'Diğer öğün',
}
const dateFormatter = new Intl.DateTimeFormat('tr-TR', {
  day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZoneName: 'short',
})
// Display individual source values without selecting a clinical rounding policy
// or computing daily totals/targets from the still-open day/time-zone contract.
const numberFormatter = new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 20 })

function Quantity({ label, value, unit }: { label: string; value: number | null; unit: string }) {
  return <div><dt>{label}</dt><dd className={value === null ? 'unknown-value' : undefined}>{value === null ? 'Bilinmiyor' : `${numberFormatter.format(value)} ${unit}`}</dd></div>
}

function RecordTime({ at }: { at: string }) {
  return <time dateTime={at}><Icon name="clock" />{dateFormatter.format(new Date(at))}</time>
}

export function MealLogList({ clientId, records }: { clientId: string; records: MealLog[] }) {
  const visibleRecords = records.filter((record) => record.clientId === clientId).sort((a, b) => b.consumedAt.localeCompare(a.consumedAt))
  if (visibleRecords.length === 0) return <EmptyState icon="leaf" title="Henüz öğün kaydı yok">Bu görünümde görüntülenebilecek öğün kaydı bulunmuyor.</EmptyState>
  return <div className="record-list" aria-label="Öğün kayıtları">
    {visibleRecords.map((record) => <article className="meal-record" key={record.id} aria-labelledby={`meal-${record.id}`}>
      <header className="record-header"><div><h3 id={`meal-${record.id}`}>{mealLabels[record.mealType]}</h3><RecordTime at={record.consumedAt} /></div><span className="neutral-badge">{sourceLabels[record.source]}</span></header>
      <ul className="meal-items">
        {record.items.filter((item) => item.mealLogId === record.id).map((item) => <li key={item.id}>
          <div className="meal-item-title"><h4>{item.displayName}</h4>{item.isEstimated && <span className="estimate-badge">Tahmini</span>}</div>
          <dl className="record-quantities">
            <Quantity label="Porsiyon" value={item.quantityGrams} unit="g" />
            <Quantity label="Enerji" value={item.caloriesKcal} unit="kcal" />
            <Quantity label="Protein" value={item.proteinGrams} unit="g" />
            <Quantity label="Karbonhidrat" value={item.carbsGrams} unit="g" />
            <Quantity label="Yağ" value={item.fatGrams} unit="g" />
          </dl>
        </li>)}
      </ul>
      {record.note && <p className="record-note"><Icon name="info" />{record.note}</p>}
    </article>)}
    <p className="record-footnote">Tahmini değerler kesin ölçüm değildir. Diyetisyen görünümü danışanın tüketim kayıtlarını değiştirmez.</p>
  </div>
}

export function WaterLogList({ clientId, records }: { clientId: string; records: WaterLog[] }) {
  const visibleRecords = records.filter((record) => record.clientId === clientId).sort((a, b) => b.consumedAt.localeCompare(a.consumedAt))
  if (visibleRecords.length === 0) return <EmptyState icon="plan" title="Henüz su kaydı yok">Bu görünümde görüntülenebilecek su kaydı bulunmuyor.</EmptyState>
  return <ul className="record-list water-records" aria-label="Su kayıtları">{visibleRecords.map((record) => <li className="water-record" key={record.id}><span className="water-icon"><Icon name="water" /></span><div><strong>{numberFormatter.format(record.amountMl)} mL</strong><RecordTime at={record.consumedAt} /></div><span className="neutral-badge">{sourceLabels[record.source]}</span></li>)}</ul>
}

export function BodyMeasurementList({ clientId, records }: { clientId: string; records: BodyMeasurement[] }) {
  const visibleRecords = records.filter((record) => record.clientId === clientId).sort((a, b) => b.measuredAt.localeCompare(a.measuredAt))
  if (visibleRecords.length === 0) return <EmptyState icon="chart" title="Henüz ölçüm kaydı yok">Bu görünümde görüntülenebilecek ölçüm kaydı bulunmuyor.</EmptyState>
  return <div className="record-list" aria-label="Ölçüm kayıtları">{visibleRecords.map((record) => <article className="measurement-record" key={record.id}>
    <header className="record-header"><RecordTime at={record.measuredAt} /><span className="neutral-badge">{sourceLabels[record.source]}</span></header>
    <dl className="record-quantities measurement-quantities"><Quantity label="Kilo" value={record.weightKg} unit="kg" /><Quantity label="Bel çevresi" value={record.waistCm} unit="cm" /><Quantity label="Vücut yağ oranı" value={record.bodyFatPercent} unit="%" /></dl>
  </article>)}<p className="record-footnote">Ölçümler kaydedildiği tarih ve birimle gösterilir. Bu ekran klinik değerlendirme veya hedef önerisi üretmez.</p></div>
}

export function ActivityLogList({ clientId, records }: { clientId: string; records: ActivityLog[] }) {
  const visibleRecords = records.filter((record) => record.clientId === clientId)
    .sort((a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt))
  if (visibleRecords.length === 0) return <EmptyState icon="activity" title="Henüz aktivite kaydı yok">Bu görünümde görüntülenebilecek aktivite kaydı bulunmuyor.</EmptyState>
  return <div className="record-list" aria-label="Aktivite kayıtları">{visibleRecords.map((record) => <article className="activity-record" key={record.id} aria-labelledby={`activity-${record.id}`}>
    <header className="record-header"><div><h3 id={`activity-${record.id}`}>{record.activityType}</h3><RecordTime at={record.startedAt} /></div><span className="neutral-badge">{sourceLabels[record.source]}</span></header>
    <dl className="record-quantities activity-quantities"><Quantity label="Süre" value={record.durationMinutes} unit="dk" /><Quantity label="Mesafe" value={record.distanceKm} unit="km" /><Quantity label="Enerji" value={record.caloriesKcal} unit="kcal" /></dl>
  </article>)}</div>
}

const labFlagLabels: Record<LabFlag, string> = {
  low: 'Alt referansın altında',
  normal: 'Referans aralığında',
  high: 'Üst referansın üzerinde',
  unknown: 'Değerlendirilemiyor',
}

function LabResultRow({ result }: { result: LabResult }) {
  const hasUnit = result.unit.trim().length > 0
  const hasCompleteReference = result.referenceLow !== null && result.referenceHigh !== null
    && Number.isFinite(result.referenceLow) && Number.isFinite(result.referenceHigh)
    && result.referenceLow <= result.referenceHigh
  // Preserve the supplied flag. Missing context can only suppress an assessment;
  // the client never calculates a new clinical flag or interprets a one-sided range.
  const displayedFlag = hasUnit && hasCompleteReference ? result.flag : 'unknown'
  const unit = hasUnit ? result.unit : '(birim bilinmiyor)'
  return (
    <li className="lab-result" aria-labelledby={`lab-result-${result.id}`}>
      <div className="lab-result-heading">
        <h4 id={`lab-result-${result.id}`}>{result.testName}</h4>
        {result.testCode && <span className="lab-test-code">Kayıttaki kod: {result.testCode}</span>}
      </div>
      <dl className="record-quantities lab-quantities">
        <Quantity label="Sonuç" value={result.value} unit={unit} />
        <Quantity label="Alt referans" value={result.referenceLow} unit={unit} />
        <Quantity label="Üst referans" value={result.referenceHigh} unit={unit} />
        <div><dt>Kayıttaki durum</dt><dd className={displayedFlag === 'unknown' ? 'unknown-value' : undefined}>{labFlagLabels[displayedFlag]}</dd></div>
      </dl>
    </li>
  )
}

export function LabReportList({ clientId, records }: { clientId: string; records: LabReport[] }) {
  const visibleReports = records.filter((report) => report.clientId === clientId)
    .sort((a, b) => Date.parse(b.collectedAt) - Date.parse(a.collectedAt))
  if (visibleReports.length === 0) return <EmptyState icon="lab" title="Henüz tahlil raporu yok">Bu görünümde görüntülenebilecek tahlil raporu bulunmuyor.</EmptyState>
  return (
    <div className="record-list" aria-label="Tahlil raporları">
      {visibleReports.map((report) => {
        const results = report.results.filter((result) => result.labReportId === report.id)
        return (
          <article className="lab-record" key={report.id} aria-labelledby={`lab-report-${report.id}`}>
            <header className="record-header">
              <div><h3 id={`lab-report-${report.id}`}>{report.labName?.trim() || 'Laboratuvar belirtilmemiş'}</h3><RecordTime at={report.collectedAt} /></div>
              <span className="neutral-badge">Laboratuvar raporu</span>
            </header>
            {results.length > 0
              ? <ul className="lab-results" aria-label="Rapor sonuçları">{results.map((result) => <LabResultRow key={result.id} result={result} />)}</ul>
              : <p className="record-note">Bu raporda görüntülenebilecek sonuç yok.</p>}
            {report.note && <p className="record-note"><Icon name="info" />{report.note}</p>}
          </article>
        )
      })}
      <p className="record-footnote">Değerler ve referanslar rapordaki birimle gösterilir. Eksik birim veya referansta değerlendirme yapılmaz. Referans aralığı genel sağlık hükmü değildir; bu görünüm tanı veya tedavi önerisi üretmez.</p>
    </div>
  )
}
