import { test, expect } from '@playwright/test'
import type { APIRequestContext, Page } from '@playwright/test'
import { execFileSync } from 'node:child_process'
import { randomUUID } from 'node:crypto'

const origin = 'https://localhost:5446', password = 'Synthetic U6 password 🔑', changedPassword = ' New synthetic U6 password 🔒 '
type Account = { id: string; email: string; displayName: string }
type Identity = { accessToken: string; refreshToken: string }
async function api(request: APIRequestContext, path: string, method: string, status: number, data?: object, bearer?: string) {
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
  await expect(page.getByRole('heading', { name: 'Danışan detayı', exact: true })).toBeVisible()
  const tasks = page.getByRole('region', { name: 'Danışan görevleri' }), waterPanel = page.getByRole('region', { name: 'Su takibi', exact: true })
  await expect(waterPanel.getByRole('alert')).toContainText('Su paylaşımı kapalı')
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
  const grant = await api(request, '/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category: 'water_logs', isGranted: true }, mobile.accessToken)
  await waterPanel.getByRole('button', { name: 'Su takibini yenile' }).click()
  await expect(waterPanel.getByRole('status', { name: 'Seçilen günün su toplamı' })).toContainText('321,125 mL')
  await expect(waterPanel.getByRole('table')).toBeVisible()
  await api(request, `/api/v1/data-sharing-permissions/${grant.id}`, 'PATCH', 200, { isGranted: false }, mobile.accessToken)
  await waterPanel.getByRole('button', { name: 'Su takibini yenile' }).click()
  await expect(waterPanel.getByRole('alert')).toContainText('Su paylaşımı kapalı')
  await expect(waterPanel.getByText('321,125 mL', { exact: true })).toHaveCount(0)
  await expect(waterPanel.getByRole('table')).toHaveCount(0)
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
