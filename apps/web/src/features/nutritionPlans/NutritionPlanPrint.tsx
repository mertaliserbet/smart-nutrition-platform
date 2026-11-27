import { useCallback, useEffect, useRef, useState } from 'react'
import { Brand, Icon } from '../../core/components/Icon'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { getNutritionPlan, getNutritionPlanVersion, mealLabels } from './nutritionPlanApi'
import type { MealType, NutritionPlanItem, NutritionPlanResponse, NutritionPlanVersionResponse } from './nutritionPlanApi'
import './nutritionPlanPrint.css'

const days = ['Her gün', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar']
const formatDate = (value: string) => new Date(value + 'T12:00:00').toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' })
const number = (value: number) => value.toLocaleString('tr-TR')

async function readable<T>(read: () => Promise<T>) {
  try { return { kind: 'ready' as const, value: await read() } }
  catch (error) {
    if (error instanceof WebSessionError && [403, 404].includes(error.status)) return { kind: 'denied' as const, message: error.message }
    throw error
  }
}

type PrintDocument = { plan: NutritionPlanResponse; version: NutritionPlanVersionResponse }
type PrintProps = { clientId: string; clientName: string; program: NutritionPlanResponse; onBack: () => void }

function MealItems({ items }: { items: NutritionPlanItem[] }) {
  const groups = new Map<string, NutritionPlanItem[]>()
  for (const item of items) {
    const key = item.alternativeGroupId ?? item.id
    groups.set(key, [...(groups.get(key) ?? []), item])
  }
  return <div className="nutrition-print-meal-content">{[...groups].map(([id, rows]) =>
    <div key={id} className={rows[0]!.alternativeGroupId ? 'nutrition-print-alternatives' : undefined}>
      {rows[0]!.alternativeGroupId && <p className="nutrition-print-alternative-label">Alternatifler · Birini seçin</p>}
      <ul>{rows.map(item => <li key={item.id} className="nutrition-print-item">
        <p>{item.description}</p><span className="nutrition-print-quantity">Miktar: {item.recommendedQuantity?.trim() || 'Belirtilmemiş'}</span>
      </li>)}</ul>
    </div>
  )}</div>
}

function ProgramDocument({ value, clientName, dietitianName }: { value: PrintDocument; clientName: string; dietitianName: string }) {
  const [documentDate] = useState(() => new Date().toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' }))
  const { snapshot } = value.version
  const presentDays = days.map((label, index) => ({ label, day: index === 0 ? null : index }))
    .filter(day => snapshot.items.some(item => item.dayOfWeek === day.day))
  return <article className="nutrition-print-document" aria-label="Yazdırılabilir beslenme programı">
    <header className="nutrition-print-header">
      <div className="nutrition-print-brand"><Brand subtitle="" /><p>Beslenme ve danışan takibi</p></div>
      <div><h1 tabIndex={-1}>Beslenme programı</h1><dl>
        <div><dt>Danışan</dt><dd>{clientName}</dd></div>
        <div><dt>Diyetisyen</dt><dd>{dietitianName}</dd></div>
        <div><dt>Belge tarihi</dt><dd>{documentDate}</dd></div>
      </dl></div>
    </header>
    <section className="nutrition-print-program" aria-label="Program ve içerik sürümü">
      <h2>{snapshot.title}</h2><p>İçerik sürümü {value.version.versionNumber} · {new Date(value.version.createdAt).toLocaleString('tr-TR')}</p>
    </section>
    <dl className="nutrition-print-summary">
      <div><dt>Günlük enerji hedefi</dt><dd>{snapshot.dailyCaloriesTargetKcal === null ? 'Belirtilmemiş' : number(snapshot.dailyCaloriesTargetKcal) + ' kcal'}</dd></div>
      <div><dt>Günlük su hedefi</dt><dd>{snapshot.dailyWaterTargetMl === null ? 'Belirtilmemiş' : number(snapshot.dailyWaterTargetMl) + ' mL'}</dd></div>
      <div><dt>Başlangıç</dt><dd>{formatDate(snapshot.startDate)}</dd></div>
      <div><dt>Bitiş</dt><dd>{snapshot.endDate ? formatDate(snapshot.endDate) : 'Belirtilmemiş'}</dd></div>
    </dl>
    <div className="nutrition-print-days">{presentDays.map(day => <section className="nutrition-print-day" key={day.label}>
      <h2>{day.label}</h2>{day.day === null && <p className="nutrition-print-day-note">Tüm günler için ortak öneriler.</p>}
      {(Object.keys(mealLabels) as MealType[]).map(meal => {
        const items = snapshot.items.filter(item => item.dayOfWeek === day.day && item.mealType === meal).sort((a, b) => a.sortOrder - b.sortOrder)
        return items.length ? <div className="nutrition-print-meal" key={meal}>
          <h3>{mealLabels[meal]}</h3><MealItems items={items} />
        </div> : null
      })}
    </section>)}</div>
    <footer className="nutrition-print-footer"><strong>Limely</strong><p>Bu belge planlanan beslenme önerilerini içerir. Gerçek tüketim kaydı değildir.</p></footer>
  </article>
}

export function NutritionPlanPrint(props: PrintProps) {
  const session = useWorkspaceSession()
  return <PrintPanel key={[session.dietitianId, session.token, props.clientId, props.program.id, props.program.versionId].join(':')} {...props} />
}

function PrintPanel({ clientId, clientName, program, onBack }: PrintProps) {
  const session = useWorkspaceSession()
  const [printFailure, setPrintFailure] = useState('')
  const [printing, setPrinting] = useState(false)
  const operation = useRef<AbortController | null>(null)
  const documentRoot = useRef<HTMLDivElement>(null)
  const [assets, setAssets] = useState<{ source: PrintDocument; ready: boolean; message?: string }>()
  const loadDocument = useCallback((signal: AbortSignal) => readable(async () => {
    if (program.clientId !== clientId) throw new WebSessionError(500, 'Programın danışan bilgisi doğrulanamadı.')
    const plan = await getNutritionPlan(clientId, program.id, signal)
    const version = await getNutritionPlanVersion(plan.id, program.versionId, signal)
    if (version.versionNumber !== program.versionNumber) throw new WebSessionError(500, 'İçerik sürümü doğrulanamadı. Programlar bölümünden yeniden açın.')
    return { plan, version }
  }), [clientId, program])
  const content = useWorkspaceRead(loadDocument)
  const value = content.data?.kind === 'ready' ? content.data.value : undefined
  const documentValue = printFailure ? undefined : value
  const assetsReady = !!documentValue && assets?.source === documentValue && assets.ready
  const denied = content.data?.kind === 'denied' ? content.data.message : ''
  const assetMessage = assets?.source === documentValue ? assets?.message : ''

  useEffect(() => {
    if (!documentValue) return
    let current = true
    const logo = documentRoot.current?.querySelector<HTMLImageElement>('.brand-logo')
    void (async () => {
      try {
        if (!logo || !document.fonts) throw new Error('Print assets unavailable')
        const fonts = await Promise.all([document.fonts.load('700 16px Manrope'), document.fonts.load('400 14px Inter')])
        if (fonts.some(faces => !faces.length)) throw new Error('Print fonts unavailable')
        await Promise.all([document.fonts.ready, logo.decode()])
        if (!logo.naturalWidth) throw new Error('Print logo unavailable')
        if (current) setAssets({ source: documentValue, ready: true })
      } catch {
        if (current) setAssets({ source: documentValue, ready: false, message: 'Belgenin yazı tipleri veya logosu yüklenemedi. Yeniden deneyin.' })
      }
    })()
    return () => { current = false }
  }, [documentValue])

  useEffect(() => () => { operation.current?.abort(); operation.current = null }, [loadDocument])

  function refresh() {
    operation.current?.abort(); operation.current = null
    setPrinting(false); setPrintFailure(''); content.refresh()
  }

  async function print() {
    if (!documentValue || !assetsReady || operation.current) return
    const controller = new AbortController()
    operation.current = controller; setPrinting(true)
    try {
      // Recheck access to the same immutable version immediately before printing.
      await getNutritionPlan(clientId, documentValue.plan.id, controller.signal)
      await getNutritionPlanVersion(documentValue.plan.id, documentValue.version.id, controller.signal)
      await document.fonts.ready
      if (!controller.signal.aborted) window.print()
    } catch (error) {
      if (!controller.signal.aborted) {
        if (!(error instanceof WebSessionError && [403, 404].includes(error.status)) && session.onFailure(error)) return
        setPrintFailure(error instanceof WebSessionError ? error.message : 'Belge yazdırmaya hazırlanamadı. Yeniden deneyin.')
      }
    } finally {
      if (operation.current === controller) { operation.current = null; setPrinting(false) }
    }
  }

  return <section className="nutrition-print" aria-label="Beslenme programını yazdır">
    <div className="nutrition-print-toolbar">
      <button className="text-link" type="button" onClick={onBack}><Icon name="back" />Programlara dön</button>
      <p>A4 dikey çıktı · PDF için yazdırma penceresinde “PDF olarak kaydet” seçin.</p>
      <button className="button button-primary" type="button" onClick={() => { void print() }} disabled={!assetsReady || printing || !!denied}>
        {printing ? 'Yazdırmaya hazırlanıyor…' : 'Yazdır / PDF'}
      </button>
    </div>
    <div className="nutrition-print-controls">
      <div><h2>Seçilen program</h2><p>{program.title} · {clientName}</p></div>
      <button className="button button-secondary" type="button" onClick={refresh} disabled={printing}>Belgeyi yeniden yükle</button>
      {(denied || printFailure || content.message || assetMessage) && <p role="alert">{denied || printFailure || content.message || assetMessage}</p>}
      {content.pending && <p role="status">Programın içerik sürümü okunuyor…</p>}
      {documentValue && !assetsReady && !assetMessage && <p role="status">Belgenin yazı tipleri ve logosu hazırlanıyor…</p>}
      {documentValue && <p>Belge, seçtiğiniz programın {documentValue.version.versionNumber}. içerik sürümünü gösterir.</p>}
    </div>
    <div ref={documentRoot}>{!denied && documentValue && <ProgramDocument value={documentValue} clientName={clientName}
      dietitianName={documentValue.plan.dietitianId === null ? 'Kişisel program' : documentValue.plan.dietitianId === session.dietitianId ? session.dietitianName ?? 'Belirtilmemiş' : 'Belirtilmemiş'} />}</div>
  </section>
}
