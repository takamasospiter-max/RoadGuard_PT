import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

interface ConfirmDialogProps {
  open: boolean
  title: string
  description: string
  confirmLabel: string
  destructive?: boolean
  onConfirm: () => void
  onCancel: () => void
}

// Generic "are you sure?" modal — currently only used for deactivating a
// user (Users page), but written to be reusable for any yes/no
// confirmation. The parent controls `open` (usually by storing "which
// record am I about to act on?" and checking it's non-null).
export function ConfirmDialog({
  open,
  title,
  description,
  confirmLabel,
  destructive = false,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  return (
    // Backdrop: clicking it cancels, same as clicking outside a native
    // dialog. Stays mounted even when closed (opacity 0 + pointer-events
    // none) so the fade-out transition can play instead of instantly
    // disappearing.
    <div
      className={cn(
        'fixed inset-0 z-[1400] flex items-center justify-center bg-black/30 p-4 backdrop-blur-[2px] transition-opacity duration-200',
        open ? 'opacity-100' : 'pointer-events-none opacity-0',
      )}
      onClick={onCancel}
      aria-hidden={!open}
    >
      {open && (
        <div
          role="alertdialog"
          aria-modal="true"
          className="w-full max-w-sm rounded-2xl border border-border-light bg-surface p-6 shadow-xl"
          // Stop the click from bubbling up to the backdrop above, which
          // would otherwise close the dialog when clicking inside it.
          onClick={(e) => e.stopPropagation()}
        >
          <h2 className="text-base font-semibold text-text-primary">{title}</h2>
          <p className="mt-2 text-sm text-text-secondary">{description}</p>
          <div className="mt-5 flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={onCancel}>
              Cancel
            </Button>
            <Button
              type="button"
              onClick={onConfirm}
              className={destructive ? 'bg-severity-high hover:bg-severity-high/90' : undefined}
            >
              {confirmLabel}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
