import { createPortal } from 'react-dom'
import { useCallback, useId, useLayoutEffect, useRef, useState } from 'react'
import type { InputHTMLAttributes } from 'react'
import { Icon } from './Icon'
import { useFloatingControl } from './useFloatingControl'
import './formControls.css'

type Props = Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> & { type: 'date' | 'datetime-local' }
const dateAt = (year: number, month: number, day: number) => new Date(Date.UTC(year, month, day))
const iso = (date: Date) => date.toISOString().slice(0, 10)
const parse = (value: string) => { const [year, month, day] = value.split('-').map(Number); return dateAt(year!, month! - 1, day!) }
const label = (value: string) => parse(value).toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' })
const today = () => { const date = new Date(); return iso(dateAt(date.getFullYear(), date.getMonth(), date.getDate())) }

// The original input remains editable, focusable and responsible for validation.
export function DateField({ type, value, onChange, className = '', ...props }: Props) {
  const input = useRef<HTMLInputElement>(null)
  const anchor = useRef<HTMLSpanElement>(null)
  const time = useRef<HTMLInputElement>(null)
  const trigger = useRef<HTMLButtonElement>(null)
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(today)
  const [picked, setPicked] = useState('')
  const [hours, setHours] = useState('')
  const close = useCallback(() => setOpen(false), [])
  const popup = useFloatingControl(open, anchor, close)
  const id = useId()
  const calendarLabel = props['aria-label'], inputId = props.id
  useLayoutEffect(() => {
    const text = calendarLabel ?? input.current?.labels?.[0]?.textContent?.trim()
    if (text) trigger.current?.setAttribute('aria-label', `${text} için takvimi aç`)
  }, [inputId, calendarLabel])
  const selected = String(value ?? picked).slice(0, 10)
  const calendarDate = parse(active), year = calendarDate.getUTCFullYear(), month = calendarDate.getUTCMonth()
  const monthStart = dateAt(year, month, 1), offset = (monthStart.getUTCDay() + 6) % 7
  useLayoutEffect(() => { if (open) popup.current?.querySelector<HTMLButtonElement>(`[data-date="${active}"]`)?.focus({ preventScroll: true }) }, [open, active, popup])

  function show() {
    if (!input.current || input.current.matches(':disabled') || props.readOnly) return
    const current = input.current.value
    setPicked(current.slice(0, 10)); setHours(current.split('T')[1] ?? ''); setActive(current.slice(0, 10) || today()); setOpen(true)
  }
  function commit(day: string, hour = hours) {
    const element = input.current
    if (!element || element.matches(':disabled')) return
    if (type === 'datetime-local' && (!hour || !time.current?.checkValidity())) return
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set?.call(element, type === 'date' ? day : `${day}T${hour}`)
    element.dispatchEvent(new Event('input', { bubbles: true }))
    element.dispatchEvent(new Event('change', { bubbles: true }))
    close(); element.focus({ preventScroll: true })
  }
  function changeMonth(amount: number) {
    const first = dateAt(year, month + amount, 1)
    setActive(iso(dateAt(first.getUTCFullYear(), first.getUTCMonth(), Math.min(calendarDate.getUTCDate(), dateAt(first.getUTCFullYear(), first.getUTCMonth() + 1, 0).getUTCDate()))))
  }
  function unavailable(day: string) { return (props.min && day < String(props.min).slice(0, 10)) || (props.max && day > String(props.max).slice(0, 10)) }
  return <span className={`date-control ${className}`} ref={anchor}>
    <input {...props} type={type} value={value} ref={input} onChange={event => { close(); onChange?.(event) }} onKeyDown={event => {
      props.onKeyDown?.(event)
      if (!event.defaultPrevented && event.altKey && event.key === 'ArrowDown') { event.preventDefault(); show() }
    }} />
    <button ref={trigger} type="button" className="date-calendar-toggle" disabled={props.disabled || props.readOnly} aria-label="Takvimi aç" aria-expanded={open} aria-controls={open ? id : undefined} aria-haspopup="dialog" onClick={event => { event.preventDefault(); if (open) close(); else show() }}><Icon name="calendar" /></button>
    {open && createPortal(<div ref={popup} id={id} popover="manual" className="control-popup date-popup" role="dialog" aria-label="Tarih seç" onKeyDown={event => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(); input.current?.focus({ preventScroll: true }); return }
      if (!(event.target instanceof HTMLElement) || !event.target.dataset.date) return
      const day = parse(event.target.dataset.date), key = event.key
      const moves: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7, Home: -(day.getUTCDay() + 6) % 7, End: 6 - (day.getUTCDay() + 6) % 7 }
      if (key === 'PageUp' || key === 'PageDown') { event.preventDefault(); changeMonth(key === 'PageUp' ? -1 : 1) }
      else if (moves[key] !== undefined) { event.preventDefault(); setActive(iso(dateAt(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate() + moves[key]!))) }
    }}>
      <header className="calendar-header"><button type="button" className="calendar-arrow" aria-label="Önceki ay" onClick={() => changeMonth(-1)}><Icon name="back" /></button><h3 id={`${id}-month`}>{monthStart.toLocaleDateString('tr-TR', { month: 'long', year: 'numeric', timeZone: 'UTC' })}</h3><button type="button" className="calendar-arrow" aria-label="Sonraki ay" onClick={() => changeMonth(1)}><Icon name="arrow" /></button></header>
      <div role="grid" aria-labelledby={`${id}-month`}><div className="calendar-row calendar-weekdays" role="row">{['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'].map(day => <span key={day} role="columnheader">{day}</span>)}</div>
        {Array.from({ length: 6 }, (_, row) => <div key={row} className="calendar-row" role="row">{Array.from({ length: 7 }, (_, column) => {
          const date = dateAt(year, month, row * 7 + column - offset + 1), day = iso(date)
          return <button key={day} type="button" role="gridcell" data-date={day} aria-label={label(day)} aria-selected={day === (type === 'datetime-local' ? picked : selected)} aria-current={day === today() ? 'date' : undefined} disabled={Boolean(unavailable(day))} tabIndex={day === active ? 0 : -1} className={`calendar-day${date.getUTCMonth() !== month ? ' is-adjacent' : ''}`} onClick={() => { if (type === 'date') commit(day); else { setPicked(day); setActive(day) } }}>{date.getUTCDate()}</button>
        })}</div>)}
      </div>
      {type === 'datetime-local' && <label className="calendar-time">Saat<input ref={time} type="time" step={props.step ?? 60} value={hours} required onChange={event => setHours(event.target.value)} /></label>}
      <footer className="calendar-footer"><button type="button" className="calendar-today" disabled={Boolean(unavailable(today()))} onClick={() => { if (type === 'date') commit(today()); else { setPicked(today()); setActive(today()) } }}>Bugün</button><button type="button" className="calendar-done" onClick={() => { if (type === 'datetime-local' && picked && hours) commit(picked); else { close(); input.current?.focus({ preventScroll: true }) } }} disabled={type === 'datetime-local' && (!picked || !hours)}>{type === 'datetime-local' ? 'Uygula' : 'Kapat'}</button></footer>
    </div>, document.body)}
  </span>
}
