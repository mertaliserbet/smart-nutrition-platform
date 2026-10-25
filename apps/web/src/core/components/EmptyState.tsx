import type { ReactNode } from 'react'
import { Icon } from './Icon'
import type { IconName } from './Icon'

export function EmptyState({ icon, title, children, action }: {
  icon: IconName; title: string; children: ReactNode; action?: ReactNode
}) {
  return (
    <div className="empty-state">
      <span className="empty-icon"><Icon name={icon} /></span><h3>{title}</h3><p>{children}</p>{action}
    </div>
  )
}
