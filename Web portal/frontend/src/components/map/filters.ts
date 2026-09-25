import type { Defect, ReportStatus, Severity } from '@/types'

// Shape of the Map page's filter bar state. Each field is either "all"
// (no filtering on that dimension) or one specific value from the type.
// No hazard-type filter here — the project only tracks potholes now, so
// filtering "by type" would never have more than one meaningful option.
export interface MapFilters {
  severity: 'all' | Severity
  status: 'all' | ReportStatus
  search: string
}

// What the filter bar resets to when "Reset" is clicked (or on first load).
export const defaultMapFilters: MapFilters = {
  severity: 'all',
  status: 'all',
  search: '',
}

// Pure function: given the full defect list and the current filter state,
// return only the defects that match every active filter (AND, not OR).
// Kept separate from any component so MapPage can call it inside a
// useMemo without re-defining the logic inline.
export function applyMapFilters(defects: Defect[], filters: MapFilters): Defect[] {
  const search = filters.search.trim().toLowerCase()

  return defects.filter((defect) => {
    if (filters.severity !== 'all' && defect.severity !== filters.severity) return false
    if (filters.status !== 'all' && defect.status !== filters.status) return false
    // Free-text search matches either the road name or the region.
    if (search && !defect.road.toLowerCase().includes(search) && !defect.region.toLowerCase().includes(search)) {
      return false
    }
    return true
  })
}
