import { RotateCcw, Search } from 'lucide-react'
import { defaultUserFilters, type UserFilters } from '@/components/users/filters'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'

interface UserFilterBarProps {
  filters: UserFilters
  authorities: string[]
  onChange: (patch: Partial<UserFilters>) => void
  onReset: () => void
}

// Search/Role/Authority/Status controls for the Users tab — same
// controlled-component pattern as ReportFilterBar and Map's FilterBar.
export function UserFilterBar({ filters, authorities, onChange, onReset }: UserFilterBarProps) {
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
          placeholder="Search name, email or user ID"
          className="h-10 pl-9"
          aria-label="Search name, email or user ID"
        />
      </div>

      <Select
        className="w-auto min-w-[170px]"
        value={filters.role}
        onChange={(e) => onChange({ role: e.target.value as UserFilters['role'] })}
        aria-label="Filter by role"
      >
        <option value="all">All roles</option>
        <option value="Admin">System Administrator</option>
        <option value="TARURA Officer">Road Authority Officer</option>
      </Select>

      <Select
        className="w-auto min-w-[150px]"
        value={filters.authority}
        onChange={(e) => onChange({ authority: e.target.value })}
        aria-label="Filter by authority"
      >
        <option value="all">All authorities</option>
        {authorities.map((authority) => (
          <option key={authority} value={authority}>
            {authority}
          </option>
        ))}
      </Select>

      <Select
        className="w-auto min-w-[140px]"
        value={filters.status}
        onChange={(e) => onChange({ status: e.target.value as UserFilters['status'] })}
        aria-label="Filter by status"
      >
        <option value="all">All statuses</option>
        <option value="Active">Active</option>
        <option value="Inactive">Inactive</option>
      </Select>

      <Button
        type="button"
        variant="ghost"
        size="sm"
        onClick={onReset}
        disabled={JSON.stringify(filters) === JSON.stringify(defaultUserFilters)}
      >
        <RotateCcw size={14} />
        Reset
      </Button>
    </div>
  )
}
