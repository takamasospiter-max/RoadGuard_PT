import { Info } from 'lucide-react'

// Static disclaimer footer on the Reports tab — no props, no logic. Just
// reinforces that AI/sensor detections are decision support, not the
// final word.
export function HumanReviewNotice() {
  return (
    <div className="flex items-start gap-2.5 rounded-xl border border-border-light bg-app-bg/60 px-4 py-3 text-xs text-text-secondary">
      <Info size={15} className="mt-0.5 shrink-0 text-accent" />
      <p>
        <span className="font-medium text-text-primary">Review remains a human decision.</span>{' '}
        Sensor and optional visual evidence support the road-condition record, but the authority
        should verify the information before making an operational maintenance decision.
      </p>
    </div>
  )
}
