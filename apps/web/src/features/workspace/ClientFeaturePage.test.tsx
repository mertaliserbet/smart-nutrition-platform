import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, useLocation, useNavigate } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'

const clients = Array.from({ length: 11 }, (_, index) => ({
  id: `10000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
  displayName: `Sentetik Danışan ${String(index + 1).padStart(2, '0')}`,
}))
const first = clients[0]!, second = clients[1]!, last = clients[10]!

function api() {
  return vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
    const url = new URL(String(input), window.location.origin), path = url.pathname
    if (path === '/api/v1/auth/csrf') return Response.json({ requestToken: 'synthetic-csrf' })
    if (path === '/api/v1/auth/me') return Response.json({ id: '20000000-0000-4000-8000-000000000001', displayName: 'Sentetik Uzman', email: 'synthetic@example.test', role: 'dietitian', isEmailVerified: true })
    if (path === '/api/v1/dietitians/me') return Response.json({ id: '30000000-0000-4000-8000-000000000001', displayName: 'Sentetik Uzman', isVerified: true })
    if (path === '/api/v1/dietitian/clients') {
      const query = url.searchParams.get('query') ?? ''
      const items = clients.filter(client => client.displayName.includes(query))
      const offset = (Number(url.searchParams.get('page')) - 1) * 10
      return Response.json({ items: items.slice(offset, offset + 10), totalCount: items.length })
    }
    const detail = path.match(/^\/api\/v1\/dietitian\/clients\/([^/]+)\/(dashboard|meal-logs|body-measurements)$/)
    if (detail) {
      const client = clients.find(client => client.id === detail[1])
      if (!client) return new Response(null, { status: 404 })
      return Response.json(detail[2] === 'dashboard' ? { clientId: client.id, displayName: client.displayName } : { items: [], totalCount: 0 })
    }
    if (path === '/api/v1/nutrition-plans') return Response.json({ items: [], totalCount: 0 })
    throw new Error(`Unexpected test request: ${path}`)
  })
}

function HistoryControls() {
  const location = useLocation(), navigate = useNavigate()
  return <><output data-testid="location">{location.pathname}{location.search}</output><button onClick={() => navigate(-1)}>Geri</button><button onClick={() => navigate(1)}>İleri</button></>
}
function page(path = '/calisma-alani/ogun-incelemeleri') {
  return { ...render(<MemoryRouter initialEntries={[path]}><App /><HistoryControls /></MemoryRouter>), user: userEvent.setup() }
}
async function selected(clientId: string) {
  await waitFor(() => expect(screen.getByRole('combobox', { name: 'Danışan seç' })).toHaveValue(clientId))
  await waitFor(() => expect(new URL(screen.getByTestId('location').textContent!, window.location.origin).searchParams.get('clientId')).toBe(clientId))
}

describe('client selection across workspace features', () => {
  it('keeps the chosen client across meals, plans, reports and back/forward navigation', async () => {
    api()
    const { user } = page()
    await selected(first.id)
    fireEvent.change(screen.getByRole('combobox', { name: 'Danışan seç' }), { target: { value: second.id } })
    await selected(second.id)
    const navigation = screen.getByRole('navigation', { name: 'Diyetisyen çalışma alanı' })
    await user.click(within(navigation).getByRole('link', { name: 'Programlar' }))
    await selected(second.id)
    await user.click(within(navigation).getByRole('link', { name: 'Raporlar' }))
    await selected(second.id)
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Raporlar')
    await user.click(screen.getByRole('button', { name: 'Geri' }))
    await selected(second.id)
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Programlar')
    await user.click(screen.getByRole('button', { name: 'İleri' }))
    await selected(second.id)
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Raporlar')
  })

  it('restores a client from a later list page after a full remount without changing to the first client', async () => {
    const request = api()
    const view = page()
    await selected(first.id)
    await view.user.click(screen.getByRole('button', { name: 'Sonraki danışanlar' }))
    await selected(last.id)
    const address = screen.getByTestId('location').textContent!
    view.unmount()
    request.mockClear()
    page(address)
    await selected(last.id)
    expect(request.mock.calls.some(([path]) => String(path).endsWith(`/clients/${last.id}/dashboard`))).toBe(true)
    expect(request.mock.calls.some(([path]) => String(path).includes(`/clients/${first.id}/meal-logs`))).toBe(false)
  })

  it('carries the client from their profile into a feature sidebar destination', async () => {
    api()
    const { user } = page(`/calisma-alani/danisanlar/${second.id}?bolum=program`)
    await screen.findByRole('heading', { level: 1, name: second.displayName })
    const meals = within(screen.getByRole('navigation', { name: 'Diyetisyen çalışma alanı' })).getByRole('link', { name: 'Öğün incelemeleri' })
    expect(meals).toHaveAttribute('href', `/calisma-alani/ogun-incelemeleri?clientId=${second.id}`)
    await user.click(meals)
    await selected(second.id)
  })

  it('carries the first search result into another feature even when search filters reset', async () => {
    api()
    const { user } = page()
    await selected(first.id)
    fireEvent.change(screen.getByRole('searchbox', { name: 'Danışan ara' }), { target: { value: last.displayName } })
    fireEvent.submit(screen.getByRole('form', { name: 'Bölümde danışan ara' }))
    await selected(last.id)
    await user.click(within(screen.getByRole('navigation', { name: 'Diyetisyen çalışma alanı' })).getByRole('link', { name: 'Programlar' }))
    await selected(last.id)
    expect(screen.getByRole('option', { name: last.displayName })).toBeInTheDocument()
  })

  it.each(['not-a-client-id', '90000000-0000-4000-8000-000000000009'])('never substitutes another client for inaccessible URL selection %s', async clientId => {
    const request = api()
    const { user } = page(`/calisma-alani/ogun-incelemeleri?clientId=${clientId}`)
    expect(await screen.findByRole('alert')).toHaveTextContent(/bulunamadı/)
    expect(screen.queryByText('Aktif bağlantı')).not.toBeInTheDocument()
    expect(request.mock.calls.some(([path]) => /\/meal-logs/.test(String(path)))).toBe(false)
    await user.click(screen.getByRole('button', { name: 'Seçimi temizle' }))
    await selected(first.id)
  })

  it('requires confirmation before replacing an edited program with another client', async () => {
    api()
    const { user } = page(`/calisma-alani/programlar?clientId=${first.id}`)
    await selected(first.id)
    await user.click(await screen.findByRole('button', { name: 'Yeni program oluştur' }))
    fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: 'Kaydedilmemiş sentetik taslak' } })
    fireEvent.change(screen.getByRole('combobox', { name: 'Danışan seç' }), { target: { value: second.id } })
    expect(screen.getByRole('alertdialog')).toHaveTextContent('Kaydedilmemiş program değişiklikleri')
    await user.click(screen.getByRole('button', { name: 'Düzenlemeye dön' }))
    await selected(first.id)
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Kaydedilmemiş sentetik taslak')
    fireEvent.change(screen.getByRole('combobox', { name: 'Danışan seç' }), { target: { value: second.id } })
    await user.click(screen.getByRole('button', { name: 'Değişiklikleri sil ve devam et' }))
    await selected(second.id)
    expect(screen.queryByDisplayValue('Kaydedilmemiş sentetik taslak')).not.toBeInTheDocument()
  })

  it('retains the existing unsaved-program guard when following a feature sidebar link', async () => {
    api()
    const { user } = page(`/calisma-alani/programlar?clientId=${second.id}`)
    await selected(second.id)
    await user.click(await screen.findByRole('button', { name: 'Yeni program oluştur' }))
    fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: 'Sentetik taslak' } })
    const reports = within(screen.getByRole('navigation', { name: 'Diyetisyen çalışma alanı' })).getByRole('link', { name: 'Raporlar' })
    await user.click(reports)
    expect(screen.getByRole('alertdialog')).toHaveTextContent('Kaydedilmemiş değişiklikler')
    await user.click(screen.getByRole('button', { name: 'Düzenlemeye dön' }))
    await selected(second.id)
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Sentetik taslak')
    await user.click(reports)
    await user.click(screen.getByRole('button', { name: 'Değişiklikleri sil' }))
    await selected(second.id)
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Raporlar')
  })
})
