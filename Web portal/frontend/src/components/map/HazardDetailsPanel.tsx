import { X } from 'lucide-react'
import { StatusBadge } from '@/components/dashboard/StatusBadge'
import { DefectPhoto } from '@/components/reports/DefectPhoto'
import { SpotEvidence } from '@/components/reports/SpotEvidence'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import type { Defect, ReportStatus } from '@/types'
import { formatDateTime } from '@/lib/format'
import { DetailRow } from '@/components/ui/detail-row'

const severityLabel: Record<Defect['severity'], string> = {
  high: 'High',
  medium: 'Medium',
  low: 'Low',
}

const statusActions: { label: string; status: ReportStatus }[] = [
  { label: 'Mark as Verified', status: 'Verified' },
  { label: 'Mark as Under Repair', status: 'Under Repair' },
  { label: 'Mark as Resolved', status: 'Resolved' },
]


interface HazardDetailsPanelProps {
  defect: Defect | null
  onClose: () => void
  onStatusChange: (id: string, status: ReportStatus) => void
}

// Slide-over shown when someone clicks "View Details" in a map popup.
// Quick-action version of a review flow: three status buttons, no note
// field (compare to Reports' ReportDetailsPanel, which is the same idea
// but with a formal status + note "Save Review" flow instead).
//
// `defect` is null when the panel should be hidden — rather than
// unmounting, it's kept in the DOM and just translated off-screen
// (translate-x-full), so the closing slide animation can play instead of
// the panel just vanishing.
export function HazardDetailsPanel({ defect, onClose, onStatusChange }: HazardDetailsPanelProps) {
  return (
    <>
      {/* Dimmed, blurred backdrop — click it to close, same as clicking
          the X button. */}
      <div
        className={cn(
          'fixed inset-0 z-1200 bg-black/20 backdrop-blur-[2px] transition-opacity duration-200',
          defect ? 'opacity-100' : 'pointer-events-none opacity-0',
        )}
        onClick={onClose}
        aria-hidden="true"
      />
      <aside
        className={cn(
          'fixed right-0 top-0 z-1300 h-screen w-full max-w-sm overflow-y-auto border-l border-border-light bg-surface shadow-xl transition-transform duration-300 ease-out',
          defect ? 'translate-x-0' : 'translate-x-full',
        )}
      >
        {defect && (
          <div className="flex flex-col gap-5 p-6">
            <div className="flex items-start justify-between">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">
                  Road Condition Details
                </p>
                <h2 className="mt-1 text-lg font-semibold text-text-primary">{defect.hazardType}</h2>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="flex h-8 w-8 items-center justify-center rounded-lg text-text-secondary transition-colors duration-150 hover:bg-app-bg active:scale-90"
                aria-label="Close details"
              >
                <X size={18} />
              </button>
            </div>

            <dl className="space-y-3 text-sm">
              <DetailRow label="Report ID" value={defect.id} />
              <DetailRow label="Road" value={defect.road} />
              <DetailRow label="Region" value={defect.region} />
              <DetailRow label="Location" value={`${defect.lat.toFixed(4)}, ${defect.lng.toFixed(4)}`} />
              <DetailRow label="Severity" value={severityLabel[defect.severity]} />
              <div className="flex items-center justify-between">
                <dt className="text-text-secondary">Status</dt>
                <dd>
                  <StatusBadge status={defect.status} />
                </dd>
              </div>
              <DetailRow label="Source" value={defect.source === 'device' ? 'Phone sensors (AI)' : 'Traveller report'} />
              <DetailRow label="Confidence" value={`${defect.confidence}%`} />
              <DetailRow label="Corroborating observations" value={String(defect.observationCount)} />
              <DetailRow label="Detected" value={formatDateTime(defect.detectedAt)} />
            </dl>

            <div className="space-y-3 rounded-xl border border-border-light bg-app-bg/60 p-4 text-sm">
              {/* Real evidence: driver visibility, the phones' AI detections,
                  and the traveller's photo and note if this came from the app. */}
              <SpotEvidence defect={defect} />
              <DefectPhoto defectId={defect.id} hasPhoto={defect.hasPhoto} />
              {defect.notes && (
                <div>
                  <p className="text-xs font-medium text-text-secondary">Traveller&apos;s note</p>
                  <p className="mt-1 whitespace-pre-line text-text-primary">{defect.notes}</p>
                </div>
              )}
            </div>

            <div className="flex flex-col gap-2 border-t border-border-light pt-4">
              {statusActions.map((action) => (
                <Button
                  key={action.status}
                  variant={defect.status === action.status ? 'secondary' : 'outline'}
                  disabled={defect.status === action.status}
                  onClick={() => onStatusChange(defect.id, action.status)}
                >
                  {action.label}
                </Button>
              ))}
            </div>
          </div>
        )}
      </aside>
    </>
  )
}

