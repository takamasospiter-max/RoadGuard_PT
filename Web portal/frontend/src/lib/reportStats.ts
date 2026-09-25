import type { Defect, OverviewStats, ReportStatus, StatusSummaryItem } from '@/types'

// Single source of truth for report-count aggregates so every page (Dashboard,
// Map, Report & Analysis) derives the same numbers from the same `defects`
// dataset instead of drifting apart with page-specific mock values.

export function computeOverviewStats(defects: Defect[]): OverviewStats {
  return {
    totalReports: defects.length,
    manualReports: defects.filter((d) => d.source === 'manual').length,
    deviceReports: defects.filter((d) => d.source === 'device').length,
    newReports: defects.filter((d) => d.status === 'New').length,
    resolved: defects.filter((d) => d.status === 'Resolved').length,
  }
}

const STATUS_ORDER: ReportStatus[] = ['New', 'Verified', 'Under Repair', 'Resolved']

export function countByStatus(defects: Defect[]): StatusSummaryItem[] {
  return STATUS_ORDER.map((status) => ({
    status,
    count: defects.filter((d) => d.status === status).length,
  }))
}
