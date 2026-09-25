import { Smartphone, User } from 'lucide-react'

const severityItems = [
  { label: 'High', color: 'bg-severity-high' },
  { label: 'Medium', color: 'bg-severity-medium' },
  { label: 'Low', color: 'bg-severity-low' },
]

// Static key (severity colors + source icons) floating in the map's
// bottom-left corner. Purely explanatory — no interactivity.
export function MapLegend() {
  return (
    <div className="pointer-events-auto absolute bottom-3 left-3 z-[1000] rounded-xl border border-border-light bg-surface/95 px-3.5 py-2.5 shadow-sm backdrop-blur">
      <div className="flex items-center gap-3">
        {severityItems.map((item) => (
          <span key={item.label} className="flex items-center gap-1.5 text-xs font-medium text-text-secondary">
            <span className={`h-2.5 w-2.5 rounded-full ${item.color}`} />
            {item.label}
          </span>
        ))}
      </div>
      <div className="mt-1.5 flex items-center gap-3 border-t border-border-light pt-1.5">
        <span className="flex items-center gap-1.5 text-xs text-text-secondary">
          <Smartphone size={12} /> Device
        </span>
        <span className="flex items-center gap-1.5 text-xs text-text-secondary">
          <User size={12} /> Manual
        </span>
      </div>
    </div>
  )
}
