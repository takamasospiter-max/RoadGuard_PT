import { useQuery } from '@tanstack/react-query'
import { Cpu, Megaphone, Smartphone } from 'lucide-react'
import { useState } from 'react'
import { fetchSpotEvidence } from '@/lib/defects'
import { formatRelativeTime } from '@/lib/formatRelativeTime'
import type { Defect } from '@/types'
import { formatShortDateTime } from '@/lib/format'

// The real evidence behind a defect, for the Reports and Map detail panels:
// - how many different phones' AI detections confirm it, the combined
//   confidence and the severity score (crowd sensing, detection/spots.py);
// - whether drivers are currently being warned about it;
// - the individual detections (time, confidence, hit strength, model),
//   loaded from GET /api/defects/<id>/detections/ only when there are some.
//
// It replaces the earlier fixed wording ("High vibration detected across
// multiple passes"), which was chosen from the severity alone and was shown
// even for photo reports that had no sensor data at all.

// Only the newest few detections are listed at first; "Show all" expands.
const INITIAL_ROWS = 5

function percent(value: number) {
  return `${Math.round(value * 100)}%`
}


export function SpotEvidence({ defect }: { defect: Defect }) {
  return (
    <div className="space-y-3">
      <DriverVisibility defect={defect} />
      {defect.deviceCount > 0 ? (
        // Keyed by id so switching defects never shows the previous one's list.
        <DetectionEvidence key={defect.id} defect={defect} />
      ) : (
        <p className="flex items-center gap-1.5 text-xs font-medium text-text-secondary">
          <Smartphone size={13} />
          Phone sensors: no AI detections at this spot yet
        </p>
      )}
    </div>
  )
}

// Says plainly whether the mobile app is warning drivers about this defect,
// and why (the backend decides, with the same rule as the app's live map).
function DriverVisibility({ defect }: { defect: Defect }) {
  let reason: string
  if (defect.shownToDrivers) {
    reason =
      defect.status === 'New'
        ? `Shown to drivers as "reported by drivers" (${defect.deviceCount} phones agree)`
        : 'Shown to drivers as confirmed'
  } else if (defect.status === 'Resolved') {
    reason = 'Not shown to drivers: resolved'
  } else if (defect.isSimulated) {
    reason = 'Not shown to drivers: built from test (simulated) detections only'
  } else if (defect.publishedAt) {
    reason = 'Not shown to drivers: no phone has detected it recently'
  } else {
    reason = 'Not shown to drivers until an officer verifies it or enough phones detect it'
  }
  return (
    <p
      className={
        defect.shownToDrivers
          ? 'flex items-start gap-1.5 text-xs font-medium text-accent'
          : 'flex items-start gap-1.5 text-xs font-medium text-text-secondary'
      }
    >
      <Megaphone size={13} className="mt-0.5 shrink-0" />
      {reason}
    </p>
  )
}

function DetectionEvidence({ defect }: { defect: Defect }) {
  const [showAll, setShowAll] = useState(false)
  const { data, isPending, isError } = useQuery({
    queryKey: ['spot-evidence', defect.id],
    queryFn: () => fetchSpotEvidence(defect.id),
  })

  return (
    <div className="space-y-2">
      <p className="flex items-center gap-1.5 text-xs font-medium text-text-secondary">
        <Cpu size={13} />
        Phone sensors (AI)
      </p>

      {/* Headline numbers come with the defect itself, so they show at once. */}
      <dl className="grid grid-cols-3 gap-2 text-center">
        <Figure label="Phones" value={String(defect.deviceCount)} />
        <Figure label="Confidence" value={`${defect.confidence}%`} />
        <Figure
          label="Severity score"
          value={defect.severityScore !== undefined ? defect.severityScore.toFixed(2) : '—'}
        />
      </dl>
      {defect.lastDetectedAt && (
        <p className="text-[11px] text-text-secondary">
          Last detected {formatRelativeTime(new Date(defect.lastDetectedAt))}
          {defect.publishedAt && <> &middot; drivers alerted since {formatShortDateTime(defect.publishedAt)}</>}
        </p>
      )}

      {isPending && <p className="text-xs text-text-secondary">Loading detections...</p>}
      {isError && <p className="text-xs text-text-secondary">The detections could not be loaded.</p>}

      {data && data.detections.length > 0 && (
        <div className="overflow-hidden rounded-lg border border-border-light bg-surface">
          <table className="w-full text-left text-[11px]">
            <thead className="bg-app-bg/60 text-text-secondary">
              <tr>
                <th className="px-2 py-1.5 font-medium">When</th>
                <th className="px-2 py-1.5 font-medium">Phone</th>
                <th className="px-2 py-1.5 text-right font-medium">Conf.</th>
                <th className="px-2 py-1.5 text-right font-medium">Hit</th>
              </tr>
            </thead>
            <tbody>
              {(showAll ? data.detections : data.detections.slice(0, INITIAL_ROWS)).map((d) => (
                <tr
                  key={d.id}
                  className="border-t border-border-light text-text-primary"
                  title={`Model ${d.modelVersion}`}
                >
                  <td className="px-2 py-1.5">
                    {formatShortDateTime(d.detectedAt)}
                    {d.isSimulated && <span className="ml-1 text-text-secondary">(test)</span>}
                  </td>
                  <td className="px-2 py-1.5 font-mono text-text-secondary">{d.device}</td>
                  <td className="px-2 py-1.5 text-right tabular-nums">{percent(d.confidence)}</td>
                  <td className="px-2 py-1.5 text-right tabular-nums">
                    {d.intensity !== null ? d.intensity.toFixed(2) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {data.detections.length > INITIAL_ROWS && (
            <button
              type="button"
              onClick={() => setShowAll((v) => !v)}
              className="w-full border-t border-border-light py-1.5 text-[11px] font-medium text-accent hover:bg-app-bg/60"
            >
              {showAll ? 'Show fewer' : `Show all ${data.detections.length} detections`}
            </button>
          )}
        </div>
      )}
      {data && data.detections.length > 0 && (
        <p className="text-[11px] text-text-secondary">
          Model: {data.detections[0].modelVersion}. Each phone is shown by a short anonymous code, never by
          account.
        </p>
      )}
    </div>
  )
}

function Figure({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-border-light bg-surface px-2 py-1.5">
      <dd className="text-sm font-semibold tabular-nums text-text-primary">{value}</dd>
      <dt className="text-[10px] text-text-secondary">{label}</dt>
    </div>
  )
}
