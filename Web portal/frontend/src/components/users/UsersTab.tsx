import { UserPlus } from 'lucide-react'
import { useMemo, useState } from 'react'
import { AddUserDrawer } from '@/components/users/AddUserDrawer'
import { applyUserFilters, defaultUserFilters, type UserFilters } from '@/components/users/filters'
import { UserFilterBar } from '@/components/users/UserFilterBar'
import type { UserFormValues } from '@/components/users/UserFormFields'
import { UserPanel } from '@/components/users/UserPanel'
import { UsersSummaryCards } from '@/components/users/UsersSummaryCards'
import { UserTable } from '@/components/users/UserTable'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { ApiError } from '@/lib/api'
import { inviteUser, updateUser } from '@/lib/users'
import type { Authority, PortalUser } from '@/types'

interface UsersTabProps {
  users: PortalUser[]
  authorities: Authority[]
  // UsersPage owns the actual query — this just tells it "the list on the
  // server changed, go get the fresh one" after a successful mutation.
  onRefetch: () => void
}

// The "Users" half of the Users & Authorities page: summary cards, filter
// bar, table, and everything needed to add/view/edit/deactivate a user.
// Owns all the UI state (which filters are set, which user's panel is
// open, in which mode, and which user — if any — is pending a deactivate
// confirmation).
export function UsersTab({ users, authorities, onRefetch }: UsersTabProps) {
  const [filters, setFilters] = useState<UserFilters>(defaultUserFilters)
  const [selectedUser, setSelectedUser] = useState<PortalUser | null>(null)
  const [panelMode, setPanelMode] = useState<'view' | 'edit'>('view')
  const [addOpen, setAddOpen] = useState(false)
  // Holds the user about to be deactivated while the confirm dialog is
  // open; null means no confirmation is pending.
  const [deactivateTarget, setDeactivateTarget] = useState<PortalUser | null>(null)
  // Surfaces a failed edit/deactivate (e.g. the backend's "you can't
  // deactivate your own account" or a non-Admin's 403) — the panel/dialog
  // that triggered it closes regardless (see handleSave/applyStatusChange),
  // so this is the one place that failure becomes visible.
  const [actionError, setActionError] = useState<string | null>(null)

  const authorityNames = useMemo(() => authorities.map((a) => a.name), [authorities])
  const filteredUsers = useMemo(() => applyUserFilters(users, filters), [users, filters])

  const handleView = (user: PortalUser) => {
    setSelectedUser(user)
    setPanelMode('view')
  }

  const handleEdit = (user: PortalUser) => {
    setSelectedUser(user)
    setPanelMode('edit')
  }

  // Applies edited form values back onto the matching user record, for
  // real this time — a PATCH to the backend, not a local array splice.
  // Doesn't touch `selectedUser` — UserPanel already calls onClose() the
  // instant Save is clicked (see UserPanel.tsx), so there's no open panel
  // left to keep in sync here; only applyStatusChange below needs that,
  // since its panel deliberately stays open after a toggle.
  const handleSave = async (id: string, values: UserFormValues) => {
    setActionError(null)
    try {
      await updateUser(id, {
        name: values.name,
        email: values.email,
        phone: values.phone || undefined,
        role: values.role,
        authority: values.authority,
        status: values.status,
      })
      onRefetch()
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong')
    }
  }

  // Deactivating needs confirmation first (per the doc's UX rule);
  // reactivating doesn't, since it's not destructive.
  const handleToggleStatus = (user: PortalUser) => {
    if (user.status === 'Active') {
      setDeactivateTarget(user)
      return
    }
    void applyStatusChange(user.id, 'Active')
  }

  // Actually flips a user's status — called either straight from
  // handleToggleStatus (reactivating) or from the ConfirmDialog's
  // onConfirm below (deactivating, after the user confirms).
  const applyStatusChange = async (id: string, status: PortalUser['status']) => {
    setActionError(null)
    try {
      const updated = await updateUser(id, { status })
      setSelectedUser((prev) => (prev && prev.id === id ? updated : prev))
      onRefetch()
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong')
    }
  }

  // Sends the invite through the real backend (see src/lib/users.ts) —
  // id/status/timestamps all come back from there now, not synthesized
  // locally. Left to throw on failure; AddUserDrawer's form is what
  // catches it and keeps the drawer open with an error shown.
  const handleCreate = async (newUser: Pick<PortalUser, 'name' | 'email' | 'phone' | 'role' | 'authority'>) => {
    await inviteUser(newUser)
    onRefetch()
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <p className="max-w-xl text-sm text-text-secondary">
          Control who can access RoadGuard and what they are allowed to manage.
        </p>
        <Button size="sm" onClick={() => setAddOpen(true)}>
          <UserPlus size={14} />
          Add User
        </Button>
      </div>

      {actionError && (
        <p className="rounded-lg bg-severity-high/10 px-3 py-2 text-xs text-severity-high">{actionError}</p>
      )}

      <UsersSummaryCards users={users} authorities={authorities} />

      <UserFilterBar
        filters={filters}
        authorities={authorityNames}
        onChange={(patch) => setFilters((prev) => ({ ...prev, ...patch }))}
        onReset={() => setFilters(defaultUserFilters)}
      />

      <Card>
        <CardContent className="p-0">
          <UserTable users={filteredUsers} onView={handleView} onEdit={handleEdit} />
        </CardContent>
      </Card>

      <AddUserDrawer open={addOpen} authorities={authorityNames} onClose={() => setAddOpen(false)} onCreate={handleCreate} />

      <UserPanel
        user={selectedUser}
        mode={panelMode}
        authorities={authorityNames}
        onClose={() => setSelectedUser(null)}
        onEditRequested={() => setPanelMode('edit')}
        onSave={handleSave}
        onToggleStatus={handleToggleStatus}
      />

      <ConfirmDialog
        open={deactivateTarget !== null}
        title="Deactivate this user?"
        description="This user will no longer be able to access RoadGuard until the account is activated again."
        confirmLabel="Deactivate"
        destructive
        onCancel={() => setDeactivateTarget(null)}
        onConfirm={() => {
          if (deactivateTarget) void applyStatusChange(deactivateTarget.id, 'Inactive')
          setDeactivateTarget(null)
        }}
      />
    </div>
  )
}
