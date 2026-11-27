import { render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { LabReportList } from './ClientRecordViews'
import { getPreviewRecords, previewClients } from '../../test/clientTrackingFixtures'
import type { LabResult } from './clientTracking.types'

const clientId = previewClients[0]!.id

function resultReport(overrides: Partial<LabResult> = {}) {
  const report = getPreviewRecords(clientId)!.labReports[1]!
  return { ...report, results: [{ ...report.results[0]!, ...overrides }] }
}

describe('read-only lab report history', () => {
  it('shows units, genuine zero references and no requests or storage', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const storage = vi.spyOn(Storage.prototype, 'setItem')
    render(<LabReportList clientId={clientId} records={getPreviewRecords(clientId)!.labReports} />)
    const report = screen.getByRole('article', { name: 'Örnek laboratuvar' })
    const zero = within(report).getByRole('listitem', { name: 'Örnek analit A' })
    expect(within(zero).getAllByText('0 birim')).toHaveLength(2)
    expect(within(zero).getByText('5 birim')).toBeVisible()
    expect(within(zero).getByText('Referans aralığında')).toBeVisible()
    const partial = within(report).getByRole('listitem', { name: 'Örnek analit C' })
    expect(within(partial).getByText('1,2 birim')).toBeVisible()
    expect(within(partial).getByText('Bilinmiyor')).toBeVisible()
    expect(within(partial).getByText('Değerlendirilemiyor')).toBeVisible()
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

})
