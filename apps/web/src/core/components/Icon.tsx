// Canonical shared SVG assets; unavailable symbols stay text-accessible at their call sites.
const assets = {
  target: null,
  leaf: 'leaf',
  grid: 'grid-2x2',
  user: 'user-round',
  users: 'users',
  link: null,
  plan: 'clipboard-list',
  layers: 'layers',
  chart: 'chart-column',
  activity: 'activity',
  lab: null,
  check: 'check',
  shield: 'shield-check',
  arrow: 'arrow-right',
  back: 'arrow-left',
  eye: 'eye',
  // The shared eye symbol uses the parent button's pressed state for visibility.
  eyeOff: 'eye',
  sun: null,
  menu: 'menu',
  chevron: 'chevron-down',
  close: 'x',
  search: 'search',
  clock: 'clock',
  water: 'glass-water',
  info: 'info',
  settings: 'settings',
  meal: 'salad',
  utensils: 'utensils',
  bowl: 'salad',
  plus: 'plus',
  mail: null,
  lock: null,
  camera: null,
  barcode: null,
  edit: 'pencil',
  energy: null,
  calendar: 'calendar-days',
  message: 'messages-square',
  attachment: 'file',
  send: 'send',
  scale: 'body-scale',
  bell: 'bell',
  refresh: 'rotate-ccw',
  download: null,
  database: null,
} as const
export type IconName = keyof typeof assets

export function Icon({ name, className = '' }: { name: IconName; className?: string }) {
  const asset = assets[name]
  if (!asset) {
    const labels: Record<string, string> = { eye: 'Göster', eyeOff: 'Gizle', attachment: 'Dosya', send: 'Gönder' }
    const text = labels[name]
    return text ? <span className={`icon-text ${className}`} aria-hidden="true">{text}</span> : null
  }
  return <span className={`icon ${className}`} aria-hidden="true">
    <img className="icon-normal" src={`/limely/ikonlar/koyu/${asset}.svg`} width="24" height="24" alt="" />
    <img className="icon-inverse" src={`/limely/ikonlar/beyaz/${asset}.svg`} width="24" height="24" alt="" />
  </span>
}

export function Brand({ inverse = false, subtitle = 'DİYETİSYEN' }: { inverse?: boolean; subtitle?: string }) {
  return <div className={`brand ${inverse ? 'brand-inverse' : ''}`}>
    <img className="brand-logo" src={`/limely/logolar/limely-yazili-logo-${inverse ? 'beyaz' : 'renkli'}.svg`} alt="Limely" width="202" height="73" />
    {subtitle && <small>{subtitle}</small>}
  </div>
}
