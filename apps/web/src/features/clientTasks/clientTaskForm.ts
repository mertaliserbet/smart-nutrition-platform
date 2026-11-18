import type { ClientTaskResponse } from './clientTaskApi'

export type TaskDraft = { original?: ClientTaskResponse; description: string; dueInput: string }
export function localTaskTime(instant: string | null): string {
  if (!instant) return ''
  const date = new Date(instant)
  const two = (value: number) => String(value).padStart(2, '0')
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}T${two(date.getHours())}:${two(date.getMinutes())}:${two(date.getSeconds())}`
}
export function taskDraft(original?: ClientTaskResponse): TaskDraft { return { original, description: original?.description ?? '', dueInput: localTaskTime(original?.dueAt ?? null) } }
export function isDirtyDraft(draft: TaskDraft) { return draft.description !== (draft.original?.description ?? '') || draft.dueInput !== localTaskTime(draft.original?.dueAt ?? null) }
export function taskContent(draft: TaskDraft): { description: string; dueAt: string | null } {
  const description = draft.description.trim()
  if (!description || description.includes('\0') || [...description].length > 2000) throw new Error('Açıklama 1–2000 karakter olmalı ve yalnız boşluk içermemeli.')
  if (!draft.dueInput) return { description, dueAt: null }
  // datetime-local may normalize seconds to an explicit .000 (including in DOM tests).
  const parts = /^(\d{4}-\d\d-\d\dT\d\d:\d\d)(?::(\d\d)(?:\.(\d{1,3}))?)?$/.exec(draft.dueInput)
  if (!parts) throw new Error('Geçerli bir yerel tarih ve saat seçin.')
  const localSeconds = `${parts[1]}:${parts[2] ?? '00'}`
  const milliseconds = Number((parts[3] ?? '').padEnd(3, '0'))
  if (milliseconds === 0 && localSeconds === localTaskTime(draft.original?.dueAt ?? null)) return { description, dueAt: draft.original?.dueAt ?? null }
  const date = new Date(draft.dueInput)
  if (!Number.isFinite(date.getTime()) || localTaskTime(date.toISOString()) !== localSeconds || date.getMilliseconds() !== milliseconds)
    throw new Error('Geçerli bir yerel tarih ve saat seçin.')
  if (date.getTime() <= Date.now()) throw new Error('Yeni son tarih gelecekte olmalı.')
  return { description, dueAt: date.toISOString() }
}
