import { expect, test } from '@playwright/test'
import type { Page } from '@playwright/test'
import { mkdir, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-11-24T09:00:00Z'))
})

const previewClients = ['Deniz', 'İpek', 'Işık', 'Çağla', 'Öykü', 'Şule'].map((name, index) => ({ id: `10000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`, displayName: `Örnek ${name}` }))
function getPreviewRecords(clientId: string) {
  const mealLogs = ['lunch', 'snack', 'dinner'].map((mealType, index) => {
    const id = `20000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`
    return { id, clientId, mealType, consumedAt: `2026-11-24T${String(15 - index).padStart(2, '0')}:00:00Z`, createdAt: '2026-11-24T16:00:00Z', source: 'manual', foodAnalysisId: null, note: 'Yalnız görsel doğrulama için sentetik kayıt.', items: [{ id: `30000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`, mealLogId: id, foodItemId: null, recipeId: null, displayName: ['Sentetik mercimek çorbası', 'Sentetik meyve', 'Sentetik sebze öğünü'][index], quantityGrams: 150, caloriesKcal: 180, proteinGrams: 9, carbsGrams: 25, fatGrams: 5, isEstimated: false }] }
  })
  const bodyMeasurements = [0, 1, 2].map(index => ({ id: `70000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`, clientId, measuredAt: `2026-11-${24 - index}T08:00:00Z`, weightKg: 72 + index, waistCm: 80, hipCm: null, chestCm: null, bodyFatPercent: null, source: 'manual', note: 'Sentetik ölçüm' }))
  return { mealLogs, bodyMeasurements }
}

const expertId = '22222222-2222-4222-8222-222222222222'
const userId = '33333333-3333-4333-8333-333333333333'
const client = previewClients[0]!
const planId = '44444444-4444-4444-8444-444444444444'
const versionId = '55555555-5555-4555-8555-555555555555'
const plan = {
  id: planId, clientId: client.id, dietitianId: expertId, title: 'Sentetik haftalık program', status: 'draft', startDate: '2026-11-24', endDate: '2026-11-30',
  createdAt: '2026-11-24T08:00:00Z', versionId, versionNumber: 1, dailyCaloriesTargetKcal: 1700, dailyWaterTargetMl: 2000,
  items: ['Kahvaltı önerisi', 'Öğle önerisi', 'Akşam önerisi'].map((description, index) => ({ id: `60000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`, nutritionPlanId: planId, dayOfWeek: null, mealType: (['breakfast', 'lunch', 'dinner'] as const)[index]!, description, recommendedQuantity: 'Sentetik miktar', sortOrder: index, recipeId: null, alternativeGroupId: null })),
}

async function fixtures(page: Page) {
  const unexpected: string[] = []
  page.on('pageerror', error => unexpected.push(error.message))
  page.on('console', message => { if (message.type() === 'error') unexpected.push(message.text()) })
  await page.route('**/api/**', async route => {
    const url = new URL(route.request().url()), path = url.pathname
    const json = (body: unknown, status = 200) => route.fulfill({ status, json: body })
    if (path.endsWith('/auth/csrf')) return json({ requestToken: 'synthetic-presentation-csrf' })
    if (path.endsWith('/auth/me')) return json({ id: userId, displayName: 'Sentetik Diyetisyen', email: 'presentation@example.test', role: 'dietitian', isEmailVerified: true })
    if (path.endsWith('/dietitians/me')) return json({ id: expertId, displayName: 'Sentetik Diyetisyen', isVerified: true })
    if (path === '/api/v1/dietitian/clients') {
      const query = url.searchParams.get('query')?.toLocaleLowerCase('tr-TR') ?? ''
      const items = previewClients.filter(item => item.displayName.toLocaleLowerCase('tr-TR').includes(query))
      return json({ items, totalCount: items.length })
    }
    if (path === '/api/v1/dietitian-relationships') return json({ items: [], totalCount: 0 })
    const owner = path.match(/\/clients\/([^/]+)/)?.[1] ?? client.id
    const records = getPreviewRecords(owner)
    if (path.endsWith('/dashboard')) return json({ clientId: owner, displayName: previewClients.find(item => item.id === owner)?.displayName })
    if (path.endsWith('/meal-logs')) { const items = records.mealLogs.filter(row => (!url.searchParams.has('from') || Date.parse(row.consumedAt) >= Date.parse(url.searchParams.get('from')!)) && (!url.searchParams.has('to') || Date.parse(row.consumedAt) < Date.parse(url.searchParams.get('to')!))); return json({ items, totalCount: items.length }) }
    if (path.endsWith('/body-measurements')) return json({ items: records?.bodyMeasurements ?? [], totalCount: records?.bodyMeasurements.length ?? 0 })
    if (path.includes('/water-logs')) {
      const from = new Date(url.searchParams.get('from')!).toISOString(), to = new Date(url.searchParams.get('to')!).toISOString()
      if (path.endsWith('/daily-total')) return json({ from, to, totalAmountMl: 0 })
      if (path.endsWith('/daily-history')) return json({ items: Array.from({ length: Math.round((Date.parse(to) - Date.parse(from)) / 86400000) }, (_, index) => ({ from: new Date(Date.parse(from) + index * 86400000).toISOString(), to: new Date(Date.parse(from) + (index + 1) * 86400000).toISOString(), totalAmountMl: 0 })) })
      return json({ items: [], totalCount: 0 })
    }
    if (path.endsWith('/comments')) return json({ items: [], totalCount: 0 })
    if (path === '/api/v1/nutrition-plans') return json({ items: [plan], totalCount: 1 })
    if (path === '/api/v1/client-tasks') return json({ items: [], totalCount: 0 })
    if (path.startsWith('/api/v1/nutrition-plans/') && path.endsWith('/versions')) return json({ items: [{ id: versionId, nutritionPlanId: planId, versionNumber: 1, createdAt: plan.createdAt }], totalCount: 1 })
    if (path.includes('/versions/')) return json({ id: versionId, nutritionPlanId: planId, versionNumber: 1, createdAt: plan.createdAt, snapshot: { title: plan.title, startDate: plan.startDate, endDate: plan.endDate, dailyCaloriesTargetKcal: plan.dailyCaloriesTargetKcal, dailyWaterTargetMl: plan.dailyWaterTargetMl, items: plan.items } })
    unexpected.push(`Unhandled mock request: ${path}`)
    return route.fulfill({ status: 501, json: { error: { code: 'unexpected_test_request', message: 'No fixture' } } })
  })
  return unexpected
}

async function fits(page: Page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  expect(await page.locator('.sidebar').evaluateAll(sidebars => sidebars.flatMap(sidebar => {
    const bounds = sidebar.getBoundingClientRect()
    return [...sidebar.querySelectorAll('.sidebar nav a, .sidebar-account > a, .workspace-avatar')].flatMap(node => {
      const rect = node.getBoundingClientRect()
      return rect.width && (rect.left < bounds.left - 1 || rect.right > bounds.right + 1) ? [node.textContent] : []
    })
  }))).toEqual([])
  const escapedCards = await page.locator('.marketing-card .illustration-food-list > div, .marketing-card .illustration-options > span, .marketing-card .how-example-actions > span').evaluateAll(nodes => nodes.flatMap(node => {
    const card = node.closest('.marketing-card')!.getBoundingClientRect(), content = node.getBoundingClientRect()
    return content.left < card.left - 1 || content.right > card.right + 1 ? [node.textContent] : []
  }))
  expect(escapedCards).toEqual([])
}

for (const long of [false, true]) {
  test('nutrition program print ' + (long ? 'fragments a long program into A4 pages' : 'retains Limely layout on desktop and mobile'), async ({ page }, testInfo) => {
    const errors = await fixtures(page)
    const items = Array.from({ length: long ? 100 : 23 }, (_, index) => ({
      ...plan.items[0]!, id: '90000000-0000-4000-8000-' + String(index + 1).padStart(12, '0'), sortOrder: index,
      dayOfWeek: index === 0 ? null : long || index <= 2 ? 1 : (index - 1) % 7 + 1,
      mealType: index <= 2 || long ? 'breakfast' : (['lunch', 'dinner', 'snack', 'other'] as const)[Math.floor(index / 7)]!,
      description: 'SENTETIK-' + String(index + 1).padStart(3, '0') + ' · Çığ, öğün, ıspanak ve yoğurt önerisi. ' +
        (long ? 'Bu açıklama yalnız sayfa bölünmesi ve Türkçe karakter doğrulaması içindir. '.repeat(4) + 'UzunBesinAçıklaması'.repeat(8) : 'Diyetisyenin kaydettiği öneri metni.'),
      recommendedQuantity: index % 3 === 0 ? null : '½ kase · kayıtlı miktar',
      alternativeGroupId: !long && (index === 1 || index === 2) ? '80000000-0000-4000-8000-000000000001' : null,
    }))
    const printable = { ...plan, status: 'active', title: 'Sentetik Çıktı Programı', items }
    await page.route('**/api/v1/nutrition-plans**', async route => {
      const path = new URL(route.request().url()).pathname
      if (path === '/api/v1/nutrition-plans') return route.fulfill({ json: { items: [printable], totalCount: 1 } })
      if (path === '/api/v1/nutrition-plans/' + planId) return route.fulfill({ json: printable })
      if (path === '/api/v1/nutrition-plans/' + planId + '/versions/' + versionId) return route.fulfill({ json: {
        id: versionId, nutritionPlanId: planId, versionNumber: 1, createdAt: plan.createdAt,
        snapshot: { title: printable.title, startDate: plan.startDate, endDate: plan.endDate,
          dailyCaloriesTargetKcal: plan.dailyCaloriesTargetKcal, dailyWaterTargetMl: plan.dailyWaterTargetMl, items },
      } })
      errors.push('Unexpected print fixture request: ' + path)
      return route.fulfill({ status: 501, json: { error: { code: 'unexpected_test_request', message: 'No fixture' } } })
    })
    await page.setViewportSize({ width: 1440, height: 1000 })
    await page.goto('/calisma-alani/programlar?clientId=' + client.id)
    await page.getByRole('button', { name: printable.title + ' programını yazdır', exact: true }).waitFor()
    await page.screenshot({ path: testInfo.outputPath('program-cards.png') })
    await page.getByRole('button', { name: printable.title + ' programını yazdır', exact: true }).click()
    const printButton = page.getByRole('button', { name: 'Yazdır / PDF', exact: true })
    await expect(printButton).toBeEnabled()
    const document = page.getByRole('article', { name: 'Yazdırılabilir beslenme programı' })
    await expect(document.locator('.nutrition-print-item')).toHaveCount(items.length)
    await expect(document.getByRole('heading', { name: 'Her gün', exact: true })).toBeVisible()
    expect(await document.locator('.nutrition-print-days').evaluate(element => getComputedStyle(element).gridTemplateColumns.split(' ').length)).toBe(2)
    await expect(page.getByRole('heading', { name: 'Programlar', exact: true })).not.toBeVisible()
    expect(await document.locator('h1').evaluate(element => getComputedStyle(element).fontFamily)).toContain('Manrope')
    await page.screenshot({ path: testInfo.outputPath('print-desktop.png'), fullPage: !long })
    if (!long) {
      for (const width of [768, 390, 320]) {
        await page.setViewportSize({ width, height: 900 })
        await fits(page)
        expect(await document.evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true)
        if (width <= 700) expect(await document.locator('.nutrition-print-days').evaluate(element => getComputedStyle(element).gridTemplateColumns.split(' ').length)).toBe(1)
        await page.screenshot({ path: testInfo.outputPath('print-mobile-' + width + '.png'), fullPage: true })
      }
      await page.setViewportSize({ width: 1440, height: 1000 })
    }
    await page.emulateMedia({ media: 'print' })
    await expect(page.locator('.sidebar')).not.toBeVisible()
    await expect(printButton).not.toBeVisible()
    await expect(page.locator('.nutrition-panel')).not.toBeVisible()
    await expect(document).toBeVisible()
    const pdf = await page.pdf({ path: testInfo.outputPath(long ? 'program-long-a4.pdf' : 'program-a4.pdf'),
      format: 'A4', preferCSSPageSize: true, printBackground: false, displayHeaderFooter: false })
    expect(pdf.subarray(0, 4).toString()).toBe('%PDF')
    if (long) expect((pdf.toString('latin1').match(/\/Type\s*\/Page\b/g) ?? []).length).toBeGreaterThan(1)
    await page.emulateMedia({ media: 'screen' })
    await page.getByRole('button', { name: 'Programlara dön' }).click()
    await expect(page.getByRole('heading', { name: 'Programlar', exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: printable.title + ' programını yazdır', exact: true })).toBeFocused()
    await page.goto('/calisma-alani/raporlar?clientId=' + client.id)
    await expect(page.getByRole('heading', { name: 'Raporlar', exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: /Yazdır|PDF/ })).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'CSV indir' })).toBeEnabled()
    expect(errors).toEqual([])
  })
}

for (const width of [1585, 1024, 768, 390]) {
  test(`reference screens and responsive layout at ${width}px`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width, height: width === 390 ? 844 : 992 })
    const errors = await fixtures(page)
    const routes = ['/nasil-calisir', '/ozellikler', '/diyetisyenler-icin', '/giris', '/uzman-basvurusu', '/sifremi-unuttum', '/eposta-dogrulama', '/yonetici-giris', '/calisma-alani', '/calisma-alani/danisanlar', '/calisma-alani/ogun-incelemeleri', '/calisma-alani/programlar', '/calisma-alani/randevular', '/calisma-alani/mesajlar', '/calisma-alani/raporlar', '/hesabim', '/calisma-alani/baglantilar', `/calisma-alani/danisanlar/${client.id}?bolum=gorevler`]
    for (const path of routes) {
      await page.goto(path)
      await expect(page.locator('h1')).toBeVisible()
      await expect(page.getByText('Hesap ve uzman doğrulaması kontrol ediliyor…')).toHaveCount(0)
      if (path === '/calisma-alani/danisanlar') await expect(page.getByRole('link', { name: `${client.displayName} için danışan detayını aç` })).toBeVisible()
      if (path.endsWith('/programlar')) await expect(page.getByRole('heading', { name: plan.title })).toBeVisible()
      if (path.endsWith('/ogun-incelemeleri')) await expect(page.locator('.meal-record').getByRole('heading', { name: client.displayName })).toBeVisible()
      if (path.endsWith('/raporlar')) await expect(page.getByRole('img', { name: 'Seçilen danışanın haftalara göre öğün sayıları' })).toBeVisible()
      await page.evaluate(() => document.fonts.ready)
      if (path.endsWith('/randevular')) expect(await page.locator('.calendar-view button').evaluateAll(buttons => buttons.every(button => button.scrollWidth <= button.clientWidth && button.getBoundingClientRect().height < 55))).toBe(true)
      await fits(page)
      await page.screenshot({ path: testInfo.outputPath(`${path.replace(/[^a-z0-9]+/gi, '-')}-${width}.png`), fullPage: true })
    }
    expect(errors).toEqual([])
  })
}

test('program draft, meal selection, keyboard menus and empty client search', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1585, height: 992 })
  const errors = await fixtures(page)
  await page.goto('/calisma-alani/programlar')
  await page.locator('.program-content-disclosure > summary').first().click()
  await page.getByRole('button', { name: 'Sürüm geçmişini aç' }).click()
  await expect(page.getByRole('region', { name: 'Program sürüm geçmişi' })).toBeVisible()
  await page.getByRole('button', { name: 'Sürüm 1', exact: true }).click()
  await expect(page.getByRole('heading', { name: `Sürüm 1: ${plan.title}` })).toBeVisible()
  await page.getByRole('button', { name: 'Geçmişi kapat' }).click()
  await page.getByRole('button', { name: 'Programı arşivle', exact: true }).click()
  await expect(page.getByRole('alertdialog', { name: 'Programı arşivle' })).toBeVisible()
  await page.getByRole('button', { name: 'Düzenlemeye dön' }).click()
  await page.locator('.program-content-disclosure > summary').first().click()
  await page.getByRole('button', { name: 'Yeni program oluştur' }).click()
  await expect(page.getByLabel('Program başlığı', { exact: true })).toBeFocused()
  await page.getByLabel('Program başlığı', { exact: true }).fill('Sentetik düzenlenebilir taslak')
  await page.getByRole('combobox', { name: 'Danışan seç', exact: true }).selectOption(previewClients[1]!.id)
  await expect(page.getByRole('alertdialog', { name: 'Danışanı değiştir' })).toBeVisible()
  await page.getByRole('button', { name: 'Düzenlemeye dön' }).click()
  await expect(page.getByLabel('Program başlığı', { exact: true })).toHaveValue('Sentetik düzenlenebilir taslak')
  await fits(page)
  await page.screenshot({ path: testInfo.outputPath('program-editor-1585.png'), fullPage: true })
  await page.setViewportSize({ width: 390, height: 844 })
  await fits(page)
  expect(await page.locator('.plan-days button').evaluateAll(buttons => buttons.every(button => button.getBoundingClientRect().height <= 48))).toBe(true)
  await page.getByRole('button', { name: 'Cuma', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Cuma', exact: true })).toHaveAttribute('aria-pressed', 'true')
  await page.getByRole('button', { name: 'Her gün', exact: true }).click()
  await page.screenshot({ path: testInfo.outputPath('program-editor-390.png'), fullPage: true })
  await page.goto('/calisma-alani/ogun-incelemeleri')
  await page.getByRole('button', { name: /Öğle öğünü/ }).click()
  await expect(page.locator('.meal-record').getByRole('heading', { name: client.displayName })).toBeVisible()
  await expect(page.getByRole('textbox', { name: 'Öğüne yorumunuz' })).toBeEditable()
  await page.locator('.meal-nutrition-values > summary').first().click()
  await expect(page.getByText('180 kcal', { exact: true })).toBeVisible()
  await fits(page)
  await page.getByRole('button', { name: 'Menüyü aç' }).click()
  await page.getByRole('button', { name: 'Menüyü kapat' }).press('Escape')
  await expect(page.getByRole('button', { name: 'Menüyü aç' })).toBeFocused()
  await page.goto('/calisma-alani/danisanlar')
  await page.getByRole('searchbox', { name: 'Danışan adı' }).fill('Olmayan sentetik danışan')
  await page.getByRole('button', { name: 'Ara', exact: true }).click()
  await expect(page.getByText('Aramanıza uygun danışan bulunamadı')).toBeVisible()
  await page.getByRole('button', { name: 'Filtreyi temizle' }).click()
  await expect(page.getByRole('link', { name: `${client.displayName} için danışan detayını aç` })).toBeVisible()
  await page.route('**/api/v1/dietitian/clients?*', route => route.fulfill({ json: { items: previewClients, totalCount: 100 } }))
  await page.reload()
  await page.getByRole('button', { name: '5. sayfayı aç' }).click()
  await expect(page.getByRole('button', { name: '5. sayfayı aç' })).toHaveAttribute('aria-current', 'page')
  await expect(page.getByText('41–46 / 100 danışan')).toBeVisible()
  await fits(page)
  await page.screenshot({ path: testInfo.outputPath('client-pagination-390.png'), fullPage: true })
  expect(errors).toEqual([])
})

test('approved brand assets and visual selection retain the native filter contract', async ({ page }, testInfo) => {
  const errors = await fixtures(page)
  await page.setViewportSize({ width: 1585, height: 992 })
  await page.goto('/calisma-alani/danisanlar')
  await expect(page.getByRole('link', { name: `${client.displayName} için danışan detayını aç` })).toBeVisible()
  await page.evaluate(() => document.fonts.ready)
  expect(await page.locator('body').evaluate(element => getComputedStyle(element).backgroundColor)).toBe('rgb(248, 250, 242)')
  expect(await page.locator('h1').evaluate(element => getComputedStyle(element).fontFamily)).toContain('Manrope')
  expect(await page.locator('body').evaluate(element => getComputedStyle(element).fontFamily)).toContain('Inter')
  await expect(page.locator('.brand-logo')).toHaveAttribute('src', '/limely/logolar/limely-yazili-logo-renkli.svg')
  expect(await page.locator('.icon svg, .brand svg').count()).toBe(0)
  const select = page.getByRole('combobox', { name: 'Sıralama', exact: true })
  await select.click()
  const popup = page.getByRole('listbox', { name: 'Sıralama seçenekleri' })
  await expect(popup).toBeVisible()
  const request = page.waitForRequest(request => request.url().includes('/dietitian/clients?') && new URL(request.url()).searchParams.get('sortOrder') === 'desc')
  await popup.getByRole('option', { name: 'Ad: Z → A', exact: true }).click()
  await request
  await expect(select).toHaveValue('desc')
  await expect(select).toBeFocused()
  await select.press('Home'); await select.press('Enter')
  await expect(select).toHaveValue('asc')
  await select.click(); await select.press('ArrowDown'); await select.press('Escape')
  await expect(select).toHaveValue('asc')
  await select.click()
  await page.screenshot({ path: testInfo.outputPath('approved-select-1585.png') })
  await select.press('Escape')
  await fits(page)
  expect(errors).toEqual([])
})

test('approved calendar edits the existing program draft without an API write', async ({ page }, testInfo) => {
  const errors = await fixtures(page)
  const writes: string[] = []
  page.on('request', request => { if (request.url().includes('/api/') && !['GET', 'HEAD'].includes(request.method())) writes.push(request.url()) })
  await page.goto('/calisma-alani/programlar')
  await page.getByRole('button', { name: 'Yeni program oluştur', exact: true }).click()
  await page.getByLabel('Program başlığı', { exact: true }).fill('Sentetik takvim taslağı')
  for (const width of [1585, 768, 390]) {
    await page.setViewportSize({ width, height: width === 390 ? 844 : 992 })
    const control = page.locator('.date-control').filter({ has: page.locator('#plan-start') })
    await control.getByRole('button').click()
    const calendar = page.getByRole('dialog', { name: 'Tarih seç' })
    await expect(calendar).toBeVisible()
    await expect(calendar.locator('[data-date][tabindex="0"]')).toBeFocused()
    await page.keyboard.press('ArrowRight')
    await expect(calendar.locator('[data-date][tabindex="0"]')).toBeFocused()
    await expect(calendar.getByRole('columnheader')).toHaveCount(7)
    const box = (await calendar.boundingBox())!
    expect(box.x).toBeGreaterThanOrEqual(11)
    expect(box.x + box.width).toBeLessThanOrEqual(width - 11)
    await page.screenshot({ path: testInfo.outputPath(`approved-calendar-${width}.png`) })
    await calendar.getByRole('gridcell', { name: '27 Kasım 2026', exact: true }).click()
    await expect(page.locator('#plan-start')).toHaveValue('2026-11-27')
    await expect(page.getByLabel('Program başlığı', { exact: true })).toHaveValue('Sentetik takvim taslağı')
    await fits(page)
  }
  expect(writes).toEqual([])
  expect(errors).toEqual([])
})

test('report permission denial keeps unknown counts and prevents CSV export', async ({ page }) => {
  await fixtures(page)
  await page.route('**/api/v1/dietitian/clients/*/meal-logs?*', route => route.fulfill({ status: 403, json: { error: { code: 'forbidden', message: 'Synthetic denial' } } }))
  await page.goto('/calisma-alani/raporlar')
  await expect(page.getByRole('alert').filter({ hasText: 'Öğün paylaşımı kapalı' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'CSV indir' })).toBeDisabled()
  await expect(page.getByRole('img', { name: 'Seçilen danışanın haftalara göre öğün sayıları' })).toHaveCount(0)
  await expect(page.getByRole('heading', { name: 'Dönemdeki öğün' }).locator('..')).toHaveText(/—/)
})

test('report CSV contains the selected synthetic client and server counts', async ({ page }) => {
  const errors = await fixtures(page)
  await page.goto('/calisma-alani/raporlar')
  const exportButton = page.getByRole('button', { name: 'CSV indir' })
  await expect(exportButton).toBeEnabled()
  const downloadEvent = page.waitForEvent('download')
  await exportButton.click()
  const download = await downloadEvent
  expect(download.suggestedFilename()).toBe('limely-danisan-ozeti.csv')
  const stream = await download.createReadStream()
  expect(stream).not.toBeNull()
  let contents = ''
  for await (const chunk of stream!) contents += chunk.toString('utf8')
  expect(contents).toContain('Örnek Deniz')
  expect(contents).toContain('"Öğün kaydı";"Kayıtlı program";"Kayıtlı ölçüm"')
  expect(contents).toMatch(/;"3";"1";"3"/)
  expect(errors).toEqual([])
})

// Capture the UI area at its source dimensions, independently of the responsive checks.
test('each full resolution web reference and the program side panel', async ({ page }) => {
  const errors = await fixtures(page)
  const folder = resolve('node_modules/.cache/visual-revision/current')
  await mkdir(folder, { recursive: true })
  const cases = [
    ['00', '/calisma-alani/raporlar', 1586, 992], ['01', '/calisma-alani/danisanlar', 1585, 992],
    ['02', '/calisma-alani/mesajlar', 1585, 992], ['03', '/calisma-alani/programlar', 1585, 992],
    ['04', '/diyetisyenler-icin', 1586, 992], ['05', '/calisma-alani/ogun-incelemeleri', 1586, 992],
    ['06', '/hesabim', 1585, 992], ['login', '/giris', 706, 914],
    ['register', '/uzman-basvurusu', 719, 914], ['10', '/ozellikler', 1585, 992],
    ['11', '/calisma-alani/randevular', 1586, 992], ['12', '/nasil-calisir', 1586, 992],
  ] as const
  const inventory = []
  for (const [reference, path, width, height] of cases) {
    await page.setViewportSize({ width, height })
    if (reference === '03') {
      await page.route('**/api/v1/nutrition-plans?**', route => route.fulfill({ json: { items: [0, 1, 2, 3].map(index => {
        const id = `44444444-4444-4444-8444-${String(index + 1).padStart(12, '0')}`
        return { ...plan, id, title: ['Sentetik dengeli program', 'Sentetik haftalık program', 'Sentetik ikinci program', 'Sentetik üçüncü program'][index], items: plan.items.map((item, i) => ({ ...item, id: `60000000-0000-4000-8000-${String(index * 10 + i + 1).padStart(12, '0')}`, nutritionPlanId: id })) }
      }), totalCount: 4 } }))
    }
    if (reference === 'login') await page.emulateMedia({ colorScheme: 'dark' })
    await page.goto(path)
    await expect(page.locator('h1')).toBeVisible()
    if (reference === 'login') {
      await expect(page.locator('html')).toHaveAttribute('data-theme', 'light')
      await expect(page.locator('meta[name="color-scheme"]')).toHaveAttribute('content', 'light')
      expect(await page.locator('html').evaluate(element => getComputedStyle(element).colorScheme)).toBe('light')
      await expect(page.getByRole('button', { name: /^Görünüm/ })).toHaveCount(0)
    }
    await expect(page.getByText('Hesap ve uzman doğrulaması kontrol ediliyor…')).toHaveCount(0)
    if (reference === '00') await expect(page.getByRole('img', { name: 'Seçilen danışanın haftalara göre öğün sayıları' })).toBeVisible()
    if (reference === '01') await expect(page.getByRole('link', { name: `${client.displayName} için danışan detayını aç` })).toBeVisible()
    if (reference === '03') {
      await expect(page.getByRole('heading', { name: 'Sentetik dengeli program' })).toBeVisible()
      await page.getByRole('button', { name: 'Programı düzenle', exact: true }).first().click()
      await expect(page.getByLabel('Program başlığı', { exact: true })).toHaveValue('Sentetik dengeli program')
      await expect(page.locator('.nutrition-editor').getByRole('button', { name: 'Vazgeç', exact: true })).toBeInViewport()
    }
    if (reference === '05') await expect(page.getByRole('textbox', { name: 'Öğüne yorumunuz' })).toBeEditable()
    if (reference === '06') await expect(page.getByText('presentation@example.test', { exact: true })).toBeVisible()
    await page.evaluate(() => document.fonts.ready)
    await fits(page)
    await page.screenshot({ path: resolve(folder, `${reference}.png`) })
    const geometry = await page.locator('h1, .sidebar, .client-table, .nutrition-editor, .metric-card, .marketing-card, .settings-profile').evaluateAll(elements => elements.map(element => { const r = element.getBoundingClientRect(); const style = getComputedStyle(element); return { selector: element.className || element.tagName, x: r.x, y: r.y, width: r.width, height: r.height, font: style.font, color: style.color, background: style.backgroundColor } }))
    inventory.push({ reference, path, width, height, geometry })
  }
  await writeFile(resolve(folder, 'geometry.json'), JSON.stringify(inventory, null, 2))
  expect(errors).toEqual([])
})
