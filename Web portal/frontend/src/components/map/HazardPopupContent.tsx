import { Smartphone, User } from 'lucide-react'
import { StatusBadge } from '@/components/dashboard/StatusBadge'
import type { Defect } from '@/types'
import { sourceLabel } from '@/lib/sourceLabels'
import { formatDateTime } from '@/lib/format'

const severityLabel: Record<Defect['severity'], string> = {
  high: 'High',
  medium: 'Medium',
  low: 'Low',
}

const severityTextColor: Record<Defect['severity'], string> = {
  high: 'text-severity-high',
  medium: 'text-severity-medium',
  low: 'text-yellow-600',
}


// Rendered inside a Leaflet <Popup> when a marker is clicked — deliberately
// a quick-glance summary only (severity/status/source/confidence/date), no
// sensor evidence or edit controls. "View Details" hands off to
// HazardDetailsPanel (the full slide-over) via `onViewDetails`.
export function HazardPopupContent({
  defect,
  onViewDetails,
}: {
  defect: Defect
  onViewDetails: () => void
}) {
  return (
    <div className="p-4">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-text-secondary">
        {defect.hazardType}
      </p>
      <p className="mb-3 text-base font-semibold text-text-primary">{defect.road}</p>

      <dl className="space-y-1.5 text-[13px]">
        <div className="flex items-center justify-between">
          <dt className="text-text-secondary">Severity</dt>
          <dd className={`font-medium ${severityTextColor[defect.severity]}`}>
            {severityLabel[defect.severity]}
          </dd>
        </div>
        <div className="flex items-center justify-between">
          <dt className="text-text-secondary">Status</dt>
          <dd>
            <StatusBadge status={defect.status} />
          </dd>
        </div>
        <div className="flex items-center justify-between">
          <dt className="text-text-secondary">Source</dt>
          <dd className="flex items-center gap-1.5 font-medium text-text-primary">
            {defect.source === 'device' ? <Smartphone size={13} /> : <User size={13} />}
            {sourceLabel[defect.source]}
          </dd>
        </div>
        <div className="flex items-center justify-between">
          <dt className="text-text-secondary">Confidence</dt>
          <dd className="font-medium text-text-primary">{defect.confidence}%</dd>
        </div>
      </dl>

      <p className="mt-3 text-xs text-text-secondary">Detected: {formatDateTime(defect.detectedAt)}</p>

      <button
        type="button"
        onClick={onViewDetails}
        className="mt-3 w-full rounded-lg bg-accent px-3 py-2 text-xs font-medium text-white hover:bg-accent-hover"
      >
        View Details
      </button>
    </div>
  )
}
