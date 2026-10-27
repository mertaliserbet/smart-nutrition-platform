import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'
import { LabReportList } from './ClientRecordViews'
import { getPreviewRecords, previewClients } from './clientTracking.preview'
import type { LabResult } from './clientTracking.types'

const clientId = previewClients[0]!.id
const detailPath = `/onizleme/danisanlar/${clientId}`
const labPath = `${detailPath}?kayit=tahliller`

function renderApp(path = labPath) {
  render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return userEvent.setup()
}

function resultReport(overrides: Partial<LabResult> = {}) {
  const report = getPreviewRecords(clientId)!.labReports[1]!
  return { ...report, results: [{ ...report.results[0]!, ...overrides }] }
}

describe('read-only lab report history', () => {
  it('opens from navigation with units, genuine zero references and no requests or storage', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const storage = vi.spyOn(Storage.prototype, 'setItem')
    const user = renderApp(detailPath)
    await user.click(screen.getByRole('link', { name: 'Tahliller' }))
    expect(screen.getByRole('link', { name: 'Tahliller' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('heading', { name: 'Tahlil geçmişi' })).toBeVisible()
    const report = screen.getByRole('article', { name: 'Örnek laboratuvar' })
    const zero = within(report).getByRole('listitem', { name: 'Örnek analit A' })
    expect(within(zero).getAllByText('0 birim')).toHaveLength(2)
    expect(within(zero).getByText('5 birim')).toBeVisible()
    expect(within(zero).getByText('Referans aralığında')).toBeVisible()
    const partial = within(report).getByRole('listitem', { name: 'Örnek analit C' })
    expect(within(partial).getByText('1,2 birim')).toBeVisible()
    expect(within(partial).getByText('Bilinmiyor')).toBeVisible()
    expect(within(partial).getByText('Değerlendirilemiyor')).toBeVisible()
    expect(screen.getByText(/tahliller için ayrıca açık onay gerekir/)).toBeVisible()
    expect(screen.queryByRole('button', { name: /düzenle|sil|kaydet|analiz|yükle/i })).not.toBeInTheDocument()
    expect(request).not.toHaveBeenCalled()
    expect(storage).not.toHaveBeenCalled()
  })

  it('sorts actual collection instants without mutating the input and preserves UTC timestamps', () => {
    const reports = getPreviewRecords(clientId)!.labReports
    reports[0] = { ...reports[0]!, collectedAt: '2026-10-25T07:00:00Z' }
    reports[1] = { ...reports[1]!, collectedAt: '2026-10-25T07:00:00.900Z' }
    render(<LabReportList clientId={clientId} records={reports} />)
    expect(screen.getAllByRole('article')[0]).toHaveAccessibleName('Örnek laboratuvar')
    expect(screen.getAllByRole('article')[0]!.querySelector('time'))
      .toHaveAttribute('datetime', '2026-10-25T07:00:00.900Z')
    expect(reports[0]!.labName).toBeNull()
    expect(screen.getByRole('article', { name: 'Laboratuvar belirtilmemiş' })).toBeVisible()
  })

  it('excludes another client and a result linked to a different report', () => {
    const own = resultReport()
    own.results.push({ ...own.results[0]!, id: 'foreign-result', labReportId: 'another-report', testName: 'Başka raporun analiti' })
    const foreign = { ...resultReport(), id: 'foreign-report', clientId: previewClients[1]!.id, labName: 'Başka danışanın laboratuvarı', note: 'Başka danışanın notu' }
    render(<LabReportList clientId={clientId} records={[own, foreign]} />)
    expect(screen.getAllByRole('article')).toHaveLength(1)
    expect(screen.getByText('Örnek analit A')).toBeVisible()
    expect(screen.queryByText('Başka raporun analiti')).not.toBeInTheDocument()
    expect(screen.queryByText('Başka danışanın laboratuvarı')).not.toBeInTheDocument()
    expect(screen.queryByText('Başka danışanın notu')).not.toBeInTheDocument()
  })

  it('shows an empty report list after ownership filtering', () => {
    render(<LabReportList clientId={previewClients[1]!.id} records={getPreviewRecords(clientId)!.labReports} />)
    expect(screen.getByText('Henüz tahlil raporu yok')).toBeVisible()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
  })

  it.each([
    { referenceLow: null, referenceHigh: 5 },
    { referenceLow: 0, referenceHigh: null },
    { unit: ' ' },
    { referenceLow: 5, referenceHigh: 0 },
  ])('suppresses an assessment with missing or invalid context: %j', (context) => {
    render(<LabReportList clientId={clientId} records={[resultReport({ flag: 'high', ...context })]} />)
    expect(screen.getByText('Değerlendirilemiyor')).toBeVisible()
    expect(screen.queryByText('Üst referansın üzerinde')).not.toBeInTheDocument()
    expect(screen.queryByText('Referans aralığında')).not.toBeInTheDocument()
  })

  it('retains an unknown server flag even with a complete reference and displays an existing test code', () => {
    render(<LabReportList clientId={clientId} records={[resultReport({ flag: 'unknown', testCode: 'sentetik-kod' })]} />)
    expect(screen.getByText('Değerlendirilemiyor')).toBeVisible()
    expect(screen.queryByText('Referans aralığında')).not.toBeInTheDocument()
    expect(screen.getByText('Kayıttaki kod: sentetik-kod')).toBeVisible()
  })

  it.each([
    ['low', -1, 'Alt referansın altında'],
    ['high', 6, 'Üst referansın üzerinde'],
  ] as const)('displays the supplied %s flag without adding a diagnosis', (flag, value, label) => {
    render(<LabReportList clientId={clientId} records={[resultReport({ flag, value })]} />)
    expect(screen.getByText(label)).toBeVisible()
    expect(screen.getByText(/bu görünüm tanı veya tedavi önerisi üretmez/)).toBeVisible()
  })

  it('hides report values in unavailable states and preserves restrictions across record views', async () => {
    const user = renderApp()
    const scenario = screen.getByRole('combobox', { name: 'Önizleme senaryosu' })
    expect(screen.getByRole('article', { name: 'Örnek laboratuvar' })).toBeVisible()
    for (const [value, message] of [
      ['empty', 'Henüz kayıt bulunmuyor'], ['disconnected', 'Veri bağlantısı bekleniyor'],
      ['loading', 'Kayıtlar yükleniyor…'], ['error', 'Kayıtlar görüntülenemedi'],
      ['restricted', 'Bu kayıtlar paylaşılmıyor'],
    ] as const) {
      await user.selectOptions(scenario, value)
      expect(screen.getByText(message)).toBeVisible()
      expect(screen.queryByLabelText('Tahlil raporları')).not.toBeInTheDocument()
      expect(screen.queryByText('Örnek laboratuvar')).not.toBeInTheDocument()
      expect(screen.queryByText('0 birim')).not.toBeInTheDocument()
    }
    await user.click(screen.getByRole('link', { name: 'Aktiviteler' }))
    await user.click(screen.getByRole('link', { name: 'Tahliller' }))
    expect(screen.getByText('Bu kayıtlar paylaşılmıyor')).toBeVisible()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
    await user.selectOptions(scenario, 'sample')
    expect(screen.getByRole('article', { name: 'Örnek laboratuvar' })).toBeVisible()
  })

  it('blocks the direct lab preview URL in production', () => {
    vi.stubEnv('DEV', false)
    renderApp()
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Bu sayfa bulunamadı.')
    expect(screen.queryByLabelText('Tahlil raporları')).not.toBeInTheDocument()
  })
})
