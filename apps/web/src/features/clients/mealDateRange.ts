import { localDayRange } from '../nutritionPlans/mealComparisonApi'
import { localDateInput } from './waterLogApi'

export type MealPeriod = 'today' | 'yesterday' | 'week'
export function mealDateRange(first: string, last: string) {
  if (!first || !last || first > last) throw new Error('Geçerli bir başlangıç ve bitiş günü seçin; bitiş başlangıçtan önce olamaz.')
  const start = localDayRange(first), end = localDayRange(last)
  return { from: new Date(start.from).toISOString(), to: new Date(end.to).toISOString() }
}
export function mealPeriodRange(period: MealPeriod, now = new Date()) {
  const first = new Date(now), last = new Date(now)
  if (period === 'yesterday') { first.setDate(first.getDate() - 1); last.setDate(last.getDate() - 1) }
  if (period === 'week') first.setDate(first.getDate() - 6)
  return mealDateRange(localDateInput(first), localDateInput(last))
}
