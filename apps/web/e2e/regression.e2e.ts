import { test, expect } from '@playwright/test'
import type { APIRequestContext, Page } from '@playwright/test'
import { execFileSync } from 'node:child_process'
import { randomUUID } from 'node:crypto'

const origin = 'https://localhost:5446', password = 'Synthetic U6 password 🔑', changedPassword = ' New synthetic U6 password 🔒 '
type Account = { id: string; email: string; displayName: string }
type Identity = { accessToken: string; refreshToken: string }
const attempts: Record<'login' | 'application', number[]> = { login: [], application: [] }
async function paceRequests(kind: keyof typeof attempts) {
  // Keep setup within the real limits; do not weaken the API for browser tests.
  const limit = kind === 'login' ? 10 : 5
  while (true) {
    const now = Date.now()
    attempts[kind] = attempts[kind].filter(time => now - time < 60_100)
    if (attempts[kind].length < limit) { attempts[kind].push(now); return }
    await new Promise(resolve => setTimeout(resolve, Math.min(60_000, 60_100 - (now - attempts[kind][0]!))))
  }
}
async function api(request: APIRequestContext, path: string, method: string, status: number, data?: object, bearer?: string) {
  if (path === '/api/v1/auth/login') await paceRequests('login')
  if (path === '/api/v1/dietitians/apply') await paceRequests('application')
  // Mobile-only endpoints are intentionally absent from the web proxy.
  const direct = bearer || /^\/api\/v1\/(?:auth\/(?:login|refresh)|water-logs)(?:[/?]|$)/.test(path)
  const response = await request.fetch(direct ? 'https://localhost:7099' + path : path, { method, data, headers: bearer ? { Authorization: `Bearer ${bearer}`, 'X-Profile-Context': 'client' } : {} })
  // No response bodies, credentials or reset links in assertion messages/artifacts.
  expect(response.status(), `${method} ${path.split('?')[0]}`).toBe(status)
  return status === 204 ? undefined : response.json()
}
async function mailText(email: string, subject: string) {
  for (let n = 0; n < 100; n++) {
    const list = await fetch(`http://127.0.0.1:58028/api/v1/search?query=${encodeURIComponent(`to:${email}`)}`).then(r => r.json()) as { messages: { ID: string; Subject: string }[] }
    const item = list.messages.find((m: { Subject: string }) => m.Subject.includes(subject))
    if (item) return String(((await fetch(`http://127.0.0.1:58028/api/v1/message/${item.ID}`).then(r => r.json())) as { Text: string }).Text)
    await new Promise(resolve => setTimeout(resolve, 100))
  }
  throw new Error('Synthetic test email did not arrive in the isolated Mailpit.')
}
function updateSynthetic(sql: string) {
  if (process.env.SNP_E2E_TEST_ENV !== 'nutrition_u6_test') throw new Error('Test database required.')
  const label = execFileSync('docker', ['inspect', '--format', '{{index .Config.Labels "smart-nutrition.test"}}', 'nutrition-u6-postgres'], { encoding: 'utf8' }).trim()
  if (label !== 'U6') throw new Error('Not an owned U6 PostgreSQL container.')
  execFileSync('docker', ['exec', 'nutrition-u6-postgres', 'psql', '-U', 'nutrition_test', '-d', 'nutrition_u6_test', '-v', 'ON_ERROR_STOP=1', '-c', sql], { stdio: 'pipe' })
}
async function account(request: APIRequestContext, expert: boolean, approved = true): Promise<Account> {
  const email = `synthetic-u6-${randomUUID()}@example.test`, displayName = expert ? 'Sentetik U6 uzman' : 'Sentetik U6 danışan'
  const result = await api(request, expert ? '/api/v1/dietitians/apply' : '/api/v1/auth/register', 'POST', 201,
    { email, password, displayName, ...(expert ? { licenseInfo: 'Synthetic U6 license' } : { role: 'client' }) })
  const text = await mailText(email, 'E-posta doğrulama')
  const token = text.split('\n').map(v => v.trim()).find(v => /^[\w-]{43}$/.test(v))
  if (!token) throw new Error('Verification code missing.')
  await api(request, '/api/v1/auth/verify-email', 'POST', 204, { token })
  expect(/^[a-f0-9-]{36}$/.test(result.id)).toBe(true)
  if (expert && approved) updateSynthetic(`UPDATE dietitian_profiles SET is_verified=true WHERE user_id='${result.id}' AND EXISTS (SELECT 1 FROM users WHERE id='${result.id}' AND email='${email.toUpperCase()}');`)
  return { id: result.id, email, displayName }
}
async function signIn(page: Page, email: string, value = password) {
  await page.goto('/giris')
  await page.getByLabel('E-posta adresi').fill(email); await page.getByLabel('Şifre', { exact: true }).fill(value)
  await paceRequests('login')
  await page.getByRole('button', { name: 'Giriş yap', exact: true }).click()
}
async function pair(page: Page, request: APIRequestContext) {
  const client = await account(request, false), expert = await account(request, true)
  const mobile: Identity = await api(request, '/api/v1/auth/login', 'POST', 200, { email: client.email, password })
  await signIn(page, expert.email); await expect(page).toHaveURL(origin + '/calisma-alani')
  const profile = await api(page.request, '/api/v1/dietitians/me', 'GET', 200)
  const relation = await api(request, '/api/v1/dietitian-relationships', 'POST', 201, { dietitianId: profile.id }, mobile.accessToken)
  const csrf = await api(page.request, '/api/v1/auth/csrf', 'GET', 200)
  const accepted = await page.request.post(`/api/v1/dietitian-relationships/${relation.id}/accept`, { headers: { Origin: origin, 'X-CSRF-TOKEN': csrf.requestToken, 'X-Profile-Context': 'dietitian' } })
  expect(accepted.status()).toBe(200)
  return { client, expert, mobile, relation, csrf: csrf.requestToken }
}

test('HTTPS UI: login, client, task completion/history, independent water grant/revocation and logout', async ({ page, request }) => {
  const { mobile, relation, csrf } = await pair(page, request)
  await api(request, '/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category: 'client_tasks', isGranted: true }, mobile.accessToken)
  const water = await api(request, '/api/v1/water-logs', 'POST', 201, { amountMl: 321.125, consumedAt: new Date().toISOString(), source: 'manual' }, mobile.accessToken)
  await page.getByRole('link', { name: 'Danışanlarım', exact: true }).click()
  await page.getByRole('link', { name: 'Sentetik U6 danışan için danışan detayını aç' }).click()
  await expect(page.getByRole('heading', { name: 'Sentetik U6 danışan', exact: true })).toBeVisible()
  const sections = page.getByRole('navigation', { name: 'Danışan bölümleri' })
  await sections.getByRole('link', { name: 'Görevler', exact: true }).click()
  const tasks = page.getByRole('region', { name: 'Danışan görevleri' }), waterPanel = page.getByRole('region', { name: 'Su takibi', exact: true })
  await tasks.getByRole('button', { name: 'Yeni görev ata' }).click()
  await tasks.getByLabel('Görev açıklaması').fill('Sentetik HTTPS görevi')
  const due = new Date(Date.now() + 86_400_000)
  const dueLocal = new Date(due.getTime() + 3 * 3600_000).toISOString().slice(0, 16)
  await tasks.getByLabel('Son tarih ve saat (isteğe bağlı)').fill(dueLocal)
  await tasks.getByRole('button', { name: 'Görevi oluştur ve ata' }).click()
  await expect(tasks.getByText('Görev oluşturuldu ve danışana atandı.')).toBeVisible()
  const own = await api(request, '/api/v1/client-tasks?page=1&pageSize=10', 'GET', 200, undefined, mobile.accessToken), assigned = own.items[0]
  expect(assigned.description).toBe('Sentetik HTTPS görevi'); expect(assigned.dueAt).not.toBeNull()
  await api(request, `/api/v1/client-tasks/${assigned.id}`, 'PATCH', 200, { expectedVersionNumber: assigned.versionNumber, status: 'completed' }, mobile.accessToken)
  await tasks.getByRole('button', { name: 'Görevleri yenile' }).click()
  await expect(tasks.getByText('Sürüm 2 · Tamamlandı')).toBeVisible()
  await expect(tasks.getByText('Danışanın tamamlama zamanı', { exact: true })).toBeVisible()
  await sections.getByRole('link', { name: 'Ölçüm ve Su', exact: true }).click()
  await expect(waterPanel.getByRole('alert')).toContainText('Su paylaşımı kapalı')
  const grant = await api(request, '/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category: 'water_logs', isGranted: true }, mobile.accessToken)
  await waterPanel.getByRole('button', { name: 'Su takibini yenile' }).click()
  await expect(waterPanel.getByRole('status', { name: 'Seçilen günün su toplamı' })).toContainText('321,125 mL')
  await expect(waterPanel.getByRole('table')).toBeVisible()
  await api(request, `/api/v1/data-sharing-permissions/${grant.id}`, 'PATCH', 200, { isGranted: false }, mobile.accessToken)
  await waterPanel.getByRole('button', { name: 'Su takibini yenile' }).click()
  await expect(waterPanel.getByRole('alert')).toContainText('Su paylaşımı kapalı')
  await expect(waterPanel.getByText('321,125 mL', { exact: true })).toHaveCount(0)
  await expect(waterPanel.getByRole('table')).toHaveCount(0)
  await sections.getByRole('link', { name: 'Görevler', exact: true }).click()
  await expect(tasks.getByText('Sürüm 2 · Tamamlandı')).toBeVisible()
  await api(request, `/api/v1/water-logs/${water.id}`, 'GET', 200, undefined, mobile.accessToken)
  const invalidHeaders: Record<string, string>[] = [{ Origin: origin }, { Origin: origin, 'X-CSRF-TOKEN': 'invalid' }, { Origin: 'https://invalid.example.test', 'X-CSRF-TOKEN': csrf }]
  for (const headers of invalidHeaders) {
    const rejected = await page.request.post('/api/v1/client-tasks', { headers, data: { clientId: relation.clientId, description: 'Rejected CSRF task' } })
    expect(rejected.status()).toBe(headers.Origin === origin ? 400 : 403)
  }
  await page.reload()
  await tasks.getByRole('button', { name: /Görev detayını aç/ }).click()
  await expect(tasks.getByText('Sürüm 2 · Tamamlandı')).toBeVisible()
  await page.getByRole('button', { name: 'Profil menüsü' }).click(); await page.keyboard.press('Escape')
  await expect(page.getByRole('button', { name: 'Profil menüsü' })).toBeFocused()
  await page.getByRole('button', { name: 'Profil menüsü' }).click(); await page.getByRole('button', { name: 'Çıkış yap', exact: true }).click()
  await expect(page).toHaveURL(origin + '/giris'); expect((await page.request.get('/api/v1/auth/me')).status()).toBe(401)
  await page.goBack(); await expect(page.getByText('Sentetik HTTPS görevi', { exact: true })).toHaveCount(0)
})

test('HTTPS UI: real Mailpit link resets password, clears URL and invalidates prior web/mobile credentials', async ({ page, context, request }) => {
  const expert = await account(request, true)
  const oldMobile: Identity = await api(request, '/api/v1/auth/login', 'POST', 200, { email: expert.email, password })
  await signIn(page, expert.email); await expect(page).toHaveURL(origin + '/calisma-alani')
  const resetPage = await context.newPage(); await resetPage.goto('/giris')
  await resetPage.getByRole('link', { name: 'Şifremi unuttum' }).click()
  await resetPage.getByLabel('E-posta adresi').fill(expert.email)
  await resetPage.getByRole('button', { name: 'Sıfırlama bağlantısı iste' }).click()
  await expect(resetPage.getByRole('status')).toContainText('Uygun bir hesap varsa')
  const text = await mailText(expert.email, 'Parola sıfırlama'), link = text.match(/https:\/\/[^\s]+/)?.[0]
  if (!link || !link.startsWith(origin + '/sifremi-unuttum#token=')) throw new Error('Reset link does not use the trusted test origin.')
  const token = new URL(link).hash.slice(7)
  try { await resetPage.goto(link) } catch { throw new Error('Email-link navigation failed; secret omitted.') }
  // Assert only the clean URL, never place the live secret into assertion output.
  await expect.poll(() => resetPage.url()).toBe(origin + '/sifremi-unuttum')
  await resetPage.getByLabel('Yeni şifre', { exact: true }).fill(changedPassword)
  await resetPage.getByLabel('Yeni şifre tekrarı').fill(changedPassword)
  await resetPage.getByRole('button', { name: 'Şifreyi yenile' }).click()
  await expect(resetPage).toHaveURL(origin + '/giris'); await expect(resetPage.getByRole('status')).toContainText('Şifreniz yenilendi')
  expect((await page.request.get('/api/v1/auth/me')).status()).toBe(401)
  await api(request, '/api/v1/auth/me', 'GET', 401, undefined, oldMobile.accessToken)
  await api(request, '/api/v1/auth/refresh', 'POST', 401, { refreshToken: oldMobile.refreshToken })
  await api(request, '/api/v1/auth/login', 'POST', 401, { email: expert.email, password })
  await api(request, '/api/v1/auth/reset-password', 'POST', 422, { token, password: changedPassword })
  await signIn(resetPage, expert.email, changedPassword); await expect(resetPage).toHaveURL(origin + '/calisma-alani')
})

test('HTTPS UI: client sections preserve drafts and task focus during delayed rechecks in both themes and widths', async ({ page, context, request }, testInfo) => {
  const { mobile, relation } = await pair(page, request)
  const grant = await api(request, '/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category: 'client_tasks', isGranted: true }, mobile.accessToken)
  await api(request, '/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category: 'nutrition_plans', isGranted: true }, mobile.accessToken)
  const detail = `/calisma-alani/danisanlar/${relation.clientId}`
  await page.goto(detail)
  const sections = page.getByRole('navigation', { name: 'Danışan bölümleri' })
  await expect(sections.getByRole('link', { name: 'Özet', exact: true })).toHaveAttribute('aria-current', 'page')
  await sections.getByRole('link', { name: 'Görevler', exact: true }).click()
  await page.getByRole('button', { name: 'Yeni görev ata' }).click()
  const input = page.getByLabel('Görev açıklaması')
  await input.fill('Sentetik yarım görev')
  const original = await input.elementHandle()
  await input.evaluate(node => (node as HTMLTextAreaElement).setSelectionRange(7, 7))
  let release!: () => void, reads = 0
  const delayed = new Promise<void>(resolve => { release = resolve })
  await page.route('**/api/v1/client-tasks?**', async route => {
    reads++
    const response = await route.fetch()
    await delayed
    await route.fulfill({ response })
  })
  await page.evaluate(() => { window.dispatchEvent(new Event('focus')); window.dispatchEvent(new Event('focus')); document.dispatchEvent(new Event('visibilitychange')) })
  await expect.poll(() => reads).toBe(1)
  await expect(input).toBeFocused()
  expect(await input.evaluate((node, old) => node === old, original)).toBe(true)
  expect(await input.evaluate(node => (node as HTMLTextAreaElement).selectionStart)).toBe(7)
  await page.keyboard.type(' ek')
  const draft = await input.inputValue()
  await expect(page.getByRole('button', { name: 'Görevi oluştur ve ata' })).toBeDisabled()
  release()
  await expect(page.getByText('Görevler kontrol ediliyor…')).toHaveCount(0)
  await expect(input).toBeFocused(); await expect(input).toHaveValue(draft)
  expect(await original!.evaluate(node => node.isConnected)).toBe(true)
  await page.unroute('**/api/v1/client-tasks?**')
  await sections.getByRole('link', { name: 'Program', exact: true }).click()
  await page.getByRole('button', { name: 'Yeni program oluştur' }).click()
  await page.getByLabel('Program başlığı').fill('Sentetik yarım program')
  await sections.getByRole('link', { name: 'Özet', exact: true }).click()
  await page.goBack(); await expect(page.getByLabel('Program başlığı')).toHaveValue('Sentetik yarım program')
  await page.goBack(); await expect(input).toHaveValue(draft)
  await page.goForward(); await expect(page.getByLabel('Program başlığı')).toHaveValue('Sentetik yarım program')
  await sections.getByRole('link', { name: 'Görevler', exact: true }).click()
  for (const theme of ['light', 'dark'] as const) {
    await page.emulateMedia({ colorScheme: theme })
    for (const width of [1366, 390]) {
      await page.setViewportSize({ width, height: 900 })
      await expect(page.locator('html')).toHaveAttribute('data-theme', theme)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
      await input.scrollIntoViewIfNeeded()
      await page.screenshot({ path: testInfo.outputPath(`client-tasks-${theme}-${width}.png`), fullPage: true })
    }
  }
  page.once('dialog', dialog => dialog.accept()) // Explicitly discard the hidden unsaved program on reload.
  await page.reload()
  await expect(sections.getByRole('link', { name: 'Görevler', exact: true })).toHaveAttribute('aria-current', 'page')
  await page.getByRole('button', { name: 'Yeni görev ata' }).click(); await input.fill('İzin geri çekme taslağı')
  await api(request, `/api/v1/data-sharing-permissions/${grant.id}`, 'PATCH', 200, { isGranted: false }, mobile.accessToken)
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await expect(input).toHaveCount(0)
  await expect(page.getByRole('region', { name: 'Danışan görevleri' }).getByRole('alert')).toContainText('Görev paylaşımı kapalı')
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin })
  await page.goto('/calisma-alani/baglantilar')
  await page.getByRole('button', { name: 'Davet kodu oluştur' }).click()
  await page.getByRole('button', { name: 'Kodu kopyala' }).click()
  await expect(page.getByText('Davet kodu kopyalandı.')).toBeVisible()
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(await page.locator('.invitation-code').textContent())
})

test('HTTPS UI: unapproved expert boundary, client web denial, narrow layout and keyboard validation', async ({ page, request }) => {
  const client = await account(request, false), expert = await account(request, true, false)
  await page.setViewportSize({ width: 390, height: 844 }); await page.emulateMedia({ colorScheme: 'dark' })
  await page.goto('/giris'); await page.getByRole('button', { name: 'Giriş yap', exact: true }).click()
  await expect(page.getByLabel('E-posta adresi')).toBeFocused()
  await signIn(page, client.email); await expect(page.getByRole('status')).toContainText('Giriş bilgileri doğrulanamadı')
  await signIn(page, expert.email); await expect(page).toHaveURL(origin + '/uzman/basvuru-durumu')
  await page.goto('/calisma-alani/danisanlar'); await expect(page).toHaveURL(origin + '/uzman/basvuru-durumu')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
  await page.emulateMedia({ colorScheme: 'light' }); await expect(page.locator('html')).toHaveAttribute('data-theme', 'light')
})

test('HTTPS UI: an expired server session removes the client workspace and rejects its old cookie', async ({ page, request }) => {
  const { expert } = await pair(page, request)
  await page.getByRole('link', { name: 'Danışanlarım', exact: true }).click()
  await expect(page.getByRole('link', { name: 'Sentetik U6 danışan için danışan detayını aç' })).toBeVisible()
  updateSynthetic(`UPDATE auth_sessions SET created_at=now()-interval '31 minutes',last_seen_at=now()-interval '2 minutes',idle_expires_at=now()-interval '1 minute' WHERE user_id='${expert.id}' AND EXISTS (SELECT 1 FROM users WHERE id='${expert.id}' AND email='${expert.email.toUpperCase()}');`)
  await page.getByRole('button', { name: 'Listeyi yenile' }).click()
  await expect(page).toHaveURL(origin + '/giris')
  await expect(page.getByText('Sentetik U6 danışan', { exact: true })).toHaveCount(0)
  expect((await page.request.get('/api/v1/auth/me')).status()).toBe(401)
})

test('HTTPS UI: reuse own program as an independent draft, weekly editing and explicit assignment', async ({ page, request }, testInfo) => {
  const { mobile, relation, csrf } = await pair(page, request)
  const sourcePermission = await api(request, '/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category: 'nutrition_plans', isGranted: true }, mobile.accessToken)
  const headers = { Origin: origin, 'X-CSRF-TOKEN': csrf, 'X-Profile-Context': 'dietitian' }
  const sourceGroup = randomUUID()
  const response = await page.request.post('/api/v1/nutrition-plans', { headers, data: {
    clientId: relation.clientId, title: 'Sentetik yeniden kullanılabilir program', startDate: '2026-11-01', endDate: '2026-11-30', dailyCaloriesTargetKcal: 1800, dailyWaterTargetMl: 2000,
    items: [0, 1].map(index => ({ dayOfWeek: 1, mealType: 'breakfast', description: `Sentetik alternatif ${index + 1}`, recommendedQuantity: '1 porsiyon', sortOrder: index, recipeId: null, alternativeGroupId: sourceGroup })),
  } })
  expect(response.status()).toBe(201)
  const source = await response.json()
  const target = await account(request, false)
  const targetMobile: Identity = await api(request, '/api/v1/auth/login', 'POST', 200, { email: target.email, password })
  const profile = await api(page.request, '/api/v1/dietitians/me', 'GET', 200)
  const targetRelation = await api(request, '/api/v1/dietitian-relationships', 'POST', 201, { dietitianId: profile.id }, targetMobile.accessToken)
  expect((await page.request.post(`/api/v1/dietitian-relationships/${targetRelation.id}/accept`, { headers })).status()).toBe(200)
  await api(request, '/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: targetRelation.id, category: 'nutrition_plans', isGranted: true }, targetMobile.accessToken)
  await page.getByRole('button', { name: 'Özeti yenile' }).click()
  await expect(page.getByRole('heading', { name: 'Danışanlarım', exact: true })).toBeVisible()
  for (const theme of ['light', 'dark'] as const) {
    await page.emulateMedia({ colorScheme: theme })
    for (const width of [1366, 390]) {
      await page.setViewportSize({ width, height: 900 })
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
      const clientsTop = await page.getByRole('heading', { name: 'Danışanlarım', exact: true }).boundingBox()
      expect(clientsTop!.y).toBeLessThan(900)
      await page.screenshot({ path: testInfo.outputPath(`overview-${theme}-${width}.png`), fullPage: true })
    }
  }
  await page.getByRole('link', { name: 'Bekleyen isteklere git' }).focus()
  await expect(page.getByRole('link', { name: 'Bekleyen isteklere git' })).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(origin + '/calisma-alani/baglantilar')
  await expect(page.getByLabel('Durum')).toHaveValue('pending')
  await page.setViewportSize({ width: 1366, height: 900 })
  const detail = `/calisma-alani/danisanlar/${targetRelation.clientId}?bolum=program`
  // Start from the list so native browser Back has a genuine route to guard.
  await page.goto('/calisma-alani/danisanlar')
  await page.locator(`a[href="/calisma-alani/danisanlar/${targetRelation.clientId}"]`).click()
  await page.getByRole('navigation', { name: 'Danışan bölümleri' }).getByRole('link', { name: 'Program', exact: true }).click()
  let writes = 0, activations = 0
  page.on('request', request => {
    if (request.method() === 'POST' && request.url().endsWith('/api/v1/nutrition-plans')) writes++
    if (request.url().endsWith('/activate')) activations++
  })
  await page.getByRole('button', { name: 'Kendi programımdan kopyala' }).click()
  const picker = page.getByRole('region', { name: 'Kaynak program seçimi' })
  // The source list is paged; wait for its real response before selecting a row.
  const sources = await api(page.request, '/api/v1/dietitian/clients?page=1&pageSize=10&sortOrder=asc', 'GET', 200)
  const sourceIndex = sources.items.findIndex((row: { id: string }) => row.id === relation.clientId)
  expect(sourceIndex).toBeGreaterThanOrEqual(0)
  const sourceName = picker.getByRole('button', { name: 'Sentetik U6 danışan', exact: true })
  await expect(sourceName).toHaveCount(sources.items.length)
  await sourceName.nth(sourceIndex).click()
  const copySource = picker.getByRole('button', { name: 'Sentetik yeniden kullanılabilir program programını kopyala' })
  await expect(copySource).toBeVisible()
  await api(request, `/api/v1/data-sharing-permissions/${sourcePermission.id}`, 'PATCH', 200, { isGranted: false }, mobile.accessToken)
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await expect(picker.getByRole('alert')).toContainText('Programlara erişim veya düzenleme izniniz bulunmuyor.')
  await api(request, `/api/v1/data-sharing-permissions/${sourcePermission.id}`, 'PATCH', 200, { isGranted: true }, mobile.accessToken)
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await expect(copySource).toBeVisible()
  await expect(picker.getByRole('alert')).toHaveCount(0)
  await picker.getByRole('button', { name: 'Kaynakları yeniden kontrol et' }).click()
  await expect(copySource).toHaveCount(0)
  await sourceName.nth(sourceIndex).click()
  for (const theme of ['light', 'dark'] as const) {
    await page.emulateMedia({ colorScheme: theme })
    for (const width of [1366, 768, 390]) {
      await page.setViewportSize({ width, height: 900 })
      await expect(copySource).toBeVisible()
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
      const sourceOption = sourceName.nth(sourceIndex)
      const labelBox = (await sourceOption.locator('span').boundingBox())!
      const arrowBox = (await sourceOption.locator('svg').boundingBox())!
      expect(arrowBox.x).toBeGreaterThan(labelBox.x + labelBox.width)
      await picker.screenshot({ path: testInfo.outputPath(`source-buttons-${theme}-${width}.png`) })
    }
  }
  await page.setViewportSize({ width: 1366, height: 900 })
  await copySource.click()
  await page.getByRole('button', { name: 'Vazgeç', exact: true }).click()
  await page.getByRole('button', { name: 'Değişiklikleri sil', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Yeni program oluştur', exact: true })).toBeFocused()
  await page.getByRole('button', { name: 'Kendi programımdan kopyala' }).click()
  await sourceName.nth(sourceIndex).click()
  await copySource.click()
  await expect(page.getByText('Hedef danışan: Sentetik U6 danışan')).toBeVisible()
  await expect(page.getByLabel('Program başlığı')).toHaveValue('')
  await expect(page.getByLabel('Başlangıç tarihi')).toHaveValue('')
  await expect(page.getByLabel('Günlük enerji hedefi (kcal, isteğe bağlı)')).toHaveValue('')
  expect(writes).toBe(0); expect(activations).toBe(0)
  await page.getByLabel('Program başlığı').fill('Hedefe uyarlanan sentetik program')
  await page.getByLabel('Başlangıç tarihi').fill('2026-11-21')
  await page.getByLabel('Günlük enerji hedefi (kcal, isteğe bağlı)').fill('1950')
  await page.getByRole('button', { name: 'Pazartesi', exact: true }).click()
  await page.getByLabel('Öğün 1 açıklaması').fill('Hedefe uyarlanan sentetik kahvaltı')
  await page.getByLabel('Hedef gün').selectOption('2'); await page.getByRole('button', { name: 'Günü kopyala', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Salı', exact: true })).toHaveAttribute('aria-pressed', 'true')
  // Native POP is restored while the user decides; cancel retains the exact draft.
  await page.evaluate(() => history.go(-2))
  await expect(page.getByRole('alertdialog')).toContainText('Kaydedilmemiş değişiklikler')
  await page.getByRole('button', { name: 'Düzenlemeye dön' }).click()
  await expect(page.getByLabel('Program başlığı')).toBeFocused()
  await expect(page).toHaveURL(origin + detail)
  await expect(page.getByLabel('Program başlığı')).toHaveValue('Hedefe uyarlanan sentetik program')
  for (const theme of ['light', 'dark'] as const) {
    await page.emulateMedia({ colorScheme: theme })
    for (const width of [1366, 390]) {
      await page.setViewportSize({ width, height: 900 })
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
      await page.getByRole('button', { name: 'Taslak oluştur' }).scrollIntoViewIfNeeded()
      expect(await page.getByRole('button', { name: 'Taslak oluştur' }).evaluate(node => getComputedStyle(node.parentElement!).position)).toBe(width === 390 ? 'static' : 'sticky')
      await page.screenshot({ path: testInfo.outputPath(`weekly-plan-${theme}-${width}.png`), fullPage: true })
    }
  }
  await page.getByRole('button', { name: 'Taslak oluştur' }).click()
  await expect(page.getByText('Taslak kaydedildi. Danışana atamak için programı etkinleştirin.')).toBeVisible()
  expect(writes).toBe(1); expect(activations).toBe(0)
  const before = await api(page.request, `/api/v1/nutrition-plans?clientId=${targetRelation.clientId}&page=1&pageSize=10`, 'GET', 200)
  expect(before.items).toHaveLength(1)
  const copied = before.items[0]
  expect(copied.status).toBe('draft'); expect(copied.clientId).toBe(targetRelation.clientId); expect(copied.id).not.toBe(source.id)
  expect(copied.items).toHaveLength(4); expect(copied.items[0].alternativeGroupId).not.toBe(sourceGroup)
  expect(copied.items[0].alternativeGroupId).toBe(copied.items[1].alternativeGroupId)
  expect(copied.items[2].alternativeGroupId).not.toBe(copied.items[0].alternativeGroupId)
  expect(copied.items[2].alternativeGroupId).toBe(copied.items[3].alternativeGroupId)
  await page.getByRole('button', { name: 'Programı etkinleştir', exact: true }).click()
  await expect(page.getByRole('alertdialog')).toContainText('Hedefe uyarlanan sentetik program'); expect(activations).toBe(0)
  await page.keyboard.press('Tab'); await expect(page.getByRole('button', { name: 'Onayla ve etkinleştir' })).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(page.getByText('Beslenme programı etkinleştirildi ve danışana atandı.')).toBeVisible(); expect(activations).toBe(1)
  const unchanged = await api(page.request, `/api/v1/nutrition-plans/${source.id}`, 'GET', 200)
  expect(unchanged).toEqual(source)
  // Confirmed native POP discards a later unsaved draft without losing the saved program.
  await page.getByRole('button', { name: 'Yeni program oluştur' }).click()
  await page.getByLabel('Program başlığı').fill('Silinecek sentetik taslak')
  await page.evaluate(() => history.go(-2))
  await page.getByRole('button', { name: 'Değişiklikleri sil' }).click()
  await expect(page).toHaveURL(origin + '/calisma-alani/danisanlar')
  await page.locator(`a[href="/calisma-alani/danisanlar/${targetRelation.clientId}"]`).click()
  await page.getByRole('navigation', { name: 'Danışan bölümleri' }).getByRole('link', { name: 'Program', exact: true }).click()
  await expect(page.getByLabel('Program başlığı')).toHaveCount(0)
  // A successful save clears native beforeunload protection.
  await page.reload(); await expect(page.getByText('Aktif · Sürüm 1')).toBeVisible()
})

test('HTTPS UI: usable meal controls, editor focus and confirmed relationship ending in both themes and widths', async ({ page, request }, testInfo) => {
  const { mobile, relation, csrf } = await pair(page, request)
  for (const category of ['meal_logs', 'nutrition_plans', 'client_tasks'])
    await api(request, '/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category, isGranted: true }, mobile.accessToken)
  await api(request, '/api/v1/meal-logs', 'POST', 201, { mealType: 'breakfast', consumedAt: new Date().toISOString(), source: 'manual', items: [{ displayName: 'Sentetik deneme öğünü', isEstimated: false }] }, mobile.accessToken)
  const headers = { Origin: origin, 'X-CSRF-TOKEN': csrf, 'X-Profile-Context': 'dietitian' }
  const planResponse = await page.request.post('/api/v1/nutrition-plans', { headers, data: {
    clientId: relation.clientId, title: 'Sentetik sonlandırma programı', startDate: '2026-11-01', endDate: null,
    dailyCaloriesTargetKcal: null, dailyWaterTargetMl: null,
    items: [{ dayOfWeek: null, mealType: 'breakfast', description: 'Sentetik öneri', recommendedQuantity: null, sortOrder: 0, recipeId: null, alternativeGroupId: null }],
  } })
  expect(planResponse.status()).toBe(201)
  const plan = await planResponse.json()
  expect((await page.request.post(`/api/v1/nutrition-plans/${plan.id}/activate`, { headers })).status()).toBe(200)
  expect((await page.request.post('/api/v1/client-tasks', { headers, data: { clientId: relation.clientId, description: 'Sentetik açık görev' } })).status()).toBe(201)
  async function openNavigation(name: string) {
    const menu = page.getByRole('button', { name: 'Menüyü aç', exact: true })
    if (await menu.isVisible()) await menu.click()
    await page.getByRole('navigation', { name: 'Diyetisyen çalışma alanı', exact: true }).getByRole('link', { name, exact: true }).click()
  }
  for (const theme of ['light', 'dark'] as const) {
    await page.emulateMedia({ colorScheme: theme })
    for (const width of [1366, 768, 390]) {
      await page.setViewportSize({ width, height: 900 })
      await openNavigation('Danışanlarım')
      await page.getByRole('link', { name: 'Sentetik U6 danışan için danışan detayını aç', exact: true }).click()
      await page.getByRole('link', { name: 'Öğünler', exact: true }).click()
      const meal = page.getByRole('region', { name: 'Öğün günlüğü', exact: true })
      const today = meal.getByRole('button', { name: 'Bugün', exact: true })
      await today.click()
      await expect(today).toHaveAttribute('aria-pressed', 'true')
      await expect(meal.getByRole('heading', { name: 'Sentetik deneme öğünü' })).toBeVisible()
      const cardBox = (await meal.boundingBox())!, buttonBox = (await today.boundingBox())!
      expect(buttonBox.x - cardBox.x).toBeGreaterThanOrEqual(16)
      expect(cardBox.x + cardBox.width - buttonBox.x - buttonBox.width).toBeGreaterThanOrEqual(16)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
      if (width === 390) await page.screenshot({ path: testInfo.outputPath(`meal-controls-${theme}.png`), fullPage: true })
      await page.getByRole('link', { name: 'Program', exact: true }).click()
      await page.getByRole('button', { name: 'Programı düzenle', exact: true }).click()
      const title = page.getByRole('textbox', { name: 'Program başlığı', exact: true })
      await expect(title).toBeFocused()
      await expect(title).toBeInViewport()
      await page.getByRole('button', { name: 'Vazgeç', exact: true }).click()
      await expect(page.getByRole('button', { name: 'Programı düzenle', exact: true })).toBeFocused()
      const pagination = page.getByRole('navigation', { name: 'Beslenme programı sayfaları', exact: true })
      const refreshPlans = page.getByRole('button', { name: 'Programları yeniden kontrol et', exact: true })
      const paginationBox = (await pagination.boundingBox())!, refreshBox = (await refreshPlans.boundingBox())!
      expect(refreshBox.y - paginationBox.y - paginationBox.height).toBeGreaterThanOrEqual(20)
      if (width === 390) {
        await refreshPlans.scrollIntoViewIfNeeded()
        await page.screenshot({ path: testInfo.outputPath(`program-footer-${theme}.png`) })
      }
      await openNavigation('Bağlantılar ve davet')
      await page.getByRole('combobox', { name: 'Durum', exact: true }).selectOption('active')
      const end = page.getByRole('button', { name: 'Bağlantıyı sonlandır', exact: true })
      await end.click()
      const dialog = page.getByRole('alertdialog')
      await expect(dialog).toContainText('açık görevleriniz iptal edilecek')
      await expect(page.locator('#root')).toHaveAttribute('inert', '')
      await expect(dialog.getByRole('button', { name: 'Vazgeç', exact: true })).toBeFocused()
      await page.keyboard.press('Shift+Tab')
      await expect(dialog.getByRole('button', { name: 'Onayla ve sonlandır' })).toBeFocused()
      const box = (await dialog.boundingBox())!
      expect(box.x).toBeGreaterThanOrEqual(0); expect(box.x + box.width).toBeLessThanOrEqual(width)
      expect(box.y).toBeGreaterThanOrEqual(0); expect(box.y + box.height).toBeLessThanOrEqual(900)
      if (width === 390) await page.screenshot({ path: testInfo.outputPath(`relationship-confirmation-${theme}.png`) })
      await page.keyboard.press('Escape')
      await expect(dialog).toHaveCount(0)
      await expect(end).toBeFocused()
      await expect(page.locator('#root')).not.toHaveAttribute('inert', '')
    }
  }
  let writes = 0
  page.on('request', sent => { if (sent.method() === 'POST' && sent.url().endsWith(`/dietitian-relationships/${relation.id}/end`)) writes++ })
  await page.getByRole('button', { name: 'Bağlantıyı sonlandır', exact: true }).click()
  expect(writes).toBe(0)
  await page.getByRole('button', { name: 'Onayla ve sonlandır', exact: true }).click()
  await expect(page.getByText('Bağlantı sonlandırıldı.', { exact: true })).toBeVisible()
  expect(writes).toBe(1)
  expect((await api(request, `/api/v1/nutrition-plans/${plan.id}`, 'GET', 200, undefined, mobile.accessToken)).status).toBe('archived')
  const tasks = await api(request, '/api/v1/client-tasks?page=1&pageSize=10', 'GET', 200, undefined, mobile.accessToken)
  expect(tasks.items[0].status).toBe('cancelled'); expect(tasks.items[0].versionNumber).toBe(2)
})
