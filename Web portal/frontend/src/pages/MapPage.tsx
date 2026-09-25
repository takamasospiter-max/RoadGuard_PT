import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useMemo, useState } from 'react'
import { applyMapFilters, defaultMapFilters, type MapFilters } from '@/components/map/filters'
import { FilterBar } from '@/components/map/FilterBar'
import { HazardDetailsPanel } from '@/components/map/HazardDetailsPanel'
import { HazardMap } from '@/components/map/HazardMap'
import { QuickSummaryRow } from '@/components/map/QuickSummaryRow'
import { ApiError } from '@/lib/api'
import { updateDefect, listDefects } from '@/lib/defects'
import type { Defect, ReportStatus } from '@/types'

// The "/map" route — owns the active filters and which marker's details
// panel (if any) is open. The defect data comes from the same `['defects']`
// query as Dashboard/Reports/Header (see src/lib/defects.ts), so a status
// change made here is visible everywhere else once the mutation below
// invalidates that query.
export function MapPage() {
  const { data: defects, isPending, isError } = useQuery({ queryKey: ['defects'], queryFn: listDefects })
  const queryClient = useQueryClient()
  const [filters, setFilters] = useState<MapFilters>(defaultMapFilters)
  const [selectedDefect, setSelectedDefect] = useState<Defect | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)

  const filteredDefects = useMemo(() => applyMapFilters(defects ?? [], filters), [defects, filters])

  const handleFilterChange = (patch: Partial<MapFilters>) => {
    setFilters((prev) => ({ ...prev, ...patch }))
  }

  // Quick "Mark as..." from HazardDetailsPanel — a real PATCH now, not a
  // local array splice. If that same defect's panel is still open, it's
  // updated with the mutation's own response so it shows the new status
  // immediately rather than waiting on the refetch.
  const handleStatusChange = async (id: string, status: ReportStatus) => {
    setActionError(null)
    try {
      const updated = await updateDefect(id, { status })
      setSelectedDefect((prev) => (prev && prev.id === id ? updated : prev))
      queryClient.invalidateQueries({ queryKey: ['defects'] })
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong')
    }
  }

  if (isPending) {
    return <p className="p-6 text-sm text-text-secondary">Loading…</p>
  }

  if (isError) {
    return <p className="p-6 text-sm text-severity-high">Couldn't load reports. Try refreshing the page.</p>
  }

  return (
    <div className="flex h-full flex-col gap-4">
      <p className="-mt-2 text-sm text-text-secondary">
        View detected potholes by location.
      </p>

      {actionError && (
        <p className="rounded-lg bg-severity-high/10 px-3 py-2 text-xs text-severity-high">{actionError}</p>
      )}

      <FilterBar filters={filters} onChange={handleFilterChange} />

      <QuickSummaryRow defects={filteredDefects} />

      <div className="h-145 overflow-hidden rounded-2xl border border-border-light bg-surface shadow-sm">
        <HazardMap defects={filteredDefects} onSelectDefect={setSelectedDefect} />
      </div>

      <HazardDetailsPanel
        defect={selectedDefect}
        onClose={() => setSelectedDefect(null)}
        onStatusChange={(id, status) => void handleStatusChange(id, status)}
      />
    </div>
  )
}
