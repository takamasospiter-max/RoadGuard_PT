import { latLng } from 'leaflet'
import { MapContainer, Marker, Popup, TileLayer, useMap } from 'react-leaflet'
import MarkerClusterGroup from 'react-leaflet-cluster'
import { EmptyMapState } from '@/components/map/EmptyMapState'
import { HazardPopupContent } from '@/components/map/HazardPopupContent'
import { MapLegend } from '@/components/map/MapLegend'
import { RecenterControl } from '@/components/map/RecenterControl'
import { severityIcon } from '@/components/map/severityIcon'
import type { Defect } from '@/types'

// Roughly the geographic center of Tanzania (near Dodoma/Singida) rather
// than Dar es Salaam — the data now spans regions across the whole
// country, so the default view needs to show all of it, not just one city.
const TANZANIA_CENTER: [number, number] = [-6.369, 34.8888]
const DEFAULT_ZOOM = 6

// Clicking a defect zooms to about ±30 m around it: a 60 m square box.
const FOCUS_RADIUS_M = 30
// OpenStreetMap has tile images down to zoom 19 (about ±120 m on a normal
// screen). To show ±30 m the map may zoom 2 steps further, enlarging the
// zoom-19 tiles (slightly softer, but the view is really ±30 m).
const OSM_MAX_NATIVE_ZOOM = 19
const MAX_ZOOM = 21

interface HazardMapProps {
  defects: Defect[]
  onSelectDefect: (defect: Defect) => void
}

// The full interactive map for the Map page (as opposed to Dashboard's
// smaller, non-interactive MapPreview). `defects` is already filtered by
// the caller (MapPage) before it gets here — this component just renders
// whatever list it's handed. `onSelectDefect` fires when someone clicks
// "View Details" inside a marker's popup, letting MapPage open the
// HazardDetailsPanel for that record.
export function HazardMap({ defects, onSelectDefect }: HazardMapProps) {
  return (
    <div className="relative h-full w-full">
      <MapContainer
        center={TANZANIA_CENTER}
        zoom={DEFAULT_ZOOM}
        maxZoom={MAX_ZOOM}
        className="h-full w-full"
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          maxNativeZoom={OSM_MAX_NATIVE_ZOOM}
          maxZoom={MAX_ZOOM}
        />

        {/* Groups nearby markers into a single numbered "cluster" bubble at
            low zoom levels (SRS FR-MAP-3), so the map stays readable as
            defect volume grows instead of a wall of overlapping pins. */}
        <MarkerClusterGroup chunkedLoading showCoverageOnHover={false} maxClusterRadius={50}>
          {defects.map((defect) => (
            <DefectMarker key={defect.id} defect={defect} onSelectDefect={onSelectDefect} />
          ))}
        </MarkerClusterGroup>

        {/* Both need to be *inside* MapContainer: RecenterControl uses
            react-leaflet's useMap() hook, and MapLegend is just an
            absolutely-positioned overlay div — Leaflet's container is
            `position: relative`, so it anchors correctly either way. */}
        <RecenterControl center={TANZANIA_CENTER} zoom={DEFAULT_ZOOM} />
        <MapLegend />
      </MapContainer>

      {defects.length === 0 && <EmptyMapState />}
    </div>
  )
}

// One defect pin. Clicking it opens its popup and flies the map to about
// ±FOCUS_RADIUS_M around the defect, so a pin picked from a country-wide view
// is shown at street level. (useMap() needs to run inside <MapContainer>,
// hence a small component of its own.)
function DefectMarker({ defect, onSelectDefect }: { defect: Defect; onSelectDefect: (defect: Defect) => void }) {
  const map = useMap()
  return (
    <Marker
      position={[defect.lat, defect.lng]}
      icon={severityIcon(defect.severity)}
      eventHandlers={{
        click: () =>
          // toBounds(size) = a square `size` metres wide centred on the point.
          map.flyToBounds(latLng(defect.lat, defect.lng).toBounds(FOCUS_RADIUS_M * 2), {
            maxZoom: MAX_ZOOM,
            duration: 0.8,
          }),
      }}
    >
      <Popup>
        <HazardPopupContent defect={defect} onViewDetails={() => onSelectDefect(defect)} />
      </Popup>
    </Marker>
  )
}
