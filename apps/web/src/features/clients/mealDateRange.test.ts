import { execFileSync } from 'node:child_process'
import { describe, expect, it } from 'vitest'

// Start Node with TZ set before Date initializes (including on Windows).
// Transpile the actual module graph, not a reimplementation of its arithmetic.
function rangeInZone(zone: string, expression: string) {
  const code = `
    const fs = require('node:fs'), ts = require('typescript');
    require.extensions['.ts'] = (module, path) => module._compile(ts.transpileModule(fs.readFileSync(path, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText, path);
    const { mealDateRange, mealPeriodRange } = require('./src/features/clients/mealDateRange.ts');
    process.stdout.write(JSON.stringify(${expression}));
  `
  return JSON.parse(execFileSync(process.execPath, ['-e', code], { cwd: process.cwd(), env: { ...process.env, TZ: zone }, encoding: 'utf8' })) as { from: string; to: string }
}
describe('local meal calendar boundaries', () => {
  it('includes an Istanbul 00:15 meal, excludes the next midnight and agrees with water/comparison boundaries', () => {
    const range = rangeInZone('Europe/Istanbul', "mealDateRange('2026-11-21', '2026-11-21')")
    expect(range).toEqual({ from: '2026-11-20T21:00:00.000Z', to: '2026-11-21T21:00:00.000Z' })
    const meal = Date.parse('2026-11-21T00:15:00+03:00')
    expect(meal).toBeGreaterThanOrEqual(Date.parse(range.from)); expect(meal).toBeLessThan(Date.parse(range.to))
    expect(Date.parse('2026-11-22T00:00:00+03:00')).toBe(Date.parse(range.to))
  })
  it('computes today, yesterday and the last seven inclusive calendar days', () => {
    expect(rangeInZone('Europe/Istanbul', "mealPeriodRange('today', new Date('2026-11-21T00:15:00+03:00'))").from).toBe('2026-11-20T21:00:00.000Z')
    expect(rangeInZone('Europe/Istanbul', "mealPeriodRange('yesterday', new Date('2026-11-21T00:15:00+03:00'))").to).toBe('2026-11-20T21:00:00.000Z')
    expect(rangeInZone('Europe/Istanbul', "mealPeriodRange('week', new Date('2026-11-21T00:15:00+03:00'))")).toEqual({ from: '2026-11-14T21:00:00.000Z', to: '2026-11-21T21:00:00.000Z' })
  })
  it.each([
    ['2026-03-29', '2026-03-28T23:00:00.000Z', '2026-03-29T22:00:00.000Z', 23],
    ['2026-10-25', '2026-10-24T22:00:00.000Z', '2026-10-25T23:00:00.000Z', 25],
  ])('preserves the %s Europe/Berlin DST day (%s to %s)', (date, from, to, hours) => {
    const range = rangeInZone('Europe/Berlin', `mealDateRange('${date}', '${date}')`)
    expect(range).toEqual({ from, to }); expect((Date.parse(to) - Date.parse(from)) / 3600000).toBe(hours)
  })
  it('computes a seven-day range crossing DST by calendar, not 168 hours', () => {
    const range = rangeInZone('Europe/Berlin', "mealPeriodRange('week', new Date('2026-03-30T12:00:00+02:00'))")
    expect(range).toEqual({ from: '2026-03-23T23:00:00.000Z', to: '2026-03-30T22:00:00.000Z' })
  })
})
