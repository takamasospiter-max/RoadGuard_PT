import type { CSSProperties } from 'react'
import { Card, CardHeader, CardTitle } from '@/components/ui/card'
import { countByStatus } from '@/lib/reportStats'
import { statusColor as colorByStatus } from '@/lib/statusColors'
import type { Defect } from '@/types'

// Status breakdown as horizontal percentage bars — the Analytics tab's
// version of Dashboard's StatusSummaryChart donut, same underlying counts
// (via the shared countByStatus helper) shown a different way.
export function LifecycleBreakdown({ defects }: { defects: Defect[] }) {
  const total = defects.length || 1 // avoid divide-by-zero when there's no data at all
  const summary = countByStatus(defects)

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Verification lifecycle</CardTitle>
      </CardHeader>
      <div className="space-y-3 px-5 pb-5">
        {summary.map(({ status, count }) => {
          const pct = Math.round((count / total) * 100)
          // Bar grows from 0 to its target width via the grow-width
          // keyframes (index.css), driven by this CSS custom property —
          // a key change (status/count set) restarts the animation.
          const barStyle = { '--bar-target-width': `${pct}%` } as CSSProperties
          return (
            <div key={status}>
              <div className="mb-1 flex items-center justify-between text-sm">
                <span className="text-text-primary">{status}</span>
                <span className="font-medium tabular-nums text-text-secondary">{count}</span>
              </div>
              <div className="h-2 w-full overflow-hidden rounded-full bg-app-bg">
                <div
                  key={`${status}-${count}`}
                  className="h-full animate-[grow-width_0.7s_ease-out_both] rounded-full"
                  style={{ ...barStyle, backgroundColor: colorByStatus[status] }}
                />
              </div>
            </div>
          )
        })}
      </div>
    </Card>
  )
}
