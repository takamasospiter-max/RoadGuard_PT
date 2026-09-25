import { MapPinOff } from 'lucide-react'

// Overlay shown by HazardMap when the active filters match zero defects,
// so the map doesn't just look broken/blank.
export function EmptyMapState() {
  return (
    <div className="absolute inset-0 z-[1000] flex items-center justify-center bg-surface/90">
      <div className="flex max-w-xs flex-col items-center gap-2 text-center">
        <MapPinOff size={28} className="text-text-secondary" />
        <p className="text-sm font-medium text-text-primary">No road-condition reports found.</p>
        <p className="text-xs text-text-secondary">
          Try changing the filters or selecting another area.
        </p>
      </div>
    </div>
  )
}
