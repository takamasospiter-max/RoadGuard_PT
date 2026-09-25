import { X } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import type { Defect, ReportStatus } from '@/types'
import { DefectPhoto } from './DefectPhoto'
import { SpotEvidence } from './SpotEvidence'
import { formatDateTime } from '@/lib/format'
import { DetailRow } from '@/components/ui/detail-row'


interface ReportDetailsPanelProps {
  defect: Defect | null
  onClose: () => void
  // Called when "Save Review" is clicked, with the chosen status and
  // whatever note text was typed — ReportsTab applies this to the defect.
  onSaveReview: (id: string, status: ReportStatus, note: string) => void
}

// The formal review slide-over for the Reports tab (status dropdown + note
// + Save), as opposed to Map's HazardDetailsPanel which has quick one-click
// "Mark as..." buttons and no note field. Split into an outer shell
// (this function) that's always mounted, and an inner
// ReportDetailsContent that's only rendered while a defect is selected —
// see the comment on its `key` below for why.
export function ReportDetailsPanel({ defect, onClose, onSaveReview }: ReportDetailsPanelProps) {
  return (
    <>
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
          // Keyed by report id so the review form (status/note) resets to
          // fresh initial state whenever a different report is selected,
          // instead of syncing it with an effect.
          <ReportDetailsContent
            key={defect.id}
            defect={defect}
            onClose={onClose}
            onSaveReview={onSaveReview}
          />
        )}
      </aside>
    </>
  )
}

function ReportDetailsContent({
  defect,
  onClose,
  onSaveReview,
}: {
  defect: Defect
  onClose: () => void
  onSaveReview: (id: string, status: ReportStatus, note: string) => void
}) {
  const [status, setStatus] = useState<ReportStatus>(defect.status)
  const [note, setNote] = useState('')

  return (
    <div className="flex flex-col gap-5 p-6">
      <div className="flex items-start justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">Report</p>
          <h2 className="mt-1 text-lg font-semibold text-text-primary">{defect.id}</h2>
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
        <DetailRow label="Road" value={defect.road} />
        <DetailRow label="Region" value={defect.region} />
        <DetailRow label="Condition" value={defect.hazardType} />
        <DetailRow label="Detected" value={formatDateTime(defect.detectedAt)} />
        <DetailRow label="GPS" value={`${defect.lat.toFixed(4)}, ${defect.lng.toFixed(4)}`} />
        <DetailRow label="Source" value={defect.source === 'device' ? 'Phone sensors (AI)' : 'Traveller report'} />
      </dl>

      <div className="space-y-3 rounded-xl border border-border-light bg-app-bg/60 p-4 text-sm">
        {/* Evidence the reviewer judges before choosing a status: whether
            drivers are being warned, the phones' AI detections, the
            traveller's photo and note. */}
        <SpotEvidence defect={defect} />
        <DefectPhoto defectId={defect.id} hasPhoto={defect.hasPhoto} />
        {defect.notes && (
          <div>
            <p className="text-xs font-medium text-text-secondary">Traveller&apos;s note</p>
            <p className="mt-1 whitespace-pre-line text-text-primary">{defect.notes}</p>
          </div>
        )}
      </div>

      {defect.reviewedBy && (
        <p className="text-xs text-text-secondary">
          Last reviewed by <span className="font-medium text-text-primary">{defect.reviewedBy}</span> on{' '}
          {defect.reviewedAt && formatDateTime(defect.reviewedAt)}
          {defect.reviewNote && <span className="mt-1 block italic">&ldquo;{defect.reviewNote}&rdquo;</span>}
        </p>
      )}

      <div className="flex flex-col gap-3 border-t border-border-light pt-4">
        <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">Review</p>

        <div className="space-y-1.5">
          <label htmlFor="review-status" className="text-xs font-medium text-text-secondary">
            Status
          </label>
          <Select id="review-status" value={status} onChange={(e) => setStatus(e.target.value as ReportStatus)}>
            <option value="New">New</option>
            <option value="Verified">Verified</option>
            <option value="Under Repair">Under Repair</option>
            <option value="Resolved">Resolved</option>
          </Select>
        </div>

        <div className="space-y-1.5">
          <label htmlFor="review-note" className="text-xs font-medium text-text-secondary">
            Review note
          </label>
          <textarea
            id="review-note"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            rows={3}
            placeholder="Add context for this decision..."
            className="w-full rounded-lg border border-border-light bg-surface px-3.5 py-2.5 text-sm text-text-primary placeholder:text-text-secondary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
          />
        </div>

        <Button
          type="button"
          onClick={() => {
            onSaveReview(defect.id, status, note)
            onClose()
          }}
        >
          Save Review
        </Button>
      </div>
    </div>
  )
}

