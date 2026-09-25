import { Check, Pencil, X } from 'lucide-react'
import { useState } from 'react'
import { permissionsForRole } from '@/components/users/permissions'
import { UserFormFields, type UserFormValues } from '@/components/users/UserFormFields'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import type { PortalUser } from '@/types'
import { DetailRow } from '@/components/ui/detail-row'

function formatDateTime(iso: string) {
  return new Date(iso).toLocaleString('en-GB', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

type PanelMode = 'view' | 'edit'

interface UserPanelProps {
  user: PortalUser | null
  // Which of the two layouts to show — UsersTab sets this based on
  // whether "View" or "Edit" was clicked in the table (and switches it to
  // 'edit' if "Edit" is clicked from inside the view layout too).
  mode: PanelMode
  authorities: string[]
  onClose: () => void
  onEditRequested: () => void
  onSave: (id: string, values: UserFormValues) => void
  // Deactivate/Activate button in view mode. UsersTab decides whether this
  // needs a confirmation dialog first (only for deactivating).
  onToggleStatus: (user: PortalUser) => void
}

// One slide-over, two very different layouts depending on `mode`: a
// read-only account summary + permissions list ('view'), or an editable
// form ('edit') — see UserPanelContent below for the actual branch.
export function UserPanel({
  user,
  mode,
  authorities,
  onClose,
  onEditRequested,
  onSave,
  onToggleStatus,
}: UserPanelProps) {
  return (
    <>
      <div
        className={cn(
          'fixed inset-0 z-[1200] bg-black/20 backdrop-blur-[2px] transition-opacity duration-200',
          user ? 'opacity-100' : 'pointer-events-none opacity-0',
        )}
        onClick={onClose}
        aria-hidden="true"
      />
      <aside
        className={cn(
          'fixed right-0 top-0 z-[1300] h-screen w-full max-w-sm overflow-y-auto border-l border-border-light bg-surface shadow-xl transition-transform duration-300 ease-out',
          user ? 'translate-x-0' : 'translate-x-full',
        )}
      >
        {/* Keying by both user id AND mode means: selecting a different
            user resets the form, AND switching view -> edit (or back)
            for the *same* user also resets it — e.g. clicking "Edit" from
            inside the view layout gets a form seeded fresh from that
            user's current values, not leftover edit state from someone
            else. */}
        {user && (
          <UserPanelContent
            key={`${user.id}-${mode}`}
            user={user}
            mode={mode}
            authorities={authorities}
            onClose={onClose}
            onEditRequested={onEditRequested}
            onSave={onSave}
            onToggleStatus={onToggleStatus}
          />
        )}
      </aside>
    </>
  )
}

function UserPanelContent({
  user,
  mode,
  authorities,
  onClose,
  onEditRequested,
  onSave,
  onToggleStatus,
}: {
  user: PortalUser
  mode: PanelMode
  authorities: string[]
  onClose: () => void
  onEditRequested: () => void
  onSave: (id: string, values: UserFormValues) => void
  onToggleStatus: (user: PortalUser) => void
}) {
  // Form state only matters in 'edit' mode, but it's declared
  // unconditionally since hooks can't be called after an early return.
  const [values, setValues] = useState<UserFormValues>({
    name: user.name,
    email: user.email,
    phone: user.phone ?? '',
    role: user.role,
    authority: user.authority,
    status: user.status,
  })

  if (mode === 'edit') {
    return (
      <div className="flex flex-col gap-5 p-6">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">Edit User</p>
            <h2 className="mt-1 text-lg font-semibold text-text-primary">{user.name}</h2>
            <p className="text-xs text-text-secondary">
              {user.role === 'Admin' ? 'System Administrator' : 'Road Authority Officer'}
            </p>
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

        <UserFormFields values={values} authorities={authorities} onChange={(patch) => setValues((prev) => ({ ...prev, ...patch }))} />

        <div className="flex gap-2 border-t border-border-light pt-4">
          <Button type="button" variant="outline" className="flex-1" onClick={onClose}>
            Cancel
          </Button>
          <Button
            type="button"
            className="flex-1"
            onClick={() => {
              onSave(user.id, values)
              onClose()
            }}
          >
            Save Changes
          </Button>
        </div>
      </div>
    )
  }

  // 'view' mode from here down: read-only summary + the role's fixed
  // permission list (see permissions.ts).
  const permissions = permissionsForRole(user.role)

  return (
    <div className="flex flex-col gap-5 p-6">
      <div className="flex items-start justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">Account</p>
          <h2 className="mt-1 text-lg font-semibold text-text-primary">{user.name}</h2>
          <p className="text-xs text-text-secondary">
            {user.role === 'Admin' ? 'System Administrator' : 'Road Authority Officer'}
          </p>
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

      <dl className="space-y-3 text-sm">
        <DetailRow label="User ID" value={user.id} />
        <DetailRow label="Email" value={user.email} />
        <DetailRow label="Phone" value={user.phone ?? '—'} />
        <DetailRow label="Authority" value={user.authority} />
        <div className="flex items-center justify-between gap-3">
          <dt className="text-text-secondary">Status</dt>
          <dd>
            <Badge variant={user.status === 'Active' ? 'resolved' : 'neutral'}>{user.status}</Badge>
          </dd>
        </div>
      </dl>

      <div className="rounded-xl border border-border-light bg-app-bg/60 p-4 text-sm">
        <p className="mb-2 text-xs font-medium text-text-secondary">Activity</p>
        <DetailRow label="Last active" value={formatDateTime(user.lastActiveAt)} />
        <DetailRow label="Account created" value={formatDateTime(user.createdAt)} />
      </div>

      <div className="text-sm">
        <p className="mb-2 text-xs font-medium text-text-secondary">Permissions</p>
        <ul className="space-y-1.5">
          {permissions.map((permission) => (
            <li key={permission.label} className="flex items-center gap-2">
              {permission.granted ? (
                <Check size={14} className="shrink-0 text-success" />
              ) : (
                <X size={14} className="shrink-0 text-text-secondary" />
              )}
              <span className={permission.granted ? 'text-text-primary' : 'text-text-secondary'}>
                {permission.label}
              </span>
            </li>
          ))}
        </ul>
      </div>

      <div className="flex gap-2 border-t border-border-light pt-4">
        <Button type="button" variant="outline" className="flex-1" onClick={onEditRequested}>
          <Pencil size={14} />
          Edit
        </Button>
        <Button
          type="button"
          variant={user.status === 'Active' ? 'outline' : 'default'}
          className={cn('flex-1', user.status === 'Active' && 'border-severity-high text-severity-high hover:bg-severity-high/10')}
          onClick={() => onToggleStatus(user)}
        >
          {user.status === 'Active' ? 'Deactivate' : 'Activate'}
        </Button>
      </div>
    </div>
  )
}
