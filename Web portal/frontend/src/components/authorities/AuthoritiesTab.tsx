import { Plus } from 'lucide-react'
import { useState } from 'react'
import { AuthorityFormDrawer } from '@/components/authorities/AuthorityFormDrawer'
import { AuthorityTable } from '@/components/authorities/AuthorityTable'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ApiError } from '@/lib/api'
import { createAuthority, updateAuthority } from '@/lib/authorities'
import type { Authority, PortalUser } from '@/types'

interface AuthoritiesTabProps {
  authorities: Authority[]
  users: PortalUser[]
  // UsersPage owns the actual query — this just tells it "the list on the
  // server changed, go get the fresh one" after a successful mutation.
  onRefetch: () => void
}

// The "Authorities" half of the Users & Authorities page: a table + an
// Add/Edit drawer. Much simpler than UsersTab — no filters or pagination,
// since the SRS scopes this pilot to a single authority (TARURA).
export function AuthoritiesTab({ authorities, users, onRefetch }: AuthoritiesTabProps) {
  const [formOpen, setFormOpen] = useState(false)
  // Which authority the drawer is editing; null means "Add" mode (see the
  // "Add Authority" button below, which explicitly resets this to null).
  const [editing, setEditing] = useState<Authority | null>(null)
  // Surfaces a failed create/edit (e.g. a non-Admin's 403) — the drawer
  // closes regardless (see handleSave), so this is the one place that
  // failure becomes visible.
  const [actionError, setActionError] = useState<string | null>(null)

  // Shared by both Add and Edit: an id means updating that existing
  // record via PATCH; no id means creating a new one via POST — both real
  // backend calls now (see src/lib/authorities.ts), not a local splice.
  const handleSave = async (authority: Omit<Authority, 'id'> & { id?: string }) => {
    setActionError(null)
    try {
      if (authority.id) {
        await updateAuthority(authority.id, {
          name: authority.name,
          coverageArea: authority.coverageArea,
          contact: authority.contact,
          status: authority.status,
        })
      } else {
        await createAuthority({
          name: authority.name,
          coverageArea: authority.coverageArea,
          contact: authority.contact,
        })
      }
      onRefetch()
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong')
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <p className="max-w-xl text-sm text-text-secondary">
          Manage the road authorities participating in RoadGuard. TARURA already coordinates road
          maintenance across Tanzania Mainland; additional authorities can be added here if the
          platform later expands to other operators.
        </p>
        <Button
          size="sm"
          onClick={() => {
            setEditing(null)
            setFormOpen(true)
          }}
        >
          <Plus size={14} />
          Add Authority
        </Button>
      </div>

      {actionError && (
        <p className="rounded-lg bg-severity-high/10 px-3 py-2 text-xs text-severity-high">{actionError}</p>
      )}

      <Card>
        <CardContent className="p-0">
          <AuthorityTable
            authorities={authorities}
            users={users}
            onEdit={(authority) => {
              setEditing(authority)
              setFormOpen(true)
            }}
          />
        </CardContent>
      </Card>

      <AuthorityFormDrawer
        open={formOpen}
        authority={editing}
        onClose={() => setFormOpen(false)}
        onSave={handleSave}
      />
    </div>
  )
}
