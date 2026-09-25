import { RotateCcw, Search } from 'lucide-react'
import type { ReportFilters } from '@/components/reports/filters'
import { defaultReportFilters } from '@/components/reports/filters'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { sourceLabel } from '@/lib/sourceLabels'

interface ReportFilterBarProps {
  filters: ReportFilters
  // The distinct region names present in the current data, so the
  // dropdown's options are always accurate (ReportsTab computes this from
  // the live `defects` list rather than it being hardcoded here).
  regions: string[]
  onChange: (patch: Partial<ReportFilters>) => void
  onReset: () => void
}

export function ReportFilterBar({ filters, regions, onChange, onReset }: ReportFilterBarProps) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <div className="relative min-w-[240px] flex-1 sm:flex-none">
        <Search
          size={15}
          className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-secondary"
        />
        <Input
          value={filters.search}
          onChange={(e) => onChange({ search: e.target.value })}
          placeholder="Search road, region or report ID"
          className="h-10 pl-9"
          aria-label="Search road, region or report ID"
        />
      </div>

      <Select
        className="w-auto min-w-[150px]"
        value={filters.status}
        onChange={(e) => onChange({ status: e.target.value as ReportFilters['status'] })}
        aria-label="Filter by status"
      >
        <option value="all">All statuses</option>
        <option value="New">New</option>
        <option value="Verified">Verified</option>
        <option value="Under Repair">Under Repair</option>
        <option value="Resolved">Resolved</option>
      </Select>

      <Select
        className="w-auto min-w-[150px]"
        value={filters.region}
        onChange={(e) => onChange({ region: e.target.value })}
        aria-label="Filter by region"
      >
        <option value="all">All regions</option>
        {regions.map((region) => (
          <option key={region} value={region}>
            {region}
          </option>
        ))}
      </Select>

      <Select
        className="w-auto min-w-[170px]"
        value={filters.source}
        onChange={(e) => onChange({ source: e.target.value as ReportFilters['source'] })}
        aria-label="Filter by source"
      >
        <option value="all">All sources</option>
        <option value="manual">{sourceLabel.manual}s</option>
        <option value="device">{sourceLabel.device}</option>
      </Select>

      {/* Disabled when the filters already match the defaults, so it's
          not clickable when there's nothing to reset. Comparing via
          JSON.stringify is a simple way to deep-compare these small,
          flat filter objects without a dedicated equality helper. */}
      <Button
        type="button"
        variant="ghost"
        size="sm"
        onClick={onReset}
        disabled={JSON.stringify(filters) === JSON.stringify(defaultReportFilters)}
      >
        <RotateCcw size={14} />
        Reset
      </Button>
    </div>
  )
}
