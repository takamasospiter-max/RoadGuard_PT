import { Download } from 'lucide-react'
import { useMemo, useState } from 'react'
import { applyReportFilters, defaultReportFilters, type ReportFilters } from '@/components/reports/filters'
import { exportDefectsToCsv } from '@/components/reports/exportCsv'
import { HumanReviewNotice } from '@/components/reports/HumanReviewNotice'
import { ReportDetailsPanel } from '@/components/reports/ReportDetailsPanel'
import { ReportFilterBar } from '@/components/reports/ReportFilterBar'
import { ReportTable } from '@/components/reports/ReportTable'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ApiError } from '@/lib/api'
import { updateDefect } from '@/lib/defects'
import type { Defect, ReportStatus } from '@/types'

interface ReportsTabProps {
  defects: Defect[]
  // ReportsPage owns the actual query — this just tells it "the data on
  // the server changed, go get the fresh one" after a successful review.
  onRefetch: () => void
}

// The "Reports" half of the Report & Analysis page: filter bar, table,
// CSV export, and the review slide-over. Owns all of that page's UI state
// (filters, which row is selected) — the defect data itself comes from
// ReportsPage's query.
export function ReportsTab({ defects, onRefetch }: ReportsTabProps) {
  const [filters, setFilters] = useState<ReportFilters>(defaultReportFilters)
  const [selectedDefect, setSelectedDefect] = useState<Defect | null>(null)
  // Surfaces a failed review save — ReportDetailsPanel closes regardless
  // (see handleSaveReview), so this is the one place that failure becomes
  // visible.
  const [actionError, setActionError] = useState<string | null>(null)

  // Distinct region names found in the data, for the filter dropdown's
  // options — recomputed only when `defects` actually changes.
  const regions = useMemo(
    () => Array.from(new Set(defects.map((d) => d.region))).sort(),
    [defects],
  )

  const filteredDefects = useMemo(() => applyReportFilters(defects, filters), [defects, filters])

  // Applies a saved review via a real PATCH — reviewedBy/reviewedAt are no
  // longer set here at all, the backend stamps both from whoever's
  // session made the request (see DefectDetailView in new-backend/roadguard/views.py).
  const handleSaveReview = async (id: string, status: ReportStatus, note: string) => {
    setActionError(null)
    try {
      await updateDefect(id, { status, reviewNote: note })
      onRefetch()
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong')
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <p className="max-w-xl text-sm text-text-secondary">
          Inspect supporting evidence and keep the road record trustworthy.
        </p>
        <Button
          variant="outline"
          size="sm"
          onClick={() => exportDefectsToCsv(filteredDefects)}
          disabled={filteredDefects.length === 0}
        >
          <Download size={14} />
          Export filtered CSV
        </Button>
      </div>

      {actionError && (
        <p className="rounded-lg bg-severity-high/10 px-3 py-2 text-xs text-severity-high">{actionError}</p>
      )}

      <ReportFilterBar
        filters={filters}
        regions={regions}
        onChange={(patch) => setFilters((prev) => ({ ...prev, ...patch }))}
        onReset={() => setFilters(defaultReportFilters)}
      />

      <Card>
        <CardContent className="p-0">
          <ReportTable defects={filteredDefects} onSelect={setSelectedDefect} />
        </CardContent>
      </Card>

      <HumanReviewNotice />

      <ReportDetailsPanel
        defect={selectedDefect}
        onClose={() => setSelectedDefect(null)}
        onSaveReview={handleSaveReview}
      />
    </div>
  )
}
