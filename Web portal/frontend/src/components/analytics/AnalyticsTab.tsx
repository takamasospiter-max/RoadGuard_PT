import { useState } from 'react'
import { AnalyticsSummaryCards } from '@/components/analytics/AnalyticsSummaryCards'
import { LifecycleBreakdown } from '@/components/analytics/LifecycleBreakdown'
import { RegionBarChart } from '@/components/analytics/RegionBarChart'
import { SourceMixChart } from '@/components/analytics/SourceMixChart'
import { TrendChart } from '@/components/analytics/TrendChart'
import { FadeIn } from '@/components/ui/fade-in'
import { Select } from '@/components/ui/select'
import type { Defect } from '@/types'

// The "Analytics" half of the Report & Analysis page: summary cards + four
// charts (trend, source mix, by-region, lifecycle). `defects` is the
// same array ReportsTab reads and edits — this tab is read-only over it,
// so any status change saved in Reports shows up here immediately too.
export function AnalyticsTab({ defects }: { defects: Defect[] }) {
  // Only the period selector is local state; every chart recomputes its
  // own numbers from `defects` + `periodDays` on every render rather than
  // being cached anywhere.
  const [periodDays, setPeriodDays] = useState(30)

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <p className="max-w-xl text-sm text-text-secondary">
          Understand road-condition patterns across monitored roads and areas.
        </p>
        <Select
          className="w-auto min-w-[150px]"
          value={String(periodDays)}
          onChange={(e) => setPeriodDays(Number(e.target.value))}
          aria-label="Trend period"
        >
          <option value="7">Last 7 days</option>
          <option value="30">Last 30 days</option>
        </Select>
      </div>

      <AnalyticsSummaryCards defects={defects} />

      {/* Each chart wrapped in FadeIn with an increasing delay so they
          cascade in one after another (see AnalyticsSummaryCards for the
          same pattern on the cards above). */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <FadeIn delay={80}>
          <TrendChart defects={defects} days={periodDays} />
        </FadeIn>
        <FadeIn delay={140}>
          <SourceMixChart defects={defects} />
        </FadeIn>
        <FadeIn delay={200}>
          <RegionBarChart defects={defects} />
        </FadeIn>
        <FadeIn delay={260}>
          <LifecycleBreakdown defects={defects} />
        </FadeIn>
      </div>
    </div>
  )
}
