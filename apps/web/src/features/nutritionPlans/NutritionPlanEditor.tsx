import { useState } from 'react'
import type { FormEvent } from 'react'
import { mealLabels } from './nutritionPlanApi'
import type { MealType, NutritionPlanResponse, PlanContentRequest } from './nutritionPlanApi'

type ItemForm = { key: string; day: string; meal: MealType; description: string; quantity: string; group: string }
const blankItem = (): ItemForm => ({ key: crypto.randomUUID(), day: '', meal: 'breakfast', description: '', quantity: '', group: '' })
const days = ['Her gün', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar']
export function NutritionPlanEditor({ initial, busy, onSave, onCancel }: { initial?: NutritionPlanResponse; busy: boolean; onSave: (value: PlanContentRequest) => Promise<void>; onCancel: () => void }) {
  const [title, setTitle] = useState(initial?.title ?? '')
  const [start, setStart] = useState(initial?.startDate ?? '')
  const [end, setEnd] = useState(initial?.endDate ?? '')
  const [calories, setCalories] = useState(initial?.dailyCaloriesTargetKcal?.toString() ?? '')
  const [water, setWater] = useState(initial?.dailyWaterTargetMl?.toString() ?? '')
  const [items, setItems] = useState<ItemForm[]>(() => initial?.items.map(item => ({ key: item.id, day: item.dayOfWeek?.toString() ?? '', meal: item.mealType,
    description: item.description, quantity: item.recommendedQuantity ?? '', group: item.alternativeGroupId ?? '' })) ?? [blankItem()])
  const [groups, setGroups] = useState<string[]>(() => [...new Set(initial?.items.flatMap(row => row.alternativeGroupId ? [row.alternativeGroupId] : []) ?? [])])
  const [message, setMessage] = useState('')
  function update(key: string, value: Partial<ItemForm>) { setItems(current => current.map(item => item.key === key ? { ...item, ...value } : item)); setMessage('') }
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (busy) return; setMessage('')
    const number = (input: string) => input.trim() === '' ? null : /^\d+(?:[.,]\d+)?$/.test(input.trim()) ? Number(input.trim().replace(',', '.')) : NaN
    const kcal = number(calories); const ml = number(water)
    const invalidTarget = (value: number | null) => value !== null && (!Number.isFinite(value) || value <= 0)
    if (!title.trim() || Array.from(title.trim()).length > 120 || !start || (end && end < start) || invalidTarget(kcal) || invalidTarget(ml) || items.length < 1 || items.length > 100 ||
      items.some(item => !item.description.trim() || Array.from(item.description.trim()).length > 2000 || Array.from(item.quantity.trim()).length > 200)) {
      setMessage('Başlık, tarih, pozitif hedefler ve öğün açıklamalarını kontrol edin.'); return
    }
    if (groups.some(group => {
      const members = items.filter(item => item.group === group)
      return members.length > 0 && (members.length < 2 || members.some(item => item.day !== members[0]?.day || item.meal !== members[0]?.meal))
    })) { setMessage('Alternatif grubunda aynı gün ve öğün türüne ait en az iki öneri bulunmalı.'); return }
    await onSave({ title: title.trim(), startDate: start, endDate: end || null, dailyCaloriesTargetKcal: kcal, dailyWaterTargetMl: ml,
      items: items.map((item, index) => ({ dayOfWeek: item.day ? Number(item.day) : null, mealType: item.meal, description: item.description.trim(),
        recommendedQuantity: item.quantity.trim() || null, sortOrder: index, recipeId: null, alternativeGroupId: item.group || null })) })
  }
  return <form className="nutrition-editor" aria-label="Beslenme programı formu" noValidate onSubmit={event => { void submit(event) }}>
    <h3>{initial ? 'Programı düzenle' : 'Yeni program taslağı'}</h3>
    <fieldset disabled={busy}><legend>Program bilgileri</legend>
      <div className="form-field"><label htmlFor="plan-title">Program başlığı</label><input id="plan-title" value={title} required onChange={event => setTitle(event.target.value)} /></div>
      <div className="plan-grid"><div className="form-field"><label htmlFor="plan-start">Başlangıç tarihi</label><input id="plan-start" type="date" value={start} required onChange={event => setStart(event.target.value)} /></div>
        <div className="form-field"><label htmlFor="plan-end">Bitiş tarihi (isteğe bağlı)</label><input id="plan-end" type="date" value={end} onChange={event => setEnd(event.target.value)} /></div></div>
      <div className="plan-grid"><div className="form-field"><label htmlFor="plan-kcal">Günlük enerji hedefi (kcal, isteğe bağlı)</label><input id="plan-kcal" inputMode="decimal" value={calories} onChange={event => setCalories(event.target.value)} /></div>
        <div className="form-field"><label htmlFor="plan-water">Günlük su hedefi (mL, isteğe bağlı)</label><input id="plan-water" inputMode="decimal" value={water} onChange={event => setWater(event.target.value)} /></div></div>
      <p>Hedefler otomatik hesaplanmaz. Ondalık için virgül veya nokta kullanabilirsiniz.</p>
    </fieldset>
    {items.map((item, index) => <fieldset key={item.key} disabled={busy}><legend>Öğün önerisi {index + 1}</legend>
      <div className="plan-grid"><label>Gün<select aria-label={`Öğün ${index + 1} günü`} value={item.day} onChange={event => update(item.key, { day: event.target.value })}>{days.map((day, dayIndex) => <option key={day} value={dayIndex === 0 ? '' : String(dayIndex)}>{day}</option>)}</select></label>
        <label>Öğün türü<select aria-label={`Öğün ${index + 1} türü`} value={item.meal} onChange={event => update(item.key, { meal: event.target.value as MealType })}>{Object.entries(mealLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label></div>
      <div className="form-field"><label htmlFor={`description-${item.key}`}>Öğün {index + 1} açıklaması</label><textarea id={`description-${item.key}`} rows={3} value={item.description} required onChange={event => update(item.key, { description: event.target.value })} /></div>
      <div className="form-field"><label htmlFor={`quantity-${item.key}`}>Öğün {index + 1} miktar önerisi (isteğe bağlı)</label><input id={`quantity-${item.key}`} value={item.quantity} onChange={event => update(item.key, { quantity: event.target.value })} /></div>
      <label>Alternatif grubu<select aria-label={`Öğün ${index + 1} alternatif grubu`} value={item.group} onChange={event => {
        if (event.target.value === 'new') { const id = crypto.randomUUID(); setGroups(current => [...current, id]); update(item.key, { group: id }) }
        else update(item.key, { group: event.target.value })
      }}><option value="">Bağımsız öneri</option>{groups.map((group, groupIndex) => <option key={group} value={group}>Alternatif {groupIndex + 1}</option>)}<option value="new">Yeni alternatif grubu</option></select></label>
      <button className="button button-secondary" type="button" disabled={items.length === 1} onClick={() => setItems(current => current.filter(row => row.key !== item.key))}>Öğün {index + 1} önerisini kaldır</button>
    </fieldset>)}
    <p>Aynı gün ve öğündeki en az iki öneriyi aynı alternatif grubuna alabilirsiniz. Alternatifler birlikte tüketilecek ayrı öğünler değildir.</p>
    {message && <p className="form-message error-message" role="alert">{message}</p>}
    <div className="expert-pagination"><button className="button button-secondary" type="button" disabled={busy || items.length >= 100} onClick={() => setItems(current => [...current, blankItem()])}>Öğün önerisi ekle</button>
      <button className="button button-primary" type="submit" disabled={busy}>{busy ? 'Kaydediliyor…' : initial ? 'Yeni sürüm kaydet' : 'Taslak oluştur'}</button>
      <button className="button button-secondary" type="button" disabled={busy} onClick={onCancel}>Vazgeç</button></div>
  </form>
}
