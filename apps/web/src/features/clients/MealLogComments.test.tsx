import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { MealLogComments } from './MealLogComments'
import { MealLogPanel } from './MealLogPanel'
import { createMealLogComment, getMealLogComments } from './mealLogCommentApi'

const mealId = '11111111-1111-4111-8111-111111111111'
const otherMealId = '22222222-2222-4222-8222-222222222222'
const clientId = '33333333-3333-4333-8333-333333333333'
const rootId = '44444444-4444-4444-8444-444444444444'
const replyId = '55555555-5555-4555-8555-555555555555'
const authorId = '66666666-6666-4666-8666-666666666666'
const session = { token: 'synthetic-csrf', dietitianId: authorId, onFailure: vi.fn(() => false) }
const root = () => ({ id: rootId, mealLogId: mealId, authorUserId: authorId, text: 'Sentetik diyetisyen yorumu', createdAt: '2026-11-18T12:00:00.123456Z', parentCommentId: null as string | null })
const reply = () => ({ ...root(), id: replyId, authorUserId: clientId, text: 'Sentetik danışan yanıtı', parentCommentId: rootId })
const comments = (items = [root(), reply()], totalCount = items.length) => Response.json({ items, totalCount })
const empty = () => comments([])
const meal = () => ({ id: mealId, clientId, mealType: 'lunch', consumedAt: '2026-11-18T10:00:00Z', createdAt: '2026-11-18T10:00:00Z', source: 'manual', note: 'Sentetik öğün notu', foodAnalysisId: null,
  items: [{ id: rootId, mealLogId: mealId, foodItemId: null, recipeId: null, displayName: 'Sentetik öğün', quantityGrams: 100, caloriesKcal: 120, proteinGrams: null, carbsGrams: null, fatGrams: null, isEstimated: false }] })
function view(id = mealId, context = session, denied = vi.fn()) {
  return <WorkspaceContext.Provider value={context}><MealLogComments mealLogId={id} onAccessDenied={denied} /></WorkspaceContext.Provider>
}
async function expand() { await userEvent.setup().click(screen.getByRole('button', { name: 'Yorumlar ve yanıtlar' })) }

describe('meal comment API', () => {
  it('reads canonical flat paging with cookie expert context', async () => {
    const fetch = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(comments())
    const signal = new AbortController().signal
    const page = await getMealLogComments(mealId, 1, signal)
    expect(page.items[1]?.parentCommentId).toBe(rootId)
    expect(fetch).toHaveBeenCalledWith(`/api/v1/meal-logs/${mealId}/comments?page=1&pageSize=10`, { method: 'GET', signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error', headers: { 'X-Profile-Context': 'dietitian' } })
  })
  it('writes only trimmed root text and CSRF, with no author/client/parent fields', async () => {
    const fetch = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json(root(), { status: 201 }))
    await createMealLogComment(mealId, `  ${root().text}  `, session.token, new AbortController().signal)
    const [url, options] = fetch.mock.calls[0]!
    expect(url).toBe(`/api/v1/meal-logs/${mealId}/comments`)
    expect(options?.method).toBe('POST'); expect(options?.credentials).toBe('same-origin')
    expect(options?.headers).toEqual({ 'X-Profile-Context': 'dietitian', 'X-CSRF-TOKEN': session.token, 'Content-Type': 'application/json' })
    expect(JSON.parse(options!.body as string)).toEqual({ text: root().text })
  })
  it.each(['', ' \n\t', 'x'.repeat(2001), 'bad\0text', '🥣'.repeat(2001)])('rejects invalid text before sending', async text => {
    const fetch = vi.spyOn(globalThis, 'fetch')
    await expect(createMealLogComment(mealId, text, session.token, new AbortController().signal)).rejects.toMatchObject({ status: 422 })
    expect(fetch).not.toHaveBeenCalled()
  })
  it('accepts 2000 Unicode scalars rather than counting surrogate halves', async () => {
    const text = '🥣'.repeat(2000)
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ ...root(), text }, { status: 201 }))
    expect((await createMealLogComment(mealId, text, session.token, new AbortController().signal)).text).toBe(text)
  })
  it.each(['foreign', 'author', 'parent', 'time', 'shape', 'count', 'duplicate', 'text'])('rejects corrupt %s lists', async scenario => {
    const row = root()
    if (scenario === 'foreign') row.mealLogId = otherMealId
    if (scenario === 'author') row.authorUserId = 'invalid'
    if (scenario === 'parent') row.parentCommentId = row.id
    if (scenario === 'time') row.createdAt = '2026-11-18T12:00:00'
    if (scenario === 'shape') Reflect.deleteProperty(row, 'parentCommentId')
    if (scenario === 'text') row.text = ''
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(comments(scenario === 'duplicate' ? [row, row] : [row], scenario === 'count' ? 0 : 2))
    await expect(getMealLogComments(mealId, 1, new AbortController().signal)).rejects.toMatchObject({ status: 500 })
  })
  it.each([401, 403, 404, 422, 500])('never replays rejected POST %s', async status => {
    const fetch = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(new Response(null, { status }))
    await expect(createMealLogComment(mealId, 'Sentetik', session.token, new AbortController().signal)).rejects.toMatchObject({ status })
    expect(fetch).toHaveBeenCalledTimes(1)
  })
})

describe('meal comment panel', () => {
  it('loads on expansion, identifies replies, quotes their parent, and renders plain text safely', async () => {
    const fetch = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(comments([{ ...root(), text: '<img src=x onerror=alert(1)>' }, reply()]))
    const { container } = render(view())
    expect(fetch).not.toHaveBeenCalled(); await expand()
    expect(await screen.findByText('Danışan yanıtı')).toBeVisible()
    expect(screen.getAllByText('<img src=x onerror=alert(1)>')).toHaveLength(2)
    expect(container.querySelector('img')).toBeNull()
    expect(screen.queryByRole('button', { name: /^(yanıtla|sil|düzenle)$/i })).not.toBeInTheDocument()
    expect(screen.getByLabelText('Öğüne yorumunuz')).toBeEnabled()
  })
  it('keeps loading and empty distinct, then submits once and refreshes real comments', async () => {
    let finishRead!: (response: Response) => void, finishWrite!: (response: Response) => void
    const fetch = vi.spyOn(globalThis, 'fetch').mockImplementationOnce(() => new Promise(resolve => { finishRead = resolve }))
      .mockImplementationOnce(() => new Promise(resolve => { finishWrite = resolve })).mockResolvedValueOnce(comments([root()]))
    const user = userEvent.setup(); render(view()); await expand()
    expect(screen.getByText('Yorumlar okunuyor…')).toBeVisible(); expect(screen.queryByText('Henüz yorum veya yanıt yok.')).not.toBeInTheDocument()
    await act(async () => finishRead(empty()))
    expect(await screen.findByText('Henüz yorum veya yanıt yok.')).toBeVisible()
    await user.type(screen.getByLabelText('Öğüne yorumunuz'), root().text)
    await user.dblClick(screen.getByRole('button', { name: 'Yorum gönder' }))
    expect(fetch.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1)
    expect(screen.getByText('Yorum gönderiliyor…')).toBeVisible()
    await act(async () => finishWrite(Response.json(root(), { status: 201 })))
    expect(await screen.findByText('Diyetisyen yorumu')).toBeVisible()
    expect(screen.getByText('Yorum kaydedildi.')).toBeVisible(); expect(screen.getByLabelText('Öğüne yorumunuz')).toHaveValue('')
  })
  it('pages comments independently and explains a reply whose parent is on another page', async () => {
    const fetch = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(comments([root()], 11)).mockResolvedValueOnce(comments([reply()], 11))
    const user = userEvent.setup(); render(view()); await expand(); await screen.findByText('Diyetisyen yorumu')
    await user.click(screen.getByRole('button', { name: 'Sonraki yorum sayfası' }))
    expect(await screen.findByText('11 yorum/yanıt · Sayfa 2')).toBeVisible()
    expect(screen.getByText('İlgili yorum başka bir sayfada.')).toBeVisible()
    expect(String(fetch.mock.calls[1]?.[0])).toContain('page=2&pageSize=10')
  })
  it('blocks another submission after uncertain network result until explicit verification', async () => {
    const fetch = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(empty()).mockRejectedValueOnce(new TypeError('Synthetic network loss'))
      .mockResolvedValueOnce(empty()).mockResolvedValueOnce(empty())
    const user = userEvent.setup(); render(view()); await expand(); await screen.findByText('Henüz yorum veya yanıt yok.')
    await user.type(screen.getByLabelText('Öğüne yorumunuz'), root().text)
    await user.click(screen.getByRole('button', { name: 'Yorum gönder' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Gönderim sonucu doğrulanamadı')
    await waitFor(() => expect(screen.getByRole('button', { name: 'Yorumları yenile' })).toBeEnabled())
    expect(screen.getByRole('button', { name: 'Yorum gönder' })).toBeDisabled()
    expect(fetch.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1)
    await user.click(screen.getByRole('button', { name: 'Yorumları yenile' }))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Yorum gönder' })).toBeEnabled())
    expect(screen.getByLabelText('Öğüne yorumunuz')).toHaveValue('')
  })
  it('clears a late previous meal/session result and aborts its request', async () => {
    let finish!: (response: Response) => void
    const fetch = vi.spyOn(globalThis, 'fetch').mockImplementationOnce(() => new Promise(resolve => { finish = resolve })).mockResolvedValueOnce(empty())
    const rendered = render(view()); await expand()
    rendered.rerender(view(otherMealId, { ...session, token: 'new-session' })); await expand()
    expect(await screen.findByText('Henüz yorum veya yanıt yok.')).toBeVisible()
    expect(fetch.mock.calls[0]?.[1]?.signal?.aborted).toBe(true)
    await act(async () => finish(comments()))
    expect(screen.queryByText(root().text)).not.toBeInTheDocument()
  })
  it.each([['GET', 403], ['GET', 404], ['POST', 403], ['POST', 404]] as const)('%s denial %s clears the entire meal and its comment drafts', async (method, status) => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ items: [meal()], totalCount: 1 })).mockResolvedValueOnce(comments())
      .mockResolvedValueOnce(new Response(null, { status }))
    const user = userEvent.setup()
    render(<WorkspaceContext.Provider value={session}><MealLogPanel clientId={clientId} /></WorkspaceContext.Provider>)
    await screen.findByText('Sentetik öğün'); await expand(); await screen.findByText('Danışan yanıtı')
    await user.type(screen.getByLabelText('Öğüne yorumunuz'), 'Sentetik taslak')
    await user.click(screen.getByRole('button', { name: method === 'GET' ? 'Yorumları yenile' : 'Yorum gönder' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(status === 403 ? 'Öğün paylaşımı kapalı' : 'aktif danışan bağlantınız sona erdi')
    expect(screen.queryByRole('article')).not.toBeInTheDocument(); expect(screen.queryByText(root().text)).not.toBeInTheDocument()
    expect(screen.queryByDisplayValue('Sentetik taslak')).not.toBeInTheDocument()
  })
  it('aborts a pending write on session change without replay or old success feedback', async () => {
    let finish!: (response: Response) => void
    const fetch = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(empty()).mockImplementationOnce(() => new Promise(resolve => { finish = resolve })).mockResolvedValueOnce(empty())
    const user = userEvent.setup(); const rendered = render(view()); await expand(); await screen.findByText('Henüz yorum veya yanıt yok.')
    await user.type(screen.getByLabelText('Öğüne yorumunuz'), root().text)
    await user.click(screen.getByRole('button', { name: 'Yorum gönder' }))
    rendered.rerender(view(otherMealId, { ...session, token: 'another-session' })); await expand()
    expect(await screen.findByText('Henüz yorum veya yanıt yok.')).toBeVisible()
    expect(fetch.mock.calls[1]?.[1]?.signal?.aborted).toBe(true)
    await act(async () => finish(Response.json(root(), { status: 201 })))
    expect(screen.queryByText('Yorum kaydedildi.')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Öğüne yorumunuz')).toHaveValue('')
    expect(fetch.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1)
  })
  it('rechecks an open section periodically and purges comments on visibility changes', async () => {
    vi.useFakeTimers()
    try {
      const visibility = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
      const fetch = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(comments()).mockResolvedValueOnce(comments()).mockResolvedValueOnce(empty())
      render(view())
      await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Yorumlar ve yanıtlar' })) })
      expect(screen.getByText('Danışan yanıtı')).toBeVisible()
      await act(async () => { await vi.advanceTimersByTimeAsync(30_000) })
      expect(fetch).toHaveBeenCalledTimes(2)
      visibility.mockReturnValue('hidden'); await act(async () => document.dispatchEvent(new Event('visibilitychange')))
      expect(screen.queryByText(root().text)).not.toBeInTheDocument()
      visibility.mockReturnValue('visible'); await act(async () => document.dispatchEvent(new Event('visibilitychange')))
      expect(screen.getByText('Henüz yorum veya yanıt yok.')).toBeVisible()
    } finally { vi.useRealTimers() }
  })
})
