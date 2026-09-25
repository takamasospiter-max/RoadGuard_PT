import type { AccountStatus, PortalUser, UserRole } from '@/types'

// The Users tab's filter state — same "all-or-one-value" pattern as
// MapFilters/ReportFilters (see the equivalent files in map/ and reports/).
export interface UserFilters {
  search: string
  role: 'all' | UserRole
  authority: 'all' | string
  status: 'all' | AccountStatus
}

export const defaultUserFilters: UserFilters = {
  search: '',
  role: 'all',
  authority: 'all',
  status: 'all',
}

// Same filtering pattern as applyMapFilters/applyReportFilters: search
// matches name, email, or user ID.
export function applyUserFilters(users: PortalUser[], filters: UserFilters): PortalUser[] {
  const search = filters.search.trim().toLowerCase()

  return users.filter((user) => {
    if (filters.role !== 'all' && user.role !== filters.role) return false
    if (filters.authority !== 'all' && user.authority !== filters.authority) return false
    if (filters.status !== 'all' && user.status !== filters.status) return false
    if (
      search &&
      !user.name.toLowerCase().includes(search) &&
      !user.email.toLowerCase().includes(search) &&
      !user.id.toLowerCase().includes(search)
    ) {
      return false
    }
    return true
  })
}
