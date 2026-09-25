import { api, apiGet, apiPatch } from '@/lib/api'
import type { Defect } from '@/types'

// Matches new-backend/roadguard/serializers.py's DefectSerializer field-for-field.
interface DefectOutResponse {
  id: string
  hazard_type: Defect['hazardType']
  road: string
  region: string
  severity: Defect['severity']
  status: Defect['status']
  source: Defect['source']
  confidence: number
  observation_count: number
  detected_at: string
  lat: number
  lng: number
  has_photo: boolean
  review_note: string | null
  reviewed_by: string | null
  reviewed_at: string | null
  notes: string
  device_count: number
  severity_score: number | null
  last_detected_at: string | null
  published_at: string | null
  is_simulated: boolean
  shown_to_drivers: boolean
}

function toDefect(res: DefectOutResponse): Defect {
  return {
    id: res.id,
    hazardType: res.hazard_type,
    road: res.road,
    region: res.region,
    severity: res.severity,
    status: res.status,
    source: res.source,
    confidence: res.confidence,
    observationCount: res.observation_count,
    detectedAt: res.detected_at,
    lat: res.lat,
    lng: res.lng,
    hasPhoto: res.has_photo,
    reviewNote: res.review_note ?? undefined,
    reviewedBy: res.reviewed_by ?? undefined,
    reviewedAt: res.reviewed_at ?? undefined,
    notes: res.notes || undefined,
    deviceCount: res.device_count,
    severityScore: res.severity_score ?? undefined,
    lastDetectedAt: res.last_detected_at ?? undefined,
    publishedAt: res.published_at ?? undefined,
    isSimulated: res.is_simulated,
    shownToDrivers: res.shown_to_drivers,
  }
}

export async function listDefects(): Promise<Defect[]> {
  const res = await apiGet<DefectOutResponse[]>('/defects/')
  return res.map(toDefect)
}

// A moderation decision (SRS FR-DEF-3 / FR-MOD-2) — status and/or a note.
// reviewedBy/reviewedAt aren't parameters: the backend always stamps those
// from whoever's session made the request, never from the client.
export async function updateDefect(
  id: string,
  patch: { status?: Defect['status']; reviewNote?: string },
): Promise<Defect> {
  const res = await apiPatch<DefectOutResponse>(`/defects/${id}/`, {
    ...(patch.status !== undefined && { status: patch.status }),
    ...(patch.reviewNote !== undefined && patch.reviewNote !== '' && { review_note: patch.reviewNote }),
  })
  return toDefect(res)
}

// The traveller's photo for a mobile-app report, as a Blob (JPEG).
// GET /api/defects/<id>/photo/ (DefectPhotoView) only answers logged-in portal
// users, so it's fetched through axios, which sends the session cookie, and
// shown from a local object URL rather than a plain <img src="..."> link.
export async function fetchDefectPhoto(id: string): Promise<Blob> {
  const res = await api.get<Blob>(`/defects/${id}/photo/`, { responseType: 'blob' })
  return res.data
}

// One phone's detection of a spot, as returned by
// GET /api/defects/<id>/detections/ (new-backend/detection/views.py).
export interface SpotDetection {
  id: string
  detectedAt: string
  latitude: number
  longitude: number
  confidence: number          // 0-1: how sure the AI model was
  intensity: number | null    // 0-1: how hard the hit was
  severity: Defect['severity'] | null
  modelVersion: string        // which AI model produced it
  isSimulated: boolean        // a test detection, not a real phone
  device: string              // short pseudonymous phone id (never the account)
}

// The evidence behind a spot: the counts plus every detection (newest first).
export interface SpotEvidence {
  deviceCount: number
  observationCount: number
  severityScore: number | null
  publishedAt: string | null
  detections: SpotDetection[]
}

export async function fetchSpotEvidence(id: string): Promise<SpotEvidence> {
  return apiGet<SpotEvidence>(`/defects/${id}/detections/`)
}
