import type { Defect } from '@/types'
import { sourceShortLabel } from '@/lib/sourceLabels'

function count(defects: Defect[], predicate: (defect: Defect) => boolean) {
  return defects.reduce((total, defect) => (predicate(defect) ? total + 1 : total), 0)
}

// The "14 Reports · 11 Device · 3 Manual · ..." line above the map. Note
// it receives the *filtered* defects from MapPage, not the full list — so
// these counts update live as filters change, doubling as a "how many
// results match right now" indicator.
export function QuickSummaryRow({ defects }: { defects: Defect[] }) {
  const items = [
    { label: 'Reports', value: defects.length },
    { label: sourceShortLabel.device, value: count(defects, (d) => d.source === 'device') },
    { label: sourceShortLabel.manual, value: count(defects, (d) => d.source === 'manual') },
    { label: 'Shown to drivers', value: count(defects, (d) => d.shownToDrivers) },
    { label: 'New', value: count(defects, (d) => d.status === 'New') },
    { label: 'Resolved', value: count(defects, (d) => d.status === 'Resolved') },
  ]

  return (
    <div className="flex flex-wrap items-center gap-x-6 gap-y-1 text-sm">
      {items.map((item) => (
        <p key={item.label} className="text-text-secondary">
          <span className="font-semibold text-text-primary">{item.value}</span> {item.label}
        </p>
      ))}
    </div>
  )
}
