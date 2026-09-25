import { StatCard } from '@/components/dashboard/StatCard'
import type { OverviewStats } from '@/types'

interface OverviewCardsProps {
  stats: OverviewStats
}

// The "5-card" layout from the design doc: one large Total reports card on
// the left, spanning both rows of a 2x2 grid of smaller cards on the
// right. `stats` is computed by the caller (DashboardPage) via
// computeOverviewStats() — this component just lays the numbers out.
export function OverviewCards({ stats }: OverviewCardsProps) {
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
      {/* lg:row-span-2 makes this card as tall as the 2x2 grid beside it;
          the arbitrary selector bumps just its number to a bigger size. */}
      <StatCard
        label="Total reports"
        value={stats.totalReports}
        accent
        className="lg:row-span-2 lg:py-0 lg:[&>p:last-child]:text-5xl"
      />
      <div className="grid grid-cols-2 gap-4 lg:col-span-2">
        <StatCard label="Traveller reports" value={stats.manualReports} />
        <StatCard label="Phone-sensor (AI) spots" value={stats.deviceReports} />
        <StatCard label="New reports" value={stats.newReports} />
        <StatCard label="Resolved" value={stats.resolved} />
      </div>
    </div>
  )
}
