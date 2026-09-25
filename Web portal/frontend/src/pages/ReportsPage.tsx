import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { AnalyticsTab } from '@/components/analytics/AnalyticsTab'
import { ReportsTab } from '@/components/reports/ReportsTab'
import { SegmentedTabs } from '@/components/ui/segmented-tabs'
import { listDefects } from '@/lib/defects'

type Tab = 'reports' | 'analytics'

// The "/reports" route ("Report & Analysis" in the sidebar). Owns which of
// the two tabs is active; `defects` comes from the same `['defects']`
// query as Dashboard/Map/Header (see src/lib/defects.ts) — a status change
// saved in Reports invalidates that query, so Analytics' charts and
// Dashboard/Map all pick up the change too.
export function ReportsPage() {
  const [tab, setTab] = useState<Tab>('reports')
  const { data: defects, isPending, isError } = useQuery({ queryKey: ['defects'], queryFn: listDefects })
  const queryClient = useQueryClient()

  if (isPending) {
    return <p className="p-6 text-sm text-text-secondary">Loading…</p>
  }

  if (isError) {
    return <p className="p-6 text-sm text-severity-high">Couldn't load reports. Try refreshing the page.</p>
  }

  return (
    <div className="flex flex-col gap-4">
      <SegmentedTabs
        value={tab}
        onChange={setTab}
        options={[
          { value: 'reports', label: 'Reports' },
          { value: 'analytics', label: 'Analytics' },
        ]}
      />

      {/* key={tab} remounts this div (and everything inside it) on every
          tab switch — both to replay the fade-in animation, and because
          ReportsTab/AnalyticsTab are different component types anyway so
          React would remount them regardless. */}
      <div key={tab} className="animate-[fade-in_0.25s_ease-out_both]">
        {tab === 'reports' ? (
          <ReportsTab
            defects={defects}
            onRefetch={() => queryClient.invalidateQueries({ queryKey: ['defects'] })}
          />
        ) : (
          <AnalyticsTab defects={defects} />
        )}
      </div>
    </div>
  )
}
