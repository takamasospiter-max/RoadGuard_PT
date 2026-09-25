import { Search } from 'lucide-react'
import type { MapFilters } from '@/components/map/filters'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'

interface FilterBarProps {
  filters: MapFilters
  // Called with just the field(s) that changed, e.g. onChange({severity:
  // 'high'}) — MapPage merges this into its full filters state. Purely
  // "dumb"/controlled: this component holds no state of its own.
  onChange: (patch: Partial<MapFilters>) => void
}

// The Map page's Severity/Status/Search controls, rendered above the map.
// Each control is uncontrolled-looking but is actually fully controlled by
// `filters` — this is a presentation-only component. No hazard-type
// filter — the project only tracks potholes, so there's nothing to
// distinguish between.
export function FilterBar({ filters, onChange }: FilterBarProps) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <Select
        className="w-auto min-w-[150px]"
        value={filters.severity}
        onChange={(e) => onChange({ severity: e.target.value as MapFilters['severity'] })}
        aria-label="Filter by severity"
      >
        <option value="all">All Severity</option>
        <option value="high">High</option>
        <option value="medium">Medium</option>
        <option value="low">Low</option>
      </Select>

      <Select
        className="w-auto min-w-[150px]"
        value={filters.status}
        onChange={(e) => onChange({ status: e.target.value as MapFilters['status'] })}
        aria-label="Filter by status"
      >
        <option value="all">All Status</option>
        <option value="New">New</option>
        <option value="Verified">Verified</option>
        <option value="Under Repair">Under Repair</option>
        <option value="Resolved">Resolved</option>
      </Select>

      <div className="relative min-w-[220px] flex-1 sm:flex-none">
        <Search
          size={15}
          className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-secondary"
        />
        <Input
          value={filters.search}
          onChange={(e) => onChange({ search: e.target.value })}
          placeholder="Search road or area"
          className="h-10 pl-9"
          aria-label="Search road or area"
        />
      </div>
    </div>
  )
}
