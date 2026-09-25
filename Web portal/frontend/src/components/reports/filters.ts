import type { Defect, ReportSource, ReportStatus } from '@/types'

// Same shape/pattern as src/components/map/filters.ts (the Map page's
// filter state), but for the Reports tab: status/region dropdowns plus a
// search box, instead of Map's severity/status/search. No hazard-type
// filter — the project only tracks potholes now, so there's nothing to
// distinguish between.
export interface ReportFilters {
  status: 'all' | ReportStatus
  region: 'all' | string
  // Traveller photo reports vs spots found by the AI in phones' sensor data.
  source: 'all' | ReportSource
  search: string
}

export const defaultReportFilters: ReportFilters = {
  status: 'all',
  region: 'all',
  source: 'all',
  search: '',
}

// Pure filtering function — see map/filters.ts's applyMapFilters for the
// same pattern. Unlike the Map page's search, this one also matches
// against the report ID (e.g. typing "RG-00133" finds that exact report).
export function applyReportFilters(defects: Defect[], filters: ReportFilters): Defect[] {
  const search = filters.search.trim().toLowerCase()

  return defects.filter((defect) => {
    if (filters.status !== 'all' && defect.status !== filters.status) return false
    if (filters.region !== 'all' && defect.region !== filters.region) return false
    if (filters.source !== 'all' && defect.source !== filters.source) return false
    if (
      search &&
      !defect.road.toLowerCase().includes(search) &&
      !defect.region.toLowerCase().includes(search) &&
      !defect.id.toLowerCase().includes(search)
    ) {
      return false
    }
    return true
  })
}
