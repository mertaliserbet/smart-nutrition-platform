import { render, screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { BodyMeasurementList, MealLogList, WaterLogList } from './ClientRecordViews'
import { getPreviewRecords, previewClients } from '../../test/clientTrackingFixtures'

const firstClient = previewClients[0]!

describe('read-only client records', () => {
  it.each([
    ['2026-10-25T09:00:00Z', '2026-10-25T09:00:00.001Z'],
    ['2026-10-25T09:00:00.001Z', '2026-10-25T09:00:00.001001Z'],
    ['2026-10-25T12:00:00+03:00', '2026-10-25T09:00:00.001Z'],
  ])('shows the newer meal first for %s and %s', (olderTime, newerTime) => {
    const records = getPreviewRecords(firstClient.id)!
    const older = { ...records.mealLogs[0]!, consumedAt: olderTime }
    const newer = { ...records.mealLogs[1]!, consumedAt: newerTime }
    render(<MealLogList clientId={firstClient.id} records={[older, newer]} />)

    const meals = screen.getAllByRole('article')
    expect(meals.map(meal => meal.querySelector('time')?.dateTime)).toEqual([newer.consumedAt, older.consumedAt])
  })

  it('keeps unknown meal values separate from genuine zero values and labels estimates', () => {
    render(<MealLogList clientId={firstClient.id} records={getPreviewRecords(firstClient.id)!.mealLogs} />)
    const unknownItem = screen.getByText('Salata (örnek)').closest('li')!
    expect(within(unknownItem).getAllByText('Bilinmiyor')).toHaveLength(5)
    expect(within(unknownItem).queryByText('0 kcal')).not.toBeInTheDocument()
    expect(within(unknownItem).getByText('Tahmini')).toBeVisible()
    const zeroItem = screen.getByText('Şekersiz çay (örnek)').closest('li')!
    expect(within(zeroItem).getByText('0 kcal')).toBeVisible()
    expect(within(zeroItem).getAllByText('0 g')).toHaveLength(3)
    expect(within(zeroItem).queryByText('Tahmini')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /düzenle|sil|kaydet/i })).not.toBeInTheDocument()
  })

  it('shows water and measurement units and retains UTC source timestamps', () => {
    const records = getPreviewRecords(firstClient.id)!
    render(<><WaterLogList clientId={firstClient.id} records={records.waterLogs} /><BodyMeasurementList clientId={firstClient.id} records={records.bodyMeasurements} /></>)
    expect(screen.getByText('400 mL')).toBeVisible()
    expect(screen.getByText('250 mL')).toBeVisible()
    expect(document.querySelector('time')).toHaveAttribute('datetime', '2026-10-25T10:00:00Z')
    expect(screen.getByText('72,1 kg')).toBeVisible()
    expect(screen.getByText('83,1 cm')).toBeVisible()
    expect(screen.getAllByText('Bilinmiyor')).toHaveLength(7)
    expect(screen.queryByText('0 %')).not.toBeInTheDocument()
  })

  it('does not render records belonging to a different client', () => {
    const records = getPreviewRecords(firstClient.id)!
    render(<MealLogList clientId={previewClients[1]!.id} records={records.mealLogs} />)
    expect(screen.getByText('Henüz öğün kaydı yok')).toBeVisible()
    expect(screen.queryByText('Mercimek çorbası (örnek)')).not.toBeInTheDocument()
  })

  it('does not render a food item attached to another meal', () => {
    const records = getPreviewRecords(firstClient.id)!
    records.mealLogs[0]!.items.push({ ...records.mealLogs[0]!.items[0]!, id: '30000000-0000-4000-8000-000000000001', mealLogId: '30000000-0000-4000-8000-000000000002', displayName: 'Başka öğünün kalemi' })
    render(<MealLogList clientId={firstClient.id} records={records.mealLogs} />)
    expect(screen.queryByText('Başka öğünün kalemi')).not.toBeInTheDocument()
    expect(screen.getByText('Mercimek çorbası (örnek)')).toBeVisible()
  })
})
