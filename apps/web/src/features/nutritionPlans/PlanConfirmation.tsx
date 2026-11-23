import { ConfirmationDialog } from '../../core/components/ConfirmationDialog'

export function PlanConfirmation({ title, children, confirmLabel, onConfirm, onCancel }: {
  title: string; children: React.ReactNode; confirmLabel: string; onConfirm: () => void; onCancel: () => void
}) {
  return <ConfirmationDialog title={title} confirmLabel={confirmLabel} cancelLabel="Düzenlemeye dön" onConfirm={onConfirm} onCancel={onCancel}>{children}</ConfirmationDialog>
}
