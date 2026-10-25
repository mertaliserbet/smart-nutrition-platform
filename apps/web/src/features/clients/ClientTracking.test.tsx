import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'
import { MealLogList } from './ClientRecordViews'
import { getPreviewRecords, previewClients } from './clientTracking.preview'

const firstClient = previewClients[0]!
const detailPath = `/onizleme/danisanlar/${firstClient.id}`
function renderApp(path = '/onizleme/danisanlar') {
  const user = userEvent.setup()
  render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return user
}
function sampleListNames() {
  return within(screen.getByRole('list', { name: 'Örnek danışanlar' })).getAllByRole('link').map((link) => link.textContent)
}

describe('client list preview', () => {
  it('searches Turkish dotted and dotless letters and trims query whitespace', async () => {
    const user = renderApp()
    const search = screen.getByRole('searchbox', { name: 'Danışan ara' })
    await user.type(search, '  İPEK  ')
    expect(sampleListNames()).toHaveLength(1)
    expect(sampleListNames()[0]).toContain('Örnek İpek')
    await user.clear(search)
    await user.type(search, 'IŞIK')
    expect(sampleListNames()).toHaveLength(1)
    expect(sampleListNames()[0]).toContain('Örnek Işık')
  })

  it('sorts Turkish names and restores the search after visiting a profile', async () => {
    const user = renderApp()
    expect(sampleListNames()[0]).toContain('Örnek Çağla')
    await user.selectOptions(screen.getByRole('combobox', { name: 'Sıralama' }), 'za')
    expect(sampleListNames()[0]).toContain('Örnek Şule')
    await user.type(screen.getByRole('searchbox', { name: 'Danışan ara' }), 'ipek')
    await user.click(screen.getByRole('link', { name: /Örnek İpek/ }))
    expect(screen.getByRole('heading', { level: 1, name: 'Örnek İpek' })).toHaveFocus()
    await user.click(screen.getByRole('link', { name: 'Danışan listesine dön' }))
    expect(screen.getByRole('searchbox', { name: 'Danışan ara' })).toHaveValue('ipek')
    expect(screen.getByRole('combobox', { name: 'Sıralama' })).toHaveValue('za')
    expect(sampleListNames()).toHaveLength(1)
  })

  it('reads direct search URLs and recovers from a search with no matches', async () => {
    const user = renderApp('/onizleme/danisanlar?arama=bulunamayan&sirala=za')
    expect(screen.getByText('Aramanızla eşleşen danışan yok')).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Aramayı temizle' }))
    expect(sampleListNames()).toHaveLength(6)
    expect(sampleListNames()[0]).toContain('Örnek Şule')
  })

  it('distinguishes an empty result, no connection, loading and an access restriction', async () => {
    const user = renderApp()
    const scenario = screen.getByRole('combobox', { name: 'Önizleme senaryosu' })
    await user.selectOptions(scenario, 'empty')
    expect(screen.getByText('Henüz danışan bulunmuyor')).toBeVisible()
    expect(screen.queryByRole('list', { name: 'Örnek danışanlar' })).not.toBeInTheDocument()
    await user.selectOptions(scenario, 'disconnected')
    expect(screen.getByText('Veri bağlantısı bekleniyor')).toBeVisible()
    expect(screen.queryByText('Henüz danışan bulunmuyor')).not.toBeInTheDocument()
    await user.selectOptions(scenario, 'loading')
    expect(screen.getByRole('status')).toHaveTextContent('Kayıtlar yükleniyor')
    await user.selectOptions(scenario, 'restricted')
    expect(screen.getByText('Danışan listesine erişilemiyor')).toBeVisible()
    expect(screen.queryByText('Örnek Deniz')).not.toBeInTheDocument()
    expect(screen.queryByText(/örnek danışan gösteriliyor/)).not.toBeInTheDocument()
  })
})

describe('read-only client records', () => {
  it('keeps unknown meal values separate from genuine zero values and labels estimates', () => {
    renderApp(detailPath)
    const unknownItem = screen.getByText('Salata (örnek)').closest('li')!
    expect(within(unknownItem).getAllByText('Bilinmiyor')).toHaveLength(5)
    expect(within(unknownItem).queryByText('0 kcal')).not.toBeInTheDocument()
    expect(within(unknownItem).getByText('Tahmini')).toBeVisible()
    const zeroItem = screen.getByText('Şekersiz çay (örnek)').closest('li')!
    expect(within(zeroItem).getByText('0 kcal')).toBeVisible()
    expect(within(zeroItem).getAllByText('0 g')).toHaveLength(3)
    expect(within(zeroItem).queryByText('Tahmini')).not.toBeInTheDocument()
    expect(screen.getByText('Salt okunur')).toBeVisible()
    expect(screen.queryByRole('button', { name: /düzenle|sil|kaydet/i })).not.toBeInTheDocument()
  })

  it('shows water and measurement units and retains UTC source timestamps', async () => {
    const user = renderApp(detailPath)
    await user.click(screen.getByRole('link', { name: 'Su kayıtları' }))
    expect(screen.getByRole('link', { name: 'Su kayıtları' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByText('400 mL')).toBeVisible()
    expect(screen.getByText('250 mL')).toBeVisible()
    expect(document.querySelector('time')).toHaveAttribute('datetime', '2026-10-25T10:00:00Z')
    await user.click(screen.getByRole('link', { name: 'Ölçümler' }))
    expect(screen.getByText('72,1 kg')).toBeVisible()
    expect(screen.getByText('83,1 cm')).toBeVisible()
    expect(screen.getAllByText('Bilinmiyor')).toHaveLength(3)
    expect(screen.queryByText('0 %')).not.toBeInTheDocument()
  })

  it('removes every record value when sharing is closed, including after changing views', async () => {
    const user = renderApp(detailPath)
    const scenario = screen.getByRole('combobox', { name: 'Önizleme senaryosu' })
    expect(screen.getByText('Mercimek çorbası (örnek)')).toBeVisible()
    await user.selectOptions(scenario, 'restricted')
    expect(screen.getByText('Bu kayıtlar paylaşılmıyor')).toBeVisible()
    expect(screen.queryByText('Mercimek çorbası (örnek)')).not.toBeInTheDocument()
    expect(screen.queryByText('180 kcal')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Öğün kayıtları')).not.toBeInTheDocument()
    await user.click(screen.getByRole('link', { name: 'Su kayıtları' }))
    expect(screen.getByText('Bu kayıtlar paylaşılmıyor')).toBeVisible()
    expect(screen.queryByText('250 mL')).not.toBeInTheDocument()
    await user.selectOptions(scenario, 'sample')
    expect(screen.getByText('250 mL')).toBeVisible()
  })

  it('presents a connection error without network or storage and explicitly returns to sample mode', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const store = vi.spyOn(Storage.prototype, 'setItem')
    const user = renderApp(detailPath)
    await user.selectOptions(screen.getByRole('combobox', { name: 'Önizleme senaryosu' }), 'error')
    expect(screen.getByRole('alert')).toHaveTextContent('Kayıtlar görüntülenemedi')
    expect(screen.queryByText('180 kcal')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Örnek görünümüne dön' }))
    expect(screen.getByRole('combobox', { name: 'Önizleme senaryosu' })).toHaveValue('sample')
    expect(screen.getByText('180 kcal')).toBeVisible()
    expect(request).not.toHaveBeenCalled()
    expect(store).not.toHaveBeenCalled()
  })

  it('supports direct record URLs without first opening the client list', () => {
    renderApp(`${detailPath}?kayit=olcumler`)
    expect(screen.getByRole('heading', { name: 'Ölçüm geçmişi' })).toBeVisible()
    expect(screen.queryByText('Mercimek çorbası (örnek)')).not.toBeInTheDocument()
  })

  it('does not substitute an existing client when a URL ID is unknown', () => {
    const request = vi.spyOn(globalThis, 'fetch')
    renderApp('/onizleme/danisanlar/90000000-0000-4000-8000-000000000009')
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Danışan bulunamadı.')
    expect(screen.queryByRole('navigation', { name: 'Kayıt türü' })).not.toBeInTheDocument()
    expect(screen.queryByText('180 kcal')).not.toBeInTheDocument()
    expect(request).not.toHaveBeenCalled()
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
