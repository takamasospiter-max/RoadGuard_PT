import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import type { Authority, PortalUser } from '@/types'

interface AuthorityTableProps {
  authorities: Authority[]
  // Needed only to compute the "Users" column count below — not rendered
  // directly.
  users: PortalUser[]
  onEdit: (authority: Authority) => void
}

// Plain table (no sorting/pagination — there's only ever a handful of
// authorities, unlike the Reports/Users tables). One "View / Edit" action
// per row opens AuthorityFormDrawer.
export function AuthorityTable({ authorities, users, onEdit }: AuthorityTableProps) {
  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="border-y border-border-light text-left text-xs font-medium text-text-secondary">
          <th className="px-4 py-2.5 font-medium">Authority</th>
          <th className="px-4 py-2.5 font-medium">Coverage area</th>
          <th className="px-4 py-2.5 font-medium">Users</th>
          <th className="px-4 py-2.5 font-medium">Status</th>
          <th className="px-4 py-2.5 font-medium"></th>
        </tr>
      </thead>
      <tbody>
        {authorities.map((authority) => (
          <tr key={authority.id} className="border-b border-border-light transition-colors duration-150 last:border-0 hover:bg-app-bg/50">
            <td className="whitespace-nowrap px-4 py-3 font-medium text-text-primary">{authority.name}</td>
            <td className="whitespace-nowrap px-4 py-3 text-text-primary">{authority.coverageArea}</td>
            {/* Computed live from portalUsers rather than stored on the
                Authority record, so it can never go stale/out of sync. */}
            <td className="whitespace-nowrap px-4 py-3 text-text-primary">
              {users.filter((u) => u.authority === authority.name).length}
            </td>
            <td className="whitespace-nowrap px-4 py-3">
              <Badge variant={authority.status === 'Active' ? 'resolved' : 'neutral'}>{authority.status}</Badge>
            </td>
            <td className="whitespace-nowrap px-4 py-3 text-right">
              <Button variant="outline" size="sm" onClick={() => onEdit(authority)}>
                View / Edit
              </Button>
            </td>
          </tr>
        ))}
        {authorities.length === 0 && (
          <tr>
            <td colSpan={5} className="px-4 py-10 text-center text-sm text-text-secondary">
              No authorities registered yet.
            </td>
          </tr>
        )}
      </tbody>
    </table>
  )
}
