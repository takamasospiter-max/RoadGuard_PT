import { StatCard } from '@/components/dashboard/StatCard'
import type { Authority, PortalUser } from '@/types'

// Four StatCards at the top of the Users tab — same reused card component
// as Dashboard and Analytics, this time summarizing accounts instead of
// road reports.
export function UsersSummaryCards({ users, authorities }: { users: PortalUser[]; authorities: Authority[] }) {
  const active = users.filter((u) => u.status === 'Active').length
  const admins = users.filter((u) => u.role === 'Admin').length

  return (
    <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <StatCard label="Total Users" value={users.length} accent />
      <StatCard label="Active Users" value={active} />
      <StatCard label="Road Authorities" value={authorities.length} />
      <StatCard label="Administrators" value={admins} />
    </div>
  )
}
