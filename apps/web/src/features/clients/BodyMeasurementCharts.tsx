import type { BodyMeasurement } from './clientTracking.types'

const metrics = [
  { field: 'weightKg', label: 'Kilo', unit: 'kg' },
  { field: 'waistCm', label: 'Bel çevresi', unit: 'cm' },
  { field: 'hipCm', label: 'Kalça çevresi', unit: 'cm' },
  { field: 'chestCm', label: 'Göğüs çevresi', unit: 'cm' },
  { field: 'bodyFatPercent', label: 'Vücut yağ oranı', unit: '%' },
] as const
const number = new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 2 })
const date = new Intl.DateTimeFormat('tr-TR', { day: '2-digit', month: '2-digit', year: 'numeric' })

export function BodyMeasurementCharts({ records }: { records: BodyMeasurement[] }) {
  const chronological = [...records].sort((a, b) => Date.parse(a.measuredAt) - Date.parse(b.measuredAt) ||
    Number(a.measuredAt.match(/\.\d+/)?.[0] ?? 0) - Number(b.measuredAt.match(/\.\d+/)?.[0] ?? 0) || a.id.localeCompare(b.id))
  return <div className="measurement-charts" aria-label="Ölçüm gelişim grafikleri">
    <p className="measurement-chart-description">Grafikler seçilen tarih aralığındaki tüm kayıtları kapsar. Tarihler cihazın saat dilimindedir; yalnız kaydedilmiş değerler gösterilir.</p>
    {metrics.map(metric => {
      const points = chronological.flatMap(record => record[metric.field] === null ? [] : [{ id: record.id, at: record.measuredAt, time: Date.parse(record.measuredAt), value: record[metric.field] as number }])
      const label = `${metric.label} gelişimi (${metric.unit})`
      if (points.length === 0) return <figure className="measurement-chart" key={metric.field}><figcaption>{label}</figcaption><p>Bu alan için ölçüm kaydı yok.</p></figure>
      const minimum = points.reduce((value, point) => Math.min(value, point.value), points[0]!.value)
      const maximum = points.reduce((value, point) => Math.max(value, point.value), points[0]!.value)
      const first = points[0]!, last = points[points.length - 1]!
      const x = (time: number) => first.time === last.time ? 270 : 72 + (time - first.time) / (last.time - first.time) * 396
      const y = (value: number) => maximum === minimum ? 116 : 188 - (value - minimum) / (maximum - minimum) * 144
      const ticks = minimum === maximum ? [minimum] : [minimum, minimum + (maximum - minimum) / 2, maximum]
      return <figure className="measurement-chart" key={metric.field}>
        <figcaption>{label}</figcaption>
        <svg viewBox="0 0 500 240" role="img" aria-label={`${label}: ${points.length} kayıt`}>
          {ticks.map(value => <g key={value}><line className="measurement-grid-line" x1="72" x2="468" y1={y(value)} y2={y(value)} /><text x="64" y={y(value) + 4} textAnchor="end">{number.format(value)}</text></g>)}
          <line className="measurement-axis" x1="72" x2="468" y1="200" y2="200" />
          {points.length > 1 && <polyline className="measurement-trend" points={points.map(point => `${x(point.time)},${y(point.value)}`).join(' ')} />}
          {points.map(point => <circle className="measurement-point" key={point.id} cx={x(point.time)} cy={y(point.value)} r="4"><title>{`${new Date(point.at).toLocaleString('tr-TR')}: ${point.value} ${metric.unit}`}</title></circle>)}
          <text x={first.time === last.time ? 270 : 72} y="224" textAnchor={first.time === last.time ? 'middle' : 'start'}>{date.format(first.time)}</text>
          {first.time !== last.time && <text x="468" y="224" textAnchor="end">{date.format(last.time)}</text>}
        </svg>
        <p>{points.length === 1 ? 'Tek ölçüm kaydı; henüz değişim çizgisi yok.' : `${points.length} ölçüm kaydı`}</p>
      </figure>
    })}
  </div>
}
