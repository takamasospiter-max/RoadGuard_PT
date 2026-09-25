import { Badge } from '@/components/ui/badge'
import type { ReportStatus } from '@/types'

// Maps a ReportStatus string straight onto the matching Badge color
// variant (see badge.tsx). Used anywhere a defect/report's status is shown
// as a colored pill: Dashboard, Map popups/details, the Reports table.
const variantByStatus: Record<ReportStatus, 'new' | 'verified' | 'underRepair' | 'resolved'> = {
  New: 'new',
  Verified: 'verified',
  'Under Repair': 'underRepair',
  Resolved: 'resolved',
}

export function StatusBadge({ status }: { status: ReportStatus }) {
  return <Badge variant={variantByStatus[status]}>{status}</Badge>
}
