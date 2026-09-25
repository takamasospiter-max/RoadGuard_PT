import { Locate } from 'lucide-react'
import { useMap } from 'react-leaflet'
import type { LatLngExpression } from 'leaflet'

// A "reset view" button rendered as a child of <MapContainer>. useMap()
// only works inside that context, which is why this is a separate
// component rather than inline logic in HazardMap.
export function RecenterControl({ center, zoom }: { center: LatLngExpression; zoom: number }) {
  const map = useMap()

  return (
    <button
      type="button"
      onClick={() => map.setView(center, zoom)}
      // Positioned top-right (Leaflet's default zoom control sits
      // top-left) so the two controls never overlap.
      className="absolute right-2.5 top-[126px] z-[1000] flex h-8 w-8 items-center justify-center rounded-md border border-border-light bg-surface text-text-secondary shadow-sm hover:bg-app-bg hover:text-text-primary"
      aria-label="Reset map view"
      title="Reset map view"
    >
      <Locate size={16} />
    </button>
  )
}
