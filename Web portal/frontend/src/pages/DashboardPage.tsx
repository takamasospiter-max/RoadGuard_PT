import { useQuery } from '@tanstack/react-query'
import { AIEngineCard } from '@/components/dashboard/AIEngineCard'
import { MapPreview } from '@/components/dashboard/MapPreview'
import { OverviewCards } from '@/components/dashboard/OverviewCards'
import { RecentReportsTable } from '@/components/dashboard/RecentReportsTable'
import { StatusSummaryChart } from '@/components/dashboard/StatusSummaryChart'
import { listDefects } from '@/lib/defects'
import { computeOverviewStats, countByStatus } from '@/lib/reportStats'

// The "/dashboard" route — assembles the 5-card overview, a small map
// preview + status donut side by side, and a recent-reports table. All
// four sections read from the same `defects` query (same queryKey as
// Map/Reports/Header — see src/lib/defects.ts), so a status change made on
// Map or Reports shows up here immediately after its mutation invalidates
// that query, and this page's own numbers always match what Map and
// Report & Analysis compute from that same data.
export function DashboardPage() {
  const { data: defects, isPending, isError } = useQuery({ queryKey: ['defects'], queryFn: listDefects })

  if (isPending) {
    return <p className="p-6 text-sm text-text-secondary">Loading…</p>
  }

  if (isError) {
    return <p className="p-6 text-sm text-severity-high">Couldn't load reports. Try refreshing the page.</p>
  }

  return (
    <div className="flex flex-col gap-6">
      <OverviewCards stats={computeOverviewStats(defects)} />

      <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
        <div className="xl:col-span-2">
          <MapPreview defects={defects} />
        </div>
        <StatusSummaryChart data={countByStatus(defects)} />
      </div>

      {/* Is the AI model running, and is it finding potholes? */}
      <AIEngineCard />

      <RecentReportsTable reports={defects} />
    </div>
  )
}
