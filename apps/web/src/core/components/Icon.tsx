const paths = {
  target: 'M21 12a9 9 0 1 1-9-9m6 9a6 6 0 1 1-6-6m3 6a3 3 0 1 1-3-3m0 3L22 2m-5 0h5v5',
  leaf: 'M20 4c-8-2-16 2-16 9a7 7 0 0 0 7 7c7 0 11-8 9-16ZM4 20 15 9M9 15v-5m0 5h5',
  grid: 'M4 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Zm11 0h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1ZM4 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1Zm11 0h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1Z',
  user: 'M20 21v-2a6 6 0 0 0-6-6h-4a6 6 0 0 0-6 6v2M16 6a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
  users: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m20 0v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
  link: 'M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71',
  plan: 'M8 3H5a2 2 0 0 0-2 2v15a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1V5a2 2 0 0 0-2-2h-3M8 2h8v4H8zM7 11h10M7 16h7',
  layers: 'm12 2 10 6-10 6L2 8l10-6ZM2 12l10 6 10-6M2 16l10 6 10-6',
  chart: 'M3 3v18h18M7 17v-5m4 5V7m4 10v-7m4 7V4M7 8v.1m8-2v.1',
  activity: 'M15 4a2 2 0 1 1-4 0 2 2 0 0 1 4 0ZM7 21l4-7m5 7-3-8 1-6m-8 5 4-5h4l3 5h4',
  lab: 'M8 3h8M10 3v7l-5 8a2 2 0 0 0 1.7 3h10.6a2 2 0 0 0 1.7-3l-5-8V3M8 15h8',
  check: 'm5 12 4 4L19 6',
  shield: 'm12 2 8 4v6c0 5-8 10-8 10S4 17 4 12V6l8-4Zm-4 10 3 3 5-6',
  arrow: 'M4 12h16m-6-6 6 6-6 6',
  back: 'M20 12H4m6-6-6 6 6 6',
  eye: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Zm13 0a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z',
  eyeOff: 'm3 3 18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M7 5.5A13 13 0 0 1 12 5c6 0 10 7 10 7a20 20 0 0 1-4 4M4.5 7.5A25 25 0 0 0 2 12s4 7 10 7a13 13 0 0 0 4.5-.8',
  sun: 'M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.4 1.4m11.2 11.2L19 19M5 19l1.4-1.4M17.6 6.4 19 5M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
  menu: 'M4 6h16M4 12h16M4 18h16',
  chevron: 'm6 9 6 6 6-6',
  close: 'm6 6 12 12M6 18 18 6',
  search: 'm16 16 5 5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0Z',
  clock: 'M12 8v5l3 2M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z',
  water: 'M12 2S4 11 4 15a8 8 0 0 0 16 0c0-4-8-13-8-13Zm-4 13a4 4 0 0 0 4 4',
  info: 'M12 11v6m0-10v.1M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z',
  settings: 'M9.09 4.98 10.03 4.66 10.26 2.15 13.74 2.15 13.97 4.66 14.91 4.98 15.80 5.42 17.74 3.81 20.19 6.26 18.58 8.20 19.02 9.09 19.34 10.03 21.85 10.26 21.85 13.74 19.34 13.97 19.02 14.91 18.58 15.80 20.19 17.74 17.74 20.19 15.80 18.58 14.91 19.02 13.97 19.34 13.74 21.85 10.26 21.85 10.03 19.34 9.09 19.02 8.20 18.58 6.26 20.19 3.81 17.74 5.42 15.80 4.98 14.91 4.66 13.97 2.15 13.74 2.15 10.26 4.66 10.03 4.98 9.09 5.42 8.20 3.81 6.26 6.26 3.81 8.20 5.42ZM15.5 12a3.5 3.5 0 1 1-7 0a3.5 3.5 0 0 1 7 0Z',
  meal: 'M3 12h18a9 9 0 0 1-18 0Zm3-4V5m6 3V3m6 5V5M7 22h10',
  utensils: 'M3 2v6a3 3 0 0 0 6 0V2M6 2v20M17 2c-4 0-4 10 0 10s4-10 0-10Zm0 10v10',
  bowl: 'M3 11h18a9 9 0 0 1-18 0Zm4 11h10M8 10c0-4 5-6 9-5-1 4-5 7-9 5Zm0 0 12-8',
  plus: 'M12 5v14M5 12h14',
  mail: 'M4 5h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1ZM3 6l9 7 9-7',
  lock: 'M6 10h12a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1Zm2 0V6a4 4 0 0 1 8 0v4m-4 5v2',
  camera: 'M4 6h4l2-3h4l2 3h4a2 2 0 0 1 2 2v11H2V8a2 2 0 0 1 2-2Zm12 6a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
  barcode: 'M3 4v16M6 6v12M9 4v16m4-16v16m3-14v12m3-14v16m3-16v16',
  edit: 'm15 3 6 6L8 22H2v-6L15 3Zm-4 4 6 6',
  energy: 'm13 2-9 12h7l-1 8 10-13h-7l1-7Z',
  calendar: 'M3 5h18v16H3zM7 2v6m10-6v6M3 11h18',
  message: 'M4 3h13a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-7l-5 4v-4H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm15 3h1a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2h-2v2l-4-3',
  attachment: 'm9 16 8-8a3 3 0 0 0-4-4L3 14a5 5 0 0 0 7 7L21 10a7 7 0 0 0-10-10',
  send: 'm2 3 20 9-20 9 4-9-4-9Zm4 9h16',
  scale: 'M4 3h16a2 2 0 0 1 2 2v15a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm3 4h10l-2 5H9L7 7Zm5 0v3',
  bell: 'M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4',
  refresh: 'M20 7v5h-5M4 17v-5h5M5 7a8 8 0 0 1 13-2l2 2M4 17l2 2a8 8 0 0 0 13-2',
  download: 'M12 3v12m-5-5 5 5 5-5M3 15v6h18v-6',
  database: 'M21 5c0 2-4 3-9 3S3 7 3 5s4-3 9-3 9 1 9 3Zm0 0v14c0 2-4 3-9 3s-9-1-9-3V5m0 7c0 2 4 3 9 3s9-1 9-3',
} as const

export type IconName = keyof typeof paths

export function Icon({ name, className = '' }: { name: IconName; className?: string }) {
  return (
    <svg className={`icon ${className}`} viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round"
      aria-hidden="true" focusable="false"><path d={paths[name]} /></svg>
  )
}

export function Brand({ inverse = false, subtitle = 'DİYETİSYEN' }: { inverse?: boolean; subtitle?: string }) {
  return (
    <div className={`brand ${inverse ? 'brand-inverse' : ''}`}>
      <img className="brand-logo" src="/images/limely-logo.png" alt="limely" width="202" height="60" />
      <span className="brand-fallback" aria-hidden="true">
      <img className="brand-mark" src="/limely-mark.svg" width="44" height="48" alt="" />
      <span className="brand-wordmark">limely</span></span>{subtitle && <small>{subtitle}</small>}
    </div>
  )
}
