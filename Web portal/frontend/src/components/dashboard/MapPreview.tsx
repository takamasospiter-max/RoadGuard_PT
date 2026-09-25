import { CircleMarker, MapContainer, TileLayer, Tooltip } from 'react-leaflet'
import { Link } from 'react-router-dom'
import { buttonVariants } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import type { Defect } from '@/types'

const severityColor: Record<Defect['severity'], string> = {
  high: '#DC2626',
  medium: '#F59E0B',
  low: '#EAB308',
}

// Small, non-interactive-feeling map embedded in the Dashboard — same
// `defects` data as the full Map page, but with zoom/scroll controls
// disabled and plain CircleMarkers instead of the full page's clustering
// and click-to-open-details behavior (see HazardMap.tsx for that).
export function MapPreview({ defects }: { defects: Defect[] }) {
  // Roughly the geographic center of Tanzania — data spans regions across
  // the whole country, so the preview shouldn't default to one city.
  const center: [number, number] = [-6.369, 34.8888]

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between space-y-0">
        <CardTitle className="text-base">Road Condition Map Preview</CardTitle>
        <Link to="/map" className={buttonVariants({ variant: 'outline', size: 'sm' })}>
          View Full Map
        </Link>
      </CardHeader>
      <CardContent className="pt-0">
        <div className="h-70 overflow-hidden rounded-xl border border-border-light">
          <MapContainer
            center={center}
            zoom={5}
            scrollWheelZoom={false}
            zoomControl={false}
            className="h-full w-full"
          >
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            {defects.map((defect) => (
              <CircleMarker
                key={defect.id}
                center={[defect.lat, defect.lng]}
                radius={8}
                pathOptions={{
                  color: severityColor[defect.severity],
                  fillColor: severityColor[defect.severity],
                  fillOpacity: 0.85,
                  weight: 2,
                }}
              >
                <Tooltip direction="top" offset={[0, -6]}>
                  {defect.road}
                </Tooltip>
              </CircleMarker>
            ))}
          </MapContainer>
        </div>
      </CardContent>
    </Card>
  )
}
