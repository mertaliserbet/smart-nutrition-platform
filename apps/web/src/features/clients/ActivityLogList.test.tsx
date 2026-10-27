import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'
import { ActivityLogList } from './ClientRecordViews'
import { getPreviewRecords, previewClients } from './clientTracking.preview'

const clientId = previewClients[0]!.id
const detailPath = `/onizleme/danisanlar/${clientId}`
const activityPath = `${detailPath}?kayit=aktiviteler`

function renderApp(path = activityPath) {
  render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return userEvent.setup()
}

describe('read-only activity history', () => {
  it('opens from the client navigation and shows units, source and unknown energy without requests or storage', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const storage = vi.spyOn(Storage.prototype, 'setItem')
    const user = renderApp(detailPath)
    await user.click(screen.getByRole('link', { name: 'Aktiviteler' }))
    expect(screen.getByRole('link', { name: 'Aktiviteler' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('heading', { name: 'Aktivite geçmişi' })).toBeVisible()
    const walking = screen.getByRole('article', { name: 'Yürüyüş (örnek)' })
    expect(within(walking).getByText('35,5 dk')).toBeVisible()
    expect(within(walking).getByText('3,2 km')).toBeVisible()
    expect(within(walking).getByText('Bilinmiyor')).toBeVisible()
    expect(within(walking).getByText('Manuel kayıt')).toBeVisible()
    expect(within(walking).queryByText('0 kcal')).not.toBeInTheDocument()
    const stretching = screen.getByRole('article', { name: 'Esneme (örnek)' })
    expect(within(stretching).getByText('0 km')).toBeVisible()
    expect(within(stretching).getByText('0 kcal')).toBeVisible()
    expect(screen.queryByRole('button', { name: /düzenle|sil|kaydet/i })).not.toBeInTheDocument()
    expect(request).not.toHaveBeenCalled()
    expect(storage).not.toHaveBeenCalled()
  })

  it('opens a direct activity URL and preserves the UTC timestamp', () => {
    renderApp()
    const latest = screen.getAllByRole('article')[0]!
    expect(latest).toHaveAccessibleName('Esneme (örnek)')
    expect(latest.querySelector('time')).toHaveAttribute('datetime', '2026-10-25T15:00:00Z')
    expect(screen.queryByText('Mercimek çorbası (örnek)')).not.toBeInTheDocument()
  })

  it('keeps missing duration and distance distinct from zero values', () => {
    const records = getPreviewRecords(clientId)!.activityLogs
    records[0] = { ...records[0]!, durationMinutes: null, distanceKm: null, caloriesKcal: null }
    render(<ActivityLogList clientId={clientId} records={records} />)
    const walking = screen.getByRole('article', { name: 'Yürüyüş (örnek)' })
    expect(within(walking).getAllByText('Bilinmiyor')).toHaveLength(3)
    expect(within(walking).queryByText(/^0 /)).not.toBeInTheDocument()
    expect(screen.getByText('0 km')).toBeVisible()
  })

  it('orders by actual start instants even with different UTC fractional precision, without mutating the input', () => {
    const records = getPreviewRecords(clientId)!.activityLogs
    records[0] = { ...records[0]!, startedAt: '2026-10-25T07:00:00Z' }
    records[1] = { ...records[1]!, startedAt: '2026-10-25T07:00:00.900Z' }
    render(<ActivityLogList clientId={clientId} records={records} />)
    expect(screen.getAllByRole('article').map((entry) => entry.querySelector('h3')?.textContent))
      .toEqual(['Esneme (örnek)', 'Yürüyüş (örnek)'])
    expect(records.map((entry) => entry.activityType)).toEqual(['Yürüyüş (örnek)', 'Esneme (örnek)'])
  })

  it('filters records owned by another client and presents a genuinely empty activity list', () => {
    const records = getPreviewRecords(clientId)!.activityLogs
    render(<ActivityLogList clientId={previewClients[1]!.id} records={records} />)
    expect(screen.getByText('Henüz aktivite kaydı yok')).toBeVisible()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Aktivite kayıtları')).not.toBeInTheDocument()
  })

  it('removes activity values in every unavailable scenario and keeps a restriction when switching views', async () => {
    const user = renderApp()
    const scenario = screen.getByRole('combobox', { name: 'Önizleme senaryosu' })
    const states = [
      ['empty', 'Henüz kayıt bulunmuyor'], ['disconnected', 'Veri bağlantısı bekleniyor'],
      ['loading', 'Kayıtlar yükleniyor…'], ['error', 'Kayıtlar görüntülenemedi'],
      ['restricted', 'Bu kayıtlar paylaşılmıyor'],
    ] as const
    for (const [value, message] of states) {
      await user.selectOptions(scenario, value)
      expect(screen.getByText(message)).toBeVisible()
      expect(screen.queryByLabelText('Aktivite kayıtları')).not.toBeInTheDocument()
      expect(screen.queryByText('35,5 dk')).not.toBeInTheDocument()
      expect(screen.queryByText('0 kcal')).not.toBeInTheDocument()
    }
    await user.click(screen.getByRole('link', { name: 'Su kayıtları' }))
    await user.click(screen.getByRole('link', { name: 'Aktiviteler' }))
    expect(screen.getByText('Bu kayıtlar paylaşılmıyor')).toBeVisible()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
    await user.selectOptions(scenario, 'sample')
    expect(screen.getByText('35,5 dk')).toBeVisible()
  })

  it('keeps the direct activity preview unavailable in production', () => {
    vi.stubEnv('DEV', false)
    renderApp()
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Bu sayfa bulunamadı.')
    expect(screen.queryByText('Yürüyüş (örnek)')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Aktivite kayıtları')).not.toBeInTheDocument()
  })
})
