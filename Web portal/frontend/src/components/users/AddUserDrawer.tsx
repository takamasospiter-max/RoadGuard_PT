import { Mail, X } from 'lucide-react'
import { useState } from 'react'
import { UserFormFields, type UserFormValues } from '@/components/users/UserFormFields'
import { Button } from '@/components/ui/button'
import { ApiError } from '@/lib/api'
import { cn } from '@/lib/utils'
import type { PortalUser } from '@/types'

const emptyForm: UserFormValues = {
  name: '',
  email: '',
  phone: '',
  role: 'TARURA Officer',
  authority: '',
  status: 'Active',
}

// What the form actually collects — no id/status/lastActiveAt/createdAt,
// since the backend decides all of those (see src/lib/users.ts).
type NewUserInput = Pick<PortalUser, 'name' | 'email' | 'phone' | 'role' | 'authority'>

interface AddUserDrawerProps {
  open: boolean
  authorities: string[]
  onClose: () => void
  // A real network call now, not a synchronous local update — the drawer
  // needs to know whether it succeeded before it can safely close.
  onCreate: (user: NewUserInput) => Promise<void>
}

// The "+ Add User" slide-over — a dedicated create-only form (as opposed
// to UserPanel, which handles both viewing and editing an existing user).
export function AddUserDrawer({ open, authorities, onClose, onCreate }: AddUserDrawerProps) {
  return (
    <>
      <div
        className={cn(
          'fixed inset-0 z-[1200] bg-black/20 backdrop-blur-[2px] transition-opacity duration-200',
          open ? 'opacity-100' : 'pointer-events-none opacity-0',
        )}
        onClick={onClose}
        aria-hidden="true"
      />
      <aside
        className={cn(
          'fixed right-0 top-0 z-[1300] h-screen w-full max-w-sm overflow-y-auto border-l border-border-light bg-surface shadow-xl transition-transform duration-300 ease-out',
          open ? 'translate-x-0' : 'translate-x-full',
        )}
      >
        {/* key toggles between 'open'/'closed' so each time the drawer is
            reopened, AddUserForm remounts with a blank form instead of
            showing whatever was left typed in from last time. */}
        {open && (
          <AddUserForm
            key={open ? 'open' : 'closed'}
            authorities={authorities}
            onClose={onClose}
            onCreate={onCreate}
          />
        )}
      </aside>
    </>
  )
}

function AddUserForm({
  authorities,
  onClose,
  onCreate,
}: {
  authorities: string[]
  onClose: () => void
  onCreate: (user: NewUserInput) => Promise<void>
}) {
  const [values, setValues] = useState<UserFormValues>({
    ...emptyForm,
    authority: authorities[0] ?? '',
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const canSubmit = values.name.trim() !== '' && values.email.trim() !== '' && !submitting

  const handleSubmit = async () => {
    setError(null)
    setSubmitting(true)
    try {
      await onCreate({
        name: values.name.trim(),
        email: values.email.trim(),
        phone: values.phone.trim() || undefined,
        role: values.role,
        authority: values.authority,
      })
      onClose()
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong')
      setSubmitting(false)
    }
  }

  return (
    <div className="flex flex-col gap-5 p-6">
      <div className="flex items-start justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">Access Management</p>
          <h2 className="mt-1 text-lg font-semibold text-text-primary">Add New User</h2>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="flex h-8 w-8 items-center justify-center rounded-lg text-text-secondary transition-colors duration-150 hover:bg-app-bg active:scale-90"
          aria-label="Close"
        >
          <X size={18} />
        </button>
      </div>

      <UserFormFields
        values={values}
        authorities={authorities}
        onChange={(patch) => setValues((prev) => ({ ...prev, ...patch }))}
        showStatus={false}
      />

      {/* No password field by design — per SRS FR-USR-2 (MFA enrollment at
          account creation): the backend sends an activation link instead
          of the Admin setting a password here (see /auth/accept-invite
          and ActivateAccountPage). */}
      <p className="flex items-start gap-1.5 rounded-lg bg-app-bg/60 px-3 py-2.5 text-xs text-text-secondary">
        <Mail size={14} className="mt-0.5 shrink-0" />
        An account activation email with MFA enrollment steps will be sent to this address. No password is set here.
      </p>

      {error && <p className="text-xs text-severity-high">{error}</p>}

      <div className="flex gap-2 border-t border-border-light pt-4">
        <Button type="button" variant="outline" className="flex-1" onClick={onClose}>
          Cancel
        </Button>
        <Button type="button" className="flex-1" disabled={!canSubmit} onClick={handleSubmit}>
          {submitting ? 'Sending invite…' : 'Create User'}
        </Button>
      </div>
    </div>
  )
}
