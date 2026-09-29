// Central type vocabulary for the whole app. Every mock data file and every
// component imports its shapes from here, so this is the best starting
// point for understanding what data the app moves around.

// The two portal roles. Admin gets full access (user/authority management,
// system config); TARURA Officer can work with road-condition data but not
// manage other portal users. See SRS §2.3 for the full access table.
export type UserRole = 'Admin' | 'TARURA Officer'

// The currently signed-in user, as stored by AuthContext after login.
export interface AuthUser {
  name: string
  email: string
  role: UserRole
}

// Road-condition severity, driving marker/badge colors across Dashboard,
// Map and Reports (see src/lib/statusColors.ts for the status equivalent).
export type Severity = 'low' | 'medium' | 'high'

// Where a defect record came from: an automatic sensor/AI detection
// ("device") or a traveler-submitted report via the mobile app ("manual").
export type ReportSource = 'manual' | 'device'

// The status lifecycle a defect/report moves through. Used everywhere a
// status is shown or filtered (badges, charts, filter dropdowns).
export type ReportStatus = 'New' | 'Verified' | 'Under Repair' | 'Resolved'

// The hazard category RoadGuard detects. Scoped to potholes only — road
// cracks are out of scope for this project (the backend rejects them). Kept
// as a named type so a future category could be added in one place.
export type HazardType = 'Pothole'

// Full defect record for the Map page, aligned with SRS FR-MAP-1/4 fields:
// location, severity, source, first/last observed date, corroborating
// observation count, and optional attached photo.
export interface Defect {
  id: string
  hazardType: HazardType
  road: string
  region: string
  severity: Severity
  status: ReportStatus
  source: ReportSource
  confidence: number
  observationCount: number
  detectedAt: string
  lat: number
  lng: number
  hasPhoto: boolean
  // Populated once an authorized user saves a review (SRS FR-DEF-3 / FR-MOD-2:
  // status transitions record the acting user and timestamp).
  reviewNote?: string
  reviewedBy?: string
  reviewedAt?: string
  // The traveller's own note on a mobile-app photo report, if any.
  notes?: string
  // Crowd-sensing evidence, kept up to date by the backend
  // (new-backend/detection/spots.py) as phones detect the same spot.
  deviceCount: number          // how many different phones detected it
  severityScore?: number       // 0-1, confidence-weighted hit strength
  lastDetectedAt?: string      // latest phone detection
  publishedAt?: string         // when enough phones agreed to alert drivers
  isSimulated: boolean         // built only from test detections
  // Whether the mobile app shows/alerts it to drivers right now (same rule
  // as the app's live map: new-backend/mobile/hazards.py).
  shownToDrivers: boolean
  // The AI photo model's check of the traveller's photo (advice only).
  // Undefined = no photo, or not checked yet.
  photoCheck?: PhotoCheck
}

// Result of the AI photo model (YOLOv8, new-backend/ai_engine/photo_model.py)
// on a report photo. Each box is [x1, y1, x2, y2, confidence], with corners
// as 0-1 fractions of the photo's width and height.
export type PhotoCheck =
  | { status: 'failed'; checkedAt: string }
  | {
      status: 'pothole_found' | 'none_found'
      confidence: number
      boxes: [number, number, number, number, number][]
      modelVersion: string
      checkedAt: string
    }

// Active/Inactive account state, shared by both PortalUser and Authority
// records so their "disable this thing" UI can look identical.
export type AccountStatus = 'Active' | 'Inactive'

// Portal accounts (Admin / TARURA Officer), aligned with SRS FR-USR-1..3.
// Distinct from mobile-app contributor accounts (FR-CON-1), which this page
// does not manage.
export interface PortalUser {
  id: string
  name: string
  email: string
  phone?: string
  role: UserRole
  authority: string
  status: AccountStatus
  lastActiveAt: string
  createdAt: string
}

// Participating road authorities. The SRS scopes the current pilot to a
// single authority (TARURA) and explicitly reserves multi-authority
// support for a future phase (Appendix A), so this is deliberately a
// small, low-ceremony record rather than a full tenancy model.
export interface Authority {
  id: string
  name: string
  coverageArea: string
  contact: string
  status: AccountStatus
}

// Aggregate counts shown by the Dashboard's five overview cards. Computed
// live from `defects` via src/lib/reportStats.ts — never stored directly.
export interface OverviewStats {
  totalReports: number
  manualReports: number
  deviceReports: number
  newReports: number
  resolved: number
}

// One slice of the status-breakdown donut/bar charts (Dashboard's Report
// Status Summary, Analytics' Verification Lifecycle).
export interface StatusSummaryItem {
  status: ReportStatus
  count: number
}
