import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { ClientTaskPanel } from './ClientTaskPanel'
import { cancelClientTask, getClientTask, getClientTasks, getClientTaskVersions, saveClientTask } from './clientTaskApi'
import type { ClientTaskResponse, ClientTaskVersionResponse } from './clientTaskApi'
import { localTaskTime, taskContent, taskDraft } from './clientTaskForm'

const clientId = '11111111-1111-4111-8111-111111111111'
const expertId = '22222222-2222-4222-8222-222222222222'
const taskId = '33333333-3333-4333-8333-333333333333'
const relationId = '44444444-4444-4444-8444-444444444444'
const other = '99999999-9999-4999-8999-999999999999'
const text = 'Sentetik özel görev'
const signal = () => new AbortController().signal
const task = (values: Partial<ClientTaskResponse> = {}): ClientTaskResponse => ({ id: taskId, clientId, dietitianId: expertId, relationshipId: relationId, description: text,
  status: 'pending', dueAt: '2030-06-15T12:30:00Z', isReminderEnabled: false, createdAt: '2026-11-18T09:00:00Z', updatedAt: '2026-11-18T09:00:00Z', versionNumber: 1, ...values })
const version = (snapshot = task()): ClientTaskVersionResponse => ({ id: `55555555-5555-4555-8555-${String(snapshot.versionNumber).padStart(12, '0')}`, clientTaskId: snapshot.id, versionNumber: snapshot.versionNumber, createdAt: snapshot.updatedAt, snapshot })
function panel(id = clientId, token = 'synthetic-csrf', onFailure = vi.fn(() => false)) {
  return <WorkspaceContext.Provider value={{ token, dietitianId: expertId, onFailure }}><ClientTaskPanel clientId={id} /></WorkspaceContext.Provider>
}
function server(initial = task()) {
  const state = { rows: [initial], history: [version(initial)], denied: 0, writeError: 0, networkWrite: false }
  const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, options) => {
    const url = new URL(String(input), 'https://localhost')
    if (state.denied) return new Response(null, { status: state.denied })
    if (options?.method === 'POST' || options?.method === 'PATCH') {
      if (state.networkWrite) throw new TypeError('Synthetic connection loss')
      if (state.writeError) return new Response(null, { status: state.writeError })
      const body = JSON.parse(String(options.body))
      const created = options.method === 'POST'
      const current = state.rows[0] ?? task()
      const changed = task({ ...current, ...body, versionNumber: created ? 1 : current.versionNumber + 1, updatedAt: '2026-11-19T09:00:00Z', isReminderEnabled: body.dueAt === null ? false : current.isReminderEnabled })
      Reflect.deleteProperty(changed, 'expectedVersionNumber')
      state.rows = [changed]; state.history = [version(changed), ...(created ? [] : state.history)]
      return Response.json(changed, { status: created ? 201 : 200 })
    }
    const start = (Number(url.searchParams.get('page') ?? '1') - 1) * 10
    if (url.pathname.endsWith('/versions')) return Response.json({ items: state.history.slice(start, start + 10), totalCount: state.history.length })
    if (url.pathname === '/api/v1/client-tasks') return Response.json({ items: state.rows.slice(start, start + 10), totalCount: state.rows.length })
    return Response.json(state.rows.find(row => url.pathname.endsWith(`/${row.id}`)) ?? state.rows[0])
  })
  return { state, request }
}
async function detail(user: ReturnType<typeof userEvent.setup>) {
  await screen.findByText(text)
  await user.click(screen.getByRole('button', { name: `Görev detayını aç: ${text}` }))
  return screen.findByRole('region', { name: 'Görev detayı' })
}

describe('ClientTask U1 contract', () => {
  it('uses cookie expert context, canonical paths, paging, CSRF and exact request DTOs', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ items: [task()], totalCount: 1 }))
      .mockResolvedValueOnce(Response.json(task())).mockResolvedValueOnce(Response.json({ items: [version()], totalCount: 1 }))
      .mockResolvedValueOnce(Response.json(task(), { status: 201 })).mockResolvedValueOnce(Response.json(task({ versionNumber: 2, dueAt: null })))
      .mockResolvedValueOnce(Response.json(task({ status: 'cancelled', versionNumber: 2 })))
    await getClientTasks(clientId, expertId, 1, signal()); await getClientTask(clientId, expertId, taskId, signal()); await getClientTaskVersions(task(), 1, signal())
    await saveClientTask(clientId, expertId, { description: text, dueAt: null }, 'csrf', signal())
    await saveClientTask(clientId, expertId, { description: text, dueAt: null }, 'csrf', signal(), task())
    await cancelClientTask(task(), 'csrf', signal())
    const list = new URL(String(request.mock.calls[0]![0]), 'https://localhost')
    expect(list.pathname).toBe('/api/v1/client-tasks'); expect(Object.fromEntries(list.searchParams)).toEqual({ clientId, page: '1', pageSize: '10' })
    expect(request.mock.calls[1]![0]).toBe(`/api/v1/client-tasks/${taskId}`)
    expect(request.mock.calls[2]![0]).toBe(`/api/v1/client-tasks/${taskId}/versions?page=1&pageSize=10`)
    expect(JSON.parse(String(request.mock.calls[3]![1]!.body))).toEqual({ clientId, description: text, dueAt: null })
    expect(JSON.parse(String(request.mock.calls[4]![1]!.body))).toEqual({ expectedVersionNumber: 1, description: text, dueAt: null })
    expect(JSON.parse(String(request.mock.calls[5]![1]!.body))).toEqual({ expectedVersionNumber: 1, status: 'cancelled' })
    for (const [, options] of request.mock.calls) {
      expect(options).toMatchObject({ credentials: 'same-origin', cache: 'no-store', redirect: 'error' })
      const headers = new Headers(options?.headers); expect(headers.get('X-Profile-Context')).toBe('dietitian'); expect(headers.has('Authorization')).toBe(false)
      if (options?.method !== 'GET') expect(headers.get('X-CSRF-TOKEN')).toBe('csrf')
    }
  })
  it.each(['client', 'expert', 'unknownStatus', 'missingDue', 'stringVersion', 'missingReminder', 'time', 'duplicate', 'count'])('rejects foreign/malformed %s response', async scenario => {
    const row = task()
    if (scenario === 'client') row.clientId = other
    if (scenario === 'expert') row.dietitianId = other
    if (scenario === 'unknownStatus') Reflect.set(row, 'status', 'overdue')
    if (scenario === 'missingDue') Reflect.deleteProperty(row, 'dueAt')
    if (scenario === 'missingReminder') Reflect.deleteProperty(row, 'isReminderEnabled')
    if (scenario === 'stringVersion') Reflect.set(row, 'versionNumber', '1')
    if (scenario === 'time') row.updatedAt = '2026-11-18T09:00:00'
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json({ items: scenario === 'duplicate' ? [row, row] : [row], totalCount: scenario === 'count' ? 0 : 2 }))
    await expect(getClientTasks(clientId, expertId, 1, signal())).rejects.toMatchObject({ status: 500 })
  })
  it.each(['foreignTask', 'foreignSnapshot', 'wrongVersion', 'duplicateVersion', 'missingSnapshot'])('rejects inconsistent %s history', async scenario => {
    const row = version()
    if (scenario === 'foreignTask') row.clientTaskId = other
    if (scenario === 'foreignSnapshot') row.snapshot.id = other
    if (scenario === 'wrongVersion') row.snapshot.versionNumber = 2
    if (scenario === 'missingSnapshot') Reflect.deleteProperty(row, 'snapshot')
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json({ items: scenario === 'duplicateVersion' ? [row, { ...row, id: other }] : [row], totalCount: 2 }))
    await expect(getClientTaskVersions(task(), 1, signal())).rejects.toMatchObject({ status: 500 })
  })
  it('converts local input to UTC and preserves unchanged server microseconds and past due dates', () => {
    const input = '2030-06-15T15:30:00'
    expect(taskContent({ description: ` ${text} `, dueInput: input })).toEqual({ description: text, dueAt: new Date(input).toISOString() })
    const old = task({ dueAt: '2026-11-18T09:00:01.123456Z' })
    expect(taskContent({ ...taskDraft(old), description: 'Düzenlendi' }).dueAt).toBe(old.dueAt)
    expect(taskContent({ ...taskDraft(old), dueInput: taskDraft(old).dueInput + '.000' }).dueAt).toBe(old.dueAt)
    expect(taskContent({ description: text, dueInput: input + '.000' }).dueAt).toBe(new Date(input).toISOString())
    expect(taskContent({ ...taskDraft(old), dueInput: '' }).dueAt).toBeNull()
    expect(() => taskContent({ description: ' ', dueInput: '' })).toThrow('1–2000')
    expect(() => taskContent({ description: 'x'.repeat(2001), dueInput: '' })).toThrow('1–2000')
    expect(() => taskContent({ description: text, dueInput: '2020-01-01T12:00' })).toThrow('gelecekte')
    expect(() => taskContent({ description: text, dueInput: '2030-02-30T12:00' })).toThrow('Geçerli')
    expect(taskContent({ description: '🥣'.repeat(2000), dueInput: '' }).description).toHaveLength(4000)
    expect(localTaskTime('2030-06-15T12:30:00Z')).toBe(localTaskTime('2030-06-15T15:30:00+03:00'))
  })
})

describe('React task assignment and tracking', () => {
  it('shows empty state then creates and assigns a real-contract task with a local deadline', async () => {
    const { state, request } = server(); state.rows = []; state.history = []
    const user = userEvent.setup(); render(panel()); await screen.findByText('Henüz atanmış görev yok')
    await user.click(screen.getByRole('button', { name: 'Yeni görev ata' }))
    await user.type(screen.getByLabelText('Görev açıklaması'), text)
    fireEvent.change(screen.getByLabelText('Son tarih ve saat (isteğe bağlı)'), { target: { value: '2030-06-15T15:30' } })
    await user.click(screen.getByRole('button', { name: 'Görevi oluştur ve ata' }))
    expect(await screen.findByText('Görev oluşturuldu ve danışana atandı.')).toBeVisible()
    const body = JSON.parse(String(request.mock.calls.find(([, options]) => options?.method === 'POST')![1]!.body))
    expect(body).toEqual({ clientId, description: text, dueAt: new Date('2030-06-15T15:30').toISOString() })
    expect(await screen.findByRole('region', { name: 'Görev detayı' })).toHaveTextContent('Bekliyor')
    expect(screen.queryByRole('button', { name: /tamamla/i })).not.toBeInTheDocument()
  })
  it('shows list, detail, completion time and the API snapshot history for a completed task', async () => {
    server(task({ status: 'completed', versionNumber: 2, updatedAt: '2026-11-19T10:00:00Z' }))
    const user = userEvent.setup(); render(panel()); const region = await detail(user)
    expect(region).toHaveTextContent('Danışanın tamamlama zamanı')
    expect(within(region).getByRole('region', { name: 'Görev değişiklik geçmişi' })).toHaveTextContent('Sürüm 2 · Tamamlandı')
    expect(within(region).getAllByText(/Bildirim teslimi/)).toHaveLength(1)
    expect(screen.queryByRole('button', { name: 'Görevi düzenle' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Görevi iptal et' })).not.toBeInTheDocument()
  })
  it('edits the selected task, clears dueAt and only cancels after explicit confirmation', async () => {
    const { request } = server(); const user = userEvent.setup(); render(panel()); await detail(user)
    await user.click(screen.getByRole('button', { name: 'Görevi düzenle' }))
    await user.clear(screen.getByLabelText('Görev açıklaması')); await user.type(screen.getByLabelText('Görev açıklaması'), 'Yeni açıklama')
    fireEvent.change(screen.getByLabelText('Son tarih ve saat (isteğe bağlı)'), { target: { value: '' } })
    await user.click(screen.getByRole('button', { name: 'Değişiklikleri kaydet' }))
    await screen.findByText('Görev değişiklikleri kaydedildi.')
    const patch = request.mock.calls.find(([, options]) => options?.method === 'PATCH')!
    expect(JSON.parse(String(patch[1]!.body))).toEqual({ expectedVersionNumber: 1, description: 'Yeni açıklama', dueAt: null })
    await user.click(screen.getByRole('button', { name: 'Görevi iptal et' }))
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(1)
    await user.click(screen.getByRole('button', { name: 'İptali onayla' }))
    await screen.findByText('Görev iptal edildi.')
    expect(JSON.parse(String(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')[1]![1]!.body))).toEqual({ expectedVersionNumber: 2, status: 'cancelled' })
  })
  it('preserves a conflicting draft and requires explicit restart with the new server version', async () => {
    const { state, request } = server(); const user = userEvent.setup(); render(panel()); await detail(user)
    await user.click(screen.getByRole('button', { name: 'Görevi düzenle' })); await user.clear(screen.getByLabelText('Görev açıklaması')); await user.type(screen.getByLabelText('Görev açıklaması'), 'Kaydedilmemiş taslak')
    state.writeError = 409; state.rows = [task({ description: 'Diğer oturumdaki güncel açıklama', versionNumber: 2, status: 'in_progress' })]; state.history = [version(state.rows[0])]
    await user.click(screen.getByRole('button', { name: 'Değişiklikleri kaydet' }))
    expect(await screen.findByDisplayValue('Kaydedilmemiş taslak')).toBeVisible()
    expect(screen.getByRole('button', { name: 'Değişiklikleri kaydet' })).toBeDisabled()
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(1)
    await user.click(screen.getByRole('button', { name: 'Taslağı silip güncel sürüme dön' }))
    expect(screen.getByLabelText('Görev açıklaması')).toHaveValue('Diğer oturumdaki güncel açıklama')
    state.writeError = 0; await user.type(screen.getByLabelText('Görev açıklaması'), ' düzeltildi'); await user.click(screen.getByRole('button', { name: 'Değişiklikleri kaydet' })); await screen.findByText('Görev değişiklikleri kaydedildi.')
    expect(JSON.parse(String(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')[1]![1]!.body)).expectedVersionNumber).toBe(2)
  })
  it.each([403, 404])('removes list, detail, history and unsaved form when permission/relation returns %s', async status => {
    const { state } = server(); const user = userEvent.setup(); render(panel()); await detail(user)
    await user.click(screen.getByRole('button', { name: 'Görevi düzenle' })); state.denied = status
    act(() => window.dispatchEvent(new Event('focus')))
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(status === 403 ? 'Görev paylaşımı kapalı' : 'bağlantınız sona erdi'))
    expect(screen.queryByText(text)).not.toBeInTheDocument(); expect(screen.queryByLabelText('Görev açıklaması')).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Görev değişiklik geçmişi' })).not.toBeInTheDocument()
  })
  it('removes task data when history authorization fails independently', async () => {
    const { request } = server(); const original = request.getMockImplementation()!
    request.mockImplementation((input, options) => String(input).includes('/versions') ? Promise.resolve(new Response(null, { status: 403 })) : original(input, options))
    const user = userEvent.setup(); render(panel()); await screen.findByText(text); await user.click(screen.getByRole('button', { name: `Görev detayını aç: ${text}` }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Görev paylaşımı kapalı'); expect(screen.queryByText(text)).not.toBeInTheDocument()
  })
  it('uses visible polling to show client completion and stops requests while hidden', async () => {
    vi.useFakeTimers()
    try {
      const visible = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
      const { state, request } = server(); await act(async () => { render(panel()) })
      state.rows = [task({ status: 'completed', versionNumber: 2, updatedAt: '2026-11-19T09:00:00Z' })]
      await act(async () => { await vi.advanceTimersByTimeAsync(30_000) }); expect(screen.getByText('Tamamlandı')).toBeVisible()
      visible.mockReturnValue('hidden'); act(() => document.dispatchEvent(new Event('visibilitychange')))
      expect(screen.queryByText(text)).not.toBeInTheDocument(); const count = request.mock.calls.length
      await act(async () => { await vi.advanceTimersByTimeAsync(90_000) }); expect(request).toHaveBeenCalledTimes(count)
      state.denied = 403; visible.mockReturnValue('visible'); await act(async () => document.dispatchEvent(new Event('visibilitychange')))
      expect(screen.getByRole('alert')).toHaveTextContent('Görev paylaşımı kapalı')
    } finally { vi.useRealTimers() }
  })
  it('keeps a draft on periodic revalidation and warns before discarding it', async () => {
    const { request } = server(); const user = userEvent.setup(); render(panel()); await detail(user)
    await user.click(screen.getByRole('button', { name: 'Görevi düzenle' })); await user.type(screen.getByLabelText('Görev açıklaması'), ' ek')
    act(() => window.dispatchEvent(new Event('focus'))); expect(await screen.findByDisplayValue(`${text} ek`)).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Düzenlemeyi kapat' })); expect(screen.getByRole('group', { name: 'Kaydedilmemiş değişiklikler' })).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Değişiklikleri sil' })); expect(screen.queryByLabelText('Görev açıklaması')).not.toBeInTheDocument()
    expect(request.mock.calls.some(([, options]) => options?.method === 'PATCH')).toBe(false)
  })
  it('distinguishes validation and unknown network mutation results without automatic retries', async () => {
    const { state, request } = server(); const onFailure = vi.fn(() => false); const user = userEvent.setup(); render(panel(clientId, 'csrf', onFailure)); await detail(user)
    await user.click(screen.getByRole('button', { name: 'Görevi düzenle' })); state.writeError = 422
    await user.click(screen.getByRole('button', { name: 'Değişiklikleri kaydet' })); expect(await screen.findByRole('alert')).toHaveTextContent('Açıklamayı ve son tarihi')
    state.networkWrite = true; await user.click(screen.getByRole('button', { name: 'Değişiklikleri kaydet' })); expect(await screen.findByRole('alert')).toHaveTextContent('sonucu doğrulanamadı')
    expect(screen.getByRole('button', { name: 'Değişiklikleri kaydet' })).toBeDisabled(); expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(2)
    state.networkWrite = false; state.writeError = 0; await user.click(screen.getByRole('button', { name: 'Görevleri yenile' })); expect(await screen.findByRole('button', { name: 'Değişiklikleri kaydet' })).toBeEnabled()
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(2)
  })
  it('drops a previous client/session and ignores late responses after unmount', async () => {
    let resolve: (response: Response) => void = () => {}
    const request = vi.spyOn(globalThis, 'fetch').mockImplementationOnce(() => new Promise<Response>(done => { resolve = done })).mockResolvedValue(Response.json({ items: [], totalCount: 0 }))
    const view = render(panel()); view.rerender(panel(other, 'different-token')); await screen.findByText('Henüz atanmış görev yok')
    await act(async () => resolve(Response.json({ items: [task()], totalCount: 1 })))
    expect(screen.queryByText(text)).not.toBeInTheDocument(); expect(request.mock.calls[0]![1]!.signal!.aborted).toBe(true)
  })
  it('uses server pagination for task lists and complete snapshot history', async () => {
    const { state, request } = server(); const user = userEvent.setup()
    state.rows = Array.from({ length: 11 }, (_, index) => task({ id: `${String(60000000 + index)}-6666-4666-8666-666666666666`, description: `Sayfalı görev ${index + 1}` }))
    render(panel()); await screen.findByText('11 görev · Sayfa 1')
    expect(within(screen.getByRole('list', { name: 'Atanan görevler' })).getAllByRole('listitem')).toHaveLength(10)
    await user.click(screen.getByRole('button', { name: 'Sonraki görev sayfası' })); await screen.findByText('11 görev · Sayfa 2')
    const current = { ...state.rows[10]!, versionNumber: 12 }; state.rows[10] = current
    state.history = Array.from({ length: 12 }, (_, index) => version({ ...current, versionNumber: 12 - index }))
    await user.click(screen.getByRole('button', { name: 'Görev detayını aç: Sayfalı görev 11' }))
    await screen.findByText('12 değişiklik · Sayfa 1')
    await user.click(screen.getByRole('button', { name: 'Sonraki görev sürümleri' })); await screen.findByText('12 değişiklik · Sayfa 2')
    const history = screen.getByRole('region', { name: 'Görev değişiklik geçmişi' })
    expect(within(history).getByText('Sürüm 1 · Bekliyor')).toBeVisible(); expect(within(history).queryByText('Sürüm 12 · Bekliyor')).not.toBeInTheDocument()
    expect(request.mock.calls.some(([url]) => String(url).includes('/versions?page=2&pageSize=10'))).toBe(true)
  })
  it('keeps network loading failures separate from an empty task list and routes 401 to the session handler', async () => {
    const onFailure = vi.fn(() => false)
    const request = vi.spyOn(globalThis, 'fetch').mockRejectedValueOnce(new TypeError('Synthetic offline')).mockResolvedValueOnce(new Response(null, { status: 401 }))
    render(panel(clientId, 'csrf', onFailure))
    expect(await screen.findByRole('alert')).toHaveTextContent('Görev sunucusuna ulaşılamadı')
    expect(screen.queryByText('Henüz atanmış görev yok')).not.toBeInTheDocument()
    const user = userEvent.setup(); await user.click(screen.getByRole('button', { name: 'Görevleri yenile' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Oturumunuz sona ermiş')
    expect(onFailure).toHaveBeenLastCalledWith(expect.objectContaining({ status: 401 })); expect(request).toHaveBeenCalledTimes(2)
  })
})
