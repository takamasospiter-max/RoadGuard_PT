import L from 'leaflet'
import type { Severity } from '@/types'

const severityColor: Record<Severity, string> = {
  high: '#DC2626',
  medium: '#F59E0B',
  low: '#EAB308',
}

// Only 3 possible icons exist (one per severity), so cache them instead of
// building a new L.DivIcon every time a marker renders.
const iconCache = new Map<Severity, L.DivIcon>()

// Builds a small colored circle marker icon for the given severity.
// Deliberately an L.divIcon (an HTML <span> styled with Tailwind classes)
// rather than react-leaflet's <CircleMarker>, because the marker-clustering
// plugin (react-leaflet-cluster) only groups real L.Marker instances —
// CircleMarker isn't one, so it wouldn't cluster. See HazardMap.tsx.
export function severityIcon(severity: Severity): L.DivIcon {
  const cached = iconCache.get(severity)
  if (cached) return cached

  const icon = L.divIcon({
    className: '', // clear Leaflet's default icon classes/styles
    html: `<span style="background:${severityColor[severity]}" class="block h-4 w-4 rounded-full border-2 border-white shadow-[0_1px_4px_rgba(0,0,0,0.35)]"></span>`,
    iconSize: [16, 16],
    iconAnchor: [8, 8], // center the icon on its coordinate
    popupAnchor: [0, -8], // open popups just above the marker, not through it
  })

  iconCache.set(severity, icon)
  return icon
}
