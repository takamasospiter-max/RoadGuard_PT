import type { ReportStatus } from '@/types'

// Single definition so every chart/badge that colors by status (Dashboard's
// StatusSummaryChart, Analytics' LifecycleBreakdown, etc.) stays visually
// identical instead of each carrying its own copy of the same hex values.
export const statusColor: Record<ReportStatus, string> = {
  New: '#1490E8',
  Verified: '#F59E0B',
  'Under Repair': '#EAB308',
  Resolved: '#16A34A',
}
