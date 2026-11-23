import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { mealLabels } from './nutritionPlanApi'
import type { MealType, NutritionPlanResponse, PlanContentRequest } from './nutritionPlanApi'
import { blankItem, copyItems, draftContent, draftSignature, planDays, planDraft, validateDraft } from './planDraft'
import type { ItemForm, PlanDraft } from './planDraft'
import { PlanConfirmation } from './PlanConfirmation'

export function NutritionPlanEditor({ initial, seed, clientName, busy, onDirtyChange, onSave, onCancel }: {
  initial?: NutritionPlanResponse; seed?: PlanDraft; clientName?: string; busy: boolean; onDirtyChange?: (dirty: boolean) => void;
  onSave: (value: PlanContentRequest) => Promise<void>; onCancel: () => void
}) {
  const [baseline] = useState(() => planDraft(initial))
  const [draft, setDraft] = useState(() => seed ?? baseline)
  const [day, setDay] = useState('')
  const [open, setOpen] = useState<string[]>(() => [draft.items[0]!.key])
  const [groups, setGroups] = useState(() => [...new Set(draft.items.flatMap(row => row.group ? [row.group] : []))])
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [focus, setFocus] = useState('')
  const [copyDay, setCopyDay] = useState('1')
  const [replaceDay, setReplaceDay] = useState(false)
  const [message, setMessage] = useState('')
  const titleInput = useRef<HTMLInputElement>(null)
  useEffect(() => { titleInput.current?.focus() }, [])
  const dirty = draftSignature(draft) !== draftSignature(baseline)
  useEffect(() => { onDirtyChange?.(dirty) }, [dirty, onDirtyChange])
  useEffect(() => { if (focus) { document.getElementById(focus)?.focus() } }, [focus])
  const updateDraft = (value: Partial<PlanDraft>) => { setDraft(current => ({ ...current, ...value })); setErrors({}); setMessage('') }
  function selectDay(value: string) {
    setDay(value)
    if (value === copyDay) setCopyDay(value === '7' ? '1' : String(Number(value) + 1))
  }
  function update(key: string, value: Partial<ItemForm>) { updateDraft({ items: draft.items.map(item => item.key === key ? { ...item, ...value } : item) }) }
  function copy(replace = false) {
    const source = draft.items.filter(item => item.day === day)
    const target = draft.items.filter(item => item.day === copyDay)
    if (!source.length || day === copyDay || day === '') { setMessage('Farklı bir haftalık kaynak ve hedef gün seçin.'); return }
    if (draft.items.length - (replace ? target.length : 0) + source.length > 100) { setMessage('Kopyalama 100 öğün önerisi sınırını aşıyor.'); return }
    if (target.length && !replace) { setReplaceDay(true); return }
    const copied = copyItems(source, copyDay)
    const index = draft.items.findIndex(item => item.day === copyDay)
    const kept = draft.items.filter(item => !replace || item.day !== copyDay)
    kept.splice(index < 0 ? kept.length : index, 0, ...copied)
    updateDraft({ items: kept }); setGroups(current => [...current, ...new Set(copied.flatMap(row => row.group ? [row.group] : []))])
    setDay(copyDay); setCopyDay(day); setOpen([copied[0]!.key]); setReplaceDay(false)
  }
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (busy) return
    const found = validateDraft(draft); setErrors(found)
    const first = Object.keys(found)[0]
    if (first) {
      const item = draft.items.find(row => first.endsWith(row.key))
      if (item) { setDay(item.day); setOpen(current => [...current, item.key]) }
      setFocus(first); requestAnimationFrame(() => document.getElementById(first)?.focus()); return
    }
    await onSave(draftContent(draft))
  }
  function error(id: string) { return errors[id] ? <p id={`${id}-error`} className="error-message" role="alert">{errors[id]}</p> : null }
  function field(id: string) { return { 'aria-invalid': !!errors[id], 'aria-describedby': errors[id] ? `${id}-error` : undefined } }
  return <form className="nutrition-editor" aria-label="Beslenme programı formu" noValidate onSubmit={event => { void submit(event) }}>
    <h3>{initial ? 'Programı düzenle' : 'Yeni program taslağı'}</h3>
    {clientName && <p><strong>Hedef danışan: {clientName}</strong></p>}
    {seed && <p>Yalnız öğün yapısı kopyalandı. Serbest metin kişiye özel bilgi içerebilir; açıklama ve miktarları kaydetmeden önce inceleyin. Başlık, tarihler ve hedefleri bu danışan için girin.</p>}
    <fieldset disabled={busy}><legend>Program bilgileri</legend>
      <div className="form-field"><label htmlFor="plan-title">Program başlığı</label><input ref={titleInput} id="plan-title" {...field('plan-title')} value={draft.title} required onChange={event => updateDraft({ title: event.target.value })} />{error('plan-title')}</div>
      <div className="plan-grid"><div className="form-field"><label htmlFor="plan-start">Başlangıç tarihi</label><input id="plan-start" {...field('plan-start')} type="date" value={draft.start} required onChange={event => updateDraft({ start: event.target.value })} />{error('plan-start')}</div>
        <div className="form-field"><label htmlFor="plan-end">Bitiş tarihi (isteğe bağlı)</label><input id="plan-end" {...field('plan-end')} type="date" value={draft.end} onChange={event => updateDraft({ end: event.target.value })} />{error('plan-end')}</div></div>
      <div className="plan-grid"><div className="form-field"><label htmlFor="plan-kcal">Günlük enerji hedefi (kcal, isteğe bağlı)</label><input id="plan-kcal" {...field('plan-kcal')} inputMode="decimal" value={draft.calories} onChange={event => updateDraft({ calories: event.target.value })} />{error('plan-kcal')}</div>
        <div className="form-field"><label htmlFor="plan-water">Günlük su hedefi (mL, isteğe bağlı)</label><input id="plan-water" {...field('plan-water')} inputMode="decimal" value={draft.water} onChange={event => updateDraft({ water: event.target.value })} />{error('plan-water')}</div></div>
      <p>Hedefler otomatik hesaplanmaz. Ondalık için virgül veya nokta kullanabilirsiniz.</p>
    </fieldset>
    <div className="plan-days" role="group" aria-label="Program günü">{planDays.map((label, i) => <button className="button button-secondary" key={label} type="button" aria-pressed={day === (i ? String(i) : '')} onClick={() => selectDay(i ? String(i) : '')}>{label}</button>)}</div>
    <p>Her gün önerileri haftanın tüm günlerinde geçerlidir; güne özel önerilerle birlikte gösterilir, onların yerine geçmez.</p>
    <fieldset disabled={busy}><legend>{planDays[Number(day)]} öğünleri</legend>
      {draft.items.filter(item => item.day === day).length === 0 && <p>Bu güne özel öğün önerisi yok.</p>}
      {draft.items.map((item, index) => item.day !== day ? null : <details className="plan-meal-editor" key={item.key} open={open.includes(item.key)} onToggle={event => {
        const expanded = event.currentTarget.open
        setOpen(current => expanded ? current.includes(item.key) ? current : [...current, item.key] : current.filter(key => key !== item.key))
      }}><summary>{mealLabels[item.meal]} · Öğün önerisi {index + 1}{item.description && ` · ${item.description.slice(0, 60)}`}</summary>
        <div className="plan-grid"><label>Gün<select aria-label={`Öğün ${index + 1} günü`} value={item.day} onChange={event => { update(item.key, { day: event.target.value }); selectDay(event.target.value) }}>{planDays.map((label, i) => <option key={label} value={i ? String(i) : ''}>{label}</option>)}</select></label>
          <label>Öğün türü<select aria-label={`Öğün ${index + 1} türü`} value={item.meal} onChange={event => update(item.key, { meal: event.target.value as MealType })}>{Object.entries(mealLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label></div>
        <div className="form-field"><label htmlFor={`description-${item.key}`}>Öğün {index + 1} açıklaması</label><textarea id={`description-${item.key}`} {...field(`description-${item.key}`)} rows={3} value={item.description} required onChange={event => update(item.key, { description: event.target.value })} />{error(`description-${item.key}`)}</div>
        <div className="form-field"><label htmlFor={`quantity-${item.key}`}>Öğün {index + 1} miktar önerisi (isteğe bağlı)</label><input id={`quantity-${item.key}`} {...field(`quantity-${item.key}`)} value={item.quantity} onChange={event => update(item.key, { quantity: event.target.value })} />{error(`quantity-${item.key}`)}</div>
        <label>Alternatif grubu<select id={`group-${item.key}`} {...field(`group-${item.key}`)} aria-label={`Öğün ${index + 1} alternatif grubu`} value={item.group} onChange={event => {
          if (event.target.value === 'new') { const id = crypto.randomUUID(); setGroups(current => [...current, id]); update(item.key, { group: id }) }
          else update(item.key, { group: event.target.value })
        }}><option value="">Bağımsız öneri</option>{groups.map((group, i) => <option key={group} value={group}>Alternatif {i + 1}</option>)}<option value="new">Yeni alternatif grubu</option></select></label>{error(`group-${item.key}`)}
        <button className="button button-secondary" type="button" disabled={draft.items.length === 1} onClick={() => updateDraft({ items: draft.items.filter(row => row.key !== item.key) })}>Öğün {index + 1} önerisini kaldır</button>
      </details>)}
      <button id="plan-add-item" className="button button-secondary" type="button" disabled={draft.items.length >= 100} onClick={() => { const item = blankItem(day); updateDraft({ items: [...draft.items, item] }); setOpen(current => [...current, item.key]) }}>Öğün önerisi ekle</button>{error('plan-add-item')}
    </fieldset>
    {day !== '' && <fieldset disabled={busy}><legend>Günü kopyala</legend><label>Hedef gün<select value={copyDay} onChange={event => setCopyDay(event.target.value)}>{planDays.slice(1).map((label, i) => <option key={label} value={String(i + 1)} disabled={day === String(i + 1)}>{label}</option>)}</select></label>
      <button className="button button-secondary" type="button" onClick={() => copy()}>Günü kopyala</button></fieldset>}
    <p>Aynı gün ve öğündeki en az iki öneriyi aynı alternatif grubuna alabilirsiniz. Alternatifler birlikte tüketilecek ayrı öğünler değildir.</p>
    {message && <p className="error-message" role="alert">{message}</p>}
    <div className="plan-save-bar"><span role="status">{dirty ? 'Kaydedilmemiş değişiklikler var' : 'Değişiklik yok'}</span>
      <button className="button button-primary" type="submit" disabled={busy}>{busy ? 'Kaydediliyor…' : initial ? 'Yeni sürüm kaydet' : 'Taslak oluştur'}</button>
      <button className="button button-secondary" type="button" disabled={busy} onClick={onCancel}>Vazgeç</button></div>
    {replaceDay && <PlanConfirmation title="Hedef gün dolu" confirmLabel="Hedef günü değiştir" onCancel={() => setReplaceDay(false)} onConfirm={() => copy(true)}><p>{planDays[Number(copyDay)]} önerileri silinip {planDays[Number(day)]} önerileriyle değiştirilecek.</p></PlanConfirmation>}
  </form>
}
